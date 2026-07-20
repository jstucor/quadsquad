class_name Player
extends CharacterBody3D
## First-person player: movement, per-player device input, health, respawn.
## input_device -1 = keyboard + mouse (player 1); >= 0 = that joypad device.
## Each player's model renders on layer (2 + player_index); bind_camera()
## clears that bit from the viewport camera so you never see your own body
## while the other three players (and your shadow) still do.

signal health_changed(health: float)
signal weapon_changed(display_name: String)
signal aim_changed(aiming: bool)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0022
const STICK_LOOK_SPEED := 2.6
const STICK_DEADZONE := 0.15
const MAX_HEALTH := 100.0
const AIM_FOV_LERP := 14.0  # per-second rate the camera eases toward zoom FOV

@export var player_index := 0
@export var input_device := -1
@export var team: int = GameState.Team.REPUBLIC
## Starting weapon class (Weapon.Class); Main assigns a different one per player.
@export var weapon_class := 0

var health := MAX_HEALTH

var _anim: AnimationPlayer
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D
var _base_fov := 75.0
# Look sensitivity scales with zoom so aiming down a scope isn't twitchy.
var _look_scale := 1.0
var _prev_aim := false
var _switch_down := false  # joypad switch-button edge tracking

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon
@onready var remote_cam: RemoteTransform3D = $Head/RemoteTransform3D
@onready var model: Node3D = $Model


func _ready() -> void:
	_anim = model.find_child("AnimationPlayer", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (1 + player_index)
	weapon.set_class(weapon_class as Weapon.Class)


func bind_camera(cam: Camera3D) -> void:
	cam.cull_mask &= ~(1 << (1 + player_index))
	remote_cam.remote_path = remote_cam.get_path_to(cam)
	_camera = cam
	_base_fov = cam.fov


func take_damage(amount: float) -> void:
	health -= amount
	health_changed.emit(health)
	if health <= 0.0:
		_die()


func _die() -> void:
	GameState.take_ticket(team)
	health = MAX_HEALTH
	health_changed.emit(health)
	velocity = Vector3.ZERO
	# Own marker, never random: respawning onto another player's spawn stacks
	# bodies. Battlefront's spawn-point picker replaces this later.
	var spawn := GameState.get_spawn_point(team, player_index)
	if spawn:
		global_transform = spawn.global_transform


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
	head.rotation.x = clampf(head.rotation.x + delta_look.y * _look_scale,
		-PI / 2 + 0.05, PI / 2 - 0.05)


func _physics_process(delta: float) -> void:
	if _switch_pressed():
		_cycle_weapon()
	_update_aim(delta)

	if input_device >= 0:
		var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		_apply_look(-look * STICK_LOOK_SPEED * delta)

	var move := _move_input()
	var sprinting := _sprint_held()
	var speed := SPRINT_SPEED if sprinting else WALK_SPEED
	var dir := global_transform.basis * Vector3(move.x, 0, move.y)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif _jump_pressed():
		velocity.y = JUMP_VELOCITY
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	if _fire_held():
		weapon.try_fire(self)
	_update_anim(move, sprinting)


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


func _cycle_weapon() -> void:
	var next := (weapon.weapon_class + 1) % Weapon.PROFILES.size()
	weapon.set_class(next as Weapon.Class)
	weapon_changed.emit(weapon.display_name())


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


func _ads_held() -> bool:
	if input_device < 0:
		return Input.is_action_pressed("kb_ads")
	return Input.get_joy_axis(input_device, JOY_AXIS_TRIGGER_LEFT) > 0.5 \
		or Input.is_joy_button_pressed(input_device, JOY_BUTTON_LEFT_SHOULDER)


## Weapon-cycle is edge-triggered. Keyboard uses the InputMap action's own edge
## detection; joypad buttons are polled per-device (device-scoped, unlike a
## shared InputMap action), so we track the previous state ourselves.
func _switch_pressed() -> bool:
	if input_device < 0:
		return Input.is_action_just_pressed("kb_switch")
	var down := Input.is_joy_button_pressed(input_device, JOY_BUTTON_Y)
	var edge := down and not _switch_down
	_switch_down = down
	return edge


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
