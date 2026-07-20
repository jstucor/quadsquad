class_name Player
extends CharacterBody3D
## First-person player: movement, per-player device input, health, respawn.
## input_device -1 = keyboard + mouse (player 1); >= 0 = that joypad device.
## Each player's model renders on layer (2 + player_index); bind_camera()
## clears that bit from the viewport camera so you never see your own body
## while the other three players (and your shadow) still do.

signal health_changed(health: float)

const WALK_SPEED := 5.0
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0022
const STICK_LOOK_SPEED := 2.6
const STICK_DEADZONE := 0.15
const MAX_HEALTH := 100.0

@export var player_index := 0
@export var input_device := -1
@export var team: int = GameState.Team.REPUBLIC

var health := MAX_HEALTH

var _anim: AnimationPlayer
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon
@onready var remote_cam: RemoteTransform3D = $Head/RemoteTransform3D
@onready var model: Node3D = $Model


func _ready() -> void:
	_anim = model.find_child("AnimationPlayer", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (1 + player_index)


func bind_camera(cam: Camera3D) -> void:
	cam.cull_mask &= ~(1 << (1 + player_index))
	remote_cam.remote_path = remote_cam.get_path_to(cam)


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
	rotate_y(delta_look.x)
	head.rotation.x = clampf(head.rotation.x + delta_look.y, -PI / 2 + 0.05, PI / 2 - 0.05)


func _physics_process(delta: float) -> void:
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
