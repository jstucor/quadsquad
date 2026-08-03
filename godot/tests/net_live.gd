extends Node
## TWO REAL PROCESSES, ONE REAL SOCKET. `net_session.tscn` asks whether the rules
## are right; this asks whether they reach the other machine — and those fail in
## completely different ways. Everything below goes over ENet on the loopback
## address through the same node paths a real match uses, because the thing most
## likely to be wrong about an RPC is not its contents but WHERE IT IS ADDRESSED:
## Godot routes by node path, and a path that does not exist on the far side
## fails silently as far as play is concerned.
##
## It runs itself. With no arguments it is the HOST and launches its own client;
## with `-- --client` it is the client. So:
##
##     godot --headless --path godot tests/net_live.tscn
##
## WHAT IT PROVES, in order, and each one is a different piece of plumbing:
##   1. a client finds the host and is seated          — the session handshake
##   2. the host builds a proxy for the client's body  — the info record
##   3. the proxy lands where the client actually is   — the snapshot layout
##   4. shooting the proxy hurts the real body         — damage routed to its owner
##   5. and the confirmation comes back                — the return path
##
## Step 4 is the one worth the whole file. It is the only test in the project
## that exercises a hit crossing a machine boundary, and it is the mechanism the
## entire combat model rests on: the shooter detects, the owner applies.

## Deliberately loose. This test is measuring correctness over a socket, not
## latency, and a headless Godot starting up under a busy machine can easily take
## several seconds before its first frame.
const CONNECT_WAIT := 15.0
const EXCHANGE_WAIT := 10.0
const CLIENT_LIFETIME := 40.0

## Where the client parks its body. Arbitrary, but far from the origin and on no
## axis — a layout bug that zeroed a field would still pass at (0, 0, 0), and one
## that swapped two would still pass at (5, 5, 5).
const CLIENT_SPOT := Vector3(23.5, 4.25, -61.75)
const SHOT_DAMAGE := 34.0

## The stand-in for a body. Only what the pump reads, plus a record of what
## arrived — see `net_session.gd`, which uses the same shape for the same reason.
class FakeBody extends Node3D:
	var team := 0
	var health := 100.0
	var max_health := 100.0
	var model: Node3D = null
	var weapon: Node = null
	var head: Node3D = null
	var loadout: Loadout = null
	var took := 0.0
	var confirms := 0
	var last_headshot := false

	func is_alive() -> bool:
		return health > 0.0

	func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
		took += amount
		health -= amount
		# Exactly what a real Player does, and the reason this stub has to do it:
		# the confirmation is raised by the VICTIM, which is the only thing that
		# knows the damage survived. That is what makes the return trip real.
		if attacker != null and attacker.has_method("on_hit_confirmed"):
			attacker.on_hit_confirmed(headshot, health <= 0.0)

	func on_hit_confirmed(headshot: bool, _killed: bool) -> void:
		confirms += 1
		last_headshot = headshot


var _is_client := false
var _pump: NetSync
var _body: FakeBody
var _left := CONNECT_WAIT
var _stage := "connecting"
var _failures := 0
var _child := -1


func _ready() -> void:
	_is_client = "--client" in OS.get_cmdline_user_args()
	# THE PATH THE RPCs TRAVEL. `/root/Main/NetSync` in a real match, so the stub
	# parent is named "Main" here too — this is precisely the thing being tested
	# and faking it differently would test nothing.
	var main := Node.new()
	main.name = "Main"
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame

	if _is_client:
		_start_client(main)
	else:
		_start_host(main)


func _start_host(main: Node) -> void:
	print("\n=== NET LIVE (host) ===\n")
	GameState.team_count = 2
	GameState.free_for_all = false
	if not Net.host(1, "HOST"):
		_fail("could not open the port — is another session already running?")
		_finish()
		return
	_pump = NetSync.new()
	main.add_child(_pump)
	_body = FakeBody.new()
	_body.team = 0
	add_child(_body)
	_body.global_position = Vector3(0.0, 0.0, 0.0)
	_pump.own(_body, Net.local_ids()[0])
	_spawn_client()


func _start_client(main: Node) -> void:
	# Nothing is printed from the client: two processes writing to one terminal
	# interleave, and the host is the one being asserted. It exists to be talked
	# to, and it says so only if it cannot connect at all.
	Net.session_failed.connect(func(reason: String) -> void:
		printerr("[client] %s" % reason))
	Net.join("127.0.0.1", 1, "CLIENT")
	_pump = NetSync.new()
	main.add_child(_pump)
	_body = FakeBody.new()
	_body.team = 1
	add_child(_body)
	_body.global_position = CLIENT_SPOT
	_left = CLIENT_LIFETIME
	Net.session_joined.connect(_on_client_seated)


func _on_client_seated() -> void:
	var mine := Net.local_ids()
	if not mine.is_empty():
		_pump.own(_body, mine[0])


func _spawn_client() -> void:
	var project := ProjectSettings.globalize_path("res://")
	_child = OS.create_process(OS.get_executable_path(), [
		"--headless", "--path", project, "tests/net_live.tscn", "--", "--client"])
	if _child <= 0:
		_fail("could not launch the client process")
		_finish()


func _process(delta: float) -> void:
	_left -= delta
	if _is_client:
		if _left <= 0.0 or not Net.online():
			get_tree().quit(0)
		return
	match _stage:
		"connecting": _watch_connect()
		"exchanging": _watch_exchange(delta)
	if _left <= 0.0:
		_fail("timed out at stage '%s'" % _stage)
		_finish()


func _watch_connect() -> void:
	if Net.player_count() < 2:
		return
	print("  OK    a client found the host and was seated (%d in the session)"
		% Net.player_count())
	var sides := {}
	for id: int in Net.roster():
		sides[Net.team_of(id)] = true
	_check(sides.size() == 2, "the two machines were dealt opposite sides")
	_stage = "exchanging"
	_left = EXCHANGE_WAIT


func _watch_exchange(_delta: float) -> void:
	var proxy: NetPlayer = null
	for p: NetPlayer in _pump.proxies():
		proxy = p
	if proxy == null:
		return   # the info record has not arrived yet
	# The proxy eases toward each snapshot rather than snapping to it, so give it
	# until its position has actually settled before reading it.
	if proxy.global_position.distance_to(CLIENT_SPOT) > 0.05:
		return
	print("  OK    the host built a proxy for the client's body")
	print("  OK    and it landed where the client actually is: %s"
		% str(proxy.global_position))
	_check(proxy.team == 1, "the proxy carries the right side")

	# THE ROUND TRIP. Shooting the proxy has to hurt the body it stands for, on
	# the other machine, and the confirmation has to come back here.
	proxy.take_damage(SHOT_DAMAGE, _body, true)
	_stage = "waiting for the hit to come back"
	_left = EXCHANGE_WAIT
	await get_tree().create_timer(2.0).timeout
	_check(_body.confirms > 0,
		"a shot at the proxy was applied by its owner and confirmed back (%d)"
			% _body.confirms)
	_check(_body.last_headshot,
		"and the headshot flag survived both legs of the trip")
	_finish()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _fail(what: String) -> void:
	print("  FAIL  %s" % what)
	_failures += 1


func _finish() -> void:
	if _child > 0:
		OS.kill(_child)
	Net.leave()
	print("")
	if _failures == 0:
		print("==== THE WIRE WORKS ====")
	else:
		print("==== %d FAILURE%s ====" % [_failures, "" if _failures == 1 else "S"])
	get_tree().quit(1 if _failures > 0 else 0)
