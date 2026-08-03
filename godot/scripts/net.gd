extends Node
## NET — THE SESSION, exactly as `GameState` is the MATCH.
##
## One autoload holding who is playing, on what machine, on which side, and what
## the match is going to be. Everything about being online is asked here and
## nowhere else: `Net.online()`, `Net.is_host()`, `Net.authority()`. Nothing else
## in the game may test `multiplayer.*` directly, for the same reason nothing
## reads `PLANETS[planet]` any more — half the code would then be answering the
## question a different way, and the halves would disagree.
##
## THE MODEL IS A LAN PARTY, NOT A SHOOTER'S DEDICATED SERVER, and every trade
## below follows from that. This game is four people on a sofa; going online
## means SEVERAL sofas, so a peer is a MACHINE carrying one to four humans, not a
## player. That is the shape the game was already built for — N viewports per
## machine — so "four at one couch" and "four machines with one each" differ only
## in how many local players a peer has.
##
##   THE HOST OWNS THE MATCH.  Bots, spawns, pickups, the storm, the zone,
##   command posts, scores, tickets, the countdown and victory all run on the
##   host alone and are broadcast. That is the half that has to have exactly one
##   answer, and a match with two opinions about the score is not a match.
##
##   A MACHINE OWNS ITS OWN BODIES.  Each peer simulates its own humans at zero
##   latency and ships their state out; everyone else draws them as `NetPlayer`
##   proxies. This is the deliberate soft spot: it is trusting, and it is
##   trusting on purpose. Every number in this project — the recoil settle, the
##   stance spread, the twist rate, the carry pose — was tuned against input
##   that moves the body on the same frame it was read. Routing a local player's
##   own movement through a server would change the feel of all of it, which is
##   a far bigger loss than cheating is on a couch full of friends. Hits are
##   detected by the SHOOTER (favour the shooter, as most shooters do) and
##   applied by the VICTIM, which is also what makes the saber guard work: the
##   only machine that knows whether the blade was up is the one holding it.
##
## The consequence is stated once so nobody has to rediscover it: A CLIENT CAN
## LIE. This is a friends-and-LAN mode. If it ever needs to face strangers, the
## line to move is the one above — local players become inputs sent to the host
## — and nothing else in this file changes.

## Bumped on ANY change to the wire format: the roster payload, the session
## config, the snapshot layout in `net_sync.gd`, or the meaning of an event id.
## A mismatched build is refused at the door with a message, because the failure
## mode otherwise is a match that half-works and looks like a bug in the game.
const PROTOCOL := 1

const PORT := 27015
const DISCOVERY_PORT := 27016
const DISCOVERY_MAGIC := "QSQD"          # keeps stray broadcasts off the browser
const BROWSE_TIMEOUT := 2.5              # seconds a browse listens for replies
const MAX_MACHINES := 4
const MAX_LOCAL := 4                     # a sofa holds four; so does a viewport grid
const MAX_PLAYERS := MAX_MACHINES * MAX_LOCAL
const CONNECT_TIMEOUT := 8.0

enum Role { OFFLINE, HOST, CLIENT }

## AUTO spreads a machine's players across the sides the way a local match does.
## A machine picks ONE side for everybody on it — four people on one sofa are a
## squad, and per-seat team picking on a shared screen is the team-select screen's
## job, not a lobby's.
const TEAM_AUTO := -1

signal roster_changed()                  # somebody joined, left, or changed side
signal session_failed(reason: String)    # refused, dropped, or could not connect
signal session_joined()                  # our own connection is up and rostered
signal browse_result(servers: Array)     # LAN discovery finished
signal launching()                       # the host said go; change scene now

var role := Role.OFFLINE
var host_name := ""

## THE ROSTER, and it is the host's. net_id -> {machine, local, team, name}.
##
## `net_id` is assigned by the host and is the ONLY id anything on the wire ever
## uses. It is deliberately not derived from the ENet peer id: those are large
## random integers chosen by the engine, they say nothing about seating order,
## and a snapshot carrying one would be four bytes a body for no information.
## Small dense ids also let a snapshot address a body in a single byte.
var players := {}
var machines := {}                       # peer_id -> {name, count, protocol}

var _peer: ENetMultiplayerPeer
var _next_net_id := 1
var _local_count := 1
var _local_name := "PLAYER"
var _want_team := TEAM_AUTO
var _discovery: PacketPeerUDP
var _browser: PacketPeerUDP
var _browse_left := 0.0
var _found := []
var _connect_left := 0.0


func _ready() -> void:
	# Nothing here costs a frame until somebody hosts or browses. The autoload
	# exists in every scene including the menu, and a socket poll per frame all
	# match for a game nobody networked is exactly the kind of free cost this
	# project measures out.
	set_process(false)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


# --- asking ------------------------------------------------------------------

func online() -> bool:
	return role != Role.OFFLINE


func is_host() -> bool:
	return role == Role.HOST


## TRUE IF THIS MACHINE IS THE ONE ALLOWED TO DECIDE. Offline this is always
## true, which is what lets every caller write `if Net.authority():` once instead
## of branching on whether the game is networked at all — the single-player path
## and the host path are the same path.
func authority() -> bool:
	return role != Role.CLIENT


## Everyone this machine is actually rendering a viewport for.
func local_ids() -> Array:
	var out := []
	var me := _self_peer()
	for id: int in players:
		if int(players[id]["machine"]) == me:
			out.append(id)
	out.sort()
	return out


func owns(net_id: int) -> bool:
	var row: Dictionary = players.get(net_id, {})
	return not row.is_empty() and int(row["machine"]) == _self_peer()


func machine_of(net_id: int) -> int:
	var row: Dictionary = players.get(net_id, {})
	return -1 if row.is_empty() else int(row["machine"])


func team_of(net_id: int) -> int:
	var row: Dictionary = players.get(net_id, {})
	return 0 if row.is_empty() else int(row["team"])


func name_of(net_id: int) -> String:
	var row: Dictionary = players.get(net_id, {})
	return "" if row.is_empty() else str(row["name"])


## The roster in a STABLE order every machine agrees on, which is what makes
## "the third player" mean the same thing everywhere — spawn slots, team fill and
## the scoreboard all count through it.
func roster() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids


func player_count() -> int:
	return players.size()


func humans_on_team(team: int) -> int:
	var n := 0
	for id: int in players:
		if int(players[id]["team"]) == team:
			n += 1
	return n


func local_count() -> int:
	return _local_count


# --- hosting and joining -----------------------------------------------------

## Open a session. `locals` is how many humans are at THIS machine, which is the
## same number the split-screen grid is built from.
func host(locals: int, machine_name: String, team := TEAM_AUTO) -> bool:
	leave()
	_local_count = clampi(locals, 1, MAX_LOCAL)
	_local_name = machine_name
	_want_team = team
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(PORT, MAX_MACHINES - 1)
	if err != OK:
		session_failed.emit("Could not open port %d (error %d)" % [PORT, err])
		return false
	_peer = p
	multiplayer.multiplayer_peer = p
	role = Role.HOST
	host_name = machine_name
	players.clear()
	machines.clear()
	_next_net_id = 1
	machines[1] = {"name": machine_name, "count": _local_count, "protocol": PROTOCOL}
	_seat_machine(1, _local_count, machine_name, team)
	_open_discovery()
	set_process(true)
	roster_changed.emit()
	session_joined.emit()
	return true


func join(address: String, locals: int, machine_name: String, team := TEAM_AUTO) -> bool:
	leave()
	_local_count = clampi(locals, 1, MAX_LOCAL)
	_local_name = machine_name
	_want_team = team
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(address, PORT)
	if err != OK:
		session_failed.emit("Could not reach %s (error %d)" % [address, err])
		return false
	_peer = p
	multiplayer.multiplayer_peer = p
	role = Role.CLIENT
	host_name = address
	_connect_left = CONNECT_TIMEOUT
	set_process(true)
	return true


## Tear the session down and go back to being a local game. Safe to call when
## there is no session, which is why every exit path just calls it.
func leave() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	# Godot keeps routing RPCs at a peer that has been closed but not cleared,
	# and the errors arrive one per call with nothing naming the cause.
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	_close_discovery()
	_close_browser()
	role = Role.OFFLINE
	players.clear()
	machines.clear()
	host_name = ""
	_next_net_id = 1
	set_process(false)


# --- the roster --------------------------------------------------------------

## Seat a machine's humans. Host only: net_ids are handed out here and nowhere
## else, so they cannot collide.
func _seat_machine(peer_id: int, count: int, machine_name: String, team: int) -> void:
	var seated := 0
	for i in mini(count, MAX_LOCAL):
		if players.size() >= MAX_PLAYERS:
			break
		var id := _next_net_id
		_next_net_id += 1
		players[id] = {
			"machine": peer_id,
			"local": i,
			"team": team,
			"name": ("%s %d" % [machine_name, i + 1]) if count > 1 else machine_name,
		}
		seated += 1
	_assign_teams()


## AUTO SIDES ARE DEALT PER MACHINE, NOT PER PLAYER, and the loop is over
## machines for that reason: a sofa of four dealt round-robin across two sides
## would put the people sitting next to each other on opposite teams, which is
## the one arrangement a couch game must never produce by default. A machine that
## asked for a side keeps it; the rest fill the emptiest side in roster order.
func _assign_teams() -> void:
	var teams := maxi(GameState.active_teams(), 1)
	if GameState.free_for_all:
		# Everybody is their own side; the index is the seat, exactly as it is
		# for a local free-for-all.
		var seat := 0
		for id: int in roster():
			players[id]["team"] = seat % GameState.MAX_TEAMS
			seat += 1
		return
	var load_per := {}
	for t in teams:
		load_per[t] = 0
	# How many humans each machine seats, counted ONCE up front. The balance is
	# per machine but the load is per PERSON — a sofa of four and a machine with
	# one player on it are not the same weight on a side.
	var seats := {}
	for id: int in roster():
		var m := int(players[id]["machine"])
		seats[m] = int(seats.get(m, 0)) + 1

	var machine_team := {}
	# PASS ONE: machines that already have a side keep it — whether they asked for
	# one or were dealt it on an earlier call. Keeping it is what makes joining
	# STABLE: a third machine arriving must not re-shuffle the two already sitting
	# there, which from their side would look like the lobby changing its mind.
	#
	# EVERY SIDE TAKEN IN THIS PASS MUST BE COUNTED. Leaving them out was worth a
	# bug on its own: `_seat_machine` re-runs this after every join, so by the
	# second machine the first one's side was already set and invisible to the
	# load count — and the emptiest side was still the one the first machine was
	# on. Two machines of four came out 8 v 0.
	for id: int in roster():
		var m := int(players[id]["machine"])
		if machine_team.has(m):
			continue
		var want := int(players[id]["team"])
		if want >= 0 and want < teams:
			machine_team[m] = want
			load_per[want] = int(load_per[want]) + int(seats[m])
	# PASS TWO: everyone else onto the emptiest side, a whole machine at a time,
	# walked in roster order so every peer computes the identical answer.
	for id: int in roster():
		var m := int(players[id]["machine"])
		if machine_team.has(m):
			continue
		var best := 0
		for t in teams:
			if int(load_per[t]) < int(load_per[best]):
				best = t
		machine_team[m] = best
		load_per[best] = int(load_per[best]) + int(seats[m])
	for id: int in roster():
		players[id]["team"] = int(machine_team.get(int(players[id]["machine"]), 0))


## A machine asks for a side. Routed through the host so one authority answers,
## and the whole roster comes back rather than a patch — it is a dozen entries
## changed rarely, and a patch protocol here would be the kind of complexity that
## earns nothing.
@rpc("any_peer", "call_remote", "reliable")
func _request_team(team: int) -> void:
	if not is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	for id: int in players:
		if int(players[id]["machine"]) == from:
			players[id]["team"] = team
	_assign_teams()
	_push_roster()


func choose_team(team: int) -> void:
	_want_team = team
	if not online():
		return
	if is_host():
		for id: int in players:
			if int(players[id]["machine"]) == 1:
				players[id]["team"] = team
		_assign_teams()
		_push_roster()
	else:
		_request_team.rpc_id(1, team)


func _push_roster() -> void:
	_take_roster.rpc(players, machines)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _take_roster(rows: Dictionary, machine_rows: Dictionary) -> void:
	players = rows
	machines = machine_rows
	roster_changed.emit()


## A client introduces itself. The host decides whether it may sit down — this is
## the one place a version mismatch can still be reported to a human, because
## after this point the two builds disagree about bytes and every later failure
## is silent.
@rpc("any_peer", "call_remote", "reliable")
func _announce(protocol: int, count: int, machine_name: String, team: int) -> void:
	if not is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_refuse.rpc_id(from, "Different game version (theirs %d, ours %d)"
			% [protocol, PROTOCOL])
		return
	if players.size() + count > MAX_PLAYERS:
		_refuse.rpc_id(from, "Session is full (%d of %d players)"
			% [players.size(), MAX_PLAYERS])
		return
	machines[from] = {"name": machine_name, "count": count, "protocol": protocol}
	_seat_machine(from, count, machine_name, team)
	_push_roster()
	_welcome.rpc_id(from, players, machines)


@rpc("authority", "call_remote", "reliable")
func _welcome(rows: Dictionary, machine_rows: Dictionary) -> void:
	players = rows
	machines = machine_rows
	roster_changed.emit()
	session_joined.emit()


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	leave()
	session_failed.emit(reason)


# --- match launch ------------------------------------------------------------

## THE HOST SHIPS THE WHOLE MATCH SETUP, INCLUDING EVERY SEED. Anything that must
## agree across machines and is currently a `randf()` has to arrive from here, or
## the two builds generate different worlds and every symptom afterwards looks
## like a replication bug. `planet_seed` is the load-bearing one — the procedural
## map is built from it, so a client that rolled its own would walk into
## structures nobody else can see.
func launch_config() -> Dictionary:
	return {
		"protocol": PROTOCOL,
		"map": GameState.map_index,
		"mode": GameState.mode,
		"universe": GameState.universe,
		"planet": GameState.planet,
		"planet_seed": GameState.planet_seed,
		"time": GameState.time_of_day,
		"ttk": GameState.ttk,
		"teams": GameState.team_count,
		"ffa": GameState.free_for_all,
		"size": GameState.team_size,
		"skill": GameState.ai_skill,
		"classes": GameState.class_mode,
		"targets": GameState.score_targets,
		"rotate": GameState.rotate_maps,
		"world_seed": randi(),
	}


## Everything the host just decided, applied on a client. `human_players` is
## deliberately NOT in the payload: it means "viewports on THIS machine" and is
## the one setting that is genuinely per-machine.
func apply_config(cfg: Dictionary) -> void:
	GameState.map_index = int(cfg["map"])
	GameState.mode = int(cfg["mode"])
	GameState.universe = int(cfg["universe"])
	GameState.planet = int(cfg["planet"])
	GameState.time_of_day = int(cfg["time"])
	GameState.ttk = int(cfg["ttk"])
	GameState.team_count = int(cfg["teams"])
	GameState.free_for_all = bool(cfg["ffa"])
	GameState.team_size = int(cfg["size"])
	GameState.ai_skill = int(cfg["skill"])
	GameState.class_mode = int(cfg["classes"])
	GameState.score_targets = (cfg["targets"] as Dictionary).duplicate()
	GameState.rotate_maps = bool(cfg["rotate"])
	world_seed = int(cfg["world_seed"])
	# LAST, and after `reset_match` can no longer overwrite it: the seed is the
	# map. Main reads it while building the level, so it has to be the host's by
	# the time the scene changes.
	GameState.planet_seed = int(cfg["planet_seed"])


## The one shared RNG stream for anything both machines must agree on but the
## host does not individually announce. The storm and the royale scatter take it;
## the AI's aim wobble deliberately does NOT (it is cosmetic on a client, and
## sharing it would be bytes spent to make two machines wrong in the same way).
var world_seed := 0


## Host: go. Sends the setup, then every machine changes scene on its own.
func start_match() -> void:
	if not is_host():
		return
	GameState.planet_seed = int(Time.get_unix_time_from_system()) ^ (randi() & 0xffff)
	var cfg := launch_config()
	world_seed = int(cfg["world_seed"])
	_launch.rpc(cfg)
	launching.emit()


@rpc("authority", "call_remote", "reliable")
func _launch(cfg: Dictionary) -> void:
	if int(cfg.get("protocol", -1)) != PROTOCOL:
		session_failed.emit("Host is running a different game version")
		return
	apply_config(cfg)
	launching.emit()


# --- connection events -------------------------------------------------------

func _on_peer_connected(_id: int) -> void:
	pass   # nothing until it announces itself; see _announce


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	machines.erase(id)
	for net_id: int in players.keys():
		if int(players[net_id]["machine"]) == id:
			players.erase(net_id)
	_assign_teams()
	_push_roster()


func _on_connected() -> void:
	_connect_left = 0.0
	_announce.rpc_id(1, PROTOCOL, _local_count, _local_name, _want_team)


func _on_connect_failed() -> void:
	leave()
	session_failed.emit("Could not connect to the host")


func _on_server_gone() -> void:
	leave()
	session_failed.emit("The host closed the session")


func _self_peer() -> int:
	if multiplayer.multiplayer_peer == null:
		return 1
	return multiplayer.get_unique_id()


# --- LAN discovery -----------------------------------------------------------
#
# A HOST HAS TO BE FINDABLE WITHOUT SOMEBODY READING AN IP OUT LOUD. That is the
# whole feature: at a LAN party the address is the one piece of setup nobody
# should have to type. A plain UDP broadcast does it in thirty lines, where the
# alternatives (a rendezvous service, mDNS) are a dependency and a daemon for a
# problem that only exists on one subnet.

func _open_discovery() -> void:
	_discovery = PacketPeerUDP.new()
	if _discovery.bind(DISCOVERY_PORT) != OK:
		# Not fatal: somebody else has the port, so this session is join-by-IP
		# only. Refusing to host over it would be the wrong trade.
		_discovery = null


func _close_discovery() -> void:
	if _discovery != null:
		_discovery.close()
		_discovery = null


func _close_browser() -> void:
	if _browser != null:
		_browser.close()
		_browser = null
	_browse_left = 0.0


## Look for sessions on this subnet. Answers arrive on `browse_result`.
func browse() -> void:
	_close_browser()
	_found = []
	_browser = PacketPeerUDP.new()
	_browser.set_broadcast_enabled(true)
	if _browser.bind(0) != OK:
		browse_result.emit([])
		return
	_browser.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_browser.put_packet(DISCOVERY_MAGIC.to_utf8_buffer())
	_browse_left = BROWSE_TIMEOUT
	set_process(true)


func _process(delta: float) -> void:
	_poll_discovery()
	_poll_browser(delta)
	_poll_connect(delta)
	if role == Role.OFFLINE and _browse_left <= 0.0:
		set_process(false)


func _poll_discovery() -> void:
	if _discovery == null:
		return
	while _discovery.get_available_packet_count() > 0:
		var packet := _discovery.get_packet()
		if packet.get_string_from_utf8() != DISCOVERY_MAGIC:
			continue
		var reply := JSON.stringify({
			"magic": DISCOVERY_MAGIC,
			"protocol": PROTOCOL,
			"name": host_name,
			"players": players.size(),
			"max": MAX_PLAYERS,
			"map": GameState.MAPS[GameState.map_index]["name"],
			"mode": GameState.MODE_NAMES.get(GameState.mode, "?"),
		})
		_discovery.set_dest_address(_discovery.get_packet_ip(),
			_discovery.get_packet_port())
		_discovery.put_packet(reply.to_utf8_buffer())


func _poll_browser(delta: float) -> void:
	if _browser == null:
		return
	while _browser.get_available_packet_count() > 0:
		var text := _browser.get_packet().get_string_from_utf8()
		var ip := _browser.get_packet_ip()
		var row: Variant = JSON.parse_string(text)
		if row is Dictionary and str(row.get("magic", "")) == DISCOVERY_MAGIC:
			var entry: Dictionary = row
			entry["address"] = ip
			_found.append(entry)
	_browse_left -= delta
	if _browse_left <= 0.0:
		_close_browser()
		browse_result.emit(_found)


## TWO WINDOWS ON ONE DESK, which is the only way anybody is going to test this
## without two machines in the room. The same argument as `-- --debug`: the game
## is built for a situation the developer is not in, so there is a switch that
## puts them in it.
##
##     godot --path godot -- --host              open a session and wait
##     godot --path godot -- --join 192.168.1.5  join one (default 127.0.0.1)
##     godot --path godot -- --host --seats 2    ...with two split-screen players
##
## Read from the USER args (after the bare `--`) for the reason already on record
## in `GameState._read_cmdline`: Godot eats several of these itself otherwise.
## Returns true if it took the machine into a session, which is the menu's cue to
## open the lobby instead of the front screen.
func boot_from_cmdline() -> bool:
	var args := OS.get_cmdline_user_args()
	var seats := 1
	var at := args.find("--seats")
	if at >= 0 and at + 1 < args.size():
		seats = clampi(int(args[at + 1]), 1, MAX_LOCAL)
	GameState.human_players = seats
	if "--host" in args:
		return host(seats, "HOST")
	at = args.find("--join")
	if at < 0:
		return false
	var address := "127.0.0.1"
	if at + 1 < args.size() and not args[at + 1].begins_with("--"):
		address = args[at + 1]
	return join(address, seats, "CLIENT")


## A client that never hears back gets told so. Without this the screen sits on
## "connecting" forever, which is indistinguishable from a hung game.
func _poll_connect(delta: float) -> void:
	if role != Role.CLIENT or _connect_left <= 0.0:
		return
	_connect_left -= delta
	if _connect_left <= 0.0:
		leave()
		session_failed.emit("No answer from the host")
