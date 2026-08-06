extends Node3D

## FORCE LIGHTNING: what it hits, what it must not hit, and what it costs.
##
## The interesting half is the chain. It is measured from the LAST victim rather
## than from the caster, so it punishes a group standing together — which also
## means it is the one power that can reach somebody the caster never aimed at,
## and the only thing stopping it reaching a TEAMMATE is the enemy filter. That
## is what this checks.
##
##   godot --headless --path godot tests/arc_storm.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()

	# The caster faces -Z, so everything in front of it is at negative z.
	var warden := await _spawn(_lightning_build(), Vector3.ZERO, 0)
	var mark := await _spawn(Loadout.starter(), Vector3(0.0, 0.0, -12.0), 1)
	var near := await _spawn(Loadout.starter(), Vector3(3.0, 0.0, -14.0), 1)
	var far_chain := await _spawn(Loadout.starter(), Vector3(6.0, 0.0, -16.0), 1)
	# 8.4 m on from `far`: inside the jump, and far enough that only a chain can
	# reach it — the caster is 23 m away, well past the bolt's own range.
	var fourth := await _spawn(Loadout.starter(), Vector3(14.0, 0.0, -18.5), 1)
	var out_of_reach := await _spawn(Loadout.starter(), Vector3(0.0, 0.0, -30.0), 1)
	var mate := await _spawn(Loadout.starter(), Vector3(1.5, 0.0, -12.5), 0)
	await _frames(2)

	print("== the build ==")
	print("  gadget %s, cooldown %.0fs, %.0f HP" % [
		Loadout.GADGETS[warden.gadget]["name"],
		Loadout.GADGET_COOLDOWNS[Loadout.Gadget.ARC_STORM], warden.max_health])
	_expect(warden.gadget == Loadout.Gadget.ARC_STORM, "the adept deployed with it")

	var before := {
		"mark": mark.health, "near": near.health, "far": far_chain.health,
		"4th": fourth.health, "out": out_of_reach.health, "mate": mate.health,
	}
	# ONE bite of the channel. The power is held now (see tests/gadgets for the
	# holding), so this drives the same static function a single tick calls — the
	# whole point of this file is the CHAIN it resolves, which the channel did not
	# change.
	Kinesis.lightning(warden, warden.team)
	await _frames(1)

	print("\n== one bite ==")
	for who in ["mark", "near", "far", "4th", "out", "mate"]:
		var body: Player = {"mark": mark, "near": near, "far": far_chain,
			"4th": fourth, "out": out_of_reach, "mate": mate}[who]
		print("  %-5s at %5.1f m took %5.1f" % [who,
			warden.global_position.distance_to(body.global_position),
			before[who] - body.health])

	_expect(before["mark"] - mark.health > 0.0, "the one you are looking at is hit")
	_expect(is_equal_approx(before["mark"] - mark.health, Kinesis.BOLT_DAMAGE),
		"...for a full bite's damage")
	_expect(before["near"] - near.health > 0.0, "the arc chains to the body beside them")
	_expect(before["near"] - near.health < before["mark"] - mark.health,
		"...for less, each jump falling off")
	_expect(before["far"] - far_chain.health > 0.0, "and on again to the third")
	_expect(before["4th"] - fourth.health > 0.0,
		"the chain reaches a FOURTH body 23 m from the caster, on jumps alone")
	_expect(is_equal_approx(before["out"], out_of_reach.health),
		"nobody past the range is touched")
	_expect(is_equal_approx(before["mate"], mate.health),
		"and a TEAMMATE standing in the middle of it is not")

	# --- the chain has a limit --------------------------------------------
	print("\n== the chain stops ==")
	var caught := Kinesis.lightning(warden, warden.team)
	print("  a second bolt struck %d (cap is 1 + %d chains)" % [
		caught.size(), Kinesis.BOLT_CHAINS])
	_expect(caught.size() <= 1 + Kinesis.BOLT_CHAINS,
		"never more than the cap, however many are stood together")

	# --- the cone is WIDE and forgiving, but still has an edge -------------
	# Clear the crowd out of the way, then place one enemy well off the aim
	# line: inside the new cone but outside the old 14 deg one. Loose aim has to
	# land it now — and an enemy past the cone's edge still must not be hit, or
	# it would be an omnidirectional zap rather than a forgiving one.
	# Tested one enemy at a time, so what lands is the CONE and never the chain.
	print("\n== a wide, forgiving cone ==")
	var far_away := Vector3(0.0, 0.0, 900.0)
	for body in [mark, near, far_chain, fourth, out_of_reach, mate]:
		body.global_position = far_away
	warden.rotation.y = 0.0
	# 28 deg off the -Z aim line: inside the new 35 deg cone, outside the old 14.
	var side := await _spawn(Loadout.starter(), Vector3(5.3, 0.0, -10.0), 1)
	await _frames(2)
	var side_before := side.health
	Kinesis.lightning(warden, warden.team)
	print("  28 deg off took %.0f" % (side_before - side.health))
	_expect(side_before - side.health > 0.0,
		"loose aim lands a target the old narrow cone would have missed")

	# Now ONLY an enemy past the cone edge (52 deg): a forgiving cone is still a
	# cone, so it must find nobody.
	side.global_position = far_away
	var beyond := await _spawn(Loadout.starter(), Vector3(12.8, 0.0, -10.0), 1)
	await _frames(2)
	var edge := Kinesis.lightning(warden, warden.team)
	print("  52 deg off struck %d" % edge.size())
	_expect(edge.is_empty(), "...but a target past the cone edge is not grabbed")
	beyond.global_position = far_away
	side.global_position = Vector3(5.3, 0.0, -10.0)   # one enemy back in front

	# --- facing away hits nobody ------------------------------------------
	# `side` stays in front; turning around puts it behind, so a wide cone is
	# still a FORWARD cone.
	print("\n== facing away ==")
	warden.rotation.y = PI   # turn away from everyone
	var missed := Kinesis.lightning(warden, warden.team)
	print("  struck %d" % missed.size())
	_expect(missed.is_empty(), "nothing behind you is hit")

	# --- the bolt draws itself and cleans itself up ------------------------
	# `side` is still in front, so facing forward again finds it.
	print("\n== the arc ==")
	warden.rotation.y = 0.0
	warden._channel_arc = Kinesis.channel_bolt(
		warden, warden.team, Player.LIGHTNING_SCENE, warden.weapon, null)
	await _frames(2)
	var arcs := _count_arcs()
	print("  %d arc node(s) alive right after the bolt" % arcs)
	_expect(arcs > 0, "the bolt is actually drawn")
	for _i in 40:
		await _frames(1)
	print("  %d arc node(s) after %.2fs" % [_count_arcs(), 40.0 / 60.0])
	_expect(_count_arcs() == 0, "and frees itself once it has faded")

	print("\n==== %s ====" % ("LIGHTNING WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _count_arcs() -> int:
	var n := 0
	for c in get_children():
		if c.get_script() != null and c.name.begins_with("LightningArc"):
			n += 1
	return n


func _lightning_build() -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(Loadout.Kit.ADEPT)
	l.weapon = Loadout.weapon_index(Weapon.Class.SABER)
	l.gadget = Loadout.Gadget.ARC_STORM
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
