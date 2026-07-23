extends Node3D

## The weapon-feel batch: the split grip, the new sights, stance spread, and the
## no-ADS-while-running rule.
##
##   godot --headless --path godot tests/weapon_feel.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()

	# --- the grip split ---------------------------------------------------
	print("== the grip split ==")
	var plain := _weapon(Weapon.Class.SOLDIER, {})
	var gripped := _weapon(Weapon.Class.SOLDIER, {"grip": true})
	var foregripped := _weapon(Weapon.Class.SOLDIER, {"foregrip": true})
	var base_hip := plain.current_spread_deg()
	var base_kick: float = plain._profile["cam_recoil"]
	print("  base hip %.2f kick %.3f | GRIP hip %.2f kick %.3f | FOREGRIP hip %.2f kick %.3f" % [
		base_hip, base_kick, gripped.current_spread_deg(), gripped._profile["cam_recoil"],
		foregripped.current_spread_deg(), foregripped._profile["cam_recoil"]])
	_expect(gripped.current_spread_deg() < base_hip, "IMPROVED GRIP tightens hip fire")
	_expect(is_equal_approx(gripped._profile["cam_recoil"], base_kick),
		"...and leaves the kick alone now")
	_expect(foregripped._profile["cam_recoil"] < base_kick, "FRONT GRIP cuts the kick")
	_expect(is_equal_approx(foregripped.current_spread_deg(), base_hip),
		"...and leaves the hip spread alone")

	# --- the new sights ---------------------------------------------------
	print("\n== the new sights ==")
	var dot := _weapon(Weapon.Class.SOLDIER, {"sight": Loadout.Sight.RED_DOT})
	var scope := _weapon(Weapon.Class.SOLDIER, {"sight": Loadout.Sight.SCOPE})
	var scope4x := _weapon(Weapon.Class.SOLDIER, {"sight": Loadout.Sight.SCOPE_4X})
	print("  red dot: reddot %s holo %s scope %s | 4x: scope %s zoom %.0f vs scope zoom %.0f" % [
		dot.has_reddot(), dot.has_holo(), dot.has_scope(),
		scope4x.has_scope(), scope4x.zoom_fov(), scope.zoom_fov()])
	_expect(dot.has_reddot() and dot.has_holo() and not dot.has_scope(),
		"the red dot is a clear-view optic, not a scope")
	_expect(scope4x.has_scope(), "the 4x is a scope")
	_expect(scope4x.zoom_fov() < scope.zoom_fov(),
		"...zoomed further in than the plain scope (smaller FOV)")

	# --- stance spread ----------------------------------------------------
	print("\n== stance spread ==")
	var p := await _spawn(Vector3(0.0, 0.0, 0.0))
	await _frames(4)
	p._update_stance_spread(Vector2.ZERO, false)
	var still := p.weapon.stance_spread_mult
	p._update_stance_spread(Vector2(0.0, 1.0), false)   # moving
	var moving := p.weapon.stance_spread_mult
	p._update_stance_spread(Vector2.ZERO, true)         # crouched still
	var crouched := p.weapon.stance_spread_mult
	print("  still %.2f | moving %.2f | crouched %.2f" % [still, moving, crouched])
	_expect(is_equal_approx(still, 1.0), "standing still is the baseline")
	_expect(moving > still, "moving widens the cone")
	_expect(crouched < still, "crouching tightens it")
	# ...and the widening actually reaches the weapon's spread.
	p.weapon.stance_spread_mult = moving
	var wide := p.weapon.current_spread_deg()
	p.weapon.stance_spread_mult = 1.0
	var tight := p.weapon.current_spread_deg()
	_expect(wide > tight, "the multiplier actually widens the fired cone")

	# --- crouch lowers the kick too ---------------------------------------
	print("\n== crouch lowers kick ==")
	print("  standing kick x%.2f, crouched kick x%.2f (CROUCH_RECOIL_MULT %.2f)" % [
		1.0, Player.CROUCH_RECOIL_MULT, Player.CROUCH_RECOIL_MULT])
	_expect(Player.CROUCH_RECOIL_MULT < 1.0, "a crouched shot kicks less")

	# --- no aiming while running ------------------------------------------
	print("\n== no ADS while running ==")
	# Stand and aim: should engage. Then run and aim: should drop.
	Input.action_press("kb_ads")
	Input.action_press("kb_forward")
	await _frames(6)
	var walk_aim := p.weapon.aiming
	Input.action_press("kb_sprint")
	await _frames(6)
	var run_aim := p.weapon.aiming
	Input.action_release("kb_sprint")
	await _frames(6)
	var slow_aim := p.weapon.aiming
	Input.action_release("kb_ads")
	Input.action_release("kb_forward")
	print("  walking-aim %s -> running-aim %s -> slowed-aim %s" % [
		walk_aim, run_aim, slow_aim])
	_expect(walk_aim, "you can aim while walking")
	_expect(not run_aim, "but not while running")
	_expect(slow_aim, "and it comes back when you slow down")

	print("\n==== %s ====" % ("WEAPON FEEL WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## A bare Weapon node with a class + mods applied, for reading its profile.
func _weapon(cls: int, mods: Dictionary) -> Weapon:
	var w := Weapon.new()
	add_child(w)
	w.set_class(cls, mods)
	return w


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.collision_layer = 1
	add_child(body)


func _spawn(at: Vector3) -> Player:
	var pl: Player = PLAYER.instantiate()
	pl.input_device = -1
	pl.position = at
	add_child(pl)
	await get_tree().physics_frame
	pl.pending = Loadout.starter()
	pl._apply_loadout()
	await get_tree().physics_frame
	return pl


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
