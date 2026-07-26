extends Node3D

## The FACTION class mode: the character-select screen, and the fact that it
## works in a mode that is not Conquest.
##
##   godot --headless --path godot tests/character_select.tscn
##
## Two things are being proven. First that the CLASSES setting is genuinely
## independent of the game mode — this whole test runs in DEATHMATCH, which
## before had no such thing as a faction class. Second that the screen keeps the
## buy screen's safety property: the cursor opens on SPAWN with nothing open, so
## a stick still held on the frame you died cannot re-roll the class you are
## about to deploy as.

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.class_mode = GameState.ClassMode.FACTION
	GameState.match_live = true
	_build_floor()

	print("== the setting, not the mode ==")
	_expect(GameState.faction_classes(),
		"faction classes are on in DEATHMATCH, not just Conquest")
	GameState.mode = GameState.Mode.ROYALE
	_expect(not GameState.faction_classes(),
		"...but royale still ignores it — everything there is scavenged")
	GameState.mode = GameState.Mode.DEATHMATCH

	var p := await _spawn()
	p.begin_deploy()
	await _frames(2)

	print("\n== on death ==")
	print("  selector on box %d (SPAWN is %d), open %s" % [
		p.buy_box, Player.PICK_SPAWN_BOX, p.buy_inside])
	_expect(p.buy_box == Player.PICK_SPAWN_BOX, "the cursor opens on SPAWN")
	_expect(not p.buy_inside, "and no box is open")

	print("\n== a stick full of accidents ==")
	var before := p.spawn_class
	for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT,
			Vector2i.DOWN, Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT]:
		p.apply_pick_input(dir, false, false)
	print("  class %s -> %s" % [before, p.spawn_class])
	_expect(p.spawn_class == before,
		"shoving the stick with no box open changes NOTHING")

	print("\n== choosing a class on purpose ==")
	p.buy_box = Player.PICK_CLASS_BOX
	p.apply_pick_input(Vector2i.ZERO, true, false)
	_expect(p.buy_inside, "accept opens the CLASS box")
	var was := p.faction_class_name()
	p.apply_pick_input(Vector2i.DOWN, false, false)
	print("  %s -> %s" % [was, p.faction_class_name()])
	_expect(p.faction_class_name() != was, "down walks the roster")
	p.apply_pick_input(Vector2i.ZERO, false, true)
	_expect(not p.buy_inside, "back closes it")
	var held := p.faction_class_name()
	p.apply_pick_input(Vector2i.DOWN, false, false)
	_expect(p.faction_class_name() == held, "...and the same shove stops working")

	print("\n== no post box outside Conquest ==")
	p.buy_box = Player.PICK_POST_BOX
	p.apply_pick_input(Vector2i.ZERO, true, false)
	_expect(not p.buy_inside,
		"the deploy-post box is dead in a mode with no command posts")

	print("\n== deploying ==")
	for _i in 400:
		await _frames(1)
		if p.deploy_armed():
			break
	p.buy_box = Player.PICK_CLASS_BOX
	p.apply_pick_input(Vector2i.ZERO, true, false)
	p.apply_pick_input(Vector2i.ZERO, false, true)
	_expect(not p.is_alive(), "accept on a category box does NOT deploy")
	p.buy_box = Player.PICK_SPAWN_BOX
	var want := p.faction_class_name()
	p.apply_pick_input(Vector2i.ZERO, true, false)
	await _frames(2)
	print("  alive %s holding %s (picked %s)" % [
		p.is_alive(), p.loadout.weapon_name(), want])
	_expect(p.is_alive(), "accept on SPAWN deploys")
	var picked := Loadout.faction_build(p.faction_class_index())
	_expect(p.loadout.weapon_name() == picked.weapon_name(),
		"and you deploy holding exactly the class you chose")
	_expect(p.loadout.character_style() == picked.character_style(),
		"...wearing its body, not a generic trooper")

	print("\n==== %s ====" % ("CHARACTER SELECT WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 2.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.collision_layer = 1
	add_child(body)


func _spawn() -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	add_child(p)
	await get_tree().physics_frame
	return p


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
