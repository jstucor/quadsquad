class_name Player
extends CharacterBody3D
## First-person player: movement, per-player device input, health, the bought
## loadout, and the buy-screen/deploy flow.
## input_device -1 = keyboard + mouse (player 1); >= 0 = that joypad device.
## Each player's model renders on layer (2 + player_index); bind_camera()
## clears that bit from the viewport camera so you never see your own body
## while the other three players (and your shadow) still do.

signal health_changed(health: float)
signal weapon_changed(display_name: String)
signal aim_changed(aiming: bool)
## Entered the buy screen. `eliminated` is false for the very first deploy of
## the match (nobody died, so the HUD says DEPLOY, not ELIMINATED).
signal died(eliminated: bool)
signal respawned()
signal buy_changed(row: int)     # cursor moved or the build changed; redraw
signal deploy_ready()            # the minimum wait elapsed; the button is live
signal gear_changed(grenades: int, medkits: int)
signal squad_changed(alive: int)  # squadmates mustered or lost

const CORPSE_SCENE := preload("res://scenes/fx/corpse.tscn")
const GRENADE_SCENE := preload("res://scenes/fx/grenade.tscn")
const BOT_SCENE := preload("res://scenes/actors/bot.tscn")
# You deploy on a button press, not a timer. These are only the floor before the
# button goes live: long enough at match start for everyone to spec a build, and
# short enough after a death that you're never sat waiting on a decision made.
const DEPLOY_FLOOR := 5.0
const RESPAWN_FLOOR := 2.0
const GRENADE_THROW_SPEED := 13.0
const GRENADE_LOB := 0.28  # upward share of the throw, so it arcs

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.0
const CROUCH_SPEED_MULT := 0.45
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0022
const STICK_LOOK_SPEED := 2.6
const STICK_DEADZONE := 0.15
const BUY_DEADZONE := 0.6  # stick push that counts as one buy-screen step
const AIM_FOV_LERP := 14.0  # per-second rate the camera eases toward zoom FOV
const RECOIL_RECOVER := 12.0  # per-second rate the camera recoil settles back
# Crouch: lower stance = smaller hitbox, steadier, slower. Values are lerped by
# _crouch_t between standing and crouched.
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const STAND_HEAD_Y := 1.55
const CROUCH_HEAD_Y := 1.05
const CROUCH_MODEL_SCALE := 0.62
# Head-hit band (metres above the body origin) — anything above counts as a
# headshot; drops with the crouch so it tracks the lowered head.
const STAND_HEAD_MIN := 1.42
const CROUCH_HEAD_MIN := 0.85
# First-person viewmodels live on their own render-layer block (one bit per
# player) so each gun is seen ONLY by its owner's camera — the inverse of the
# body layers, which every camera sees except the owner's.
const VIEWMODEL_BIT := 10
const VIEWMODEL_SLOTS := 4
# Two capsules that end up inside each other are depenetrated by the solver
# straight upwards, and the pair rides that ladder out of the map forever (it
# never falls back: move_and_slide zeroes the gravity it just accumulated). So
# nudge overlapping players apart horizontally before the solver can, and treat
# anything that still leaves the map as a death.
const UNSTICK_RADIUS := 0.8   # < two capsule radii (0.35 each) + margin
const UNSTICK_SPEED := 5.0
const BOUNDS_MIN_Y := -30.0
const BOUNDS_MAX_Y := 60.0

@export var player_index := 0
@export var input_device := -1
@export var team: int = GameState.Team.REPUBLIC
var health := 100.0
var max_health := 100.0
## The build bought on the buy screen. `loadout` is what you deployed with and
## persists across deaths; `pending` is what the buy screen is editing.
var loadout := Loadout.starter()
var pending := Loadout.starter()
var buy_row := 0
var grenades_left := 0
var medkits_left := 0
var squad: Array[Bot] = []  # the AI squadmates currently alive under this player

var _anim: AnimationPlayer
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D
var _base_fov := 75.0
# Look sensitivity scales with zoom so aiming down a scope isn't twitchy.
var _look_scale := 1.0
var _prev_aim := false
var _grenade_down := false # joypad gear-button edge tracking
var _medkit_down := false
var _fire_down := false    # joypad fire-button edge tracking
var _look_pitch := 0.0     # head pitch from look input (recoil is added on top)
var _recoil_pitch := 0.0   # transient camera kick, settles back to 0
var _recoil_yaw := 0.0
var _crouch_t := 0.0       # 0 standing .. 1 crouched
var _dead := false
var _speed_mult := 1.0     # from the armour frame: scales walk + sprint
var _jump_mult := 1.0      # from the armour frame: scales jump velocity
var _buy_latch := Vector2.ZERO  # stick/key held: one step per push, not per frame
var _deploy_wait := 0.0    # seconds until the deploy button goes live
var _deploy_armed := false # ...and whether it already has
var _deploy_latch := false # deploy must be a fresh press, not one held from before
var _corpse: Node3D        # the flop spawned on death, freed on respawn

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon
@onready var remote_cam: RemoteTransform3D = $Head/RemoteTransform3D
@onready var model: Node3D = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	GameState.register_combatant(self)  # spawn picking skips the markers we occupy
	_anim = model.find_child("AnimationPlayer", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (1 + player_index)
	# Put this player's viewmodel on its private layer (owner-only).
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (VIEWMODEL_BIT + player_index)
	# Own copy of the capsule so crouch-resizing one player doesn't resize all.
	_collision.shape = _collision.shape.duplicate()
	weapon.shooter = self
	weapon.fired.connect(_on_weapon_fired)
	_apply_loadout()


## Match start: everyone picks a class before they can shoot. Main calls this
## once the viewport HUD is wired — _ready() would emit `died` into nothing.
func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func begin_deploy() -> void:
	_enter_buy_screen(DEPLOY_FLOOR, false)


func bind_camera(cam: Camera3D) -> void:
	cam.cull_mask &= ~(1 << (1 + player_index))
	# See only our own viewmodel: drop the whole viewmodel block, add ours back.
	for j in VIEWMODEL_SLOTS:
		cam.cull_mask &= ~(1 << (VIEWMODEL_BIT + j))
	cam.cull_mask |= 1 << (VIEWMODEL_BIT + player_index)
	remote_cam.remote_path = remote_cam.get_path_to(cam)
	_camera = cam
	_base_fov = cam.fov


func take_damage(amount: float, attacker: Node = null) -> void:
	if _dead:
		return  # already eliminated, waiting to respawn
	# Friendly fire is off: teammates deal no damage (self-damage still counts).
	if attacker is Player and attacker != self and attacker.team == team:
		return
	health -= amount
	health_changed.emit(health)
	if health <= 0.0:
		_die(attacker)


## False while eliminated (collision off, waiting to respawn). GameState uses it
## to skip corpses-in-waiting when it looks for a clear spawn marker.
func is_alive() -> bool:
	return not _dead


## True once the buy screen's minimum wait has elapsed and the deploy button
## will actually do something.
func deploy_armed() -> bool:
	return _deploy_armed


## What to call the deploy button in this player's prompt.
func deploy_button_name() -> String:
	return "SPACE" if input_device < 0 else "A"


## Take on the bought build: armour stats, the gun with its upgrades fitted, and
## a fresh set of consumables. Called on every deploy, never mid-life.
func _apply_loadout() -> void:
	loadout = pending.duplicate_loadout()
	var armor := loadout.armor_stats()
	max_health = armor["health"]
	_speed_mult = armor["speed"]
	_jump_mult = armor["jump"]
	health = max_health
	grenades_left = loadout.grenades
	medkits_left = loadout.medkits
	weapon.set_class(loadout.weapon_class(), loadout.weapon_mods())
	_muster_squad()
	gear_changed.emit(grenades_left, medkits_left)
	weapon_changed.emit(weapon.display_name())


## Bring the squad up to the headcount you paid for. Survivors are kept and only
## the losses are replaced, so redeploying never wipes a squad that's still
## fighting, and never stacks up more than you bought.
func _muster_squad() -> void:
	squad = squad.filter(func(b: Bot) -> bool: return is_instance_valid(b) and b.is_alive())
	var want := loadout.squad
	# Bought fewer than you have (re-spec): stand the extras down.
	while squad.size() > want:
		squad.pop_back().queue_free()
	for i in want - squad.size():
		squad.append(_spawn_bot())
	squad_changed.emit(squad.size())


func _on_squadmate_lost() -> void:
	squad = squad.filter(func(b: Bot) -> bool: return is_instance_valid(b) and b.is_alive())
	squad_changed.emit(squad.size())


func _spawn_bot() -> Bot:
	var bot: Bot = BOT_SCENE.instantiate()
	get_parent().add_child(bot)  # a sibling in the level, not a child of the player
	bot.setup(self, team, loadout.squad_skill)
	# tree_exited fires when a bot is freed on death, so the HUD count follows
	# losses without the bot needing to know anything about its owner's UI.
	bot.tree_exited.connect(_on_squadmate_lost)
	# Drop them on a clear team marker, same as a respawn, so they never spawn
	# inside a body.
	var spawn := GameState.get_spawn_point(team)
	if spawn:
		bot.global_transform = GameState.clear_of_bodies(spawn.global_transform)
	else:
		bot.global_position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	return bot


## Buy-screen input while dead: up/down picks a row, left/right changes it, and
## the jump button deploys once the floor has elapsed. All of it rides inputs
## the player already has, so there is nothing extra to bind.
func _update_buy_input() -> void:
	var move := _buy_axis()
	if move.y != 0:
		buy_row = wrapi(buy_row + move.y, 0, Loadout.Row.size())
		buy_changed.emit(buy_row)
	if move.x != 0 and pending.step(buy_row, move.x):
		buy_changed.emit(buy_row)
	# The button has to be pressed, not merely held down from before you died.
	var deploy := _deploy_held()
	if deploy and not _deploy_latch and _deploy_armed:
		_respawn()
		return
	_deploy_latch = deploy


## One step per push on each axis, from the movement stick/keys plus the d-pad.
func _buy_axis() -> Vector2i:
	var raw := _move_input()
	if input_device >= 0:
		if Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_LEFT):
			raw.x = -1.0
		elif Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_RIGHT):
			raw.x = 1.0
		if Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_UP):
			raw.y = -1.0
		elif Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_DOWN):
			raw.y = 1.0
	# Forward is -Z, which reads as "up" on the menu.
	return Vector2i(_axis_step(raw.x, "x"), _axis_step(raw.y, "y"))


func _axis_step(value: float, axis: String) -> int:
	var latched: float = _buy_latch.x if axis == "x" else _buy_latch.y
	var step := 0
	if absf(value) >= BUY_DEADZONE:
		if latched == 0.0:
			step = signi(value)
		latched = signf(value)
	else:
		latched = 0.0
	if axis == "x":
		_buy_latch.x = latched
	else:
		_buy_latch.y = latched
	return step


func view_fov() -> float:
	return _camera.fov if _camera else _base_fov


## True if a world-space hit point lands in this body's head band (tracks the
## crouch so a crouched head still counts). Weapons use it for bonus damage.
func is_headshot(world_pos: Vector3) -> bool:
	var head_min := lerpf(STAND_HEAD_MIN, CROUCH_HEAD_MIN, _crouch_t)
	return world_pos.y - global_position.y >= head_min


func _die(attacker: Node = null) -> void:
	if _dead:
		return
	# Credit the frag to an enemy killer (not suicide/self or a teammate).
	if attacker is Player and attacker != self and attacker.team != team:
		GameState.add_frag(attacker.team)
	_spawn_corpse(attacker)
	_enter_buy_screen(RESPAWN_FLOOR, true)


## Go to the buy screen. It stays up until the player presses deploy — `floor`
## is only how long the button is greyed out first. Shared by the match-start
## deploy and every death, so a build is always bought the same way.
func _enter_buy_screen(floor_secs: float, eliminated: bool) -> void:
	_dead = true
	velocity = Vector3.ZERO
	weapon.aiming = false
	if _camera:
		_camera.fov = _base_fov
	# Hide the live body + turn off its collision; the camera stays put as a
	# death cam while the flop tumbles and you spend.
	model.visible = false
	weapon.visible = false  # no gun in hand while you're still buying one
	_collision.disabled = true
	# The screen opens on the build you were using, so an unchanged respawn is
	# one button press.
	pending = loadout.duplicate_loadout()
	buy_row = 0
	# Forget any held trigger/button: the new life starts on a fresh press.
	_buy_latch = Vector2.ZERO
	_deploy_latch = true  # released-then-pressed, so a held jump can't deploy
	_fire_down = false
	_deploy_wait = floor_secs
	_deploy_armed = false
	died.emit(eliminated)
	buy_changed.emit(buy_row)


func _spawn_corpse(attacker: Node) -> void:
	_corpse = CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(_corpse)
	var push := Vector3.ZERO  # shove away from the shooter
	if attacker is Node3D and attacker != self:
		push = global_position - (attacker as Node3D).global_position
	var xform := Transform3D(Basis(Vector3.UP, rotation.y), global_position)
	_corpse.launch(xform, GameState.TEAM_COLORS[team], push)


func _process_dead(delta: float) -> void:
	if not _deploy_armed:
		_deploy_wait -= delta
		if _deploy_wait <= 0.0:
			_deploy_armed = true
			deploy_ready.emit()
	_update_buy_input()


func _respawn() -> void:
	# Place the body BEFORE clearing _dead: while we still read as dead, the
	# spawn picker skips us, so we don't treat the body we just left as an
	# obstacle and shove ourselves off our own marker.
	var spawn := GameState.get_spawn_point(team)
	if spawn:
		global_transform = GameState.clear_of_bodies(spawn.global_transform)
	_dead = false
	model.visible = true
	weapon.visible = true
	_collision.disabled = false
	# Whatever we were doing when we died (falling, jumping) must not carry over
	# into the new body at the spawn point.
	velocity = Vector3.ZERO
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	_apply_loadout()
	health_changed.emit(health)
	if is_instance_valid(_corpse):
		_corpse.queue_free()
	_corpse = null
	respawned.emit()


func _unhandled_input(event: InputEvent) -> void:
	if input_device >= 0:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(Vector2(-event.relative.x, -event.relative.y) * MOUSE_SENS)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_look(delta_look: Vector2) -> void:
	rotate_y(delta_look.x * _look_scale)
	_look_pitch = clampf(_look_pitch + delta_look.y * _look_scale,
		-PI / 2 + 0.05, PI / 2 - 0.05)
	_refresh_head()


## The camera pitch is look input plus the transient recoil kick; recoil yaw
## rides on the head so it throws off aim without turning the whole body.
func _refresh_head() -> void:
	head.rotation.x = _look_pitch + _recoil_pitch
	head.rotation.y = _recoil_yaw


func _physics_process(delta: float) -> void:
	if _dead:
		_process_dead(delta)
		return
	_update_gear()
	_update_aim(delta)
	_update_crouch(delta)

	# Settle the camera recoil back toward zero.
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_refresh_head()

	if input_device >= 0:
		var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		_apply_look(-look * STICK_LOOK_SPEED * delta)

	var move := _move_input()
	var crouching := _crouch_held()
	var sprinting := _sprint_held() and not crouching
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * _speed_mult
	if crouching:
		speed *= CROUCH_SPEED_MULT
	var dir := global_transform.basis * Vector3(move.x, 0, move.y)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _jump_pressed():
		velocity.y = JUMP_VELOCITY * _jump_mult
	var unstick := _unstick_push()
	velocity.x = dir.x * speed + unstick.x
	velocity.z = dir.z * speed + unstick.z
	move_and_slide()
	if global_position.y > BOUNDS_MAX_Y or global_position.y < BOUNDS_MIN_Y:
		_die()  # launched or fell out of the map: respawn through the normal flow
		return

	weapon.update_fire(_fire_held(), _fire_pressed())
	_update_anim(move, sprinting)


## Horizontal shove away from any living player we're standing inside, so the
## overlap resolves sideways instead of ejecting both of us upwards. Scales with
## how deep the overlap is; zero in the normal case of nobody nearby.
func _unstick_push() -> Vector3:
	var push := Vector3.ZERO
	for p in GameState.combatants:
		if p == self or not p.is_alive():
			continue
		var away := global_position - p.global_position
		away.y = 0.0
		var gap := away.length()
		if gap >= UNSTICK_RADIUS:
			continue
		if gap < 0.01:  # exactly stacked: any direction beats staying put
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			gap = 0.01
		push += away.normalized() * (1.0 - gap / UNSTICK_RADIUS) * UNSTICK_SPEED
	return push


## Ease the stance toward standing/crouched: lowers the camera, shrinks the
## capsule, and squashes the model so squadmates see the crouch too.
func _update_crouch(delta: float) -> void:
	var target := 1.0 if _crouch_held() else 0.0
	_crouch_t = move_toward(_crouch_t, target, delta / 0.12)
	head.position.y = lerpf(STAND_HEAD_Y, CROUCH_HEAD_Y, _crouch_t)
	model.scale.y = lerpf(1.0, CROUCH_MODEL_SCALE, _crouch_t)
	var cap := _collision.shape as CapsuleShape3D
	cap.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t)
	_collision.position.y = cap.height * 0.5


func _on_weapon_fired(cam_recoil: float) -> void:
	_recoil_pitch += cam_recoil
	_recoil_yaw += randf_range(-0.4, 0.4) * cam_recoil


## Hold-to-aim: eases the camera FOV toward the weapon's zoom, tells the weapon
## to tighten its spread cone, and scales look sensitivity down with the zoom.
func _update_aim(delta: float) -> void:
	var aiming := _ads_held()
	weapon.aiming = aiming
	if aiming != _prev_aim:
		_prev_aim = aiming
		aim_changed.emit(aiming)
	if _camera:
		var want := weapon.zoom_fov() if aiming else _base_fov
		_camera.fov = lerpf(_camera.fov, want, clampf(delta * AIM_FOV_LERP, 0.0, 1.0))
		_look_scale = _camera.fov / _base_fov


## Consumables bought on the buy screen: a thrown grenade and a self-heal. Both
## are edge-triggered and simply do nothing when you have none left.
func _update_gear() -> void:
	if _grenade_pressed() and grenades_left > 0:
		grenades_left -= 1
		_throw_grenade()
		gear_changed.emit(grenades_left, medkits_left)
	if _medkit_pressed() and medkits_left > 0 and health < max_health:
		medkits_left -= 1
		health = minf(health + Loadout.MEDKIT_HEAL, max_health)
		health_changed.emit(health)
		gear_changed.emit(grenades_left, medkits_left)


func _throw_grenade() -> void:
	var grenade := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(grenade)
	# Thrown from the camera, along the look direction with an upward share so it
	# arcs instead of firing flat.
	var aim := -head.global_transform.basis.z
	var toss := (aim + Vector3.UP * GRENADE_LOB).normalized() * GRENADE_THROW_SPEED
	grenade.launch(head.global_position + aim * 0.6, toss + velocity, self)


func _move_input() -> Vector2:
	if input_device < 0:
		return Input.get_vector("kb_left", "kb_right", "kb_forward", "kb_back")
	return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)


func _stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(input_device, ax), Input.get_joy_axis(input_device, ay))
	return Vector2.ZERO if v.length() < STICK_DEADZONE else v


func _jump_pressed() -> bool:
	if input_device < 0:
		return Input.is_action_just_pressed("kb_jump")
	return Input.is_joy_button_pressed(input_device, JOY_BUTTON_A)


func _sprint_held() -> bool:
	if input_device < 0:
		return Input.is_action_pressed("kb_sprint")
	return Input.is_joy_button_pressed(input_device, JOY_BUTTON_LEFT_STICK)


func _fire_held() -> bool:
	if input_device < 0:
		return Input.is_action_pressed("kb_fire")
	return Input.get_joy_axis(input_device, JOY_AXIS_TRIGGER_RIGHT) > 0.5 \
		or Input.is_joy_button_pressed(input_device, JOY_BUTTON_RIGHT_SHOULDER)


## Trigger-down edge for semi/burst weapons. Keyboard uses the action's edge;
## joypad is polled per-device, so we track the previous state ourselves.
func _fire_pressed() -> bool:
	if input_device < 0:
		return Input.is_action_just_pressed("kb_fire")
	var down := _fire_held()
	var edge := down and not _fire_down
	_fire_down = down
	return edge


func _crouch_held() -> bool:
	if input_device < 0:
		return Input.is_action_pressed("kb_crouch")
	return Input.is_joy_button_pressed(input_device, JOY_BUTTON_B)


func _ads_held() -> bool:
	if input_device < 0:
		return Input.is_action_pressed("kb_ads")
	return Input.get_joy_axis(input_device, JOY_AXIS_TRIGGER_LEFT) > 0.5 \
		or Input.is_joy_button_pressed(input_device, JOY_BUTTON_LEFT_SHOULDER)


## Gear buttons are edge-triggered. Keyboard uses the InputMap action's own edge
## detection; joypad buttons are polled per-device (device-scoped, unlike a
## shared InputMap action), so we track the previous state ourselves.
func _grenade_pressed() -> bool:
	if input_device < 0:
		return Input.is_action_just_pressed("kb_grenade")
	var down := Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_UP)
	var edge := down and not _grenade_down
	_grenade_down = down
	return edge


func _medkit_pressed() -> bool:
	if input_device < 0:
		return Input.is_action_just_pressed("kb_medkit")
	var down := Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_DOWN)
	var edge := down and not _medkit_down
	_medkit_down = down
	return edge


## Deploy off the buy screen: the same button as jump, held-state (the edge is
## tracked by the buy screen itself, which needs a fresh press).
func _deploy_held() -> bool:
	if input_device < 0:
		return Input.is_action_pressed("kb_jump")
	return Input.is_joy_button_pressed(input_device, JOY_BUTTON_A)


func _update_anim(move: Vector2, sprinting: bool) -> void:
	if _anim == null:
		return
	# Basic Minecraft/Krunker-style state machine: airborne -> jump (held),
	# moving -> walk/run, else idle. No landing clip on purpose.
	var target: String
	if not is_on_floor():
		target = "jump"
	elif move.length() > 0.1:
		target = "run" if sprinting else "walk"
	else:
		target = "idle"
	# assigned_animation (not current_animation) so the one-shot jump keeps
	# holding its last frame instead of retriggering every tick.
	if _anim.assigned_animation != target and _anim.has_animation(target):
		_anim.play(target, 0.12)
	# Scale locomotion cycles to ground speed so feet don't skate.
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	match target:
		"walk":
			_anim.speed_scale = clampf(ground_speed / 2.6, 0.6, 2.2)
		"run":
			_anim.speed_scale = clampf(ground_speed / 5.0, 0.6, 2.2)
		_:
			_anim.speed_scale = 1.0
