extends Node3D
## ORBITAL STRIKE — YOU GO UP TO THE SHIP AND YOU CALL THE FIRE YOURSELF.
##
## THE OLD ONE WAS A BUTTON THAT HAPPENED SOMEWHERE ELSE. It picked the densest
## enemy cluster, walked three shells across it every half second for seven
## seconds, and the player who earned it carried on running around at ground
## level with no idea any of it was theirs. Everything about it was correct and
## none of it was a REWARD: the one thing a seven-kill streak has to deliver is a
## moment that belongs to you, and this was a thing you were told about
## afterwards by the killfeed.
##
## So the player is lifted into the ship. The body is seated exactly the way the
## LAAT's gunner is seated — hidden, collision off, transform slaved — and the
## camera goes to a fire-control position high enough to see the whole battle.
## The stick walks a target across the ground and the trigger brings rounds down
## on it, for as long as the window lasts. The fiction and the mechanic finally
## agree: you are the one up there, and you are the reason it is happening.
##
## WHAT IT REUSES rather than reinvents, all of it already load-bearing elsewhere:
## `Player.enter_vehicle`/`exit_vehicle` for the seating, `vehicle_owns_view` +
## `take_view_delta` + `set_view_angles` for the look interception the LAAT's ball
## needed (see the note there about why a mount takes the DELTA and not the
## angles), `gunner_readout()` for the sight, and `mortar_shell.gd` for the
## ballistics. Nothing here solves an arc or drives a camera from scratch.

const SHELL := preload("res://scenes/fx/mortar_shell.tscn")

## WHERE THE ROUNDS COME FROM. High enough that the arc reads as vertical and the
## shells appear out of nothing rather than being lobbed in from off the map edge
## — an orbital strike whose shells visibly come from the side is a mortar.
const ALTITUDE := 90.0

## WHERE YOU WATCH FROM, and it is deliberately much higher than the rounds start.
## The ship has to feel like it is in ORBIT and not like a helicopter: at 210 m a
## 260 m map sits inside the frame, bodies are still resolvable as bodies, and the
## horizon curves away at the edges of the viewport.
const VIEW_HEIGHT := 210.0
## Tipped slightly off vertical rather than looking straight down. A pure nadir
## view is a map screen — it has no horizon in it, so there is nothing to say you
## are high up rather than zoomed out. A few degrees of tilt puts sky in the top
## of the frame and that is the whole difference.
const VIEW_TILT := deg_to_rad(16.0)

## HOW LONG YOU HAVE. Much longer than the old seven seconds, because seven
## seconds of automatic fire needed no player in it and this does — you have to
## arrive, read the field, choose, and shoot.
const DEFAULT_DURATION := 18.0

## --- what comes down ----------------------------------------------------------
##
## "ALL THE BOMBS AND AMMO YOU WANT" IS A DESIGN INSTRUCTION AND THIS IS IT. The
## trigger is not rationed by a magazine or a heat pool — it is rationed by the
## CLOCK, which is the only limit that keeps the reward a moment rather than a
## mode. Hold it down and the ship keeps firing for the whole window.
const PER_SALVO := 4
const SALVO_EVERY := 0.30
## How far a salvo's rounds scatter around the mark. A stack of shells on one
## point kills whoever is standing on that point and nobody else; the scatter is
## what makes it a BARRAGE and what makes bunching the thing it punishes.
const SCATTER := 6.5

## An orbital round ARRIVES; a mortar round is ANNOUNCED. `mortar_shell` solves
## its own hang time and from 90 m up that is 6.4 s — measured end to end, the
## first round of the old strike landed 12.0 s after the button on a barrage that
## ran for 7, so the player saw nothing happen for the whole of their own reward.
## The mortar's long hang is a FAIRNESS feature you hear coming and walk out from
## under; this is the opposite event and is supposed to land before you can react.
const SHELL_HANG := 1.5

const SPLASH := 6.0
const SPLASH_DAMAGE := 95.0

## --- aiming -------------------------------------------------------------------

## How fast the mark crosses the ground, as a share of the look input's own angle
## — the same model the LAAT's ball uses, and for the same reason: a point that
## crawls when you are high and snaps when you are low is unusable at both ends.
const SLEW_GAIN := 1.0
## ...and how far from the middle of the battle it may be pushed. The ship is
## over the map, not over the next valley.
const AIM_LEASH := 170.0
## A cluster is everyone within this of the densest body — roughly a squad's
## spread, so the OPENING mark covers a group rather than a battalion.
const CLUSTER := 12.0
const SEARCH := 400.0

const CALLSIGN := "FIRE CONTROL"

var team := 0

var _shooter: Node
var _gunner: Node3D
var _eye_offset := Vector3.ZERO
var _return_to := Vector3.ZERO
var _left := 0.0
var _salvo_left := 0.0
var _aim := Vector3.ZERO
var _total := 1.0
var _seat: Node3D
var _hull: Node3D
var _firing := false


## `by` is the player who earned it. They go up immediately and come back down
## where they were standing, exactly like the LAAT's gunner — the position is
## taken NOW, because by the end of the window the ground they were on may have a
## firefight on it and their body has been hidden for the whole ride anyway.
func begin(by: Node, for_team: int, seconds: float) -> void:
	_shooter = by
	team = for_team
	_left = seconds if seconds > 0.0 else DEFAULT_DURATION
	_total = _left
	_salvo_left = 0.0
	# OPEN ON THE FIGHT. Dropped in already marking the densest enemy ground,
	# which is both where the battle is and the answer the old automatic version
	# used to compute for itself — kept, and demoted from the whole mechanic to a
	# sensible starting position.
	_aim = _densest_enemy_ground()
	_build()
	if not (by is Node3D):
		return
	var body := by as Node3D
	_return_to = body.global_position
	_place_seat()
	reset_physics_interpolation()
	# THE SEAT IS AN EYE POSITION (see `Player.seat_is_eye`): a fire-control
	# station is something you sit AT, so the camera goes on the seat and not a
	# body-height above it.
	if "seat_is_eye" in body:
		body.seat_is_eye = true
	if body.has_method("enter_vehicle"):
		body.enter_vehicle(self)
	if "vehicle_owns_view" in body:
		body.vehicle_owns_view = true
	_gunner = body
	_eye_offset = body.seat_anchor_offset() if body.has_method("seat_anchor_offset") \
		else Vector3.ZERO
	_look_down()


## Where the gunner sits. ASKED for by `Player.enter_vehicle` rather than pathed
## to, the same contract the LAAT's ball answers — this seat is not a direct
## child either.
func seat() -> Node3D:
	return _seat


## What the fire-control sight draws. The same duck-typed readout the LAAT
## answers, so `gunner_hud.gd` draws both and neither knows about the other.
func gunner_readout() -> Dictionary:
	return {
		"name": CALLSIGN,
		"left": maxf(_left, 0.0),
		"total": _total,
		"ready": _salvo_left <= 0.0,
	}


func _centre() -> Vector3:
	return Vector3(GameState.map_center.x, 0.0, GameState.map_center.z)


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0 or not _gunner_ok():
		_finish()
		return
	_slew(delta)
	_place_seat()
	_look_down()
	# The gunner rides the seat, offset so their EYE lands on it.
	_gunner.global_position = _seat.global_position - _eye_offset
	_fire(delta)


func _gunner_ok() -> bool:
	# The window can outlive the body: the match can end, the map can change, and
	# Royale can strand somebody up here.
	return _gunner != null and is_instance_valid(_gunner) \
		and _gunner.has_method("is_alive") and _gunner.is_alive()


## THE STATION HANGS OVER THE MARK, NOT OVER THE MAP CENTRE, so slewing the
## target actually flies the ship — which is what makes this feel like being in
## something rather than looking through a telescope. It trails the mark rather
## than snapping to it, so a hard push reads as the ship coming about.
const FOLLOW_RATE := 1.6


var _placed := false


func _place_seat() -> void:
	if _seat == null:
		return
	var want := _aim + Vector3(0.0, VIEW_HEIGHT, VIEW_HEIGHT * tan(VIEW_TILT))
	# An explicit flag and NOT "is the position still zero": the map centre can be
	# near the origin, so the obvious test would sometimes read a legitimately
	# placed station as unplaced and snap it every frame.
	if not _placed:
		_placed = true
		global_position = want
	else:
		global_position = global_position.lerp(want, clampf(
			get_physics_process_delta_time() * FOLLOW_RATE, 0.0, 1.0))
	if _hull != null:
		# The ship's own hull sits above and behind the station, so the player is
		# looking out from under it and the underside fills the top of the frame.
		_hull.global_position = global_position + Vector3(0.0, 26.0, 34.0)


## Point the camera from the station at the mark. Written as YAW AND PITCH and
## never as a basis, so the horizon stays level — the same rule the ball turret
## records, and here it is what stops the whole battlefield appearing tilted.
func _look_down() -> void:
	if _gunner == null or not _gunner.has_method("set_view_angles"):
		return
	var from: Vector3 = _seat.global_position
	var to := _aim - from
	if to.length_squared() < 0.01:
		return
	var dir := to.normalized()
	_gunner.set_view_angles(atan2(-dir.x, -dir.z),
		asin(clampf(dir.y, -1.0, 1.0)))


## Walk the mark across the ground with the look input. Scaled by the RANGE it is
## being looked at from, so it crosses the screen at one rate whatever the
## altitude.
func _slew(_delta: float) -> void:
	if _gunner == null or not _gunner.has_method("take_view_delta"):
		return
	var look: Vector2 = _gunner.take_view_delta()
	var from: Vector3 = _seat.global_position
	var flat := _aim - from
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.5 else Vector3.FORWARD
	var right := flat.cross(Vector3.UP)
	var reach: float = maxf(20.0, from.distance_to(_aim))
	_aim += (right * -look.x + flat * look.y) * reach * SLEW_GAIN
	_aim.y = 0.0
	var off := _aim - _centre()
	if off.length() > AIM_LEASH:
		_aim = _centre() + off.normalized() * AIM_LEASH
	# `_delta` is unused on purpose: the look input is already a per-frame delta,
	# so scaling it by time again makes sensitivity depend on frame rate.


func _fire(delta: float) -> void:
	_salvo_left = maxf(0.0, _salvo_left - delta)
	_firing = _gunner.has_method("vehicle_firing") and _gunner.vehicle_firing()
	if not _firing or _salvo_left > 0.0:
		return
	_salvo_left = SALVO_EVERY
	_fire_salvo()


func _fire_salvo() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for i in PER_SALVO:
		var at := _aim + Vector3(
			randf_range(-SCATTER, SCATTER), 0.0, randf_range(-SCATTER, SCATTER))
		var shell := SHELL.instantiate()
		scene.add_child(shell)
		# Straight down from directly above the impact point, so the round that
		# lands and the streak overhead read as the same event.
		shell.launch(at + Vector3.UP * ALTITUDE, at, _shooter, SPLASH,
			SPLASH_DAMAGE, SHELL_HANG)


## The centroid of the biggest cluster of enemies, used as the OPENING mark. Two
## passes over the roster rather than a proper clustering: at this body count the
## exact densest point is not worth an algorithm, and "near whoever has the most
## company" is the question that actually matters.
func _densest_enemy_ground() -> Vector3:
	var best_n := 0
	var best_at := _centre()
	for c in GameState.combatants:
		if not _is_prey(c):
			continue
		var here: Vector3 = c.global_position
		var n := 0
		var sum := Vector3.ZERO
		for d in GameState.combatants:
			if not _is_prey(d):
				continue
			if here.distance_to(d.global_position) <= CLUSTER:
				n += 1
				sum += d.global_position
		if n > best_n:
			best_n = n
			best_at = sum / float(n)
	best_at.y = 0.0
	return best_at


func _is_prey(c: Node) -> bool:
	return is_instance_valid(c) and c.is_alive() and "team" in c and c.team != team


func _finish() -> void:
	if _gunner != null and is_instance_valid(_gunner) \
			and _gunner.has_method("exit_vehicle"):
		# PUT THEM BACK WHERE THEY STOOD, and do NOT run it through
		# `clear_of_bodies` — that avoids LIVE players and this one is live, so it
		# would shove them clear of the very spot it is meant to return them to
		# (measured at 12.8 m on the LAAT, which is where this rule is recorded).
		_gunner.exit_vehicle(_return_to + Vector3.UP * 0.4, 0.0, false)
	_gunner = null
	queue_free()


## --- the station ---------------------------------------------------------------
##
## YOU ARE INSIDE SOMETHING, AND THE ONLY WAY TO SAY SO FROM A FIRST-PERSON
## CAMERA IS TO PUT PART OF IT IN THE FRAME. A camera hanging in clear air 210 m
## up is a spectator view; the same camera with a dark hull overhead and a lit
## console edge below it is a station on a capital ship. It is three boxes and it
## does the entire job, which is the same argument the LAAT's barrels make about
## being left visible when the rest of the ball is hidden.
func _build() -> void:
	_seat = Node3D.new()
	_seat.name = "Seat"
	add_child(_seat)

	_hull = Node3D.new()
	add_child(_hull)
	var dark := StandardMaterial3D.new()
	dark.metallic = 0.0
	dark.roughness = 0.72
	dark.albedo_color = Color(0.16, 0.17, 0.20)
	var lit := StandardMaterial3D.new()
	lit.metallic = 0.0
	lit.roughness = 0.4
	lit.emission_enabled = true
	var chip: Color = GameState.team_color(team)
	lit.emission = chip
	# 1.4 and not higher, the number the turret's sensor slit is on record for:
	# AgX at this project's exposure takes emission much past unity to WHITE, and
	# a white hull light carries no side at all.
	lit.emission_energy_multiplier = 1.4
	lit.albedo_color = chip.darkened(0.6)

	# The underside of something very large, seen from beneath: a long dark keel
	# with ribs across it and a run of lit ports down the middle. Deliberately far
	# bigger than the frame — a ship you can see the ends of is a ship you can
	# estimate the size of, and this one should not be estimable.
	_slab(Vector3(220.0, 12.0, 320.0), Vector3(0, 0, 0), dark)
	for i in 7:
		var z := -120.0 + i * 40.0
		_slab(Vector3(240.0, 5.0, 9.0), Vector3(0, -8.0, z), dark)
	for i in 9:
		_slab(Vector3(6.0, 2.0, 6.0), Vector3(0, -14.0, -140.0 + i * 34.0), lit)


func _slab(size: Vector3, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = at
	mi.material_override = mat
	# Nothing up here casts a shadow on anything: it is 200 m above the map, well
	# past `directional_shadow_max_distance`, so a shadow pass on it would be a
	# full pass for geometry that can never appear in the atlas.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hull.add_child(mi)
