class_name Bot
extends CharacterBody3D
## An AI squadmate, bought on the buy screen and fighting for its owner's team.
##
## Deliberately duck-typed against Player rather than sharing a base class: the
## rest of the game only ever asks a combatant for take_damage / is_headshot /
## is_alive / team, and hitscan already resolves targets by has_method. That
## keeps Player free of AI plumbing and this file readable on its own.
##
## Behaviour is a three-state loop run on the physics tick:
##   HOLD    - no target: fall in behind the owner, or hold ground if they're
##             dead, so a squad doesn't wander off alone.
##   ADVANCE - target seen but too far: close to engagement range.
##   ENGAGE  - target in range and in sight: face it and fire.
## Skill (bought per head) sets how fast it reacts, how far it sees, how well it
## shoots and what it carries — see SKILLS, indexed by Loadout.SQUAD_SKILLS.

const CORPSE_SCENE := preload("res://scenes/fx/corpse.tscn")
const GRENADE_SCENE := preload("res://scenes/fx/grenade.tscn")
const TURRET_SCENE := preload("res://scenes/actors/turret.tscn")
const SHIELD_SCENE := preload("res://scenes/fx/front_shield.tscn")
const CABLE_WIRE_SCENE := preload("res://scenes/fx/cable_wire.tscn")

# One row per Loadout.SQUAD_SKILLS tier, same order.
# aim_error = degrees of aim wobble (the bot's "spread" on top of the weapon's);
# reaction = seconds staring at a new target before it opens fire;
# sight = metres it can acquire from; hold = metres it tries to fight at.
#
# Skill is intelligence, NOT gear: two bots on the same preset differ only in
# how well they fight it. The gun, armour and gadget come from a Loadout preset
# (Loadout.BOT_BUILDS), so a firefight has marksmen and engineers in it instead
# of a dozen identical riflemen. `health` and `speed` below are multipliers on
# whatever the preset's armour gives.
const SKILLS: Array[Dictionary] = [
	{"aim_error": 7.0, "reaction": 0.7, "sight": 45.0, "hold": 14.0,
		"health": 0.85, "speed": 0.92, "turn": 2.8},
	{"aim_error": 3.6, "reaction": 0.45, "sight": 62.0, "hold": 16.0,
		"health": 1.0, "speed": 1.0, "turn": 3.8},
	{"aim_error": 1.8, "reaction": 0.26, "sight": 80.0, "hold": 20.0,
		"health": 1.1, "speed": 1.08, "turn": 5.0},
	{"aim_error": 0.7, "reaction": 0.12, "sight": 105.0, "hold": 24.0,
		"health": 1.25, "speed": 1.15, "turn": 6.4},
]
const BASE_SPEED := 4.0        # walking pace before armour and skill scale it
# Gadget habits. Kept deliberately simple: a bot uses what it bought when the
# obvious moment arrives, rather than planning.
const GRENADE_RANGE := Vector2(9.0, 26.0)   # too close and it kills itself
const GRENADE_COOLDOWN := 6.0
const MEDKIT_AT := 0.45        # heal below this share of health
const TURRET_PLACE_GAP := 12.0  # drop it once we're near where we're heading
const CABLE_COOLDOWN := 6.0
const CABLE_MIN_GOAL := 22.0   # only worth grappling toward something far off
const CABLE_SPEED := 17.0
const CABLE_PULL_TIME := 0.9

const RETARGET_INTERVAL := 0.35  # seconds between target searches (staggered)
# With nothing to shoot, a bot pushes for the middle of the map rather than
# standing on its spawn. Team AI have no owner to follow, so without this they
# never move at all and a match with few humans looks broken.
const ROAM_SPREAD := 16.0    # how far around the middle they'll pick a spot
const ROAM_REPICK := 7.0     # seconds before choosing somewhere new
const ROAM_ARRIVE := 3.5
const FOLLOW_DISTANCE := 5.0 # how close a squadmate tucks in behind its owner
# Sight lines flicker constantly in a firefight — a teammate crosses, the bot
# strafes behind a trunk. Without memory the bot would drop its target, spin
# back toward its owner, then re-acquire and restart its reaction timer, and so
# never actually shoot. It keeps chasing a target it briefly cannot see.
const TARGET_MEMORY := 1.5
const FIRE_CONE_DEG := 12.0      # must be facing this close to shoot
# Trigger discipline. Holding the trigger down forever just overheats the gun
# and locks it out for longer than the pause would have cost — without this a
# recruit's low-heat pistol out-damages a veteran's rifle, which is backwards.
const FIRE_HEAT_CEILING := 0.7
const STRAFE_SPEED := 0.45       # share of speed used to circle at hold range
const UNSTICK_RADIUS := 0.8      # matches Player: never let capsules stack
const UNSTICK_SPEED := 5.0
const EYE_HEIGHT := 1.5
const TARGET_AIM_HEIGHT := 1.0  # aim at the chest, not the feet
const AIM_REROLL := 0.25  # seconds a given aim error is held for
# Recoil applies to bots too, or raising it across the board would just be a
# one-sided nerf to the humans. It's added straight onto the head, and _aim_head
# lerping back toward the target IS the recovery — so a bot holding the trigger
# climbs off its mark exactly like a player does. Scaled down a little because
# that lerp is slower than the player's RECOIL_RECOVER and a bot can't pull
# down against the climb the way a player can.
const RECOIL_TAKE := 0.75
const RECOIL_YAW_SHARE := 0.5  # sideways lean per shot, as a share of the pitch

enum State { HOLD, ADVANCE, ENGAGE }

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D          # who paid for it; the bot falls in behind them
var health := 90.0
var loadout: Loadout              # the preset it deployed with

var _skill: Dictionary = SKILLS[1]
var _state: int = State.HOLD
var _target: Node3D
var _retarget_in := 0.0
var _reaction_left := 0.0
var _memory_left := 0.0  # grace left on a target we've lost sight of
var _aim_offset := Vector2.ZERO  # held aim error (yaw, pitch) in radians
var _aim_reroll_in := 0.0
var _roam_target := Vector3.ZERO
var _roam_left := 0.0
var _speed := 4.0
var _grenades := 0
var _medkits := 0
var _grenade_cd := 0.0
var _cable_cd := 0.0
var _cable_left := 0.0
var _cable_anchor := Vector3.ZERO
var _turret: Node3D
var _shield: Node3D
var _strafe_dir := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon
@onready var model: CharacterModel = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	GameState.register_combatant(self)
	# Own capsule instance, so one bot's shape isn't shared with every other.
	_collision.shape = _collision.shape.duplicate()
	weapon.shooter = self
	weapon.fired.connect(_on_weapon_fired)
	# Stagger the search so a squad of four doesn't retarget on the same frame.
	_retarget_in = randf() * RETARGET_INTERVAL
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


## Called by the owner right after spawning it. `build` picks which preset it
## deploys with; -1 rolls one at random, which is what a team fill wants.
func setup(owner: Node3D, bot_team: int, skill_index: int, build := -1) -> void:
	owner_player = owner
	team = bot_team
	_skill = SKILLS[clampi(skill_index, 0, SKILLS.size() - 1)]
	loadout = Loadout.bot_build(build if build >= 0 else randi())
	var armor := loadout.armor_stats()
	health = float(armor["health"]) * float(_skill["health"])
	_speed = BASE_SPEED * float(armor["speed"]) * float(_skill["speed"])
	_grenades = loadout.grenades
	_medkits = loadout.medkits
	model.set_team_color(GameState.TEAM_COLORS[team])
	weapon.set_class(loadout.deploy_class(), loadout.primary_mods())
	if loadout.gadget == Loadout.Gadget.SHIELD:
		_raise_shield()
	# The bot's gun is a world object, not a viewmodel: everyone should see it.
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1


func is_alive() -> bool:
	return not _dead


## Same contract as Player: hitscan and splash both find this by method name.
func is_headshot(world_pos: Vector3) -> bool:
	return world_pos.y - global_position.y >= 1.42


func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if _dead:
		return
	if attacker != null and "team" in attacker and attacker.team == team:
		return  # friendly fire is off for bots too
	health -= amount
	# Same contract as Player: confirm the hit back to whoever landed it, only
	# once the damage is real.
	if attacker != null and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	if health <= 0.0:
		_die(attacker)


func _die(attacker: Node) -> void:
	_dead = true
	if attacker != null and "team" in attacker and attacker.team != team:
		GameState.add_frag(attacker.team)
		if attacker.has_method("credit_kill"):
			attacker.credit_kill()
	var corpse := CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(corpse)
	var push := Vector3.ZERO
	if attacker is Node3D:
		push = global_position - (attacker as Node3D).global_position
	corpse.launch(Transform3D(Basis(Vector3.UP, rotation.y), global_position),
		GameState.TEAM_COLORS[team], push)
	if is_instance_valid(_turret):
		_turret.queue_free()  # the engineer's turret dies with the engineer
	queue_free()  # bots don't respawn; the owner re-buys them on their next deploy


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not GameState.match_live:
		weapon.update_fire(false, false)  # hold until the match is called on
		return
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
	_cable_cd = maxf(_cable_cd - delta, 0.0)
	_use_medkit_if_hurt()
	_retarget_in -= delta
	_memory_left = maxf(_memory_left - delta, 0.0)
	if _retarget_in <= 0.0:
		_retarget_in = RETARGET_INTERVAL
		_acquire_target()

	if is_instance_valid(_target) and _target.is_alive():
		_fight(delta)
	else:
		_target = null
		_state = State.HOLD
		_patrol(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _cable_left > 0.0:
		# Being reeled in by our own grapple: that overrides normal steering.
		_cable_left -= delta
		var to_anchor := _cable_anchor - global_position
		if to_anchor.length() <= 2.5:
			_cable_left = 0.0
		else:
			velocity = to_anchor.normalized() * CABLE_SPEED
	move_and_slide()
	_animate()


## Nearest living enemy that's within sight and actually visible. Bots ignore
## anything behind cover, so they don't shoot through the map.
func _acquire_target() -> void:
	var best: Node3D = null
	var best_gap: float = _skill["sight"]
	for c in GameState.combatants:
		if c == self or not c.is_alive() or c.team == team:
			continue
		var gap := global_position.distance_to(c.global_position)
		if gap < best_gap and _can_see(c):
			best_gap = gap
			best = c
	if best == null:
		# Nothing visible: hang onto the last one for a moment before giving up.
		if _memory_left > 0.0 and is_instance_valid(_target) and _target.is_alive():
			return
		_target = null
		return
	_memory_left = TARGET_MEMORY
	if best == _target:
		return
	_target = best
	# Only a genuinely NEW target costs reaction time; re-spotting the one we
	# were already fighting does not.
	_reaction_left = _skill["reaction"]


func _can_see(other: Node3D) -> bool:
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var to := other.global_position + Vector3.UP * EYE_HEIGHT * 0.6
	# Smoke has no collider (it would stop bullets too), so it is checked
	# separately — this is what makes a smoke grenade break an AI's lock.
	if GameState.sight_blocked(from, to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 0b11  # world + bodies
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == other


func _fight(delta: float) -> void:
	var to_target := _target.global_position - global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var gap := flat.length()
	_face(flat, delta)
	_aim_head(delta)

	var hold: float = _skill["hold"]
	_state = State.ENGAGE if gap <= hold else State.ADVANCE
	var speed := _speed
	if _state == State.ADVANCE:
		var step := flat.normalized() * speed
		velocity.x = step.x
		velocity.z = step.z
	else:
		# In range: circle rather than stand still, so it isn't a free headshot.
		var side := flat.normalized().cross(Vector3.UP) * _strafe_dir
		velocity.x = side.x * speed * STRAFE_SPEED
		velocity.z = side.z * speed * STRAFE_SPEED
	_apply_unstick()

	_place_turret_if_ready(false)  # in contact: dig in where we stand
	_reaction_left = maxf(_reaction_left - delta, 0.0)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	var on_aim := rad_to_deg(facing.angle_to(flat.normalized())) <= FIRE_CONE_DEG
	var may_fire := _state == State.ENGAGE and on_aim and _reaction_left <= 0.0 \
		and weapon.heat() < FIRE_HEAT_CEILING
	weapon.update_fire(may_fire, may_fire)
	_throw_grenade_if_useful(gap)


## Nothing to shoot. A bought squadmate falls in behind the player who paid for
## it; anyone else (team AI, or a squadmate whose owner is down) pushes for the
## middle of the map, which is where the fighting is on every layout.
func _patrol(delta: float) -> void:
	# Ease the gun back to level while nothing is being aimed at.
	head.rotation.x = lerpf(head.rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	head.rotation.y = lerpf(head.rotation.y, 0.0, clampf(delta * 3.0, 0.0, 1.0))

	var goal := _patrol_goal(delta)
	_try_cable(goal)
	var flat := goal - global_position
	flat.y = 0.0
	var gap := flat.length()
	var arrive := FOLLOW_DISTANCE if _has_owner() else ROAM_ARRIVE
	_place_turret_if_ready(gap <= TURRET_PLACE_GAP)
	if gap <= arrive:
		velocity.x = 0.0
		velocity.z = 0.0
		if not _has_owner():
			_roam_left = 0.0  # arrived: pick somewhere new on the next tick
		_apply_unstick()
		return
	_state = State.ADVANCE
	_face(flat, delta)
	var step := flat.normalized() * _speed
	velocity.x = step.x
	velocity.z = step.z
	_apply_unstick()


## Gadget habits, all deliberately simple: use what you bought at the obvious
## moment. Together these are what make an AI firefight look like a firefight
## rather than two lines of riflemen.
func _use_medkit_if_hurt() -> void:
	if _medkits <= 0:
		return
	var full := float(loadout.armor_stats()["health"]) * float(_skill["health"])
	if health > full * MEDKIT_AT:
		return
	_medkits -= 1
	health = minf(health + Loadout.MEDKIT_HEAL, full)


## Lob one at a target that's far enough away not to catch us in the blast.
func _throw_grenade_if_useful(gap: float) -> void:
	if _grenades <= 0 or _grenade_cd > 0.0 or not is_instance_valid(_target):
		return
	if gap < GRENADE_RANGE.x or gap > GRENADE_RANGE.y:
		return
	_grenades -= 1
	_grenade_cd = GRENADE_COOLDOWN
	var nade := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(nade)
	var aim := (_target.global_position + Vector3.UP * 0.8) - head.global_position
	# Lob it: the further away, the more arc, so it lands rather than skids.
	var toss := (aim.normalized() + Vector3.UP * (0.25 + gap * 0.012)).normalized() \
		* (9.0 + gap * 0.45)
	nade.launch(head.global_position + aim.normalized() * 0.6, toss, self)


## Engineers drop their turret once they've reached the ground they're holding,
## or the moment they make contact, and only ever run one at a time.
##
## `near_goal` is measured against the bot's OWN patrol goal rather than the
## capture area, so this works the same in deathmatch: keying it to the zone
## meant an engineer in deathmatch had to wander within a few metres of the map
## origin before it would ever deploy.
func _place_turret_if_ready(near_goal: bool) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.TURRET:
		return
	if is_instance_valid(_turret):
		return
	if not near_goal and not is_instance_valid(_target):
		return
	_turret = TURRET_SCENE.instantiate()
	get_parent().add_child(_turret)
	_turret.global_position = global_position - global_transform.basis.z * 2.0
	_turret.setup(self, team)


## Scouts grapple ahead when they have a long way to go, which is both faster
## and the only way you'll see the wire fly in a match with no humans in it.
func _try_cable(goal: Vector3) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.CABLE:
		return
	if _cable_cd > 0.0 or _cable_left > 0.0:
		return
	if global_position.distance_to(goal) < CABLE_MIN_GOAL:
		return
	var from := head.global_position
	var toward := (goal - from)
	toward.y = 0.0
	var to := from + toward.normalized() * 30.0 + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1  # world geometry only
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_cable_cd = CABLE_COOLDOWN
	_cable_anchor = hit["position"]
	_cable_left = CABLE_PULL_TIME
	var wire := CABLE_WIRE_SCENE.instantiate()
	get_parent().add_child(wire)
	wire.launch(self, weapon, _cable_anchor, 0.12)


func _raise_shield() -> void:
	if is_instance_valid(_shield):
		return
	_shield = SHIELD_SCENE.instantiate()
	add_child(_shield)
	_shield.setup(GameState.TEAM_COLORS[team])


## Bodies our own fire ignores — the same contract Player exposes, so a bot with
## a front shield can shoot through its own cover.
func hitscan_exclusions() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	if is_instance_valid(_shield):
		out.append(_shield.get_rid())
	return out


func _has_owner() -> bool:
	return owner_player != null and is_instance_valid(owner_player) \
		and owner_player.is_alive()


func _patrol_goal(delta: float) -> Vector3:
	if _has_owner():
		return owner_player.global_position
	_roam_left -= delta
	if _roam_left <= 0.0:
		_roam_left = ROAM_REPICK
		# Head for the capture area when the mode has one, otherwise the middle
		# of the map. Spread around it, so a squad holds ground instead of all
		# standing on the same spot.
		var focus := GameState.zone_point if GameState.zone_active else Vector3.ZERO
		var spread := ROAM_SPREAD * (0.35 if GameState.zone_active else 1.0)
		var angle := randf() * TAU
		var reach := sqrt(randf()) * spread
		_roam_target = focus + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
	# A zone that moved mid-wander should pull the squad straight away.
	if GameState.zone_active and Vector2(_roam_target.x - GameState.zone_point.x,
			_roam_target.z - GameState.zone_point.z).length() > ROAM_SPREAD:
		_roam_left = 0.0
	return _roam_target


func _face(flat_dir: Vector3, delta: float) -> void:
	if flat_dir.length() < 0.01:
		return
	var want := atan2(-flat_dir.x, -flat_dir.z)  # -Z is forward
	rotation.y = rotate_toward(rotation.y, want, float(_skill["turn"]) * delta)


## Point the gun at the target, off by the skill's aim error: a recruit sprays
## around its mark, an elite is nearly on it.
##
## The error is a HELD offset re-rolled a few times a second, not fresh noise
## every frame. Per-frame noise fed through the aim lerp just averages back out
## to a perfect shot, which made all four tiers shoot identically. It's applied
## to the head in both axes, so the gun is off without the body turning — the
## same trick the player's recoil yaw uses.
##
## Pitch is measured from the HEAD, not the body origin: the gun sits about
## 1.4 m up, so solving the angle from the feet sends every shot roughly a body
## height over the target at normal range.
func _aim_head(delta: float) -> void:
	_aim_reroll_in -= delta
	if _aim_reroll_in <= 0.0:
		_aim_reroll_in = AIM_REROLL
		var wobble := deg_to_rad(float(_skill["aim_error"]))
		_aim_offset = Vector2(randf_range(-wobble, wobble), randf_range(-wobble, wobble))
	var muzzle := head.global_position
	var aim_at: Vector3 = _target.global_position + Vector3.UP * TARGET_AIM_HEIGHT
	var to_aim := aim_at - muzzle
	var flat := Vector3(to_aim.x, 0.0, to_aim.z).length()
	var pitch := atan2(to_aim.y, maxf(flat, 0.01))
	var blend := clampf(delta * 8.0, 0.0, 1.0)
	head.rotation.x = lerpf(head.rotation.x, pitch + _aim_offset.y, blend)
	head.rotation.y = lerpf(head.rotation.y, _aim_offset.x, blend)


## The gun kicks the bot's aim up the same way it kicks a player's camera. The
## shove big guns give (kick_back) is ignored: a bot walks by writing its own
## velocity every frame and would simply erase it.
func _on_weapon_fired(cam_recoil: float, _kick_back: float) -> void:
	head.rotation.x += cam_recoil * RECOIL_TAKE
	head.rotation.y += randf_range(-RECOIL_YAW_SHARE, RECOIL_YAW_SHARE) \
		* cam_recoil * RECOIL_TAKE


## Same horizontal separation the players use: two capsules inside each other
## get ejected upwards by the solver and never come back down.
func _apply_unstick() -> void:
	for c in GameState.combatants:
		if c == self or not c.is_alive():
			continue
		var away := global_position - c.global_position
		away.y = 0.0
		var gap := away.length()
		if gap >= UNSTICK_RADIUS or gap < 0.001:
			continue
		var push := away.normalized() * (1.0 - gap / UNSTICK_RADIUS) * UNSTICK_SPEED
		velocity.x += push.x
		velocity.z += push.z


## Same idle/walk/run rule the player uses, minus the jump (bots don't jump).
func _animate() -> void:
	var anim := model.anim_player
	if anim == null:
		return
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var clip := "idle"
	if ground_speed > 3.9:
		clip = "run"
	elif ground_speed > 0.15:
		clip = "walk"
	if anim.assigned_animation != clip and anim.has_animation(clip):
		anim.play(clip, 0.12)
