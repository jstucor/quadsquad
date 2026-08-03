class_name Vehicle
extends CharacterBody3D
## A drivable repulsorlift speeder — ONE mechanism and four table rows, the same
## deal as `CharacterModel.STYLES` and `Weapon.PROFILES`.
##
## ONLY STAR WARS HAS VEHICLES. That is a deliberate scope line and it is stated
## once, in `spawns_for()`: a speeder is the thing this setting is built out of,
## where a Warthog and a Trukk are whole vehicle families that would each want
## their own handling model, seat count and gunner. Halo and Warhammer field
## none, and every caller asks the one function rather than testing the universe
## itself — so when a second setting does get vehicles it is a table row here and
## nothing else in the game changes.
##
## WHY A CharacterBody3D AND NOT A VehicleBody3D. Godot's VehicleBody3D is a
## wheeled raycast-suspension car, and these maps are heightfield terrain: the
## documented split between `height_at` (the analytic surface) and the coarse
## collision MESH means the ground a wheel would ride has flat triangles sitting
## above the curve they approximate, with a seam every cell. A wheeled body
## catches on those. A repulsorlift does not care — it solves a hover height off
## a single downward ray and rides whatever it actually collides with, which is
## both the Star Wars answer and the one that survives the terrain this game has.
## It also keeps the vehicle inside `move_and_slide`, so it stops at exactly the
## walls, cover boxes and prop hulls everything else stops at, with no second
## collision story to maintain.
##
## It is a COMBATANT (`is_alive` / `team` / `take_damage` / `body_height`), so
## bots shoot at it, turrets track it and it blocks a spawn marker, all without a
## shared base class — the same duck-typed contract Bot and Turret already meet.

const REPUBLIC := 0
const SEPARATIST := 1
const EMPIRE := 2
const REBEL := 3

## ONE ROW PER STAR WARS FACTION. Everything that differs between the four is
## here; the driving, hovering, shooting, mounting and dying below is shared.
##
## The four are deliberately spread across the handling envelope rather than
## being one speeder in four colours, because the whole point of putting a
## vehicle on a map is that taking it is a DECISION. A STAP is the fastest thing
## on the field and dies to a grenade; a T-47 will survive being shot at and
## cannot turn. If they all flew the same, the faction it belonged to would be
## the only difference and nobody would ever choose one over walking.
const VEHICLES := {
	REPUBLIC: {
		"name": "BARC SPEEDER",
		"build": "barc",
		"health": 320.0,
		"top_speed": 22.0,   # m/s. A sprint is ~7, so a speeder is triple pace.
		"accel": 14.0,
		"turn": 2.2,         # rad/s at full lock
		"hover": 0.9,        # metres of clearance the repulsor holds
		"gun": Weapon.Class.TURRET,
		"hull": Vector3(1.15, 0.42, 3.10),
	},
	SEPARATIST: {
		"name": "STAP",
		"build": "stap",
		# The glass cannon: a droid stands on a pole with two guns bolted to it.
		# Fastest and highest, and the only one a single frag will finish.
		"health": 190.0,
		"top_speed": 25.0,
		"accel": 17.0,
		"turn": 2.9,
		"hover": 1.5,
		"gun": Weapon.Class.TURRET,
		"hull": Vector3(0.85, 0.36, 1.90),
	},
	EMPIRE: {
		"name": "74-Z SPEEDER BIKE",
		"build": "speeder_bike",
		"health": 250.0,
		"top_speed": 26.0,   # the fastest in a straight line, and the least armoured
		"accel": 18.0,
		"turn": 2.4,
		"hover": 0.85,
		"gun": Weapon.Class.TURRET,
		"hull": Vector3(0.80, 0.38, 3.40),
	},
	REBEL: {
		"name": "T-47 AIRSPEEDER",
		"build": "airspeeder",
		# The gunship of the four: it flies over cover the others have to go
		# around, takes real punishment, and handles like a barge.
		"health": 520.0,
		"top_speed": 19.0,
		"accel": 9.0,
		"turn": 1.5,
		"hover": 2.4,
		"gun": Weapon.Class.HMG,
		"hull": Vector3(2.30, 0.55, 3.60),
	},
}

## How far a speeder rides above the ground is a per-row number, but how HARD it
## holds that height is not: too soft and it wallows through a dip like a boat,
## too stiff and every terrain seam is a kick in the teeth. Critically damped is
## the only setting that reads as a repulsor rather than as a spring.
const HOVER_STIFFNESS := 26.0
const HOVER_DAMPING := 9.0
## Past this, there is no ground under us and we are falling, not hovering.
const HOVER_PROBE := 6.0
const GRAVITY := 22.0

## A speeder BANKS into its turn. Purely cosmetic and worth every line: without
## it the hull slides round a corner dead level, which reads as an object being
## dragged rather than a machine being flown.
const BANK_MAX := 0.42
const BANK_LERP := 5.0
## ...and pitches its nose down under power, for the same reason.
const PITCH_MAX := 0.13

## Drag, applied whenever the throttle is off. This is what makes a speeder
## coast rather than stop dead, which is most of what separates flying one from
## walking fast.
const COAST_DRAG := 3.2
const REVERSE_FRAC := 0.35   # reverse is deliberately slow; turn round instead

## The gun follows the DRIVER'S LOOK inside this cone, and no further. A speeder
## whose gun tracks anywhere the camera points is a flying turret, which removes
## the entire reason the thing has a facing; clamping it means aiming and
## STEERING are the same decision, which is what flying a gun platform should be.
const GUN_YAW_LIMIT := deg_to_rad(38.0)
const GUN_PITCH_LIMIT := deg_to_rad(26.0)
const GUN_TRACK := 9.0

## How close a player has to be, and how a dismount is placed. Sideways and clear
## of the hull: dropping the driver at the vehicle's own origin puts two capsules
## inside each other, which is the documented ejection bug.
const DISMOUNT_SIDE := 2.1
const DISMOUNT_LIFT := 0.6

## An empty vehicle nobody is driving still costs a physics tick and four draws.
## A wrecked one is worth watching go up, and then it is worth nothing.
const WRECK_LINGER := 2.5

signal driver_changed(driver: Node3D)

var team: int = REPUBLIC
var health := 320.0
var max_health := 320.0
var driver: Node3D               # the Player flying it, or null

var _row: Dictionary = {}
var _dead := false
var _throttle := 0.0             # -1..1, what the driver is asking for
var _steer := 0.0
var _bank := 0.0
var _wreck_left := 0.0
var _mats := {}
var _gun_yaw := 0.0
var _gun_pitch := 0.0

@onready var _hull: CollisionShape3D = $CollisionShape3D
@onready var _seat: Node3D = $Seat
@onready var _body: Node3D = $Body          # everything that banks
@onready var _mount: Area3D = $MountArea
@onready var _gun_pivot: Node3D = $Body/GunPivot
@onready var weapon: Weapon = $Body/GunPivot/Weapon


## WHICH TEAMS GET A VEHICLE, and the only place the Star-Wars-only rule lives.
## Returns an empty array for every other setting, so a caller never has to know
## which universe it is in — `for t in Vehicle.spawns_for(universe)` is simply an
## empty loop in Halo and Warhammer.
static func spawns_for(universe: int) -> Array:
	if universe != Loadout.Universe.STAR_WARS:
		return []
	return VEHICLES.keys()


static func vehicle_name(vehicle_team: int) -> String:
	return String(VEHICLES.get(vehicle_team, {}).get("name", "SPEEDER"))


func _ready() -> void:
	GameState.register_combatant(self)
	weapon.shooter = self
	# Built here rather than in setup() so a vehicle dropped into a look test or a
	# cost harness has a body without anybody remembering to ask, exactly like the
	# turret. setup() only re-tints and re-arms.
	if _row.is_empty():
		setup(team)
	_mount.body_entered.connect(_on_body_entered)
	_mount.body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func setup(vehicle_team: int) -> void:
	team = vehicle_team
	_row = VEHICLES.get(team, VEHICLES[REPUBLIC])
	max_health = float(_row["health"])
	health = max_health
	var size: Vector3 = _row["hull"]
	var shape := BoxShape3D.new()
	shape.size = size
	_hull.shape = shape
	_hull.position.y = size.y * 0.5 + 0.1
	_build_model()
	weapon.set_class(_row["gun"])
	# A world object, not a viewmodel: every camera sees this gun. The same stamp
	# the turret needs, and for the same reason — a Weapon's meshes default to the
	# viewmodel layer its owner would have put them on.
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1


## --- the combatant contract ---------------------------------------------------

func is_alive() -> bool:
	return not _dead


## What something aiming at this should aim AT. Duck-typed by
## `GameState.aim_height`, the same as every body in the roster — a bot that
## fires at a flat 1.0 m chest puts its rounds over a speeder bike and into the
## belly of an airspeeder.
func body_height() -> float:
	return float(_row.get("hover", 1.0)) + float(_row["hull"].y) * 0.5


func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if _dead:
		return
	if attacker != null and "team" in attacker and attacker.team == team:
		return  # friendly fire is off here exactly as it is everywhere else
	health -= amount
	if attacker != null and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	# THE DRIVER IS NOT SHIELDED BY THE HULL, they are exposed by it. A speeder
	# takes the round, and a share of it reaches whoever is flying — otherwise the
	# right play is always to sit in one, which makes the vehicle a bunker.
	if driver != null and is_instance_valid(driver) and driver.has_method("take_damage"):
		driver.take_damage(amount * DRIVER_BLEED, attacker, false)
	if health <= 0.0:
		_destroy(attacker)


const DRIVER_BLEED := 0.20


func _destroy(attacker: Node) -> void:
	_dead = true
	Blast.pop(get_tree().current_scene, global_position + Vector3.UP * 0.8, 4.5, 1.4)
	if driver != null and is_instance_valid(driver):
		_eject(true)
	if attacker != null and "team" in attacker and attacker.team != team:
		GameState.add_frag(attacker.team)
		if attacker.has_method("credit_kill"):
			attacker.credit_kill()
	GameState.unregister_combatant(self)
	weapon.update_fire(false, false)
	_wreck_left = WRECK_LINGER
	_hull.disabled = true


## --- mounting -----------------------------------------------------------------
##
## This rides the EXISTING interact edge — `Player.pickup_in_reach` advertises
## and `Player.pickup_pressed` is consumed — rather than reading the control
## itself. That is not tidiness: an input edge is consumed by whoever reads it
## first, so a vehicle parked over a royale crate would otherwise race it and one
## of the two would silently never respond. Publishing through the same field
## means the existing "one press, one thing" rule covers both.

func _on_body_entered(body: Node) -> void:
	if not (body is Player) or not may_drive(body):
		return
	body.pickup_in_reach = self


func _on_body_exited(body: Node) -> void:
	if body is Player and body.pickup_in_reach == self:
		body.pickup_in_reach = null


## The prompt string, so the HUD names it without knowing what a vehicle is —
## the same `label()` a crate answers.
func label() -> String:
	return String(_row.get("name", "SPEEDER"))


func _physics_process(delta: float) -> void:
	if _dead:
		_wreck_left -= delta
		if _wreck_left <= 0.0:
			queue_free()
		return
	# Held exactly like everything else that acts on its own until the match is
	# called on. Without it a speeder is three seconds of free ground.
	if not GameState.match_live:
		weapon.update_fire(false, false)
		_settle(delta)
		return
	if driver != null and not is_instance_valid(driver):
		driver = null   # they were freed under us (map change, a hard respawn)
	if driver != null:
		if not driver.is_alive():
			_eject(true)
		elif driver.pickup_pressed:
			driver.pickup_pressed = false   # one press, one action
			_eject(false)
	if driver == null:
		_claim_waiting_driver()
	_drive(delta)
	_carry_driver()


## Nobody in the seat: look for the player standing in the mount area with the
## interact edge pending. Reading `pickup_in_reach` back means we only ever claim
## somebody who is genuinely next to THIS vehicle and has not already spent the
## press on a crate.
##
## NOTE THE TEAM CHECK IS REPEATED HERE, and that is not redundant. The mount
## area only ADVERTISES — it decides whose HUD lights up — and a gate that lives
## only on the advertisement is a gate on the wrong thing: `pickup_in_reach` is a
## plain public field that a crate, a test or a later feature can set from
## anywhere, and the moment one does, the enemy check is gone with no error
## anywhere. The rule belongs on the ACTION. `tests/vehicles.gd` sets the field
## directly for exactly this reason and caught it doing so.
func _claim_waiting_driver() -> void:
	for c in GameState.combatants:
		if not (c is Player) or not c.is_alive():
			continue
		if c.pickup_in_reach != self or not c.pickup_pressed:
			continue
		if not may_drive(c):
			continue
		c.pickup_pressed = false
		_mount_player(c)
		return


## You fly your own side's speeder. Asked by the mount area AND by the claim, so
## the two can never disagree about who is allowed in the seat.
func may_drive(who: Node) -> bool:
	if _dead or driver != null:
		return false
	return "team" in who and who.team == team


func _mount_player(p: Node3D) -> void:
	if not may_drive(p):
		return
	driver = p
	p.pickup_in_reach = null
	p.enter_vehicle(self)
	driver_changed.emit(p)


## Put the driver back on their feet beside the hull. `forced` is a wreck or a
## death — the same exit, but it does not consume a press.
func _eject(forced: bool) -> void:
	var p := driver
	driver = null
	if p == null or not is_instance_valid(p):
		return
	if p.has_method("exit_vehicle"):
		var side := global_transform.basis.x.normalized()
		var spot := global_position + side * DISMOUNT_SIDE + Vector3.UP * DISMOUNT_LIFT
		p.exit_vehicle(spot, rotation.y, forced)
	driver_changed.emit(null)


## The driver's body is slaved to the seat every physics frame. It is hidden and
## its collision is off while mounted (`Player.enter_vehicle` does that), so this
## is only carrying the transform the camera hangs off — the existing
## RemoteTransform3D on the player's Head is untouched and keeps working.
func _carry_driver() -> void:
	if driver == null or not is_instance_valid(driver):
		return
	driver.global_position = _seat.global_position


## --- flying -------------------------------------------------------------------

func _drive(delta: float) -> void:
	var top: float = _row["top_speed"]
	if driver != null:
		var move: Vector2 = driver.vehicle_move()
		_throttle = -move.y
		_steer = move.x
		# Steering authority falls off toward a standstill, because a speeder
		# pivoting on the spot at zero throttle is a turret, not a vehicle.
		var authority := clampf(_flat_speed() / (top * 0.35), 0.0, 1.0)
		rotation.y -= _steer * float(_row["turn"]) * authority * delta
	else:
		_throttle = 0.0
		_steer = 0.0

	var forward := -global_transform.basis.z
	var want := _throttle * top * (1.0 if _throttle >= 0.0 else REVERSE_FRAC)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if absf(_throttle) > 0.01:
		var target := forward * want
		flat = flat.move_toward(target, float(_row["accel"]) * delta)
	else:
		flat = flat.move_toward(Vector3.ZERO, COAST_DRAG * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	_apply_hover(delta)
	move_and_slide()
	_apply_attitude(delta)
	_aim_gun(delta)


## The repulsor. A ray straight down finds the surface, and a damped spring holds
## the hull at the row's clearance above it. Note the ray EXCLUDES this body and
## masks WORLD ONLY (layer 1): masking bodies too would make a speeder ride up
## over anybody it drove across, which is both wrong and hilarious.
func _apply_hover(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.4
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * HOVER_PROBE)
	query.exclude = [get_rid()]
	query.collision_mask = 1
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		velocity.y -= GRAVITY * delta   # out over a chasm: fall like anything else
		return
	var ground: float = (hit["position"] as Vector3).y
	var clearance := global_position.y - ground
	var error: float = float(_row["hover"]) - clearance
	velocity.y += (error * HOVER_STIFFNESS - velocity.y * HOVER_DAMPING) * delta


## Bank into the turn and pitch under power. Applied to the BODY node, never to
## the vehicle itself: rolling the CharacterBody3D would roll its collision box
## and its hover ray with it, so the thing would climb its own bank.
func _apply_attitude(delta: float) -> void:
	var top: float = _row["top_speed"]
	var want_bank := -_steer * BANK_MAX * clampf(_flat_speed() / top, 0.0, 1.0)
	_bank = lerpf(_bank, want_bank, clampf(delta * BANK_LERP, 0.0, 1.0))
	_body.rotation.z = _bank
	_body.rotation.x = lerpf(_body.rotation.x, -_throttle * PITCH_MAX,
		clampf(delta * BANK_LERP, 0.0, 1.0))


## Point the gun where the driver is looking, inside the cone. With no driver it
## eases back to centre rather than snapping — a parked speeder with its gun
## cranked hard over reads as broken.
func _aim_gun(delta: float) -> void:
	var want_yaw := 0.0
	var want_pitch := 0.0
	if driver != null and is_instance_valid(driver):
		var look: Vector2 = driver.vehicle_look()
		# The driver's yaw is absolute; ours is relative to a hull that is itself
		# turning, so the difference is what the gun has to make up.
		want_yaw = clampf(wrapf(look.x - rotation.y, -PI, PI),
			-GUN_YAW_LIMIT, GUN_YAW_LIMIT)
		want_pitch = clampf(look.y, -GUN_PITCH_LIMIT, GUN_PITCH_LIMIT)
	var t := clampf(delta * GUN_TRACK, 0.0, 1.0)
	_gun_yaw = lerpf(_gun_yaw, want_yaw, t)
	_gun_pitch = lerpf(_gun_pitch, want_pitch, t)
	_gun_pivot.rotation.y = _gun_yaw
	_gun_pivot.rotation.x = _gun_pitch
	if driver != null and is_instance_valid(driver):
		var fire: bool = driver.vehicle_firing()
		weapon.update_fire(fire, fire and not _was_firing)
		_was_firing = fire
	else:
		weapon.update_fire(false, false)
		_was_firing = false


var _was_firing := false


## Sit still but keep hovering, for the pre-match hold.
func _settle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, COAST_DRAG * delta)
	velocity.z = move_toward(velocity.z, 0.0, COAST_DRAG * delta)
	_apply_hover(delta)
	move_and_slide()


func _flat_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## --- the models ---------------------------------------------------------------
##
## Built to exactly the rules the turret and the weapons follow: chamfered boxes
## through `Meshes.chamfer_box` (which caches per SIZE, so a pair of outriggers or
## a rank of vents is one mesh), `metallic` 0.0 on every part with steel and
## polymer separated by ALBEDO and ROUGHNESS, materials made ONCE and re-tinted
## rather than rebuilt, and one repeated small feature per hull to give a long
## flat body a sense of scale.
##
## The four are told apart by SILHOUETTE and not by paint, which is the same
## lesson the faction accessories taught: at the thirty metres where you decide
## whether to shoot at it or run from it, colour is the first thing to go. A
## speeder bike is a long thin lance, a BARC is a lance with outriggers, a STAP
## is a vertical pole with nothing around it, and a T-47 is a wide flat wedge.
## Those read at any distance and in any light.

func _build_model() -> void:
	for c in _body.get_children():
		if c is MeshInstance3D:
			_body.remove_child(c)
			c.queue_free()
	var steel := _surface(Color(0.52, 0.54, 0.58), 0.34, 0.50)
	var poly := _surface(Color(0.13, 0.14, 0.16), 0.80, 0.20)
	var trim := _surface(Color(0.75, 0.75, 0.75), 0.42, 0.40)
	var lit := StandardMaterial3D.new()
	lit.metallic = 0.0
	lit.roughness = 0.4
	lit.emission_enabled = true
	# 1.3, not higher: AgX at this project's 1.6 exposure takes emission much past
	# unity to white, and a white engine glow carries no team — which is the whole
	# reason it is lit rather than painted. Same number as the turret's slit.
	lit.emission_energy_multiplier = 1.3
	_mats = {"steel": steel, "poly": poly, "trim": trim, "lit": lit}
	_paint(GameState.team_colors[clampi(team, 0, GameState.team_colors.size() - 1)])
	match String(_row.get("build", "barc")):
		"barc": _build_barc(steel, poly, trim, lit)
		"stap": _build_stap(steel, poly, trim, lit)
		"speeder_bike": _build_speeder_bike(steel, poly, trim, lit)
		"airspeeder": _build_airspeeder(steel, poly, trim, lit)
		_: _build_barc(steel, poly, trim, lit)


## Re-tint, never rebuild — the command posts' 1.7 ms lesson.
func _paint(team_color: Color) -> void:
	if _mats.is_empty():
		return
	_mats["trim"].albedo_color = team_color
	var glow: StandardMaterial3D = _mats["lit"]
	glow.albedo_color = team_color.darkened(0.7)
	glow.emission = team_color


## REPUBLIC — BARC SPEEDER. A fat forward cowl with two outrigger vanes swept out
## and down, which is the shape everyone recognises: it is the only one of the
## four that is WIDE at the front and narrow at the back.
func _build_barc(steel: Material, poly: Material, trim: Material, lit: Material) -> void:
	_box(Vector3(0.60, 0.30, 2.20), Vector3(0, 0.55, 0.10), steel)         # spine
	_box(Vector3(0.86, 0.40, 0.95), Vector3(0, 0.60, -0.95), steel)        # cowl
	_box(Vector3(0.52, 0.16, 0.40), Vector3(0, 0.82, -1.20), trim)         # nose flash
	_box(Vector3(0.44, 0.26, 0.60), Vector3(0, 0.44, 0.95), poly)          # engine block
	_box(Vector3(0.30, 0.12, 0.16), Vector3(0, 0.44, 1.28), lit, false)
	# The outriggers. Swept out AND down, so the silhouette is a shallow V rather
	# than a T — a flat crossbar reads as a plank nailed on.
	for sx: float in [-1.0, 1.0]:
		var vane := Node3D.new()
		_body.add_child(vane)
		vane.position = Vector3(sx * 0.42, 0.56, -0.70)
		vane.rotation = Vector3(0.0, 0.0, sx * 0.34)
		_box(Vector3(0.62, 0.14, 0.70), Vector3(sx * 0.30, 0, 0), steel, true, vane)
		_box(Vector3(0.20, 0.22, 0.30), Vector3(sx * 0.56, -0.06, 0.06), poly, true, vane)
	_saddle(poly, trim)
	_ribs(poly, 3, 0.30, 0.55)


## SEPARATIST — STAP. A single vertical pole with a footplate, two long gun arms
## reaching forward and almost nothing else. It is the outlier of the four on
## purpose: the only one with no hull, so from any angle you can see straight
## through it, which is exactly what a droid riding a stick should look like.
func _build_stap(steel: Material, poly: Material, trim: Material, lit: Material) -> void:
	_box(Vector3(0.18, 1.10, 0.20), Vector3(0, 0.95, 0.25), steel)          # the pole
	_box(Vector3(0.46, 0.10, 0.44), Vector3(0, 0.40, 0.28), poly)           # footplate
	_box(Vector3(0.30, 0.26, 0.34), Vector3(0, 1.52, 0.20), steel)          # repulsor head
	_box(Vector3(0.22, 0.10, 0.12), Vector3(0, 1.52, 0.02), lit, false)
	# Handlebars: the one thing that says a body stands here and holds on.
	_box(Vector3(0.72, 0.07, 0.09), Vector3(0, 1.30, -0.10), trim)
	# The two gun arms, long and thin and reaching well past the pilot. A STAP is
	# read by how far forward its guns hang.
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.10, 0.10, 1.55), Vector3(sx * 0.30, 1.06, -0.75), poly)
		_box(Vector3(0.14, 0.14, 0.22), Vector3(sx * 0.30, 1.06, -1.48), steel)
		_box(Vector3(0.07, 0.07, 0.10), Vector3(sx * 0.30, 1.06, -1.62), trim, false)
	_ribs(poly, 4, 0.16, 1.20, 0.22)


## EMPIRE — 74-Z SPEEDER BIKE. A long thin lance with the steering vanes hinged
## out at the very front. Nearly all of its length is AHEAD of the rider, which is
## what makes it read as fast even parked.
func _build_speeder_bike(steel: Material, poly: Material, trim: Material, lit: Material) -> void:
	_box(Vector3(0.34, 0.30, 3.00), Vector3(0, 0.52, -0.20), steel)         # boom
	_box(Vector3(0.46, 0.34, 0.70), Vector3(0, 0.52, 0.95), poly)           # engine
	_box(Vector3(0.26, 0.14, 0.16), Vector3(0, 0.52, 1.34), lit, false)
	_box(Vector3(0.40, 0.22, 0.50), Vector3(0, 0.66, -1.35), steel)         # nose
	# The forward vanes, hinged out at the tip. Steel, and NOT symmetric with the
	# BARC's: these sit ahead of everything rather than beside the rider.
	for sx: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		_body.add_child(arm)
		arm.position = Vector3(sx * 0.16, 0.62, -1.42)
		arm.rotation = Vector3(0.0, sx * 0.30, 0.0)
		_box(Vector3(0.10, 0.10, 0.85), Vector3(sx * 0.18, 0, -0.35), steel, true, arm)
		_box(Vector3(0.30, 0.08, 0.26), Vector3(sx * 0.30, 0, -0.72), trim, true, arm)
	_saddle(poly, trim)
	_ribs(poly, 4, 0.24, -0.30)


## REBEL — T-47 AIRSPEEDER. Wide, flat and blunt: a two-seat wedge with the laser
## pods hung outboard. The only one of the four that is wider than it is tall by a
## long way, and the only one with a visible canopy.
func _build_airspeeder(steel: Material, poly: Material, trim: Material, lit: Material) -> void:
	_box(Vector3(1.60, 0.42, 2.60), Vector3(0, 0.72, 0.0), steel)           # fuselage
	# The wedge nose. A single tilted plate is the difference between a vehicle
	# and a crate, the same trick the turret's glacis uses.
	var nose := _box(Vector3(1.30, 0.34, 0.90), Vector3(0, 0.70, -1.55), steel)
	nose.rotation.x = 0.20
	_box(Vector3(0.86, 0.34, 0.90), Vector3(0, 1.02, -0.30), poly)          # canopy
	_box(Vector3(0.70, 0.06, 0.62), Vector3(0, 1.20, -0.36), trim)          # canopy frame
	# Outboard laser pods on stub pylons — the wide silhouette IS this vehicle.
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.55, 0.12, 0.70), Vector3(sx * 1.00, 0.72, 0.10), steel)
		_box(Vector3(0.26, 0.26, 1.30), Vector3(sx * 1.28, 0.72, -0.30), poly)
		_box(Vector3(0.14, 0.14, 0.22), Vector3(sx * 1.28, 0.72, -1.02), trim, false)
	_box(Vector3(1.10, 0.40, 0.60), Vector3(0, 0.74, 1.42), poly)           # engine deck
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.24, 0.16, 0.14), Vector3(sx * 0.34, 0.74, 1.76), lit, false)
	_ribs(poly, 5, 0.90, 0.30, 0.30)


## A rider's saddle and grips. Shared by the two bikes, because a saddle is a
## saddle — the point of a shared builder is that the two hulls differ where they
## should and not where they need not.
func _saddle(poly: Material, trim: Material) -> void:
	_box(Vector3(0.44, 0.14, 0.72), Vector3(0, 0.76, 0.28), poly)
	_box(Vector3(0.62, 0.06, 0.08), Vector3(0, 0.90, -0.18), trim)
	_box(Vector3(0.30, 0.30, 0.10), Vector3(0, 0.98, 0.72), poly)   # back rest


## A run of small repeated plates along the hull. THIS IS WHAT GIVES A LONG FLAT
## BODY ITS SCALE — the same lesson as the Coruscant tower mullions and the
## turret's vent slats. Without it a two-metre boom and a five-metre one look
## identical, because there is nothing on either to measure against.
func _ribs(mat: Material, count: int, width: float, from_z: float, step := 0.34) -> void:
	for i in count:
		_box(Vector3(width, 0.05, 0.06), Vector3(0, 0.70, from_z + i * step), mat, false)


func _surface(albedo: Color, roughness: float, spec: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = 0.0   # see the weapon/character materials note: 0.0 everywhere
	m.roughness = roughness
	m.metallic_specular = spec
	return m


## A SMALL PART IS NOT WORTH DRAWING FROM ACROSS THE MAP, exactly as on a body.
## Measured: a speeder is ~26 meshes, and at four viewports that is ~106 draw
## calls each — the same order as a character, and there is one per faction.
## `visibility_range_end` is the engine doing this per camera and for free, which
## is what makes it right for split screen: the speeder a player is standing next
## to keeps its rivets and the other three viewports drop them.
const DETAIL_TRIM := 45.0

## `shadow` off marks the SAME SET as "small trim" on these models, so the one
## flag carries both: no shadow (a 5 cm rib's shadow is not information anybody
## uses) and a visibility range. The hull, cowl, booms and pods are never culled —
## the silhouette is what says which faction's speeder that is, and it is the
## whole reason the four are shaped differently.
func _box(size: Vector3, pos: Vector3, mat: Material, shadow := true,
		into: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Meshes.chamfer_box(size)
	mi.position = pos
	mi.material_override = mat
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = DETAIL_TRIM
	(into if into != null else _body).add_child(mi)
	return mi
