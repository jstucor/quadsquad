extends Node3D

## The buy screen's new selector, driven through the real input path.
##
## The bug this rework exists to kill: dying while still holding a direction
## used to move a cursor that was sitting on the CLASS row, and a class change
## RESETS the entire build. So the first thing checked here is the one that
## matters — a stick shoved in every direction, on the frame you die, must not
## change a single thing about what you are holding.
##
##   godot --headless --path godot tests/buy_screen.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()
	var p := await _spawn()
	p.begin_deploy()
	await _frames(2)

	print("== on death ==")
	print("  selector on box %d of %d (SPAWN is %d), open %s" % [
		p.buy_box, Loadout.BUY_BOXES.size(), Player.SPAWN_BOX, p.buy_inside])
	_expect(p.buy_box == Player.SPAWN_BOX, "the selector opens on SPAWN, not on CLASS")
	_expect(not p.buy_inside, "and no box is open")

	# --- the accident, reproduced ----------------------------------------
	print("\n== a stick full of accidents ==")
	var before := _describe(p.pending)
	print("  build on death: %s" % before)
	for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i.LEFT, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		_nudge(p, dir)
	print("  after 8 shoves : %s" % _describe(p.pending))
	_expect(_describe(p.pending) == before,
		"NOTHING about the build changed — the whole point of the rework")
	_expect(not p.buy_inside, "and still nothing is open")

	# --- opening a box on purpose ----------------------------------------
	print("\n== opening CLASS on purpose ==")
	p.buy_box = 0            # CLASS
	_press_accept(p)
	await _frames(1)
	print("  open %s, row %d (%s)" % [p.buy_inside, p.buy_row,
		p.pending.row_label(p.buy_row)])
	_expect(p.buy_inside, "A opens the box the selector is on")
	_expect(p.buy_row == Loadout.Row.KIT, "and parks on its first line")
	# THE CLASS ROW WALKS CHARACTERS, NOT KIT ARCHETYPES (see
	# Loadout.custom_classes), so what has to change is the CLASS ON SCREEN —
	# `kit` is derived and two neighbours on the row share one (a Clone Trooper
	# and a Clone Engineer are both the CLONE kit). Asserting on `kit` was
	# asserting on the old meaning of the row and passed for the wrong reason.
	var class_before := p.pending.class_name_shown()
	_nudge(p, Vector2i.RIGHT)
	print("  right -> class %s" % p.pending.class_name_shown())
	_expect(p.pending.class_name_shown() != class_before,
		"inside the box, left/right DOES change it")

	print("\n== closing it again ==")
	_press_back(p)
	await _frames(1)
	var kit_now := p.pending.kit
	_nudge(p, Vector2i.RIGHT)
	_nudge(p, Vector2i.RIGHT)
	print("  closed %s, kit still %s" % [not p.buy_inside, p.pending.kit_name()])
	_expect(not p.buy_inside, "B closes the box")
	_expect(p.pending.kit == kit_now, "...and the same shoves stop changing anything")

	# --- deploying is a press on the SPAWN box ---------------------------
	print("\n== deploying ==")
	p.buy_box = 0
	_press_accept(p)     # opens CLASS instead of deploying
	await _frames(1)
	_expect(p.is_alive() == false, "A on a category box does NOT deploy")
	_press_back(p)
	await _frames(1)
	# Wait out the deploy floor, then press A on SPAWN.
	for _i in 400:
		await _frames(1)
		if p.deploy_armed():
			break
	print("  armed %s after the floor" % p.deploy_armed())
	p.buy_box = Player.SPAWN_BOX
	_press_accept(p)
	await _frames(2)
	print("  alive %s" % p.is_alive())
	_expect(p.is_alive(), "A on the SPAWN box deploys")

	# --- the cursor moves on the stick, and moving it changes NOTHING ------
	# Driven through the REAL physics path (keyboard movement keys), not the
	# logic shim above, because the thing being proven here is that the analog
	# cursor responds to the stick and that steering it never touches the build.
	print("\n== the cursor ==")
	p.begin_deploy()             # back into the buy screen (it deployed above)
	await _frames(2)
	var cur_before := p.buy_cursor
	var build_before := _describe(p.pending)
	Input.action_press("kb_right")
	for _i in 10:
		await _frames(1)
	Input.action_release("kb_right")
	Input.action_press("kb_forward")
	for _i in 10:
		await _frames(1)
	Input.action_release("kb_forward")
	print("  cursor %s -> %s" % [str(cur_before), str(p.buy_cursor)])
	_expect(p.buy_cursor.x > cur_before.x, "the stick moves the cursor right")
	_expect(p.buy_cursor.y < cur_before.y, "and forward moves it up the panel")
	_expect(p.buy_cursor.x <= 1.0 and p.buy_cursor.y >= 0.0, "and it stays on the panel")
	_expect(_describe(p.pending) == build_before,
		"moving the cursor changed NOTHING about the build")
	_expect(not p.buy_inside, "and opened no box")

	# --- every class has the two-slot GADGETS box now --------------------
	print("\n== the universal second gadget slot ==")
	for kit in [Loadout.Kit.FORCE, Loadout.Kit.CLONE, Loadout.Kit.WOOKIEE]:
		var l := Loadout.new()
		l.adopt_kit(kit)
		_expect(l.row_available(Loadout.Row.GADGET2),
			"%s has a second gadget slot" % l.kit_name())

	# --- HOW BIG THE POOL IS ------------------------------------------------
	#
	# The point of the row is that it reaches every character the universe has.
	# It used to offer the KIT archetypes — five in Star Wars, four in Warhammer
	# — while thirty-two authored classes sat one screen away in FACTION mode,
	# and nothing anywhere reported that as a fault because the row worked
	# perfectly. A count is the only thing that catches it.
	print("\n== the size of the pool ==")
	for u in [Loadout.Universe.STAR_WARS, Loadout.Universe.HALO,
			Loadout.Universe.WARHAMMER]:
		GameState.universe = u
		GameState.class_mode = GameState.ClassMode.CUSTOM
		var pool := Loadout.custom_classes(u)
		var authored := 0
		for side in Loadout.FACTION_ROSTERS[u]:
			authored += side.size()
		print("  %-14s class row %d, authored %d"
			% [Loadout.UNIVERSES[u]["name"], pool.size(), authored])
		_expect(pool.size() == authored,
			"the class row reaches every one of %s's characters" % Loadout.UNIVERSES[u]["name"])

		# ...and the cursor must be able to WALK all of them. A pool the cursor
		# cannot cross is the same bug wearing a bigger number: `step` refuses
		# anything over BUDGET, so a class whose own guns cost more than 200
		# would strand it.
		var l := Loadout.starter()
		var walked := 1
		while l.step(Loadout.Row.KIT, 1):
			walked += 1
		_expect(walked == pool.size(),
			"the cursor walks all %d of them (reached %d)" % [pool.size(), walked])

		# ...and each one can reach the universe's ordinary catalogue, which is
		# what `Loadout.custom_pool` is for. The Wookiee could hold TWO primaries.
		var narrowest := 999
		var worst := ""
		for i in pool.size():
			var b := Loadout.starter()
			b.adopt_character(i)
			var n := 0
			for w in Loadout.WEAPONS.size():
				if b.allows(Loadout.Row.WEAPON, w):
					n += 1
			if n < narrowest:
				narrowest = n
				worst = b.class_name_shown()
		print("    narrowest character is %s with %d primaries" % [worst, narrowest])
		_expect(narrowest >= 15,
			"%s can only reach %d primaries in CUSTOM" % [worst, narrowest])
	GameState.universe = Loadout.Universe.STAR_WARS

	print("\n==== %s ====" % ("BUY SCREEN WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## One shove of the stick, delivered the way the game reads it: pressed for a
## frame, then released so the latch re-arms.
func _nudge(p: Player, dir: Vector2i) -> void:
	p.apply_buy_input(dir, false, false)


func _press_accept(p: Player) -> void:
	p.apply_buy_input(Vector2i.ZERO, true, false)


func _press_back(p: Player) -> void:
	p.apply_buy_input(Vector2i.ZERO, false, true)


func _describe(l: Loadout) -> String:
	return "%s / %s / %s / armour %s / gadget %s" % [l.kit_name(),
		l.row_value(Loadout.Row.WEAPON), l.row_value(Loadout.Row.SECONDARY),
		l.row_value(Loadout.Row.ARMOR), l.row_value(Loadout.Row.GADGET)]


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
