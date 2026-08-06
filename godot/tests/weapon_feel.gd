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

	# --- AIMING IS PINPOINT, ON EVERY GUN AND EVERY SIGHT ------------------
	#
	# It used to be the SCOPE's promise alone and everything else kept a small
	# ADS cone, so a sight picture said "the round goes there" and the gun
	# answered "roughly there". Checked across the whole catalogue rather than on
	# one weapon, because the rule lives in `current_spread_deg` precisely so no
	# profile can opt out of it — and checked IN A STANCE that widens the cone,
	# since the stance multiplier is applied after it and would happily multiply
	# a non-zero number back up.
	print("\n== aiming is pinpoint ==")
	var loose := 0
	var loose_names := PackedStringArray()
	for c in Weapon.PROFILES.size():
		var w := _weapon(c, {})
		await _frames(1)
		w.aiming = true
		w.stance_spread_mult = moving        # the worst stance there is
		w._bloom = 3.0                       # ...and a cone full of spray
		if w.current_spread_deg() > 0.0:
			loose += 1
			if loose_names.size() < 6:
				loose_names.append(str(Weapon.Class.keys()[c]))
		w.queue_free()
	print("  %d of %d weapons throw a cone while aimed%s" % [
		loose, Weapon.PROFILES.size(),
		"" if loose_names.is_empty() else " (%s)" % ", ".join(loose_names)])
	_expect(loose == 0, "every gun in the catalogue is pinpoint down the sights")
	# ...and the AI's model of the gun is deliberately NOT zeroed with it. A Bot
	# derives its stand-off from `aimed_spread_deg`, so zeroing that here would
	# turn a player-facing accuracy rule into an unasked-for AI rebalance —
	# `bot_range` is where that showed up and this is where it is pinned.
	var ironed := _weapon(Weapon.Class.SOLDIER, {})
	await _frames(1)
	_expect(ironed.aimed_spread_deg() > 0.0,
		"...but the AI still tunes against the gun's authored aimed cone")
	ironed.queue_free()
	# ...and hip fire still is not, or the trade has been given away.
	var hipped := _weapon(Weapon.Class.SOLDIER, {})
	await _frames(1)
	hipped.aiming = false
	_expect(hipped.current_spread_deg() > 0.0,
		"...while hip fire still throws a cone, which is what aiming buys")
	hipped.queue_free()

	# --- aegis drone twin repeaters ------------------------------------------
	print("\n== aegis drone twin repeaters ==")
	var twin := _weapon(Weapon.Class.AEGIS_TWIN, {})
	twin.position = Vector3(0.0, 1.25, 0.0)
	await _frames(1)
	twin.shooter = p
	twin._fire_shot()
	var first_muzzle: float = twin._muzzle_light.position.x
	twin._cooldown = 0.0
	twin._fire_shot()
	var second_muzzle: float = twin._muzzle_light.position.x
	print("  muzzle x %.2f -> %.2f" % [first_muzzle, second_muzzle])
	_expect(first_muzzle * second_muzzle < 0.0,
		"the Aegis Drone alternates left and right arm cannons")

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

	# --- bolt colour ------------------------------------------------------
	# The half kit_rules cannot see: it runs with no autoloads, so it can check
	# the TABLE but never that a side's colour reaches a fired round.
	print("\n== bolt colour ==")
	var issued := _weapon(Weapon.Class.SOLDIER, {})   # an ordinary blaster: no colour of its own
	var owned := _weapon(Weapon.Class.GAUSS_RIFLE, {})  # ...and one that states one
	issued.shooter = p
	owned.shooter = p
	p.team = GameState.Team.CONCORD
	var republic := issued.bolt_color()
	var gauss_blue_side := owned.bolt_color()
	p.team = 2   # the Dominion, on the same rifle
	var empire := issued.bolt_color()
	var gauss_red_side := owned.bolt_color()
	print("  DC-15 in Concord hands %s, in Dominion hands %s" % [republic, empire])
	print("  Gauss Flayer either way %s / %s" % [gauss_blue_side, gauss_red_side])
	_expect(republic != empire, "an ordinary blaster takes its own side's colour")
	_expect(republic == GameState.bolt_color(GameState.Team.CONCORD),
		"...the one the universe table states for that side")
	_expect(gauss_blue_side == gauss_red_side,
		"a weapon with a colour of its own ignores whose hands it is in")
	# The tracer, the muzzle light and the scorch are one colour or the gun is two
	# guns: a flash that lights the wall green and an orange round arriving in it.
	p.team = GameState.Team.CONCORD
	issued._flash_muzzle()
	_expect(issued._muzzle_light.light_color == issued.bolt_color(),
		"the muzzle light is the same colour as the round it threw")

	# ...and the TRACER carries it, which is the half a colour on the weapon
	# cannot prove. Plus the rule that makes a per-colour material affordable at
	# all: two rounds of one colour are two bolts sharing ONE material, never a
	# material allocated per shot — that defect is on record (see _burn).
	var b1 := _bolt(Vector3.ZERO, Vector3(0.0, 0.0, -8.0), republic)
	var b2 := _bolt(Vector3.ZERO, Vector3(0.0, 0.0, -9.0), republic)
	var b3 := _bolt(Vector3.ZERO, Vector3(0.0, 0.0, -8.0), empire)
	var m1 := _bolt_mat(b1)
	var m2 := _bolt_mat(b2)
	var m3 := _bolt_mat(b3)
	print("  bolt emission %s | shared across two rounds %s | a second colour is its own %s" % [
		m1.emission if m1 else "none", m1 == m2, m1 != m3])
	_expect(m1 != null and m1.emission == republic,
		"a fired round's tracer is its own side's colour")
	_expect(m1 == m2, "two rounds of the same colour share one material")
	_expect(m3 != null and m3.emission == empire and m1 != m3,
		"a different colour gets its own material, once")
	for b in [b1, b2, b3]:
		b.queue_free()

	# --- the blade's voice ------------------------------------------------
	# A LIT BLADE HUMS AND A LENGTH OF STEEL DOES NOT, and which is which is read
	# off `blade_energy` — the key that already decides whether the viewmodel
	# builds a glowing blade or a dull one, so the thing that hums and the thing
	# that glows cannot drift apart.
	print("\n== the blade's voice ==")
	var saber := _weapon(Weapon.Class.SABER, {})
	var chain := _weapon(Weapon.Class.CHAINSWORD, {})
	print("  saber: energy %s voice %s | chain blade: energy %s voice %s" % [
		saber.blade_is_energy(), saber._voice(),
		chain.blade_is_energy(), chain._voice()])
	_expect(saber.blade_is_energy() and saber._voice() == "saber_swing",
		"a arc blade swings with its own pitched voice")
	_expect(not chain.blade_is_energy() and chain._voice() == "melee_swing",
		"a chain blade is steel and still just moves air")
	# Put it away before the pool is measured below. A lit blade sitting in the
	# scene is a hum whether or not this test is looking at it, which is right and
	# is also two voices where the section below counts on one.
	saber.set_class(Weapon.Class.SOLDIER, {})

	if not await _bank():
		_fails.append("the sound bank never finished rendering")
	else:
		# The hum is claimed off what is IN HAND, checked every tick, so a swap, a
		# spawn and a death are all covered without any of them knowing about audio.
		# Built AFTER the bank, which is the real order of events: a blade drawn
		# into a ready bank hums on its very first tick and never waits on a retry.
		var drawn := _weapon(Weapon.Class.SABER, {})
		drawn.position = Vector3(0.0, 1.25, 0.0)
		drawn.shooter = p
		await _frames(1)
		var lit_token: int = drawn._hum_token
		var lit_busy := Audio.loops_busy()
		print("  drawn: token %d on the first tick, %d voice(s) busy" % [
			lit_token, lit_busy])
		_expect(lit_token != 0 and lit_busy == 1,
			"a drawn blade takes a sustained voice on its first tick")

		# A SWING BENDS THE HUM. Same doppler the swing sound carries; without it a
		# lit blade is a held note with whooshes played over the top of it.
		var resting := 1.0 + Weapon.HUM_SWING_BEND * drawn._swing_t
		drawn._cooldown = 0.0
		drawn._fire_shot()
		var swinging := 1.0 + Weapon.HUM_SWING_BEND * drawn._swing_t
		print("  hum pitch resting %.2f -> mid-swing %.2f" % [resting, swinging])
		_expect(swinging > resting, "a swing bends the hum up")
		await _frames(45)
		_expect(is_equal_approx(1.0 + Weapon.HUM_SWING_BEND * drawn._swing_t, 1.0),
			"...and it settles back")

		# A BLADE IN A DEAD HAND IS NOT LIT. Not a swap at all, which is the reason
		# this is polled off what is in hand rather than pushed by the swap.
		p._dead = true
		await _frames(2)
		var dead_token: int = drawn._hum_token
		p._dead = false
		await _frames(2)
		print("  owner died: token %d, busy %d -> respawned: token %d, busy %d" % [
			dead_token, 0, drawn._hum_token, Audio.loops_busy()])
		_expect(dead_token == 0, "a blade in a dead hand falls silent")
		_expect(drawn._hum_token != 0, "...and comes back up with its owner")

		drawn.set_class(Weapon.Class.SOLDIER, {})   # holster it
		await _frames(2)
		_expect(drawn._hum_token == 0 and Audio.loops_busy() == 0,
			"holstering the blade gives the voice back")

		# THE POOL IS CAPPED AND NEAREST WINS. Four hums on one couch with no
		# panning is mud, so the fourth blade has to take a slot off a farther one
		# — and the loser's token must go STALE rather than staying live, or its
		# owner's own release would switch the new one off. That is the whole
		# reason a token exists and it is the half nothing else would catch.
		var far: Array[int] = []
		for i in Audio.SUSTAINED:
			far.append(Audio.claim_loop("saber_hum", Vector3(0.0, 0.0, -400.0 - i)))
		var full := Audio.loops_busy()
		var near := Audio.claim_loop("saber_hum", p.global_position + Vector3(1.0, 0.0, 0.0))
		var stolen := -1
		for i in far.size():
			if not Audio.has_loop(far[i]):
				stolen = i
		print("  %d far voices, then one near: near token %d, stolen slot %d, busy %d" % [
			full, near, stolen, Audio.loops_busy()])
		_expect(full == Audio.SUSTAINED, "the pool fills to its cap and no further")
		_expect(near != 0 and Audio.has_loop(near),
			"a nearer blade takes a voice off a farther one")
		_expect(stolen >= 0, "...and exactly that farther one lost it")
		_expect(Audio.loops_busy() == Audio.SUSTAINED,
			"...without the pool growing")
		# The stale owner tidies up after itself, as it must: it has no idea it was
		# outbid. This must not touch the voice that took its slot.
		Audio.release_loop(far[stolen])
		_expect(Audio.has_loop(near) and Audio.loops_busy() == Audio.SUSTAINED,
			"an outbid owner's release cannot silence whoever replaced it")
		Audio.stop_all_loops()
		_expect(Audio.loops_busy() == 0, "and the backstop clears the lot")

	print("\n==== %s ====" % ("WEAPON FEEL WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


const BOLT := preload("res://scenes/fx/blaster_bolt.tscn")


## Wait for the sound bank, which is rendered on a worker thread and is roughly a
## third of a second of work — nothing can claim a voice before it lands. Bounded
## rather than infinite: a bank that never arrives is a failure, not a hang.
func _bank() -> bool:
	for _i in 240:
		if Audio.bank_ready:
			return true
		await get_tree().physics_frame
	return false


## A bolt in flight, launched the way Weapon launches one.
func _bolt(from: Vector3, to: Vector3, col: Color) -> Node3D:
	var b: Node3D = BOLT.instantiate()
	add_child(b)
	b.launch(from, to, col)
	return b


func _bolt_mat(b: Node3D) -> StandardMaterial3D:
	var mesh := b.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return null
	return mesh.get_surface_override_material(0) as StandardMaterial3D


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
