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
# How far back the gun is pulled while aimed. The left/up part of the ADS slide
# is NOT a constant: it's solved per gun in _aim_offset() so whichever sight is
# fitted ends up on the camera axis. Hard-coding it lined the old shared body up
# by hand, but every receiver here is a different height and the sight drifted
# off centre as soon as the guns stopped being identical.
const ADS_PULL_BACK := 0.05
const AIM_TIME := 0.12       # seconds to fully raise/lower sights
const RECOIL_DECAY := 6.0    # how fast the kick springs back
const KICK_CEILING := 1.8    # a burst stacks up to here before it stops growing
# How the accumulated kick reads on screen: shoved back toward the player,
# muzzle climbing, with a small lateral lean.
#
# Kept DELIBERATELY restrained. The gun is braced against a shoulder — it is the
# steadiest thing in the frame, and a viewmodel that whips around reads as jumpy
# rather than powerful. The force of a shot belongs on the CAMERA (Player's
# cam_recoil), which is the thing a real shooter feels move. Pushed to 0.42
# radians of flip this looked like the gun was being thrown, while the view
# behind it sat flat.
const KICK_PUSH := 0.12      # metres back per unit of kick
const KICK_PITCH := 0.20     # radians of muzzle climb per unit of kick
const KICK_LEAN := 0.06
# The pushback still needs a ceiling: the Weapon anchor sits only 0.3 m in front
# of the camera (0.25 m aimed), and past that the receiver crosses the near
# plane and the gun turns inside out.
const MAX_PUSH := 0.12
# ...and the gun settles further still once the sights are up. Aimed, the weapon
# is braced and your eye is ON the sight: the same flip that reads as weight
# from the hip throws the sight picture off the camera axis when you are looking
# through it. Scaled by _aim_t, so it eases in with the sights rather than
# snapping between two amounts.
const ADS_KICK_MULT := 0.4
const FLASH_TIME := 0.045

var aiming_source: Node3D    # the parent Weapon (aiming / has_scope live here)

var _player: CharacterBody3D
var _scope: MeshInstance3D
var _holo: Node3D
var _flash: MeshInstance3D

var _kick := 0.0             # current recoil amount (0..KICK_CEILING), springs to 0
var _kick_yaw := 0.0         # random left/right lean per shot
var _aim_t := 0.0            # 0 hip .. 1 aimed
var _ads_pos := Vector3(-0.165, 0.055, ADS_PULL_BACK)  # solved in _build
var _bob_t := 0.0
var _flash_t := 0.0


func _ready() -> void:
	aiming_source = get_parent()
	# Walk up to the owning body for the bob (velocity/on-floor).
	var n: Node = get_parent()
	while n != null and not (n is CharacterBody3D):
		n = n.get_parent()
	_player = n as CharacterBody3D
	_build(Weapon.Class.SOLDIER, false, false)


## Every gun's silhouette, in parts. One shared body with a few toggles made the
## whole roster read as the same weapon, so each class gets its own proportions:
## receiver block, barrel length/bore, and which of stock / fore grip / drum /
## magazine / muzzle device it carries. Values are metres, in viewmodel space.
const SHAPES := {
	Weapon.Class.SOLDIER: {  # DC-15: standard-issue rifle
		"receiver": Vector3(0.05, 0.07, 0.26), "barrel": Vector3(0.028, 0.028, 0.34),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.11, 0.05), "muzzle": 0.05,
	},
	Weapon.Class.SNIPER: {  # NT-242: long, thin, all barrel
		"receiver": Vector3(0.045, 0.062, 0.3), "barrel": Vector3(0.022, 0.022, 0.62),
		"stock": true, "grip": false, "mag": Vector3(0.026, 0.07, 0.04), "muzzle": 0.07,
		"bipod": true,
	},
	Weapon.Class.HEAVY: {  # Z-6: squat repeater slung under a drum
		"receiver": Vector3(0.075, 0.085, 0.24), "barrel": Vector3(0.042, 0.042, 0.26),
		"stock": false, "grip": true, "drum": 0.055, "muzzle": 0.06,
	},
	Weapon.Class.HMG: {  # T-21: heavy, long, bipod
		"receiver": Vector3(0.07, 0.08, 0.34), "barrel": Vector3(0.05, 0.05, 0.44),
		"stock": true, "grip": true, "drum": 0.042, "muzzle": 0.08, "bipod": true,
	},
	Weapon.Class.BURST: {  # EL-16: boxy carbine
		"receiver": Vector3(0.055, 0.08, 0.24), "barrel": Vector3(0.026, 0.026, 0.28),
		"stock": true, "grip": true, "mag": Vector3(0.032, 0.13, 0.045), "muzzle": 0.04,
	},
	Weapon.Class.SEMI: {  # A280: long marksman rifle
		"receiver": Vector3(0.048, 0.07, 0.3), "barrel": Vector3(0.024, 0.024, 0.46),
		"stock": true, "grip": true, "mag": Vector3(0.028, 0.1, 0.045), "muzzle": 0.05,
	},
	Weapon.Class.RPG: {  # PLX-1: a tube, and not much else
		"receiver": Vector3(0.1, 0.1, 0.5), "barrel": Vector3(0.088, 0.088, 0.22),
		"stock": false, "grip": true, "muzzle": 0.13, "tube": true,
	},
	Weapon.Class.REVOLVER: {  # SE-14: heavy sidearm with a cylinder
		"receiver": Vector3(0.038, 0.06, 0.13), "barrel": Vector3(0.026, 0.026, 0.17),
		"stock": false, "grip": false, "cylinder": 0.045, "muzzle": 0.03,
	},
	Weapon.Class.PISTOL: {  # DL-44
		"receiver": Vector3(0.036, 0.058, 0.14), "barrel": Vector3(0.022, 0.022, 0.15),
		"stock": false, "grip": false, "mag": Vector3(0.026, 0.085, 0.035), "muzzle": 0.035,
	},
	Weapon.Class.HOLDOUT: {  # RK-3: stubby little thing
		"receiver": Vector3(0.034, 0.05, 0.1), "barrel": Vector3(0.018, 0.018, 0.08),
		"stock": false, "grip": false, "mag": Vector3(0.024, 0.07, 0.03), "muzzle": 0.025,
	},
	Weapon.Class.ROTARY: {  # R-90: barrel cluster on a huge drum
		"receiver": Vector3(0.09, 0.09, 0.26), "barrel": Vector3(0.03, 0.03, 0.42),
		"stock": false, "grip": true, "drum": 0.075, "muzzle": 0.05, "barrels": 4,
	},
	Weapon.Class.TURRET: {  # only ever seen as a world object, never in hand
		"receiver": Vector3(0.09, 0.09, 0.3), "barrel": Vector3(0.04, 0.04, 0.4),
		"stock": false, "grip": false, "muzzle": 0.07,
	},
	Weapon.Class.SMG: {  # Westar M5: small, stockless, tall magazine
		"receiver": Vector3(0.045, 0.07, 0.18), "barrel": Vector3(0.022, 0.022, 0.16),
		"stock": false, "grip": true, "mag": Vector3(0.03, 0.14, 0.04), "muzzle": 0.035,
	},
	Weapon.Class.CARBINE: {  # DC-15S: the rifle, cut down
		"receiver": Vector3(0.05, 0.07, 0.21), "barrel": Vector3(0.026, 0.026, 0.22),
		"stock": true, "grip": true, "mag": Vector3(0.03, 0.1, 0.045), "muzzle": 0.045,
	},
	Weapon.Class.SCATTERGUN: {  # FWMB-10: fat, short, no magazine
		"receiver": Vector3(0.07, 0.085, 0.28), "barrel": Vector3(0.055, 0.055, 0.24),
		"stock": true, "grip": true, "muzzle": 0.085,
	},
	Weapon.Class.DMR: {  # A280-CFE: long barrel, ships with optics
		"receiver": Vector3(0.046, 0.068, 0.3), "barrel": Vector3(0.023, 0.023, 0.52),
		"stock": true, "grip": true, "mag": Vector3(0.027, 0.095, 0.045), "muzzle": 0.055,
	},
	Weapon.Class.DH17: {  # DH-17: boxy service pistol
		"receiver": Vector3(0.038, 0.06, 0.15), "barrel": Vector3(0.024, 0.024, 0.13),
		"stock": false, "grip": false, "mag": Vector3(0.028, 0.09, 0.035), "muzzle": 0.03,
	},
	Weapon.Class.BRYAR: {  # Bryar: long-barrelled, cylinder under the receiver
		"receiver": Vector3(0.04, 0.062, 0.16), "barrel": Vector3(0.024, 0.024, 0.24),
		"stock": false, "grip": false, "cylinder": 0.04, "muzzle": 0.04,
	},
}


func _build(class_id: int, scoped: bool, holo: bool) -> void:
	# remove_child before queue_free: freeing is deferred to the end of the
	# frame, so a rebuild in the same frame (deploy then weapon swap) would
	# stack the new gun on top of the old one's parts.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_scope = null
	_holo = null
	_flash = null

	var shape: Dictionary = SHAPES.get(class_id, SHAPES[Weapon.Class.SOLDIER])
	var gun := StandardMaterial3D.new()
	gun.albedo_color = Color(0.12, 0.12, 0.14)
	gun.metallic = 0.1  # keep low: a near-black sky reflects into metal (Gotchas)
	gun.roughness = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.metallic = 0.1
	dark.roughness = 0.7
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.05, 0.05, 0.06)
	accent.emission_enabled = true
	accent.emission = Color(1.0, 0.25, 0.15)
	accent.emission_energy_multiplier = 2.0

	var receiver: Vector3 = shape["receiver"]
	var barrel: Vector3 = shape["barrel"]
	var barrel_z := -receiver.z * 0.5 - barrel.z * 0.5
	_box(receiver, Vector3(0, 0, -0.03), gun)

	# Barrels: one, or a cluster for the rotary cannon.
	var barrel_count: int = shape.get("barrels", 1)
	for i in barrel_count:
		var offset := Vector3.ZERO
		if barrel_count > 1:
			var angle := TAU * i / float(barrel_count)
			offset = Vector3(cos(angle), sin(angle), 0.0) * 0.032
		_box(barrel, Vector3(offset.x, 0.012 + offset.y, barrel_z - 0.03), gun)

	var muzzle_size: float = shape.get("muzzle", 0.0)
	if muzzle_size > 0.0:
		_box(Vector3(muzzle_size, muzzle_size, 0.06),
			Vector3(0, 0.012, barrel_z - barrel.z * 0.5 - 0.06), dark)

	# Pistol grip, always: it's what you're holding.
	var hand := _box(Vector3(0.035, 0.11, 0.05), Vector3(0, -0.07, 0.03), gun)
	hand.rotation.x = -0.25

	if shape.get("stock", false):
		_box(Vector3(0.04, 0.055, 0.12), Vector3(0, -0.008, receiver.z * 0.5 + 0.05), gun)
	if shape.get("grip", false):
		_box(Vector3(0.02, 0.035, 0.05), Vector3(0, -0.055, -0.1), dark)
	if shape.has("mag"):
		var mag: Vector3 = shape["mag"]
		_box(mag, Vector3(0, -receiver.y * 0.5 - mag.y * 0.4, -0.02), dark)
	if shape.has("drum"):
		var drum: float = shape["drum"]
		var d := _cyl(drum, 0.05, Vector3(0, -0.07, -0.02), dark)
		d.rotation.z = PI / 2.0  # drum face sideways
	if shape.has("cylinder"):
		var cyl_r: float = shape["cylinder"]
		var c := _cyl(cyl_r, 0.055, Vector3(0, -0.004, -0.03), gun)
		c.rotation.z = PI / 2.0
	if shape.get("tube", false):
		# The RPG reads as a launcher: a fat ring near the muzzle.
		var ring := _cyl(0.075, 0.05, Vector3(0, 0.0, barrel_z), dark)
		ring.rotation.x = PI / 2.0
	if shape.get("bipod", false):
		for side in [-1.0, 1.0]:
			var leg := _box(Vector3(0.012, 0.09, 0.012),
				Vector3(0.03 * side, -0.06, barrel_z + 0.04), dark)
			leg.rotation.z = 0.35 * side
	_box(Vector3(0.02, 0.018, 0.04), Vector3(0, receiver.y * 0.5 - 0.005, -0.02), accent)

	# Sights. The scope is a tube on a mount; the holo is a hollow ring you can
	# see the world through, which is the point of buying it.
	_scope = _cyl(0.02, 0.15, Vector3(0, receiver.y * 0.5 + 0.03, -0.06), gun)
	_scope.name = "ScopeTube"
	_box(Vector3(0.012, 0.03, 0.02), Vector3(0, receiver.y * 0.5 + 0.01, -0.06), gun) \
		.reparent(_scope, false)
	_scope.visible = scoped

	_holo = Node3D.new()
	_holo.name = "HoloSight"
	add_child(_holo)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.1, 0.1, 0.11)
	ring_mat.metallic = 0.1
	ring_mat.roughness = 0.5
	var hoop := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.022
	torus.outer_radius = 0.03
	torus.rings = 10
	torus.ring_segments = 6
	hoop.mesh = torus
	hoop.material_override = ring_mat
	hoop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# TorusMesh's hole runs along +Y, i.e. it lies flat like a donut on a table.
	# Stand it up so the hole runs down the barrel and you sight THROUGH it —
	# the same -Z convention _cyl() uses.
	hoop.rotation.x = PI / 2.0
	hoop.position = Vector3(0, receiver.y * 0.5 + 0.028, -0.08)
	_holo.add_child(hoop)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.012, 0.03, 0.014)
	post.mesh = pm
	post.material_override = ring_mat
	post.position = Vector3(0, receiver.y * 0.5 + 0.005, -0.08)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_holo.add_child(post)
	_holo.visible = holo

	# Whichever sight is fitted has to sit on the camera axis when aimed. The
	# camera is at the Head origin and this gun hangs off the Weapon anchor, so
	# the slide is simply "cancel the anchor offset, then cancel the sight's own
	# offset". Iron sights line up on the receiver's top rib.
	var sight_at := Vector3(0.0, receiver.y * 0.5 + 0.012, -0.02)
	if holo:
		sight_at = Vector3(0.0, receiver.y * 0.5 + 0.028, -0.08)
	elif scoped:
		sight_at = _scope.position
	var anchor: Vector3 = get_parent().position  # Weapon's offset under Head
	_ads_pos = Vector3(-(anchor.x + sight_at.x), -(anchor.y + sight_at.y), ADS_PULL_BACK)

	_build_flash(barrel_z - barrel.z * 0.5 - 0.06)


func _build_flash(tip_z: float) -> void:
	# Muzzle flash: a small additive glow at the barrel tip, flicked on for a
	# couple of frames per shot (additive so it reads as light, not a solid
	# orange shape, under the GL Compatibility renderer).
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
	_flash.position = Vector3(0, 0.012, tip_z)
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


## Rebuild the gun for this class and sight. Called on every class change, so
## each weapon genuinely has its own silhouette rather than a shared body with
## a couple of parts hidden. The sniper ships with optics; anything else grows
## a scope or a holo ring only when one is bought.
func configure(class_id: int, scoped := false, holo := false) -> void:
	# The sniper ships with optics, but a bought holo ring replaces them rather
	# than sitting alongside — two sights on one rail is nobody's intent.
	_build(class_id, (scoped or class_id == Weapon.Class.SNIPER) and not holo, holo)


## Called on each shot; strength scales the kick per weapon class.
func kick(strength: float) -> void:
	_kick = minf(_kick + strength, KICK_CEILING)
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

	var pos := HIP_POS.lerp(_ads_pos, _aim_t) + bob
	# How much of the kick actually SHOWS. Raising the sights damps it, so the
	# gun steadies as your eye comes onto the glass.
	var shown := _kick * lerpf(1.0, ADS_KICK_MULT, _aim_t)
	# Recoil shoves the gun back toward the player, capped so a stacked burst
	# can't drive it through the camera.
	pos.z += minf(shown * KICK_PUSH, MAX_PUSH)
	position = pos
	# Muzzle climbs (rotate about +X) with a small random lateral lean.
	rotation = Vector3(shown * KICK_PITCH, shown * _kick_yaw * KICK_LEAN, 0.0)

	if _flash:
		_flash_t = maxf(_flash_t - delta, 0.0)
		_flash.visible = _flash_t > 0.0

	# A scoped weapon replaces the gun with the scope overlay when aimed, so
	# hide the model once the sights are most of the way up (real-game feel).
	visible = not (aiming and scoped and _aim_t > 0.6)
