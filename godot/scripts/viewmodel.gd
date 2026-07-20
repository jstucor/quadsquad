extends Node3D
## First-person weapon viewmodel: a procedural blaster the OWNING player sees
## (rendered on a per-player viewmodel layer set by Player). Purely cosmetic —
## it hangs under the fixed Weapon aim anchor and animates independently, so
## recoil/bob/ADS never move the actual fire ray (that stays on Weapon's -Z).
##
## Animation is procedural, in the Minecraft/Krunker spirit of the rest of the
## game: a spring-back recoil kick + muzzle flash on fire, a gentle walk bob,
## and an aim-down-sights slide to center. The parent Weapon drives it by
## calling configure() on class change and kick() on each shot; it reads
## aiming/scope straight off the parent.

const HIP_POS := Vector3.ZERO
# Aiming slides the gun left+up to bring it under the crosshair (barrel toward
# center, body kept a bit low so it doesn't fill the screen) and pulls it back
# a touch (the Weapon anchor is offset right/down/forward).
const ADS_POS := Vector3(-0.165, 0.055, 0.05)
const AIM_TIME := 0.12       # seconds to fully raise/lower sights
const RECOIL_DECAY := 6.0    # how fast the kick springs back
const FLASH_TIME := 0.045

var aiming_source: Node3D    # the parent Weapon (aiming / has_scope live here)

var _player: CharacterBody3D
var _scope: MeshInstance3D
var _drum: MeshInstance3D
var _flash: MeshInstance3D

var _kick := 0.0             # current recoil amount (0..~1.2), springs to 0
var _kick_yaw := 0.0         # random left/right lean per shot
var _aim_t := 0.0            # 0 hip .. 1 aimed
var _bob_t := 0.0
var _flash_t := 0.0


func _ready() -> void:
	aiming_source = get_parent()
	# Walk up to the owning body for the bob (velocity/on-floor).
	var n: Node = get_parent()
	while n != null and not (n is CharacterBody3D):
		n = n.get_parent()
	_player = n as CharacterBody3D
	_build()


func _build() -> void:
	var gun := StandardMaterial3D.new()
	gun.albedo_color = Color(0.12, 0.12, 0.14)
	gun.metallic = 0.1  # keep low: a near-black sky reflects into metal (Gotchas)
	gun.roughness = 0.6
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.05, 0.05, 0.06)
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.25, 0.15)
	accent.emission_energy_multiplier = 2.0

	_box(Vector3(0.05, 0.07, 0.26), Vector3(0, 0, -0.03), gun)       # receiver
	_box(Vector3(0.028, 0.028, 0.30), Vector3(0, 0.012, -0.28), gun)  # barrel
	_box(Vector3(0.02, 0.03, 0.05), Vector3(0, -0.052, -0.10), gun)   # fore grip
	var grip := _box(Vector3(0.035, 0.11, 0.05), Vector3(0, -0.07, 0.03), gun)
	grip.rotation.x = -0.25                                           # pistol grip
	_box(Vector3(0.04, 0.055, 0.10), Vector3(0, -0.008, 0.13), gun)   # stock
	_box(Vector3(0.02, 0.018, 0.04), Vector3(0, 0.052, -0.02), accent)  # power cell

	# Sniper scope (hidden unless configured): tube + mount.
	_scope = _cyl(0.02, 0.15, Vector3(0, 0.075, -0.06), gun)
	_box(Vector3(0.012, 0.03, 0.02), Vector3(0, 0.055, -0.06), gun).reparent(_scope, false)
	_scope.visible = false

	# Heavy ammo drum (hidden unless configured), slung under the receiver.
	_drum = _cyl(0.05, 0.045, Vector3(0, -0.075, -0.02), gun)
	_drum.rotation.z = PI / 2.0  # drum face sideways
	_drum.visible = false

	# Muzzle flash: a small additive glow blob at the barrel tip, flicked on
	# for a couple of frames per shot (additive so it reads as light, not a
	# solid orange shape, under the GL Compatibility renderer).
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fmat.albedo_color = Color(1.0, 0.72, 0.35)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.55, 0.2)
	fmat.emission_energy_multiplier = 4.0
	_flash = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.045
	sph.height = 0.09
	sph.radial_segments = 8
	sph.rings = 4
	_flash.mesh = sph
	_flash.material_override = fmat
	_flash.position = Vector3(0, 0.012, -0.42)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)


func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	mi.mesh = m
	mi.position = pos
	mi.rotation.x = PI / 2.0  # CylinderMesh is Y-up; lay it along -Z (barrel/scope)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Show the parts that distinguish this class.
func configure(class_id: int) -> void:
	if _scope:
		_scope.visible = class_id == Weapon.Class.SNIPER
	if _drum:
		_drum.visible = class_id == Weapon.Class.HEAVY


## Called on each shot; strength scales the kick per weapon class.
func kick(strength: float) -> void:
	_kick = minf(_kick + strength, 1.2)
	_kick_yaw = randf_range(-1.0, 1.0)
	_flash_t = FLASH_TIME
	if _flash:
		_flash.rotation.z = randf() * TAU
		_flash.scale = Vector3.ONE * randf_range(0.8, 1.3)


func _process(delta: float) -> void:
	var aiming := false
	var scoped := false
	if aiming_source:
		aiming = aiming_source.aiming
		scoped = aiming_source.has_scope()

	_aim_t = move_toward(_aim_t, 1.0 if aiming else 0.0, delta / AIM_TIME)
	_kick = move_toward(_kick, 0.0, delta * RECOIL_DECAY)

	# Walk bob, damped while aiming and only on the ground.
	var speed := 0.0
	if _player and _player.is_on_floor():
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob_t += delta * (4.0 + speed * 1.6)
	var bob_amp := 0.011 * clampf(speed / 5.0, 0.0, 1.0) * (1.0 - 0.75 * _aim_t)
	var bob := Vector3(cos(_bob_t) * bob_amp, absf(sin(_bob_t)) * bob_amp, 0.0)

	var pos := HIP_POS.lerp(ADS_POS, _aim_t) + bob
	pos.z += _kick * 0.06  # recoil shoves the gun back toward the player
	position = pos
	# Muzzle climbs (rotate about +X) with a small random lateral lean.
	rotation = Vector3(_kick * 0.18, _kick * _kick_yaw * 0.05, 0.0)

	if _flash:
		_flash_t = maxf(_flash_t - delta, 0.0)
		_flash.visible = _flash_t > 0.0

	# A scoped weapon replaces the gun with the scope overlay when aimed, so
	# hide the model once the sights are most of the way up (real-game feel).
	visible = not (aiming and scoped and _aim_t > 0.6)
