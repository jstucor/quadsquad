extends Node3D

## Does the arc blade guard actually BLOCK? Everything about it is invisible in
## play — the arc, the exhaustion pool, the break — so this drives a real Player
## through real physics frames with the real aim control held down, and measures
## what its health does.
##
## It presses the KEYBOARD binding rather than calling guard_up() directly, on
## purpose: the guard is reached through _physics_process -> _update_guard, and a
## test that calls the internals would have passed happily while the wiring in
## front of them was broken.
##
##   godot --headless --path godot tests/guard_block.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	# The guard is only ticked once the match is live, like everything else that
	# acts on its own.
	GameState.match_live = true
	# ...and only while its owner is alive. Without a floor the players fall past
	# BOUNDS_MIN_Y, _die(), and every reading after that is of a corpse — which is
	# exactly how this test first "found" a guard that stopped draining.
	_build_floor()

	var warden := await _spawn(_force_build(), Vector3.ZERO)
	var attacker := Node3D.new()
	add_child(attacker)

	print("== the build ==")
	print("  kit %s, armour %s, %.0f HP (frame %.0f x kit %.2f)" % [
		warden.loadout.kit_name(), warden.loadout.row_value(Loadout.Row.ARMOR),
		warden.max_health, warden.loadout.armor_stats()["health"],
		warden.loadout.kit_health()])
	print("  primary %s, melee %s" % [warden.weapon.display_name(), warden.weapon.is_melee()])
	_expect(warden.weapon.is_melee(), "Kinesis adept deploys holding a blade")
	_expect(is_equal_approx(warden.max_health,
		float(warden.loadout.armor_stats()["health"]) * warden.loadout.kit_health()),
		"max health is the frame times the kit multiplier")

	# --- the control actually raises it ------------------------------------
	print("\n== raising the guard ==")
	await _frames(2)
	_expect(not warden.guard_up(), "guard is DOWN with nothing held")
	Input.action_press("kb_ads")
	await _frames(2)
	_expect(warden.guard_up(), "guard is UP while the aim control is held")

	# --- a hit from the front --------------------------------------------
	print("\n== a hit from the front ==")
	attacker.global_position = Vector3(0.0, 0.0, -6.0)   # the player faces -Z
	var pool_before := warden.guard_level()
	warden.health = warden.max_health
	warden.take_damage(40.0, attacker)
	print("  40 dmg -> health %.1f/%.1f, pool %.3f -> %.3f" % [
		warden.health, warden.max_health, pool_before, warden.guard_level()])
	_expect(is_equal_approx(warden.health, warden.max_health),
		"a blocked hit costs no health")
	_expect(is_equal_approx(pool_before - warden.guard_level(),
		40.0 * Player.BLOCK_COST), "the pool paid BLOCK_COST per point stopped")

	# --- and one from behind ----------------------------------------------
	print("\n== a hit from behind ==")
	attacker.global_position = Vector3(0.0, 0.0, 6.0)
	warden.health = warden.max_health
	var pool_flank := warden.guard_level()
	warden.take_damage(40.0, attacker)
	print("  40 dmg -> health %.1f, pool %.3f (unchanged: %s)" % [
		warden.health, warden.guard_level(),
		is_equal_approx(pool_flank, warden.guard_level())])
	_expect(is_equal_approx(warden.health, warden.max_health - 40.0),
		"a hit outside the arc lands in full")

	# --- how much it is worth, and what happens when it runs out ----------
	print("\n== spending the pool ==")
	# From a FULL pool: the hits above already spent a third of it, and measuring
	# what is left is not measuring what the guard is worth.
	warden.pending = _force_build()
	warden._apply_loadout()
	await _frames(2)
	attacker.global_position = Vector3(0.0, 0.0, -6.0)
	warden.health = 100000.0     # measure the guard, not the dying
	var absorbed := 0.0
	var leaked := 0.0
	for _i in 400:
		if warden.guard_broken():
			break
		var before := warden.health
		warden.take_damage(10.0, attacker)
		var through: float = before - warden.health
		leaked += through
		absorbed += 10.0 - through
	print("  stopped %.0f damage before breaking (leaked %.0f), pool now %.3f" % [
		absorbed, leaked, warden.guard_level()])
	print("  the pool is worth 1/BLOCK_COST = %.0f damage" % (1.0 / Player.BLOCK_COST))
	_expect(warden.guard_broken(), "sustained fire BREAKS the guard")
	_expect(absorbed > 80.0, "a full guard is worth most of a hundred damage")
	_expect(is_equal_approx(leaked, 0.0),
		"NOTHING leaks through while the guard is up — not even the shot that breaks it")

	print("\n== while broken ==")
	await _frames(2)
	_expect(not warden.guard_up(), "a broken guard cannot be held up")
	warden.health = warden.max_health
	warden.take_damage(40.0, attacker)
	print("  40 dmg -> health %.1f (%.0f taken)" % [warden.health, warden.max_health - warden.health])
	_expect(is_equal_approx(warden.health, warden.max_health - 40.0),
		"a broken guard stops nothing")

	# --- recovery ---------------------------------------------------------
	print("\n== recovery ==")
	Input.action_release("kb_ads")
	var waited := 0.0
	for _i in 600:
		await _frames(1)
		waited += get_physics_process_delta_time()
		if not warden.guard_broken():
			break
	print("  un-broke after %.2fs at pool %.3f (recovers at %.2f)" % [
		waited, warden.guard_level(), Player.BLOCK_RECOVER_AT])
	_expect(not warden.guard_broken(), "the guard recovers once it is lowered")
	Input.action_press("kb_ads")
	await _frames(2)
	_expect(warden.guard_up(), "and can be raised again")

	# --- holding it up is not free ----------------------------------------
	# --- holding it up is FREE, and it holds every round ------------------
	print("\n== holding it ==")
	Input.action_release("kb_ads")
	warden.pending = _force_build()
	warden._apply_loadout()      # back to a full pool, guard down
	await _frames(2)
	Input.action_press("kb_ads")
	var held := 0.0
	for _i in 900:
		await _frames(1)
		held += get_physics_process_delta_time()
		if warden.guard_broken():
			break
	print("  held for %.2fs with nothing incoming: pool %.3f, still up %s" % [
		held, warden.guard_level(), warden.guard_up()])
	_expect(not warden.guard_broken(), "holding the guard costs nothing by itself")
	_expect(is_equal_approx(warden.guard_level(), 1.0), "the pool is untouched by time")

	# A burst, one round at a time: every single one has to be stopped, right up
	# to the one that empties the pool. This is the thing the player asked for —
	# hold the button, block the bullets.
	print("\n== a burst, round by round ==")
	attacker.global_position = warden.global_position + Vector3(0.0, 1.0, -8.0)
	warden.health = warden.max_health
	var rounds := 0
	while not warden.guard_broken() and rounds < 200:
		await _frames(1)
		warden.take_damage(22.0, attacker)   # a rifle round
		rounds += 1
	print("  %d rounds stopped, health %.1f/%.1f, pool %.3f, broken %s" % [
		rounds, warden.health, warden.max_health, warden.guard_level(), warden.guard_broken()])
	_expect(is_equal_approx(warden.health, warden.max_health),
		"a held guard took the whole burst without losing a point of health")
	_expect(warden.guard_broken(), "and the burst is what finally broke it")
	Input.action_release("kb_ads")

	# --- and nobody else may block ----------------------------------------
	print("\n== a trooper with a rifle ==")
	var legionary := await _spawn(Loadout.starter(), Vector3(20.0, 0.0, 0.0))
	Input.action_press("kb_ads")
	await _frames(2)
	attacker.global_position = legionary.global_position + Vector3(0.0, 0.0, -6.0)
	legionary.health = legionary.max_health
	legionary.take_damage(40.0, attacker)
	print("  %s aiming, 40 dmg -> health %.1f/%.1f, guard_up %s" % [
		legionary.weapon.display_name(), legionary.health, legionary.max_health, legionary.guard_up()])
	_expect(not legionary.guard_up(), "a gun cannot raise a guard")
	_expect(is_equal_approx(legionary.health, legionary.max_health - 40.0),
		"and it stops nothing")
	Input.action_release("kb_ads")

	print("\n==== %s ====" % ("BLOCKING WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## A Kinesis adept with the saber and a light frame — the DUELLIST's shape, bought
## the way a player would buy it.
func _force_build() -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(Loadout.Kit.ADEPT)
	l.weapon = Loadout.weapon_index(Weapon.Class.SABER)
	return l


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.collision_layer = 1   # the world layer players stand on
	add_child(body)


func _spawn(build: Loadout, at: Vector3) -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1      # the keyboard path, so Input.action_press drives it
	p.position = at
	add_child(p)
	await get_tree().physics_frame
	p.pending = build
	p._apply_loadout()
	await get_tree().physics_frame
	return p


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
