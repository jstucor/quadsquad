extends Node
## A REAL NETWORKED MATCH, IN TWO REAL PROCESSES. `net_live.tscn` proves the wire
## carries a body and a hit; this proves the GAME does — Main builds its
## viewports, the host fills the teams with AI, the map is generated from one
## seed on both machines, and each side ends up with a complete picture of the
## match made of its own bodies plus everybody else's as proxies.
##
## THE ASSERTION THAT MATTERS IS THAT THE TWO WORLDS AGREE. Each machine counts
## the same number of combatants, and every body is owned by exactly one of them.
## A mismatch is the shape of nearly every networking bug worth having: AI filled
## twice, a client generating its own map, a body that was never announced.
##
## Run:  godot --headless --path godot tests/net_match.tscn
##
## It launches its own client. The client writes its tally to a file rather than
## reporting over the wire, because by the time it has a tally its own test scene
## is long gone — `change_scene_to_file` frees it, and the observer that survives
## is parked on the ROOT with no way back into a session message.

const HOST_LOOK_AT := 30.0     # seconds into the match before the host counts
const CLIENT_LOOK_AT := 20.0
const CONNECT_WAIT := 12.0

## What each side should end up owning, given the setup below: one human each,
## and the host carrying the AI that fills both sides to `team_size`.
const TEAM_SIZE := 2


## Survives the scene change into the match, which the test scene does not.
class Observer extends Node:
	var client := false
	var left := 0.0
	var done := false

	func _process(delta: float) -> void:
		left -= delta
		if left > 0.0 or done:
			return
		done = true
		var main := get_tree().current_scene
		var own := 0
		var proxies := -1
		if main != null and main.get("sync") != null:
			own = main.sync._own.size()
			proxies = main.sync.proxies().size()
		var tally := {
			"scene": main.name if main != null else "<none>",
			"combatants": GameState.combatants.size(),
			"own": own,
			"proxies": proxies,
			"seed": GameState.planet_seed,
			"map": GameState.map_index,
		}
		if not client:
			Judge.run(tally)
			return
		# The client REPORTS TO A FILE rather than over the session. By now its
		# own test scene has been freed by the scene change and the only thing
		# left of it is this observer, which has no route back into a message —
		# and the host is about to tear the session down anyway.
		var f := FileAccess.open(NetMatchPaths.CLIENT_REPORT, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(tally))
			f.close()
		get_tree().quit(0)


## A holder for the path, so both the inner classes and the script body can name
## it: a `const` on the outer script is not in scope inside an inner class.
class NetMatchPaths:
	const CLIENT_REPORT := "user://net_match_client.json"


## The host's verdict. A static holder so the Observer can reach it after its own
## test scene has been freed.
class Judge:
	static var failures := 0

	static func check(ok: bool, what: String) -> void:
		print("  %s  %s" % ["OK  " if ok else "FAIL", what])
		if not ok:
			failures += 1

	static func run(host_tally: Dictionary) -> void:
		print("")
		var client_tally := _read_client()
		check(str(host_tally["scene"]) == "Main", "the host booted the match")
		check(not client_tally.is_empty()
			and str(client_tally.get("scene", "")) == "Main",
			"the client booted the match too")
		if client_tally.is_empty():
			_finish()
			return
		print("    host   %s" % str(host_tally))
		print("    client %s" % str(client_tally))

		check(int(host_tally["seed"]) == int(client_tally["seed"]),
			"BOTH MACHINES GENERATED THE SAME WORLD (seed %d)"
				% int(host_tally["seed"]))
		check(int(host_tally["map"]) == int(client_tally["map"]),
			"...from the same map")
		check(int(host_tally["own"]) == 1 + TEAM_SIZE * 2 - 2,
			"the host owns its player and the AI that filled both sides (%d)"
				% int(host_tally["own"]))
		check(int(client_tally["own"]) == 1,
			"the client owns exactly its own player (%d)"
				% int(client_tally["own"]))
		check(int(host_tally["proxies"]) == int(client_tally["own"]),
			"the host has a proxy for every body the client owns")
		check(int(client_tally["proxies"]) == int(host_tally["own"]),
			"...and the client has one for every body the host owns")
		check(int(host_tally["combatants"]) == int(client_tally["combatants"]),
			"THE TWO WORLDS AGREE: %d combatants on each machine"
				% int(host_tally["combatants"]))
		check(int(host_tally["combatants"])
			== int(host_tally["own"]) + int(host_tally["proxies"]),
			"and every combatant is owned by exactly one machine — nothing extra")
		_finish()

	static func _read_client() -> Dictionary:
		if not FileAccess.file_exists(NetMatchPaths.CLIENT_REPORT):
			return {}
		var f := FileAccess.open(NetMatchPaths.CLIENT_REPORT, FileAccess.READ)
		if f == null:
			return {}
		var row: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		return row if row is Dictionary else {}

	static func _finish() -> void:
		print("")
		if failures == 0:
			print("==== A NETWORKED MATCH PLAYS ====")
		else:
			print("==== %d FAILURE%s ====" % [failures, "" if failures == 1 else "S"])
		Engine.get_main_loop().quit(1 if failures > 0 else 0)


var _child := -1


func _ready() -> void:
	var client := "--client" in OS.get_cmdline_user_args()
	# The setup is the host's to choose and the client inherits all of it (see
	# `Net.launch_config`) — except `human_players`, which is this machine's
	# viewport count and is deliberately never sent.
	GameState.human_players = 1
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.team_size = TEAM_SIZE
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = 0

	var obs := Observer.new()
	obs.client = client
	obs.left = CLIENT_LOOK_AT if client else HOST_LOOK_AT
	get_tree().root.add_child.call_deferred(obs)
	Net.launching.connect(_go)

	if client:
		Net.join("127.0.0.1", 1, "CLIENT")
		return

	print("\n=== NET MATCH ===")
	# A stale report from a previous run would be read as this run's answer.
	if FileAccess.file_exists(NetMatchPaths.CLIENT_REPORT):
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(NetMatchPaths.CLIENT_REPORT))
	if not Net.host(1, "HOST"):
		Judge.check(false, "could not open the port — another session running?")
		Judge._finish()
		return
	_child = OS.create_process(OS.get_executable_path(), [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"tests/net_match.tscn", "--", "--client"])
	await get_tree().create_timer(CONNECT_WAIT).timeout
	if Net.player_count() < 2:
		Judge.check(false, "the client never arrived")
		Judge._finish()
		return
	Judge.check(true, "the client connected and was seated")
	Net.start_match()


func _go() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
