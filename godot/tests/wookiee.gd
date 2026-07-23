extends Node3D

## The WOOKIEE, deployed rather than described: what it walks in with, how hard
## it is to kill, and what one pull of the bowcaster actually does to a body.
##
## kit_rules already proves the ALLOW-LISTS (who may buy what). This is the other
## half — that the build those lists produce works when it is standing on a map.
##
##   godot --headless --path godot tests/wookiee.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []
var _hits: Array[float] = []   # every `damaged` the dummy reported


func _ready() -> void:
	GameState.match_live = true
	_build_floor()

	var wook := await _spawn(_wookiee_build(Loadout.weapon_index(Weapon.Class.HMG)),
		Vector3.ZERO, 0)
	var dummy := await _spawn(Loadout.starter(), Vector3(0.0, 0.0, -4.0), 1)
	dummy.damaged.connect(func(amount: float) -> void: _hits.append(amount))
	await _frames(2)

	print("== deployed ==")
	print("  %s, %s, %s + %s" % [wook.loadout.kit_name(),
		wook.loadout.row_value(Loadout.Row.ARMOR),
		wook.weapon.display_name(),
		Weapon.PROFILES[wook.loadout.secondary_class()]["name"]])
	print("  %.0f HP (frame %.0f x kit %.2f), speed x%.3f" % [wook.max_health,
		wook.loadout.armor_stats()["health"], wook.loadout.kit_health(),
		float(wook.loadout.armor_stats()["speed"]) * wook.loadout.kit_speed()])
	_expect(wook.loadout.kit == Loadout.Kit.WOOKIEE, "it is a Wookiee")
	_expect(wook.loadout.secondary_class() == Weapon.Class.BOWCASTER,
		"...carrying the bowcaster, without having chosen it")
	_expect(wook.max_health > 160.0, "and it is the toughest thing on the map")
	_expect(wook.loadout.kit_speed() < 1.0, "...and the slowest")

	# --- one pull of the bowcaster ---------------------------------------
	print("\n== the bowcaster ==")
	wook._on_secondary = true
	wook.weapon.set_class(wook.loadout.secondary_class(),
		wook.loadout.mods_for(true))
	await _frames(2)
	var profile: Dictionary = Weapon.PROFILES[Weapon.Class.BOWCASTER]
	# Several pulls, because the cone is RANDOM: one pull says nothing about a
	# spread weapon, and the bloom has to be reset between them or what is being
	# measured is a saturated cone rather than the gun.
	#
	# They are fired at the weapon's OWN cadence, not as fast as the loop can go.
	# The bowcaster kicks the camera 0.19 rad, which at 4 m is most of a body
	# height, and a second pull before that has settled sails over the target —
	# measured as nine misses in ten, which is the gun working exactly as
	# specified and the harness firing it in a way no player could.
	var pulls := 10
	var settle := 60   # frames between pulls: one fire_interval, and then some
	var events: Array[int] = []
	var best := 0.0
	var landed := 0.0
	var heat_after := 0.0
	for _i in pulls:
		_hits.clear()
		# The dummy has to survive being measured: a bowcaster kills a standard
		# trooper in two pulls, and a corpse stops reporting damage — which reads
		# in the results as a weapon that suddenly cannot hit anything.
		dummy.health = 100000.0
		wook.weapon._bloom = 0.0
		wook.weapon.update_fire(true, true)
		await _frames(1)
		wook.weapon.update_fire(false, false)
		await _frames(settle)
		heat_after = wook.weapon.heat()
		var total := 0.0
		for h in _hits:
			total += h
		events.append(_hits.size())
		landed += total
		best = maxf(best, total)
	print("  %d pulls at 4 m: damage events per pull %s" % [pulls, str(events)])
	print("  best pull %.0f, mean %.0f (a quarrel is %.0f, %d of them)" % [
		best, landed / float(pulls), profile["damage"], int(profile["pellets"])])
	print("  heat per pull %.2f (%.1f pulls to lock out)" % [
		heat_after, 1.0 / float(profile["heat_per_shot"])])
	var multi := 0
	for n in events:
		if n > 1:
			multi += 1
	_expect(multi == 0,
		"a pull is ONE damage event, however many quarrels land — not three")
	_expect(best > float(profile["damage"]) * 1.5,
		"quarrels POOL: the best pull landed more than one quarrel's worth")
	_expect(heat_after > 0.3, "one pull costs a third of the heat pool")
	var whiffs := 0
	for n in events:
		if n == 0:
			whiffs += 1
	_expect(whiffs <= 2, "a body-sized target at 4 m is hit by nearly every pull")

	# --- the barrier is theirs and it works ------------------------------
	print("\n== the barrier ==")
	var shielded := await _spawn(_wookiee_build(
		Loadout.weapon_index(Weapon.Class.RPG), Loadout.Gadget.SHIELD),
		Vector3(12.0, 0.0, 0.0), 0)
	await _frames(2)
	shielded._use_gadget(0)
	await _frames(2)
	print("  %s with the shield up: %s" % [
		shielded.weapon.display_name(), shielded.shield_up()])
	_expect(shielded.shield_up(), "a Wookiee can raise the front shield")
	_expect(shielded.loadout.cost() <= Loadout.BUDGET,
		"and a rocket tube plus a barrier still fits the budget (%d)"
			% shielded.loadout.cost())

	# --- royale is not a class, and must not inherit the class gate --------
	print("\n== a royale scavenger ==")
	# Exactly what a crate does: it sets the field, it does not shop. Kit-locking
	# the heavy guns is a BUY-SCREEN rule, and a plain trooper who finds a rocket
	# tube on the ground has to be able to pick it up and fire it.
	var scav_build := Loadout.royale_start()
	scav_build.weapon = Loadout.weapon_index(Weapon.Class.RPG)
	var scav := await _spawn(scav_build, Vector3(-12.0, 0.0, 0.0), 1)
	await _frames(2)
	print("  %s trooper holding %s" % [scav.loadout.kit_name(),
		scav.weapon.display_name()])
	_expect(scav.weapon.display_name()
		== Weapon.PROFILES[Weapon.Class.RPG]["name"],
		"a class-free royale trooper still deploys with a scavenged rocket tube")

	print("\n==== %s ====" % ("THE WOOKIEE WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## Bought exactly as a player would: adopt the kit, then pick a primary. The
## sidearm and the armour are whatever adopting the kit handed over.
func _wookiee_build(primary: int, gadget := Loadout.Gadget.NONE) -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(Loadout.Kit.WOOKIEE)
	l.weapon = primary
	l.gadget = gadget
	return l


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


func _spawn(build: Loadout, at: Vector3, team: int) -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	p.position = at
	p.team = team
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
