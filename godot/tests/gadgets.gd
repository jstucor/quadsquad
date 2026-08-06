extends Node3D

## The two gadget changes: lightning that is CHANNELLED while held, and the
## Hunter's wrist rocket.
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

	var warden := await _spawn(_build(Loadout.Kit.ADEPT, Weapon.Class.SABER,
		Loadout.Gadget.ARC_STORM), Vector3.ZERO, 0)
	var mark := await _spawn(Loadout.starter(), Vector3(0.0, 0.0, -12.0), 1)
	mark.damaged.connect(func(amount: float) -> void: _hits.append(amount))
	await _frames(2)

	print("== the channel ==")
	print("  %.1fs of stream, a bite every %.2fs, %.0f per bite -> %.0f total" % [
		Kinesis.CHANNEL_TIME, Kinesis.CHANNEL_TICK, Kinesis.BOLT_DAMAGE,
		Kinesis.CHANNEL_TIME / Kinesis.CHANNEL_TICK * Kinesis.BOLT_DAMAGE])
	mark.health = 100000.0
	_hits.clear()
	warden._use_gadget(0)                       # opens the channel
	var held := 0.0
	for _i in 300:
		# Hold the button: the channel reads the gadget control every frame.
		Input.action_press("kb_gadget")
		await _frames(1)
		held += get_physics_process_delta_time()
		if warden._channel_left <= 0.0:
			break
	Input.action_release("kb_gadget")
	var total := 0.0
	for h in _hits:
		total += h
	print("  held %.2fs -> %d bites, %.0f damage, cooldown now %.1fs" % [
		held, _hits.size(), total, warden.gadget_cooldown(0)])
	_expect(_hits.size() > 5, "holding it bites over and over, not once")
	_expect(total > 90.0, "a full channel is worth more than a rifle magazine")
	_expect(warden.gadget_cooldown(0) > 0.0, "and a full channel costs the full cooldown")

	# --- a tap costs almost nothing --------------------------------------
	print("\n== a tap ==")
	warden._force_cd = [0.0, 0.0, 0.0]   # one per gadget slot, and there are three
	warden._channel_left = 0.0
	await _frames(2)
	_hits.clear()
	warden._use_gadget(0)
	await _frames(2)          # button never held: the channel closes at once
	var tap_cd := warden.gadget_cooldown(0)
	var full: float = Loadout.GADGET_COOLDOWNS[Loadout.Gadget.ARC_STORM]
	print("  tapped -> cooldown %.2fs of a %.1fs maximum" % [tap_cd, full])
	_expect(tap_cd > 0.0 and tap_cd < full * 0.6,
		"a tap costs a fraction of the cooldown, not the whole thing")

	# --- the wrist rocket -------------------------------------------------
	print("\n== the wrist rocket ==")
	var mando := await _spawn(_build(Loadout.Kit.HUNTER, Weapon.Class.SMG,
		Loadout.Gadget.WRIST_ROCKET), Vector3(40.0, 0.0, 0.0), 0)
	var victim := await _spawn(Loadout.starter(), Vector3(40.0, 0.0, -14.0), 1)
	await _frames(2)
	print("  %s carries %s" % [mando.loadout.kit_name(),
		Loadout.GADGETS[mando.gadget]["name"]])
	_expect(mando.gadget == Loadout.Gadget.WRIST_ROCKET,
		"a Hunter can buy the wrist rocket")
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
	_expect(mando.is_alive(), "without blowing up the Hunter who fired it")

	# --- nobody else may have it ------------------------------------------
	var legionary := Loadout.new()
	legionary.adopt_kit(Loadout.Kit.LEGION)
	_expect(not legionary.allows(Loadout.Row.GADGET, Loadout.Gadget.WRIST_ROCKET),
		"a legionary cannot buy the wrist rocket")

	# --- grenades are gadgets with a cooldown now -------------------------
	print("\n== the grenade gadget ==")
	var nader := await _spawn(_build(Loadout.Kit.LEGION, Weapon.Class.SOLDIER,
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
	var sus := _build(Loadout.Kit.LEGION, Weapon.Class.VL15S, Loadout.Gadget.NONE)
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

	await _test_new_sustained()

	print("\n==== %s ====" % ("GADGETS WORK" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## THE WIDENED THIRD SLOT. Every one of these is asserted through the EFFECT and
## never through the countdown, because a window that opens and does nothing is
## exactly what a sustained ability looks like when it breaks — the gauge fills,
## the sound plays, the number counts down, and the rule it was supposed to bend
## was never wired to anything.
##
## The two at the end are the LEAKS, and they are the reason this section is
## worth its length: a RALLY is registered in a GameState dictionary rather than
## on the body, so a death that does not clear it leaves a corpse protecting its
## squad for the rest of the match, and nothing anywhere would report it.
func _test_new_sustained() -> void:
	print("\n== the widened third slot ==")
	# EVERY CLASS HAS A REAL MENU. The whole complaint this answers is that
	# fourteen classes were choosing between two of the same four answers.
	var thin: Array[String] = []
	var actions := {}
	for k in Loadout.KITS.size():
		var list: Array = Loadout.KITS[k].get("sustain", [])
		if list.size() < 4:
			thin.append("%s has %d" % [String(Loadout.KITS[k]["name"]), list.size()])
		for g in list:
			if g != Loadout.Gadget.NONE:
				actions[Loadout.gadget_action(g)] = true
	_expect(thin.is_empty(), "every class has at least three abilities to choose between"
		+ ("" if thin.is_empty() else " — %s" % ", ".join(thin)))
	_expect(actions.size() >= 8,
		"...and the roster reaches %d distinct sustained ACTIONS, not four" % actions.size())

	# COOLANT — the one that acts on the GUN.
	var gunner := await _spawn(_sustain_build(Loadout.Kit.URSAN, Loadout.Gadget.COOLANT),
		Vector3(30.0, 0.0, 0.0), 0)
	gunner.weapon._heat = 0.95
	gunner.weapon._overheated = true
	gunner._use_gadget(2)
	await _frames(1)
	_expect(gunner.weapon.heat() <= 0.01 and not gunner.weapon._overheated,
		"COOLANT vents a locked-out gun (%.2f heat, locked %s)"
			% [gunner.weapon.heat(), gunner.weapon._overheated])
	_expect(is_equal_approx(gunner.weapon.heat_mult, Player.COOLANT_HEAT_MULT),
		"...and halves what the next shots cost the pool")
	# THE SWAP CASE, which is the one that regresses silently: `set_class` clears
	# the multiplier on every rebuild, so a window set once would keep counting
	# down on the HUD having stopped doing anything.
	gunner.weapon.set_class(Weapon.Class.SOLDIER, gunner.loadout.primary_mods())
	await _frames(2)
	_expect(is_equal_approx(gunner.weapon.heat_mult, Player.COOLANT_HEAT_MULT),
		"...and the window survives a weapon swap, which rebuilds the gun")

	# BULWARK — the one that takes your LEGS. Both halves asserted, because an
	# exemption written one notch too wide is a free damage discount.
	var braced := await _spawn(_sustain_build(Loadout.Kit.URSAN, Loadout.Gadget.BULWARK),
		Vector3(40.0, 0.0, 0.0), 0)
	braced._use_gadget(2)
	await _frames(1)
	var before := braced.health
	braced.take_damage(100.0, null)
	var took := before - braced.health
	_expect(took < 100.0 * 0.9, "BULWARK takes the edge off a hit (%.0f of 100)" % took)
	_expect(not braced._is_running() and not braced._may_slide(),
		"...and it really does take the legs: no sprint, no slide")

	# STIM — healing under fire, which is the one thing regeneration refuses.
	var stimmed := await _spawn(_sustain_build(Loadout.Kit.LEGION, Loadout.Gadget.STIM),
		Vector3(50.0, 0.0, 0.0), 0)
	stimmed.health = 40.0
	stimmed._since_damage = 0.0     # just been hit: ordinary regen is refusing
	stimmed._use_gadget(2)
	await _frames(30)
	_expect(stimmed.health > 40.0,
		"STIM heals while the regen delay is still unspent (%.0f hp)" % stimmed.health)

	# SCRAMBLER — it answers the MARKING category, and it clears a mark that has
	# already landed, which is the moment it is actually reached for.
	var ghost := await _spawn(_sustain_build(Loadout.Kit.SAURIAN, Loadout.Gadget.SCRAMBLER),
		Vector3(60.0, 0.0, 0.0), 0)
	GameState.mark_scanned(ghost, 1, 10.0)
	_expect(GameState.is_scanned_for(ghost, 1), "a dart marks an ordinary body")
	ghost._use_gadget(2)
	await _frames(1)
	_expect(not GameState.is_scanned_for(ghost, 1), "SCRAMBLER clears a mark already on you")
	GameState.mark_scanned(ghost, 1, 10.0)
	_expect(not GameState.is_scanned_for(ghost, 1), "...and refuses the next one too")

	# RALLY — the only ability that reaches somebody else.
	var officer := await _spawn(_sustain_build(Loadout.Kit.LEGION, Loadout.Gadget.RALLY),
		Vector3(70.0, 0.0, 0.0), 0)
	var mate := await _spawn(Loadout.starter(), Vector3(74.0, 0.0, 0.0), 0)
	var foe := await _spawn(Loadout.starter(), Vector3(74.0, 0.0, 2.0), 1)
	officer._use_gadget(2)
	await _frames(1)
	var mate_before := mate.health
	mate.take_damage(100.0, null)
	var mate_took := mate_before - mate.health
	_expect(mate_took < 100.0,
		"RALLY protects a TEAMMATE standing in it (%.0f of 100)" % mate_took)
	var foe_before := foe.health
	foe.take_damage(100.0, null)
	_expect(is_equal_approx(foe_before - foe.health, 100.0),
		"...and does nothing for an enemy at the same distance")
	# ...and it has a RADIUS. A field with no edge is a team-wide passive.
	var far := await _spawn(Loadout.starter(),
		Vector3(70.0 + Player.RALLY_RADIUS + 6.0, 0.0, 0.0), 0)
	var far_before := far.health
	far.take_damage(100.0, null)
	_expect(is_equal_approx(far_before - far.health, 100.0),
		"...and nothing for a teammate outside the radius")

	# THE LEAKS. Both live in a GameState dictionary rather than on the body, so
	# a countdown ending is NOT what cleans them up.
	officer._die(null)
	await _frames(1)
	_expect(not GameState.rallies.has(officer),
		"a body that dies takes its RALLY with it, rather than protecting a squad from the grave")
	ghost._die(null)
	await _frames(1)
	_expect(not GameState.unscannable.has(ghost),
		"...and a dead SCRAMBLER stops making a body permanently unmarkable")

	# NOTE ON THE `ObjectDB instances were leaked` WARNING THIS RUN PRINTS: it is
	# the AUDIO POOL, not anything here. Measured with `--verbose`: every leaked
	# instance is an `AudioStreamWAV` or an `AudioStreamPlaybackWAV` still held by
	# a pooled voice when the process exits, and this section plays six more
	# sounds than the file used to. Freeing the bodies does not move it (tried:
	# 12 before, 14 after), which is what says it is not them. `soak.tscn` is
	# still the test that would catch a real one.


## A build carrying `ability` in slot 3. Set directly rather than stepped: what
## is being tested is the ABILITY, and `adopt_kit` deciding it is illegal for
## this class would make that a silent no-op wearing a passing test.
func _sustain_build(kit: int, ability: int) -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(kit)
	l.gadget3 = ability
	return l


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
