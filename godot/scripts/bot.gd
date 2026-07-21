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

# One row per Loadout.SQUAD_SKILLS tier, same order.
# aim_error = degrees of aim wobble (the bot's "spread" on top of the weapon's);
# reaction = seconds staring at a new target before it opens fire;
# sight = metres it can acquire from; hold = metres it tries to fight at.
#
# Every tier carries the SAME rifle on purpose. What you are buying is
# intelligence, so skill alone has to decide how dangerous a squadmate is —
# giving the tiers different guns made the ladder non-monotonic (a recruit's
# low-heat pistol out-damaged a veteran's rifle, which is backwards for
# something that costs nearly three times as much).
const BOT_WEAPON := Weapon.Class.SOLDIER
const SKILLS: Array[Dictionary] = [
	{"aim_error": 9.0, "reaction": 0.85, "sight": 26.0, "hold": 14.0,
		"health": 70.0, "speed": 3.2, "turn": 2.4},
	{"aim_error": 5.0, "reaction": 0.55, "sight": 36.0, "hold": 16.0,
		"health": 90.0, "speed": 3.7, "turn": 3.4},
	{"aim_error": 2.5, "reaction": 0.32, "sight": 48.0, "hold": 20.0,
		"health": 110.0, "speed": 4.2, "turn": 4.6},
	{"aim_error": 1.0, "reaction": 0.15, "sight": 65.0, "hold": 24.0,
		"health": 130.0, "speed": 4.6, "turn": 6.0},
]

const RETARGET_INTERVAL := 0.35  # seconds between target searches (staggered)
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

enum State { HOLD, ADVANCE, ENGAGE }

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D          # who paid for it; the bot falls in behind them
var health := 90.0

var _skill: Dictionary = SKILLS[1]
var _state: int = State.HOLD
var _target: Node3D
var _retarget_in := 0.0
var _reaction_left := 0.0
var _memory_left := 0.0  # grace left on a target we've lost sight of
var _aim_offset := Vector2.ZERO  # held aim error (yaw, pitch) in radians
var _aim_reroll_in := 0.0
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
	# Stagger the search so a squad of four doesn't retarget on the same frame.
	_retarget_in = randf() * RETARGET_INTERVAL
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


## Called by the owner right after spawning it.
func setup(owner: Node3D, bot_team: int, skill_index: int) -> void:
	owner_player = owner
	team = bot_team
	_skill = SKILLS[clampi(skill_index, 0, SKILLS.size() - 1)]
	health = _skill["health"]
	model.set_team_color(GameState.TEAM_COLORS[team])
	weapon.set_class(BOT_WEAPON)
	# The bot's gun is a world object, not a viewmodel: everyone should see it.
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1


func is_alive() -> bool:
	return not _dead


## Same contract as Player: hitscan and splash both find this by method name.
func is_headshot(world_pos: Vector3) -> bool:
	return world_pos.y - global_position.y >= 1.42


func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return
	if attacker != null and "team" in attacker and attacker.team == team:
		return  # friendly fire is off for bots too
	health -= amount
	if health <= 0.0:
		_die(attacker)


func _die(attacker: Node) -> void:
	_dead = true
	if attacker != null and "team" in attacker and attacker.team != team:
		GameState.add_frag(attacker.team)
	var corpse := CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(corpse)
	var push := Vector3.ZERO
	if attacker is Node3D:
		push = global_position - (attacker as Node3D).global_position
	corpse.launch(Transform3D(Basis(Vector3.UP, rotation.y), global_position),
		GameState.TEAM_COLORS[team], push)
	queue_free()  # bots don't respawn; the owner re-buys them on their next deploy


func _physics_process(delta: float) -> void:
	if _dead:
		return
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
		_follow_owner(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
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
	var speed: float = _skill["speed"]
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

	_reaction_left = maxf(_reaction_left - delta, 0.0)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	var on_aim := rad_to_deg(facing.angle_to(flat.normalized())) <= FIRE_CONE_DEG
	var may_fire := _state == State.ENGAGE and on_aim and _reaction_left <= 0.0 \
		and weapon.heat() < FIRE_HEAT_CEILING
	weapon.update_fire(may_fire, may_fire)


## Fall in behind the owner: close if they're far, otherwise stand easy. Keeps
## a bought squad with the player who paid for it instead of scattering.
func _follow_owner(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if owner_player == null or not is_instance_valid(owner_player) \
			or not owner_player.is_alive():
		_apply_unstick()
		return
	var flat: Vector3 = owner_player.global_position - global_position
	flat.y = 0.0
	if flat.length() > 5.0:
		_face(flat, delta)
		var step := flat.normalized() * float(_skill["speed"])
		velocity.x = step.x
		velocity.z = step.z
	_apply_unstick()


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
