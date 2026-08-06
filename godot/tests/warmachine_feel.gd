extends Node3D
## THE TWO CALL-INS, MEASURED RATHER THAN WATCHED — the LAAT's ball turret and
## the orbital strike.
##
##   godot --headless --path godot tests/warmachine_feel.tscn
##
## Both are things that happen at a distance, over seconds, to bodies somewhere
## else, which makes them exactly the kind of feature a screenshot and a play
## session cannot judge. "The gunship is inaccurate" is four different possible
## faults — the crosshair drifting on its own, the view being canted, the cone
## being too wide, or the shells simply missing — and they are told apart by
## numbers, not by feel (house rule 17).
##
## The gunner is a STUB and not a real Player on purpose: what is being measured
## is what the turret does with a HELD stick, so the input has to be exactly zero
## and a real Player polls a device that is not there.

const GUNSHIP := preload("res://scripts/gunship.gd")
const ORBITAL := preload("res://scripts/orbital_strike.gd")
const BOT := preload("res://scenes/actors/bot.tscn")

## The fire-control window, taken from the reward row rather than restated, so a
## change to the table cannot leave this test measuring a length the game does
## not hand out.
const ORBITAL_WINDOW := 18.0

var _fails: Array[String] = []
var _done: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_match()
	GameState.match_live = true
	_build_ground()
	await get_tree().process_frame

	await _gunship_inside()
	await _gunship_drift()
	await _gunship_roll()
	await _gunship_boresight()
	await _gunship_cone()
	await _gunship_ttk()
	await _orbital_damage()
	await _orbital_spread()

	print("")
	for line in _done:
		print("  section done: %s" % line)
	# EVERY SECTION SIGNS OFF AT ITS OWN END, and the run fails if one did not.
	# A GDScript error aborts the enclosing function silently (house rule 6), so
	# without this a check that died half way through reports no failures and has
	# verified nothing — which is precisely what happened when `_hold_mark_on`
	# was handed a freed station.
	for want in ["inside", "drift", "roll", "boresight", "cone", "gunship ttk",
			"orbital", "orbital spread"]:
		if not _done.has(want):
			_fails.append("the `%s` section did not run to the end — something in it errored and the rest of its checks were skipped" % want)
	if _fails.is_empty():
		print("\n==== WAR MACHINES MEASURED ====")
	else:
		print("\n==== %d PROBLEM(S) ====" % _fails.size())
		for f in _fails:
			print("  ! %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## A floor to shoot at, big and flat, so where a ray LANDS is a clean read of
## where the gun was pointed.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600, 2, 600)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -1, 0)
	body.collision_layer = 1
	add_child(body)
	GameState.map_center = Vector3.ZERO


# --- the gunner stub ----------------------------------------------------------
#
# Everything the gunship asks of the body in the ball, and nothing else. `look`
# and `pitch` are HELD: this is a player who has taken their hand off the stick.
class Gunner extends Node3D:
	var team := 0
	var firing := false
	var _look_pitch := 0.0
	var vehicle_owns_view := false
	# THE STUB HAS TO CARRY THE REAL BODY'S EYE GEOMETRY, or every measurement
	# below is taken on a gunner the game does not have. A Player is anchored by
	# its FEET and the camera rides `STAND_HEAD_Y` above them; whether the seat
	# holds the feet or the eye is the whole of `Player.seat_is_eye`, and it is
	# exactly what the parallax check exists to price.
	var seat_is_eye := false
	func seat_anchor_offset() -> Vector3:
		return Vector3.UP * Player.STAND_HEAD_Y if seat_is_eye else Vector3.ZERO
	## Where the CAMERA is — the body root plus the head, same as the real one.
	func eye() -> Vector3:
		return global_position + Vector3.UP * Player.STAND_HEAD_Y
	## ...and where it is looking, rebuilt from the angles the ball wrote.
	func view_dir() -> Vector3:
		return Basis(Vector3.UP, rotation.y) \
			* Basis(Vector3.RIGHT, _look_pitch) * Vector3.FORWARD
	func is_alive() -> bool: return true
	func vehicle_look() -> Vector2: return Vector2.ZERO
	# A player with their hands OFF the controls: no look input at all.
	func take_view_delta() -> Vector2: return Vector2.ZERO
	func set_view_angles(yaw: float, pitch: float) -> void:
		rotation.y = yaw
		_look_pitch = pitch
	func vehicle_firing() -> bool: return firing
	func enter_vehicle(_v: Node3D) -> void: pass
	func exit_vehicle(_s: Vector3, _y: float, _f: bool) -> void: pass


func _launch(seconds: float) -> Array:
	var g := Gunner.new()
	add_child(g)
	g.global_position = Vector3(40, 0, 0)
	g._look_pitch = deg_to_rad(-40.0)
	var ship: Node3D = GUNSHIP.new()
	add_child(ship)
	ship.begin(g, 0, seconds)
	await get_tree().physics_frame
	return [ship, g]


## Where the gun is actually pointed, as a point on the ground.
func _aim_point(ship: Node3D) -> Vector3:
	var muzzle: Node3D = ship.get("_muzzle")
	var from: Vector3 = muzzle.global_position
	var dir: Vector3 = -muzzle.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## 1. DOES THE CROSSHAIR HOLD STILL WITH THE STICK CENTRED?
##
## The hull turns through a full circle every twenty seconds. If the gunner's aim
## is expressed in WORLD terms and differenced against that hull, then a player
## touching nothing still watches their gun sweep the ground — and every shot has
## to be fired through a correction they are making by hand.
func _gunship_drift() -> void:
	print("\n-- LAAT: does a centred stick hold its aim? --")
	var pair := await _launch(30.0)
	var ship: Node3D = pair[0]
	var g: Gunner = pair[1]
	# Let the turret settle onto the held look before measuring.
	for _i in 40:
		await get_tree().physics_frame
	var start_yaw: float = ship.get("_turret").rotation.y
	var start_at := _aim_point(ship)
	var start_hull: float = ship.rotation.y
	for _i in 60:                       # one second
		await get_tree().physics_frame
	var end_yaw: float = ship.get("_turret").rotation.y
	var end_at := _aim_point(ship)
	var hull_turned: float = absf(wrapf(ship.rotation.y - start_hull, -PI, PI))

	var turret_moved := absf(wrapf(end_yaw - start_yaw, -PI, PI))
	print("  hull turned %.1f deg/s (by design)" % rad_to_deg(hull_turned))
	print("  turret yaw moved %.1f deg/s with the stick CENTRED"
		% rad_to_deg(turret_moved))
	if start_at != Vector3.INF and end_at != Vector3.INF:
		print("  the aim point walked %.1f m across the ground in one second"
			% start_at.distance_to(end_at))
	# THE TURRET'S OWN ANGLE IS NOT THE QUESTION — a turret pinned against its
	# stop is perfectly steady and completely broken. What the player sees is
	# where the rounds LAND, so that is what is measured.
	var walked := start_at.distance_to(end_at) if start_at != Vector3.INF \
		and end_at != Vector3.INF else 999.0
	_ok(walked < 2.0,
		"the LAAT's aim point walks %.1f m/s across the ground on a CENTRED stick — the gunner spends the whole ride correcting the hull's own rotation by hand"
			% walked)
	ship.queue_free()
	g.queue_free()
	await get_tree().process_frame
	_done.append("drift")


## 2. IS THE HORIZON LEVEL IN THE BALL?
##
## The seat is inside the ball, the ball hangs off the turret and the turret is a
## child of the BANKED body — so whatever roll the airframe carries is roll on the
## gunner's camera, permanently. A canted view does not just look odd: it rotates
## the frame the stick works in, so "right" moves the crosshair diagonally.
func _gunship_roll() -> void:
	print("\n-- LAAT: is the gunner's view level? --")
	var pair := await _launch(30.0)
	var ship: Node3D = pair[0]
	var g: Gunner = pair[1]
	for _i in 80:
		await get_tree().physics_frame
	var seat: Node3D = ship.seat()
	var right: Vector3 = seat.global_transform.basis.x
	print("  the seat node itself is rolled %.1f deg (it hangs off the banked body)"
		% rad_to_deg(asin(clampf(right.y, -1.0, 1.0))))

	# WHAT THE PLAYER SEES IS NOT THE SEAT — the ball drives the view as yaw and
	# pitch, so the horizon is level by construction. The property that actually
	# matters is CROSSHAIR CORRESPONDENCE: the direction the camera points and the
	# direction the gun fires have to be the same one. They were not related at
	# all before — only the gunner's POSITION was ever written — which is a gun
	# that shoots somewhere other than where you are looking.
	var muzzle: Node3D = ship.get("_muzzle")
	var gun: Vector3 = -muzzle.global_transform.basis.z
	var view := Basis(Vector3.UP, g.rotation.y) \
		* Basis(Vector3.RIGHT, g._look_pitch) * Vector3.FORWARD
	var off := rad_to_deg(gun.angle_to(view))
	print("  camera vs barrel: %.2f deg apart" % off)
	_ok(off < 0.5,
		"the LAAT's camera and its gun point %.1f deg apart — there is no crosshair, you are aiming one thing and firing another"
			% off)
	ship.queue_free()
	g.queue_free()
	await get_tree().process_frame
	_done.append("roll")


## 2b. IF YOU PUT THE CROSSHAIR ON A MAN, DO THE ROUNDS HIT HIM?
##
## The check above compares the DIRECTION the camera points against the direction
## the gun points, and it passed at 0.00 deg while the turret was still unusable —
## because two rays can be exactly parallel and still land eighty metres apart if
## they start in different places. That is the fault it could not see.
##
## The seat is inside the ball; the body was anchored by its FEET, so the camera
## sat 1.55 m above the seat, out in the open air above the glass, on a line
## PARALLEL to the barrel and 1.55 m off it. Parallel is not boresighted. Pitched
## down at the ground from 46 m up, that offset walks the point the crosshair
## covers away from the point the shell lands, and the number is not small.
##
## So this measures the thing the player actually experiences: cast the CAMERA's
## centre ray and the GUN's own ray, and compare where the two arrive. A body is
## about half a metre wide, so anything past that is a crosshair which is honestly
## drawn and honestly wrong — you lead the target correctly and miss anyway, which
## is unfixable from the player's side and reads as the gun being broken.
func _gunship_boresight() -> void:
	print("\n-- LAAT: does the crosshair cover what the gun hits? --")
	var pair := await _launch(30.0)
	var ship: Node3D = pair[0]
	var g: Gunner = pair[1]
	for _i in 100:
		await get_tree().physics_frame

	var eye_hit := _ground_hit(g.eye(), g.view_dir())
	var gun_hit := _aim_point(ship)
	if eye_hit == Vector3.INF or gun_hit == Vector3.INF:
		_ok(false, "the LAAT's sight line or its gun line missed the ground entirely")
	else:
		var reach: float = g.eye().distance_to(gun_hit)
		var miss: float = eye_hit.distance_to(gun_hit)
		print("  firing %.0f m  ·  crosshair lands %.2f m from the round" % [reach, miss])
		_ok(miss < 0.5,
			"the LAAT's crosshair covers a point %.2f m from where the shell lands at %.0f m — you cannot aim it"
				% [miss, reach])
	ship.queue_free()
	g.queue_free()
	await get_tree().process_frame
	_done.append("boresight")


## Where a ray from `from` along `dir` meets the ground.
func _ground_hit(from: Vector3, dir: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0)
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else Vector3.INF


## 3. HOW WIDE IS THE CONE AT THE RANGE IT ACTUALLY FIGHTS AT?
##
## Fired straight down the barrel with the aim held PERFECTLY on a point, so the
## only thing left in the number is the weapon's own spread. That is the honest
## way to price a cone: everything else is the player.
func _gunship_cone() -> void:
	print("\n-- LAAT: how wide is the cone where it shoots? --")
	var pair := await _launch(30.0)
	var ship: Node3D = pair[0]
	var g: Gunner = pair[1]
	for _i in 40:
		await get_tree().physics_frame
	var muzzle: Node3D = ship.get("_muzzle")
	var centre := _aim_point(ship)
	if centre == Vector3.INF:
		_ok(false, "the LAAT's gun is not pointed at the ground at all")
		ship.queue_free(); g.queue_free()
		return
	var reach: float = muzzle.global_position.distance_to(centre)
	var spread: float = GUNSHIP.SPREAD
	# Sample the cone the way the gun does: two independent rotations.
	var worst := 0.0
	var total := 0.0
	var n := 400
	for _i in n:
		var dir: Vector3 = -muzzle.global_transform.basis.z
		dir = dir.rotated(Vector3.UP, randf_range(-spread, spread)) \
			.rotated(muzzle.global_transform.basis.x, randf_range(-spread, spread))
		var q := PhysicsRayQueryParameters3D.create(
			muzzle.global_position, muzzle.global_position + dir * 400.0)
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			continue
		var miss: float = (hit["position"] as Vector3).distance_to(centre)
		worst = maxf(worst, miss)
		total += miss
	print("  firing range to the ground: %.0f m" % reach)
	print("  cone: %.2f m average miss, %.2f m worst, over %d rounds"
		% [total / n, worst, n])
	print("  (a standing body is about 0.5 m wide and %.2f m tall)" % 1.8)
	print("  splash reaches %.1f m for %.0f at the centre"
		% [GUNSHIP.SPLASH, GUNSHIP.SPLASH_DAMAGE])
	_ok(total / n < 1.0,
		"the LAAT's average round lands %.2f m off the point it was aimed at, against a body 0.5 m wide"
			% (total / n))
	ship.queue_free()
	g.queue_free()
	await get_tree().process_frame
	_done.append("cone")


## 4. WHAT DOES AN ORBITAL STRIKE ACTUALLY DO TO A GROUP?
##
## The reward is a fire-control station you are seated at, so the question is what
## a bunched squad loses while somebody holds the mark on them.
##
## NOTE WHAT CHANGED HERE AND WHY. The strike used to aim ITSELF at the densest
## cluster and re-aim every salvo, so a stub gunner with its hands off the stick
## measured the whole feature. It is player-aimed now, and a test that leaves the
## mark where it opened measures a barrage falling on the patch of ground six
## bots have just run away from — 88 damage over eighteen seconds, which says
## nothing about the weapon and everything about the bots. So the mark is HELD ON
## THE GROUP, which is what the player holding it would be doing.
func _orbital_damage() -> void:
	print("\n-- ORBITAL STRIKE: what a bunched squad loses --")
	var caller := Gunner.new()
	add_child(caller)
	caller.global_position = Vector3(0, 0, 0)

	var victims: Array[Node3D] = []
	for i in 6:
		var b: Node3D = BOT.instantiate()
		add_child(b)
		await get_tree().process_frame
		b.setup(null, 1, 2)
		b.global_position = Vector3(30.0 + (i % 3) * 2.0, 0.6, 20.0 + (i / 3) * 2.0)
		b.reset_physics_interpolation()
		victims.append(b)
	await get_tree().physics_frame
	var start := 0.0
	for v in victims:
		start += v.health
	print("  6 bots bunched inside 4 m, %.0f health between them" % start)

	var strike: Node3D = ORBITAL.new()
	add_child(strike)
	strike.global_position = caller.global_position
	# THE TRIGGER IS NOW THE PLAYER'S. The strike used to fire on a metronome the
	# moment it existed; it is a fire-control station you are seated at, so
	# nothing comes down until somebody pulls. A stub with `firing` false measures
	# a reward that was never used.
	caller.firing = true
	strike.begin(caller, 0, ORBITAL_WINDOW)
	# WAIT OUT THE SHELLS, NOT THE STRIKE. The node frees itself when its firing
	# window closes, and the rounds it fired last are still in the air — an
	# earlier version of this test stopped on `is_instance_valid(strike)` and
	# measured zero damage because not one shell had landed yet. That is also the
	# finding below: the time of flight is longer than the whole reward.
	var waited := 0.0
	var first_landing := -1.0
	var before_each := start
	while waited < ORBITAL_WINDOW + 6.0:
		_hold_mark_on(strike, victims)
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		if first_landing < 0.0:
			var now := 0.0
			for v in victims:
				if is_instance_valid(v):
					now += maxf(0.0, v.health)
			if now < before_each - 0.5:
				first_landing = waited
	if first_landing >= 0.0:
		print("  first round landed %.1f s after the strike was called" % first_landing)
		_ok(first_landing < 4.0,
			"the orbital strike's first round lands %.1f s after it is called, and the window only runs for %.0f s — the player sees nothing happen for most of their own reward, and re-aiming each salvo is pointless when the shell arrives that much later"
				% [first_landing, ORBITAL_WINDOW])

	var left := 0.0
	var dead := 0
	for v in victims:
		if not is_instance_valid(v):
			dead += 1
			continue
		if not v.is_alive():
			dead += 1
		left += maxf(0.0, v.health)
	print("  after the barrage: %.0f health left, %d of 6 down" % [left, dead])
	print("  %.0f damage dealt over %.0f s" % [start - left, ORBITAL_WINDOW])
	_ok(start - left > 0.0,
		"the orbital strike dealt NO damage to six bodies standing in a 4 m box")
	# A HALF-DEAD SQUAD IS NOT A SEVEN-KILL REWARD. It has to be decisive on the
	# thing it is aimed at, or nobody would choose it over carrying on shooting.
	_ok(dead >= 4,
		"the orbital strike left %d of 6 bunched bodies standing with the mark held on them"
			% (6 - dead))
	# CLEAN UP. These bodies used to be left in the scene, and the NEXT orbital
	# test then measured a barrage aimed at whichever group was denser — its own
	# spread-out victims, or these survivors standing in a 4 m box next door. That
	# is how the spread test came to report the opposite of its own design claim.
	for v in victims:
		if is_instance_valid(v):
			v.queue_free()
	caller.queue_free()
	await get_tree().physics_frame
	_done.append("orbital")


## Hold the mark on the middle of a group, as the player at the station would.
## Writing `_aim` directly is the same shortcut the LAAT's TTK check takes: what
## is being measured is the ordnance, not the stick.
##
## `strike` IS DELIBERATELY UNTYPED, the same rule `GameState.combatant_name`
## records: the station frees itself the moment its window closes, and this is
## called from a loop that deliberately runs on past that to let the last shells
## land. A `Node3D` parameter cannot even be CALLED with a freed object —
## GDScript refuses the bind before the function body runs, and a refused call
## aborts the caller (house rule 6), which is exactly what took the whole damage
## measurement out while the run still reported success.
func _hold_mark_on(strike, group: Array[Node3D]) -> void:
	if not is_instance_valid(strike):
		return
	var sum := Vector3.ZERO
	var n := 0
	for v in group:
		if is_instance_valid(v) and v.is_alive():
			sum += v.global_position
			n += 1
	if n > 0:
		strike.set("_aim", Vector3(sum.x / n, 0.0, sum.z / n))


## A body for the gun to actually shoot at, on the ground under the orbit.
func _victim(at: Vector3, team := 1) -> Node3D:
	var b: Node3D = BOT.instantiate()
	add_child(b)
	await get_tree().process_frame
	b.setup(null, team, 2)
	b.global_position = at
	b.reset_physics_interpolation()
	await get_tree().physics_frame
	return b


## 5. WHAT DOES THE LAAT DO TO A MAN IT IS POINTED AT?
##
## The cone being tight is only half the answer — a gun that cannot miss and
## cannot kill is still not a reward. Held on one body with the turret tracking
## the point it is standing on.
func _gunship_ttk() -> void:
	print("\n-- LAAT: how long to kill one man under the guns? --")
	var pair := await _launch(30.0)
	var ship: Node3D = pair[0]
	var g: Gunner = pair[1]
	for _i in 30:
		await get_tree().physics_frame
	# Stand him exactly where the ball is already looking.
	var spot: Vector3 = ship.get("_aim_at")
	var victim := await _victim(Vector3(spot.x, 0.6, spot.z))
	var full: float = victim.health
	g.firing = true
	var t := 0.0
	while t < 6.0 and is_instance_valid(victim) and victim.is_alive():
		# HOLD THE CROSSHAIR ON HIM, which is what the player whose lethality is
		# being measured would be doing. The victim is a live bot and it walks —
		# an earlier version set the aim once and then measured a gun firing at
		# the patch of ground the target had left, which prices the AI's evasion
		# and says nothing at all about the weapon.
		ship.set("_aim_at", Vector3(victim.global_position.x, 0.0,
			victim.global_position.z))
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var killed: bool = not is_instance_valid(victim) or not victim.is_alive()
	print("  %.0f hp trooper: %s after %.2f s of fire"
		% [full, "DOWN" if killed else "still up", t])
	_ok(killed, "the LAAT could not kill one stationary trooper in six seconds of fire")
	_ok(t > 0.35,
		"the LAAT kills a trooper in %.2f s — that is a map-wide instant delete, not a gunship" % t)
	g.firing = false
	if is_instance_valid(victim):
		victim.queue_free()
	ship.queue_free()
	g.queue_free()
	await get_tree().process_frame
	_done.append("gunship ttk")


## 6. DOES THE BARRAGE PUNISH BUNCHING, OR JUST EVERYONE?
##
## The whole design claim for picking its own target is that it lands on the
## densest group — which is only a real claim if a SPREAD side survives it. Same
## six bodies, same seven seconds, standing 18 m apart instead of 2.
func _orbital_spread() -> void:
	print("\n-- ORBITAL STRIKE: the same six, spread out --")
	var caller := Gunner.new()
	add_child(caller)
	caller.global_position = Vector3.ZERO
	var victims: Array[Node3D] = []
	for i in 6:
		victims.append(await _victim(Vector3(-60.0 + i * 18.0, 0.6, -40.0)))
	var start := 0.0
	for v in victims:
		start += v.health
	var strike: Node3D = ORBITAL.new()
	add_child(strike)
	strike.global_position = caller.global_position
	caller.firing = true
	strike.begin(caller, 0, ORBITAL_WINDOW)
	# THE SAME AIMING EFFORT, ON A SIDE THAT IS NOT BUNCHED. The player picks a
	# target and holds the mark on him — exactly what the check above does, on
	# exactly one body — so the ONLY difference between the two measurements is
	# how the enemy was standing. That is the design claim stated as an
	# experiment: bunching is what this punishes, and spreading out is what beats
	# it. Holding the mark on the CENTROID here would be a different weapon
	# entirely, since the centroid of six men 18 m apart has nobody standing on it.
	var mark: Node3D = victims[2]
	var waited := 0.0
	while waited < ORBITAL_WINDOW + 4.0:
		if is_instance_valid(mark) and mark.is_alive():
			strike.set("_aim", Vector3(mark.global_position.x, 0.0,
				mark.global_position.z))
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var left := 0.0
	var dead := 0
	for v in victims:
		if not is_instance_valid(v) or not v.is_alive():
			dead += 1
			continue
		left += maxf(0.0, v.health)
	print("  6 bots 18 m apart: %.0f of %.0f health lost, %d down"
		% [start - left, start, dead])
	_ok(dead < 6,
		"the orbital strike wiped a side standing 18 m apart — it is a map nuke, not a punishment for bunching")
	# ...and the honest version of the same claim: most of them have to WALK AWAY
	# from it. `dead < 6` would still pass with five of six killed.
	_ok(dead <= 3,
		"the orbital strike killed %d of 6 men standing 18 m apart while aimed at ONE of them — spreading out has to be the answer to it"
			% dead)
	for v in victims:
		if is_instance_valid(v):
			v.queue_free()
	caller.queue_free()
	await get_tree().physics_frame
	_done.append("orbital spread")


## IS THE BALL ON THE INSIDE OF THE TURN, AND CAN THE GUNNER SEE OUT OF IT?
##
## "The turret is on the inside of the turn" is the stated reason this machine
## works at all — the guns stay pointed at the middle, so the gunner is looking at
## the battle for the whole lap instead of half of it. If the ball hangs on the
## OUTSIDE, then aiming at the middle means aiming back across the fuselage, and
## what the gunner sees for most of every lap is the gunship.
##
## It is one comparison and it needs no rendering: which is closer to the centre
## of the circuit, the ball or the hull.
func _gunship_inside() -> void:
	print("\n-- LAAT: which side of the turn is the ball on? --")
	var pair := await _launch(40.0)
	var ship: Node3D = pair[0]
	var g: Gunner = pair[1]
	var inboard := 0
	var laps := 0
	# Sample right round the circuit rather than at one angle: the answer must
	# hold everywhere, and a single sample is one that could be a coincidence.
	for step in 24:
		for _f in 12:
			await get_tree().physics_frame
		var ball: Node3D = ship.get("_ball")
		var centre := Vector3(GameState.map_center.x, 0.0, GameState.map_center.z)
		var ball_gap := Vector2(ball.global_position.x - centre.x,
			ball.global_position.z - centre.z).length()
		var hull_gap := Vector2(ship.global_position.x - centre.x,
			ship.global_position.z - centre.z).length()
		laps += 1
		if ball_gap < hull_gap:
			inboard += 1
	print("  the ball was inboard of the hull on %d of %d samples" % [inboard, laps])
	_ok(inboard == laps,
		"the ball hangs OUTBOARD on %d of %d samples — aiming at the battle means aiming through the fuselage, which is the whole lap spent looking at the gunship"
			% [laps - inboard, laps])
	ship.queue_free()
	g.queue_free()
	await get_tree().process_frame
	_done.append("inside")
