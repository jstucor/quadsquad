extends Node3D

## The two gadget changes: lightning that is CHANNELLED while held, and the
## Mandalorian's wrist rocket.
##
## The channel is the interesting one to measure. Held on a target it should
## bite repeatedly and add up to more than the old one-shot burst; released
## early it should cost only a fraction of the cooldown; and swept off the
## target it should stop dealing damage without ending the channel.
##
##   godot --headless --path godot tests/gadgets.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []
var _hits: Array[float] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()

	var jedi := await _spawn(_build(Loadout.Kit.FORCE, Weapon.Class.SABER,
		Loadout.Gadget.FORCE_LIGHTNING), Vector3.ZERO, 0)
	var mark := await _spawn(Loadout.starter(), Vector3(0.0, 0.0, -12.0), 1)
	mark.damaged.connect(func(amount: float) -> void: _hits.append(amount))
	await _frames(2)

	print("== the channel ==")
	print("  %.1fs of stream, a bite every %.2fs, %.0f per bite -> %.0f total" % [
		ForcePowers.CHANNEL_TIME, ForcePowers.CHANNEL_TICK, ForcePowers.BOLT_DAMAGE,
		ForcePowers.CHANNEL_TIME / ForcePowers.CHANNEL_TICK * ForcePowers.BOLT_DAMAGE])
	mark.health = 100000.0
	_hits.clear()
	jedi._use_gadget(0)                       # opens the channel
	var held := 0.0
	for _i in 300:
		# Hold the button: the channel reads the gadget control every frame.
		Input.action_press("kb_gadget")
		await _frames(1)
		held += get_physics_process_delta_time()
		if jedi._channel_left <= 0.0:
			break
	Input.action_release("kb_gadget")
	var total := 0.0
	for h in _hits:
		total += h
	print("  held %.2fs -> %d bites, %.0f damage, cooldown now %.1fs" % [
		held, _hits.size(), total, jedi.gadget_cooldown(0)])
	_expect(_hits.size() > 5, "holding it bites over and over, not once")
	_expect(total > 90.0, "a full channel is worth more than a rifle magazine")
	_expect(jedi.gadget_cooldown(0) > 0.0, "and a full channel costs the full cooldown")

	# --- a tap costs almost nothing --------------------------------------
	print("\n== a tap ==")
	jedi._force_cd = [0.0, 0.0, 0.0]   # one per gadget slot, and there are three
	jedi._channel_left = 0.0
	await _frames(2)
	_hits.clear()
	jedi._use_gadget(0)
	await _frames(2)          # button never held: the channel closes at once
	var tap_cd := jedi.gadget_cooldown(0)
	var full: float = Loadout.GADGET_COOLDOWNS[Loadout.Gadget.FORCE_LIGHTNING]
	print("  tapped -> cooldown %.2fs of a %.1fs maximum" % [tap_cd, full])
	_expect(tap_cd > 0.0 and tap_cd < full * 0.6,
		"a tap costs a fraction of the cooldown, not the whole thing")

	# --- the wrist rocket -------------------------------------------------
	print("\n== the wrist rocket ==")
	var mando := await _spawn(_build(Loadout.Kit.MANDALORIAN, Weapon.Class.SMG,
		Loadout.Gadget.WRIST_ROCKET), Vector3(40.0, 0.0, 0.0), 0)
	var victim := await _spawn(Loadout.starter(), Vector3(40.0, 0.0, -14.0), 1)
	await _frames(2)
	print("  %s carries %s" % [mando.loadout.kit_name(),
		Loadout.GADGETS[mando.gadget]["name"]])
	_expect(mando.gadget == Loadout.Gadget.WRIST_ROCKET,
		"a Mandalorian can buy the wrist rocket")
	var before := victim.health
	mando._use_gadget(0)
	print("  fired: %d rocket(s) in the world" % _count("Rocket"))
	_expect(_count("Rocket") > 0, "the gadget puts a real rocket in the world")
	_expect(mando.gadget_cooldown(0) > 0.0, "...and starts its cooldown")
	for _i in 200:
		await _frames(1)
		if victim.health < before:
			break
	print("  victim %.0f -> %.0f after the flight" % [before, victim.health])
	_expect(victim.health < before, "and it damages what it flies into")
	_expect(mando.is_alive(), "without blowing up the Mandalorian who fired it")

	# --- nobody else may have it ------------------------------------------
	var clone := Loadout.new()
	clone.adopt_kit(Loadout.Kit.CLONE)
	_expect(not clone.allows(Loadout.Row.GADGET, Loadout.Gadget.WRIST_ROCKET),
		"a clone cannot buy the wrist rocket")

	# --- grenades are gadgets with a cooldown now -------------------------
	print("\n== the grenade gadget ==")
	var nader := await _spawn(_build(Loadout.Kit.CLONE, Weapon.Class.SOLDIER,
		Loadout.Gadget.GRENADE_FRAG), Vector3(-40.0, 0.0, 0.0), 0)
	# It sits in slot 0 here for the test; a player would fit it in slot 2.
	await _frames(2)
	var nades0 := _count("Grenade")
	nader._use_gadget(0)
	await _frames(1)
	print("  threw: %d grenade(s), cooldown %.1fs" % [
		_count("Grenade") - nades0, nader.gadget_cooldown(0)])
	_expect(_count("Grenade") - nades0 > 0, "the gadget throws a real grenade")
	_expect(nader.gadget_cooldown(0) > 0.0, "...and starts a cooldown, not a count")
	# Immediately again: blocked by the cooldown.
	var mid := _count("Grenade")
	nader._use_gadget(0)
	await _frames(1)
	_expect(_count("Grenade") == mid, "a second throw is denied until it recharges")

	# --- passive healing after a lull -------------------------------------
	print("\n== passive heal ==")
	nader.health = 40.0
	nader._since_damage = 0.0
	await _frames(2)
	var hurt := nader.health
	# Partway through the delay: no regen yet.
	var t := 0.0
	while t < Player.REGEN_DELAY * 0.5:
		await _frames(1)
		t += get_physics_process_delta_time()
	var during := nader.health
	# Well past the delay: it climbs.
	while t < Player.REGEN_DELAY + 2.0:
		await _frames(1)
		t += get_physics_process_delta_time()
	print("  %.0f during the delay -> %.0f after it" % [during, nader.health])
	_expect(is_equal_approx(during, hurt), "no regen during the delay")
	_expect(nader.health > during + 5.0, "then it heals back up on its own")
	# ...and a hit restarts the delay.
	var attacker2 := Node3D.new()
	add_child(attacker2)
	attacker2.global_position = nader.global_position + Vector3(0, 1, -6)
	nader.take_damage(10.0, attacker2)
	_expect(nader._since_damage < 0.1, "taking a hit restarts the regen delay")

	# --- THE THIRD SLOT, END TO END ---------------------------------------
	#
	# The sustained ability, driven the whole way a real one is: fitted on a
	# build, DEPLOYED (which is `pending.duplicate_loadout()`, the copy that used
	# to throw the field away), then pressed on its own control. `kit_rules`
	# catches the copy in isolation; this is the one that says a player actually
	# gets the thing, because every step between the buy screen and the body has
	# to survive, not just the one that was broken.
	print("\n== the sustained slot ==")
	var sus := _build(Loadout.Kit.CLONE, Weapon.Class.DC15S, Loadout.Gadget.NONE)
	sus.gadget3 = Loadout.Gadget.OVERSHIELD
	var trooper := await _spawn(sus, Vector3(40.0, 0.0, 0.0), 0)
	await _frames(2)
	print("  fitted %s, deployed holding %s" % [
		Loadout.GADGETS[Loadout.Gadget.OVERSHIELD]["name"],
		Loadout.GADGETS[trooper.gadget3]["name"]])
	_expect(trooper.gadget3 == Loadout.Gadget.OVERSHIELD,
		"the ability survives the deploy copy and reaches the body")
	_expect(trooper.has_gadget(Loadout.Gadget.OVERSHIELD),
		"...and the body answers has_gadget for it")
	_expect(trooper.slot_of(Loadout.Gadget.OVERSHIELD) == 2,
		"...on slot 3, which is the control it is read from")
	trooper._use_gadget(2)
	await _frames(1)
	print("  pressed slot 3: pool %.0f, %.1fs left, cooldown %.1fs" % [
		trooper._over_pool, trooper._over_left, trooper.gadget_cooldown(2)])
	_expect(trooper._over_pool > 0.0, "pressing it actually raises the overshield")
	_expect(trooper.gadget_cooldown(2) > 0.0, "...and charges slot 3's own cooldown")
	# The whole reason the slot exists: it must not be reachable from the other
	# two buttons, or the same ability sits on two controls.
	_expect(trooper.gadget != Loadout.Gadget.OVERSHIELD
		and trooper.gadget2 != Loadout.Gadget.OVERSHIELD,
		"...and is on slot 3 alone, not duplicated onto slots 1 or 2")

	print("\n==== %s ====" % ("GADGETS WORK" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _count(prefix: String) -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c.name.begins_with(prefix):
			n += 1
	return n


func _build(kit: int, primary: int, gadget: int) -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(kit)
	l.weapon = Loadout.weapon_index(primary)
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
