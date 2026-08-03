extends Node
## THE SESSION'S RULES, WITHOUT A SOCKET. Everything here is arithmetic on the
## roster or bytes in a buffer — the two halves of networking that are wrong
## silently. A dropped connection announces itself; a snapshot whose unpack
## disagrees with its pack by two bytes does not, it just makes everybody stand
## in the wrong place.
##
## Headless and instant. The LIVE end of this (two real processes talking over a
## real socket) is `net_live.tscn`, which is slow and is a different question:
## this one asks whether the rules are right, that one asks whether they reach
## the other machine.
##
## Run:  godot --headless --path godot tests/net_session.tscn

var _failures := 0


## A body with just enough of a Player's shape for the pump to read it. Every
## field here is one `NetSync._pack` actually asks for, which is the point — if
## somebody adds a field to the wire without adding it here, this stub stops
## compiling against it and the test says so.
class FakeBody extends Node3D:
	var team := 0
	var health := 100.0
	var max_health := 100.0
	var model: Node3D = null
	var weapon: Node = null
	var head: Node3D = null
	var loadout: Loadout = null
	var _alive := true

	func is_alive() -> bool:
		return _alive


func _ready() -> void:
	print("\n=== NET SESSION ===\n")
	_test_seating()
	_test_auto_teams()
	_test_free_for_all()
	_test_gamestate_wiring()
	_test_config_round_trip()
	_test_client_keeps_the_hosts_seed()
	_test_snapshot_round_trip()
	_test_angle_quantisation()
	_test_ownership_gate()
	print("")
	if _failures == 0:
		print("==== ALL RULES HOLD ====")
	else:
		print("==== %d FAILURE%s ====" % [_failures, "" if _failures == 1 else "S"])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


## Seat machines by hand rather than over a socket: `_seat_machine` is where
## net_ids are handed out, and an id collision is the one bug that would make two
## bodies share a position and look like a physics fault.
func _seat_roster(machine_counts: Array) -> void:
	Net.players.clear()
	Net.machines.clear()
	Net._next_net_id = 1
	# A LIVE SESSION, minus the socket. `Net.online()` is what every read in
	# GameState branches on, so a roster without a role is a roster nothing looks
	# at — and the wiring test below would pass by reading the local numbers it
	# is supposed to have stopped reading.
	Net.role = Net.Role.HOST
	var peer := 1
	for count: int in machine_counts:
		Net.machines[peer] = {"name": "M%d" % peer, "count": count,
			"protocol": Net.PROTOCOL}
		Net._seat_machine(peer, count, "M%d" % peer, Net.TEAM_AUTO)
		peer += 1


func _test_seating() -> void:
	print("-- seating --")
	GameState.team_count = 2
	GameState.free_for_all = false
	_seat_roster([2, 2])
	_check(Net.player_count() == 4, "two machines of two seat four players")
	var ids := Net.roster()
	_check(ids == [1, 2, 3, 4], "net_ids are dense and in order: %s" % str(ids))
	var unique := {}
	for id: int in ids:
		unique[id] = true
	_check(unique.size() == ids.size(), "no two players share an id")
	_check(Net.machine_of(1) == 1 and Net.machine_of(3) == 2,
		"each player knows which machine it is sitting at")
	_seat_roster([4, 4, 4, 4])
	_check(Net.player_count() == Net.MAX_PLAYERS,
		"the roster stops at MAX_PLAYERS (%d), it does not overflow"
			% Net.MAX_PLAYERS)


## A SOFA IS NOT SPLIT UP. This is the rule most likely to be "simplified" later
## into a round-robin over players, which is why it is asserted rather than
## commented: four people at one machine dealt alternately across two sides are
## four people who cannot play together.
func _test_auto_teams() -> void:
	print("\n-- auto sides --")
	GameState.team_count = 2
	GameState.free_for_all = false
	_seat_roster([4, 4])
	var first := Net.team_of(1)
	var same := true
	for id in [1, 2, 3, 4]:
		same = same and Net.team_of(id) == first
	_check(same, "everybody at one machine lands on the same side")
	var other := Net.team_of(5)
	_check(other != first, "the second machine takes the other side")
	_check(Net.humans_on_team(0) == 4 and Net.humans_on_team(1) == 4,
		"and the sides come out even: %d v %d"
			% [Net.humans_on_team(0), Net.humans_on_team(1)])

	# Uneven machines still balance as well as whole sofas allow.
	_seat_roster([1, 3])
	_check(Net.humans_on_team(0) + Net.humans_on_team(1) == 4,
		"every player is on exactly one side")

	# An explicit pick is honoured, not re-balanced away.
	_seat_roster([2, 2])
	for id: int in Net.roster():
		if Net.machine_of(id) == 2:
			Net.players[id]["team"] = 0
	Net._assign_teams()
	_check(Net.team_of(3) == 0 and Net.team_of(4) == 0,
		"a machine that asked for a side keeps it")


func _test_free_for_all() -> void:
	print("\n-- free for all --")
	GameState.free_for_all = true
	_seat_roster([2, 2])
	Net._assign_teams()
	var sides := {}
	for id: int in Net.roster():
		sides[Net.team_of(id)] = true
	_check(sides.size() == 4, "four players are four sides, machine or not")
	GameState.free_for_all = false


## The three GameState questions that had to learn the difference between "this
## machine" and "this match". Getting these wrong is what makes every machine
## fill the same team with its own AI.
func _test_gamestate_wiring() -> void:
	print("\n-- GameState reads the session, not the sofa --")
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.human_players = 2      # this machine's viewports
	GameState.team_size = 4
	_seat_roster([2, 2])
	# Pretend we are machine 1 for the local-id lookups.
	_check(GameState.session_humans() == 4,
		"session_humans counts every machine (%d)" % GameState.session_humans())
	_check(GameState.humans_on_team(0) == 2 and GameState.humans_on_team(1) == 2,
		"humans_on_team counts every machine")
	_check(GameState.ai_needed(0) == 2,
		"AI fills to team_size once, not once per machine (%d)"
			% GameState.ai_needed(0))
	_check(GameState.human_players == 2,
		"human_players still means VIEWPORTS HERE and was not repurposed")


func _test_config_round_trip() -> void:
	print("\n-- the host's setup survives the wire --")
	GameState.map_index = 3
	GameState.mode = GameState.Mode.ZONES
	GameState.team_count = 3
	GameState.team_size = 5
	GameState.ai_skill = 2
	GameState.ttk = GameState.Ttk.HIGH
	GameState.time_of_day = GameState.TimeOfDay.NIGHT
	GameState.planet_seed = 123456
	var cfg := Net.launch_config()

	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.team_count = 2
	GameState.team_size = 1
	GameState.ai_skill = 0
	GameState.ttk = GameState.Ttk.LOW
	GameState.time_of_day = GameState.TimeOfDay.DAY
	GameState.planet_seed = 0
	Net.apply_config(cfg)

	_check(GameState.map_index == 3, "map")
	_check(GameState.mode == GameState.Mode.ZONES, "mode")
	_check(GameState.team_count == 3, "team count")
	_check(GameState.team_size == 5, "team size")
	_check(GameState.ai_skill == 2, "AI skill")
	_check(GameState.ttk == GameState.Ttk.HIGH, "time to kill")
	_check(GameState.time_of_day == GameState.TimeOfDay.NIGHT, "time of day")
	_check(GameState.planet_seed == 123456, "planet seed — the map itself")
	_check(int(cfg["protocol"]) == Net.PROTOCOL,
		"the payload states its protocol so a mismatch is refused at the door")


## THE ONE THAT COST A WHOLE CLASS OF BUG BEFORE IT WAS WRITTEN DOWN.
## `reset_match` rolls a fresh `planet_seed` and Main calls it on the way into
## every match — so on a client it would throw away the host's seed and generate
## a different world, and every symptom after that (walking into invisible
## buildings, being shot through cover) looks like a replication fault instead of
## what it is.
func _test_client_keeps_the_hosts_seed() -> void:
	print("\n-- a client does not re-roll the world --")
	Net.role = Net.Role.CLIENT
	GameState.planet_seed = 987654
	GameState.reset_match()
	_check(GameState.planet_seed == 987654,
		"reset_match leaves the host's seed alone on a client")
	Net.role = Net.Role.OFFLINE
	GameState.planet_seed = 987654
	GameState.reset_match()
	_check(GameState.planet_seed != 987654,
		"...and still rolls a fresh one when there is no host but us")


## PACK AND UNPACK ARE ONE PAIR OF FUNCTIONS WRITTEN THIRTY LINES APART AND THEY
## MUST AGREE ON EVERY BYTE. A field added to one and not the other shifts every
## field after it, which does not error — it puts bodies underground, at the map
## origin, or animating something they are not doing.
func _test_snapshot_round_trip() -> void:
	print("\n-- a snapshot survives the round trip --")
	var pump := NetSync.new()
	add_child(pump)

	var body := FakeBody.new()
	add_child(body)
	body.global_position = Vector3(12.5, 3.25, -48.75)
	body.rotation.y = 1.234
	body.head = Node3D.new()
	body.add_child(body.head)
	body.head.rotation.x = -0.42
	body.health = 37.0
	body.team = 1
	pump.own(body, 7)
	pump._shots[7] = 200

	pump._buf.encode_u16(0, 1)
	pump._pack(2, 7, body)
	var packet: PackedByteArray = pump._buf.slice(0, 2 + NetSync.REC_SIZE)

	_check(packet.size() == 2 + NetSync.REC_SIZE,
		"one body packs to %d bytes plus a 2-byte header" % NetSync.REC_SIZE)
	_check(packet.decode_u16(0) == 1, "the header states the body count")
	_check(packet.decode_u16(2) == 7, "the id survives")
	var pos := Vector3(packet.decode_float(4), packet.decode_float(8),
		packet.decode_float(12))
	_check(pos.is_equal_approx(body.global_position),
		"the position survives exactly: %s" % str(pos))
	var yaw := pump._unquantise_angle(packet.decode_s16(16))
	_check(absf(yaw - 1.234) < 0.001, "yaw survives quantisation (%.4f)" % yaw)
	var pitch := pump._unquantise_angle(packet.decode_s16(18))
	_check(absf(pitch + 0.42) < 0.001, "pitch survives quantisation (%.4f)" % pitch)
	_check(packet.decode_u8(21) & NetPlayer.F_ALIVE != 0, "the alive flag is set")
	var frac := float(packet.decode_u8(22)) / 255.0
	_check(absf(frac - 0.37) < 0.01, "health survives as a fraction (%.3f)" % frac)
	_check(packet.decode_u8(23) == 200, "the shot counter survives")

	# And the layout constant is not a guess: the offsets above have to end
	# exactly on REC_SIZE, or one of them is lying about where it sits.
	_check(24 - 2 == NetSync.REC_SIZE,
		"the fields above account for every byte of REC_SIZE")

	body.queue_free()
	pump.queue_free()


func _test_angle_quantisation() -> void:
	print("\n-- angles --")
	var pump := NetSync.new()
	add_child(pump)
	var worst := 0.0
	for i in 720:
		var a := -PI + TAU * float(i) / 720.0
		var back: float = pump._unquantise_angle(pump._quantise_angle(a))
		worst = maxf(worst, absf(wrapf(back - a, -PI, PI)))
	# A body's facing is read off a model on a quarter screen. Half a thousandth
	# of a degree is four bytes a body a tick cheaper than a float and invisible.
	_check(worst < 0.001,
		"worst angle error over a full turn is %.5f rad (%.4f deg)"
			% [worst, rad_to_deg(worst)])
	pump.queue_free()


## A MACHINE MAY ONLY MOVE ITS OWN BODIES. Not a cheating question first and
## foremost — it is what stops a stale packet from a peer that has just lost a
## player fighting the machine that now owns it.
func _test_ownership_gate() -> void:
	print("\n-- a machine may only move its own bodies --")
	var pump := NetSync.new()
	add_child(pump)
	GameState.team_count = 2
	GameState.free_for_all = false
	_seat_roster([2, 2])
	_check(pump._sender_owns(1, 1), "machine 1 may move its own player")
	_check(not pump._sender_owns(2, 1), "machine 2 may NOT move machine 1's player")
	_check(pump._sender_owns(1, NetSync.BOT_ID_BASE),
		"the host may move a bot")
	_check(not pump._sender_owns(2, NetSync.BOT_ID_BASE),
		"a client may NOT move a bot, whatever it claims")
	_check(NetSync.BOT_ID_BASE > Net.MAX_PLAYERS,
		"bot ids start above every possible human id, so the two never collide")
	pump.queue_free()
