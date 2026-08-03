extends Node
## 20v20 IN THE ORDINARY MODES.
##
## What this protects is a SPLIT that is easy to undo: `line` (what a MASSIVE
## trooper IS — a rifle and nothing else) and `thrifty` (what a crowd COSTS —
## soft bodies, half-rate stepping, crowd drawing). They used to be one flag, and
## the whole reason deathmatch could not field forty was that buying the cheap
## simulation also bought the stripped loadout.
##
## Every assertion here is therefore either "the big match got the SAVINGS" or
## "the big match kept the GAME". Both halves have to hold or the split has
## quietly collapsed back into one flag.

const MAIN := preload("res://scenes/main.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	print("\n==== big teams ====")
	if GameState == null or not GameState.has_method("crowded"):
		print("  FAIL: GameState did not load — every check below would be hollow")
		print("==== 1 FAILURES ====")
		get_tree().quit(1)
		return
	_check_ladder()
	_check_threshold()
	await _check_real_match()
	print("")
	if _fails.is_empty():
		print("==== BIG TEAMS HOLD ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _check_ladder() -> void:
	print("\n-- the menu can actually ask for twenty --")
	_ok(GameState.MAX_TEAM_SIZE >= 20,
		"MAX_TEAM_SIZE is %d — the modes cannot field 20 a side"
			% GameState.MAX_TEAM_SIZE)
	_ok(GameState.TEAM_SIZES.has(20), "20 is not on the offered ladder")
	_ok(int(GameState.TEAM_SIZES[-1]) <= GameState.MAX_TEAM_SIZE,
		"the ladder offers %d, past MAX_TEAM_SIZE %d"
			% [int(GameState.TEAM_SIZES[-1]), GameState.MAX_TEAM_SIZE])
	# The small end has to stay EXACT: that is where humans fill the slots and a
	# missing rung is a size a couch of three literally cannot select.
	for n in [1, 2, 3, 4]:
		_ok(GameState.TEAM_SIZES.has(n),
			"team size %d is not offered — humans fill those slots" % n)
	print("  ladder: %s   (max %d)" % [str(GameState.TEAM_SIZES),
		GameState.MAX_TEAM_SIZE])


## The threshold is BODIES, not mode. A small match must not be demoted to the
## cheap simulation, and a big one must not miss it.
func _check_threshold() -> void:
	print("\n-- thrift is decided by the roster, not the mode --")
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.free_for_all = false
	GameState.team_count = 2
	GameState.team_size = 4
	_ok(not GameState.crowded(), "a 4v4 was demoted to the cheap simulation")
	GameState.team_size = 20
	_ok(GameState.crowded(), "a 20v20 did not reach the cheap simulation")
	GameState.mode = GameState.Mode.MASSIVE
	_ok(GameState.crowded(), "MASSIVE is not crowded")
	print("  4v4 full fidelity, 20v20 thrifty, massive thrifty")
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.team_size = 4


## The one that matters: boot a REAL 20v20 deathmatch and count what turned up.
func _check_real_match() -> void:
	print("\n-- a real 20v20 deathmatch --")
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.class_mode = GameState.ClassMode.CUSTOM
	GameState.free_for_all = false
	GameState.team_count = 2
	GameState.team_size = 20
	GameState.human_players = 1
	GameState.map_index = GameState.procedural_map_index()
	GameState.rotate_maps = false

	# INSTANTIATED AS A CHILD, never `change_scene_to_file`: changing the scene
	# frees the CURRENT one, which is this test — so the `await` below would
	# resume on a freed node and the run would hang rather than fail. Same pattern
	# as tests/massive.gd, for the same reason.
	var main: Node = MAIN.instantiate()
	add_child(main)
	# The crowd is dealt in batches across frames, so this has to wait for the
	# queue to drain rather than sampling the frame after the scene loads.
	for i in 180:
		await get_tree().process_frame

	var bots: Array = []
	for c in GameState.combatants:
		if is_instance_valid(c) and c is Bot:
			bots.append(c)
	print("  %d bots on the field" % bots.size())
	# 2 sides x 20, less the one human seat.
	_ok(bots.size() >= 38, "expected ~39 bots at 20v20, got %d" % bots.size())
	if bots.is_empty():
		_fails.append("no bots at all — nothing below can be judged")
		return

	# --- the SAVINGS ---------------------------------------------------------
	var thrifty := 0
	var soft := 0
	var crowd_drawn := 0
	for b in bots:
		if b.thrifty:
			thrifty += 1
		if b.collision_mask == 1:
			soft += 1
		if b.model != null and b.model.crowd:
			crowd_drawn += 1
	_ok(thrifty == bots.size(),
		"only %d of %d bots took the cheap simulation" % [thrifty, bots.size()])
	_ok(soft == bots.size(),
		"only %d of %d dropped body-vs-body sweeps — that is the 13.9 ms one"
			% [soft, bots.size()])
	_ok(crowd_drawn == bots.size(),
		"only %d of %d are drawn as a crowd" % [crowd_drawn, bots.size()])
	print("  thrifty %d/%d   soft bodies %d   crowd-drawn %d"
		% [thrifty, bots.size(), soft, crowd_drawn])

	# --- and the GAME --------------------------------------------------------
	# THIS IS THE HALF THAT WOULD SILENTLY REGRESS. If a later edit re-merges the
	# two flags, every one of these turns into a line trooper and the mode still
	# "works" — it just stops being the game.
	var stripped := 0
	var with_gadgets := 0
	var distinct := {}
	for b in bots:
		if b.line:
			stripped += 1
		if b.loadout != null:
			if b.loadout.gadget != Loadout.Gadget.NONE \
					or b.loadout.gadget2 != Loadout.Gadget.NONE \
					or b.loadout.gadget3 != Loadout.Gadget.NONE:
				with_gadgets += 1
			distinct[b.loadout.build_name] = true
	_ok(stripped == 0,
		"%d of %d bots deployed as MASSIVE line troopers in a deathmatch"
			% [stripped, bots.size()])
	_ok(with_gadgets > 0,
		"not one bot in a 20v20 carries a gadget — the roster was stripped")
	_ok(distinct.size() >= 3,
		"only %d distinct builds across %d bots — a side should field a mix"
			% [distinct.size(), bots.size()])
	print("  line troopers %d (want 0)   carrying gadgets %d   distinct builds %d"
		% [stripped, with_gadgets, distinct.size()])
	print("  builds: %s" % str(distinct.keys()))
