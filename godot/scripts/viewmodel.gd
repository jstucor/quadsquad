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
## The render layer these meshes belong on: the owner's private viewmodel bit,
## so only their own camera sees the gun in their hands. 0 leaves them on the
## default layer, which is what a bot wants (its weapon IS a world object).
##
## Applied on every REBUILD, not once at spawn. Player used to set it on the
## meshes that existed when it became ready — and there are none, because the
## gun is built by the set_class on the very next line, and rebuilt again on
## every weapon swap and every respawn. All of those parts landed on layer 1, so
## every OTHER player saw this one's first-person weapon floating at their face.
## Unmissable once it was a metre of lit blade; a small dark rifle overlapping
## the third-person one is why it went unnoticed.
var view_layer := 0

var _player: CharacterBody3D
var _scope: MeshInstance3D
var _holo: Node3D
var _flash: MeshInstance3D
var _saber: Node3D           # the saber's own pivot, when a blade is in hand
var _swing := 0.0            # 1 at the start of a swing, decaying to 0
var _swing_side := 1.0       # alternates, so consecutive strikes cross over
var _parry := 0.0            # 1 the frame a hit is stopped, decaying to 0
var _parry_side := 1.0       # which way the blade is knocked, alternating
var _blade_core: StandardMaterial3D  # kept so a parry can flare them
var _blade_glow: StandardMaterial3D
var _brace_t := 0.0          # phase of the guard's slow sway

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
	Weapon.Class.BOWCASTER: {  # Wookiee crossbow: fat body, short bore, limbs
		"receiver": Vector3(0.072, 0.09, 0.22), "barrel": Vector3(0.03, 0.03, 0.18),
		"stock": true, "grip": true, "drum": 0.05, "muzzle": 0.04, "limbs": 0.15,
	},
	# The lightsaber is built by _build_saber, not from these fields: a hilt and
	# a blade share nothing with a receiver and a barrel. The entry exists so
	# the class is present in the table and `saber` can flag the branch.
	Weapon.Class.SABER: {
		"receiver": Vector3(0.042, 0.042, 0.24), "barrel": Vector3(0.03, 0.03, 0.0),
		"stock": false, "grip": false, "saber": true,
	},
}

## Blade dimensions and colour. The blade is drawn a good deal SHORTER than the
## weapon's 3.4 m reach on purpose: a true-length blade fills the whole screen
## from a first-person camera and you cannot see what you are swinging at.
const BLADE_LENGTH := 0.78
const BLADE_RADIUS := 0.019
## The ready stance: hilt held low and to the right, blade standing UP and
## tilted slightly across the body. A blade pointing down the barrel line is
## what every other weapon here does and it reads as a glowing rifle — worse,
## from a first-person camera it lies along the view axis and you cannot see
## past it. Upright puts the blade beside the crosshair instead of over it.
## Pitch, yaw, roll in radians. The blade is modelled along -Z like every barrel
## here, so a POSITIVE pitch is what stands it up: rotating -Z about +X by t
## sends it to (0, sin t, -cos t), and it was pointing at the floor until that
## sign was fixed.
const SABER_REST := Vector3(1.28, 0.18, -0.28)
const SABER_AT := Vector3(0.17, -0.26, -0.30)     # hilt low and to the right
## One swing, in seconds, and how far it travels. The arc is deliberately big:
## a sword that twitches like recoil does not read as a swing at all.
const SWING_TIME := 0.32
# NEGATIVE pitch, because rest already has the blade up: the swing brings it
# DOWN through horizontal, which is the chop. Positive would throw it backwards
# over the shoulder.
const SWING_PITCH := -1.55
const SWING_YAW := 1.05     # ...carried across the body
const SWING_ROLL := 0.55
const BLADE_CORE := Color(0.75, 0.92, 1.0)
const BLADE_GLOW := Color(0.25, 0.65, 1.0)
const BLADE_ENERGY := 5.0   # core emission at rest; a parry flares off this

## THE GUARD. It has to be unmistakable, because everything else about blocking
## is invisible: the arc it covers, the pool it spends and the break are all
## numbers. If the pose is a small tilt, a player holding the button has no idea
## whether anything is happening — so the blade comes right up across the view,
## the hilt is drawn in to the centre of the chest, and the whole weapon rides a
## slow brace instead of sitting frozen.
## ...while still leaving the player able to SEE. The blade is a metre of solid
## white: brought fully across the centre it blinds you exactly when you are
## being shot at, so it rises through the right of the frame with the hilt held
## out at chest height, and the crosshair stays clear.
const GUARD_ROT := Vector3(1.16, -0.34, 0.62)
const GUARD_AT := Vector3(0.13, -0.20, -0.40)      # out, up, and further away
const GUARD_DRAW_IN := Vector3(-0.05, 0.03, 0.0)   # ...the whole model leans in
const GUARD_BRACE := 0.035   # radians of sway, so a held guard is visibly HELD
const GUARD_BRACE_RATE := 3.4

## The parry: what a stopped hit looks like. The blade is knocked back and flares
## for a moment, which is the only confirmation that the guard just paid for
## something — the pool draining is a number on the HUD and nobody reading it is
## looking at the fight.
const PARRY_TIME := 0.26
const PARRY_ROT := Vector3(-0.30, 0.30, -0.34)
const PARRY_PUSH := Vector3(0.05, -0.03, 0.07)  # driven back toward the camera
const PARRY_FLARE := 9.0     # added to BLADE_ENERGY at the moment of the block


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
	_saber = null
	_blade_core = null
	_blade_glow = null

	var shape: Dictionary = SHAPES.get(class_id, SHAPES[Weapon.Class.SOLDIER])
	if shape.get("saber", false):
		_build_saber()
		return
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
	if shape.get("limbs", false):
		# The bowcaster's crossbow limbs, out at the MUZZLE end and swept back,
		# with a string strung between the tips. It is the whole reason the
		# weapon is recognisable — built from the same boxes as everything else,
		# because a silhouette is what a viewmodel is for and this one is a
		# CROSSBOW. Sitting them mid-barrel and short read as a rifle with a bar
		# stuck through it.
		var span: float = shape["limbs"]
		var limb_z := -receiver.z * 0.5 - barrel.z * 0.9
		for side in [-1.0, 1.0]:
			var limb := _box(Vector3(span, 0.018, 0.038),
				Vector3(span * 0.5 * side, 0.0, limb_z), gun)
			# Only a slight sweep. At 0.5 rad the limbs lay along the view axis and
			# vanished into the receiver from the owner's own camera — which is the
			# only camera that ever sees a viewmodel.
			limb.rotation.y = -0.16 * side
		# The string runs BEHIND the tips, and in gunmetal: the accent material
		# is the emissive power cell, and a glowing orange bowstring reads as a
		# fault light rather than a weapon.
		_box(Vector3(span * 1.95, 0.008, 0.008),
			Vector3(0.0, 0.0, limb_z + span * 0.16), dark)
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


## The lightsaber: a machined hilt with a blade standing out of it. Built on its
## own path because it shares no part with a gun.
##
## The blade is TWO nested cylinders — a near-white core inside a wider, softer
## coloured shell — because a single emissive cylinder reads as a flat plastic
## rod under GL Compatibility. Both are unshaded, so the blade keeps its colour
## on the night maps where a lit surface would go black on its shadow side (the
## same reason the cable's wire is unshaded).
##
## It leaves `_flash` null: a blade has no muzzle. kick() already null-checks it.
func _build_saber() -> void:
	# Everything hangs off one pivot so the whole weapon swings as a piece. The
	# viewmodel root cannot be used for that: its transform is already driven by
	# recoil, bob and the ADS slide every frame.
	_saber = Node3D.new()
	_saber.name = "Saber"
	add_child(_saber)
	_saber.position = SABER_AT
	_saber.rotation = SABER_REST

	var hilt_mat := StandardMaterial3D.new()
	hilt_mat.albedo_color = Color(0.16, 0.17, 0.19)
	hilt_mat.metallic = 0.15  # keep low: a near-black sky reflects into metal
	hilt_mat.roughness = 0.35
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.42, 0.36, 0.20)
	ring_mat.metallic = 0.15
	ring_mat.roughness = 0.4

	# The hilt sits in the hand, angled like the pistol grip every gun carries.
	var hilt := _cyl(0.021, 0.24, Vector3(0, -0.015, 0.0), hilt_mat, _saber)
	_cyl(0.025, 0.02, Vector3(0, -0.015, -0.10), ring_mat, _saber)   # emitter shroud
	_cyl(0.024, 0.015, Vector3(0, -0.015, 0.06), ring_mat, _saber)   # pommel band
	_box(Vector3(0.012, 0.014, 0.03), Vector3(0.02, -0.015, 0.02), ring_mat, _saber)

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = BLADE_CORE
	core_mat.emission_enabled = true
	core_mat.emission = BLADE_CORE
	core_mat.emission_energy_multiplier = BLADE_ENERGY

	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_color = Color(BLADE_GLOW.r, BLADE_GLOW.g, BLADE_GLOW.b, 0.5)
	glow_mat.emission_enabled = true
	glow_mat.emission = BLADE_GLOW
	glow_mat.emission_energy_multiplier = 3.0

	# Blade runs down -Z out of the emitter, the same axis every barrel uses.
	var blade_z := -0.11 - BLADE_LENGTH * 0.5
	_cyl(BLADE_RADIUS, BLADE_LENGTH, Vector3(0, -0.015, blade_z), core_mat, _saber)
	_cyl(BLADE_RADIUS * 1.9, BLADE_LENGTH * 0.99, Vector3(0, -0.015, blade_z), glow_mat, _saber)
	hilt.name = "SaberHilt"
	# Held so a parry can flare them. They belong to this blade alone (built here,
	# not shared out of a table), so writing to them cannot leak onto anyone else.
	_blade_core = core_mat
	_blade_glow = glow_mat

	# No sights on a sword. Aiming blocks instead, so the ADS slide is a small
	# guard-raise rather than bringing anything onto the camera axis.
	_ads_pos = Vector3(-0.05, 0.02, 0.02)


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


## `into` lets a caller build under its own pivot instead of straight onto the
## viewmodel root — the saber needs that, because the whole weapon swings as one
## piece and the root's transform is already spoken for by recoil and bob.
func _box(size: Vector3, pos: Vector3, mat: Material,
		into: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(into if into != null else self).add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material,
		into: Node3D = null) -> MeshInstance3D:
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
	(into if into != null else self).add_child(mi)
	return mi


## Rebuild the gun for this class and sight. Called on every class change, so
## each weapon genuinely has its own silhouette rather than a shared body with
## a couple of parts hidden. The sniper ships with optics; anything else grows
## a scope or a holo ring only when one is bought.
func configure(class_id: int, scoped := false, holo := false) -> void:
	# The sniper ships with optics, but a bought holo ring replaces them rather
	# than sitting alongside — two sights on one rail is nobody's intent.
	_build(class_id, (scoped or class_id == Weapon.Class.SNIPER) and not holo, holo)
	# Every part in there is new, so the owner's layer has to go on again. Done
	# here rather than inside _build because _build returns early for a blade.
	_apply_view_layer()


## Put the freshly built parts on the owner's private viewmodel layer.
func _apply_view_layer() -> void:
	if view_layer == 0:
		return
	for mi in find_children("*", "MeshInstance3D", true, false):
		mi.layers = view_layer


## The saber's own animation. Two states and one action:
##
## AT REST it sits in the ready stance, riding the same walk bob as every other
## weapon so it does not float independently of the body.
##
## AIMING is the GUARD, so the blade comes up ACROSS the body — the pose has to
## read as "I am blocking with this", because the exhaustion pool it spends is
## invisible otherwise.
##
## SWINGING is a single arc traced by sin(): the blade accelerates through the
## strike and settles back, and consecutive swings alternate sides so holding
## the trigger looks like a sequence of cuts rather than one chop on repeat.
## `_aim_t` is stepped by the caller, once, for every weapon: stepping it again
## here fought the caller's own step and left the raise crawling.
func _animate_saber(delta: float, bob: Vector3) -> void:
	_swing = maxf(_swing - delta / SWING_TIME, 0.0)
	_parry = maxf(_parry - delta / PARRY_TIME, 0.0)
	_brace_t += delta * GUARD_BRACE_RATE

	# The viewmodel root only carries the bob and the guard's draw-in; the swing
	# and the parry belong to the saber pivot.
	position = HIP_POS.lerp(GUARD_DRAW_IN, _aim_t) + bob + PARRY_PUSH * _parry
	rotation = Vector3.ZERO

	# Guard: blade brought up across the view, hilt drawn in to the chest.
	var pose := SABER_REST.lerp(GUARD_ROT, _aim_t)
	var at := SABER_AT.lerp(GUARD_AT, _aim_t)
	# ...and BRACED there. A pose that holds perfectly still reads as a frozen
	# animation, which is the one thing a defensive stance must not look like.
	pose += Vector3(sin(_brace_t) * GUARD_BRACE,
		sin(_brace_t * 0.63) * GUARD_BRACE * 0.7, 0.0) * _aim_t

	# 0 at the start of the swing, 1 at the end; sin() gives the arc a fast
	# middle and a soft finish at both ends.
	var t := 1.0 - _swing
	var arc := sin(t * PI)
	pose += Vector3(
		arc * SWING_PITCH,
		arc * SWING_YAW * _swing_side,
		arc * SWING_ROLL * -_swing_side)

	# The parry rocks the blade back off the impact and springs it home. Same sin
	# arc as the swing, so a block reads as a deliberate motion rather than a
	# twitch, and it alternates sides so a burst stopped by the guard looks like
	# the blade working rather than one shudder repeated.
	if _parry > 0.0:
		var knock := sin((1.0 - _parry) * PI)
		pose += Vector3(PARRY_ROT.x, PARRY_ROT.y * _parry_side,
			PARRY_ROT.z * _parry_side) * knock

	_saber.rotation = pose
	_saber.position = at
	_flare_blade()
	visible = true


## Push the parry's brightness onto the blade. The flare is on the EMISSION
## rather than on a separate flash mesh so it lights the whole length of the
## blade at once, which is what sells contact somewhere along it.
func _flare_blade() -> void:
	if _blade_core == null:
		return
	var flare := PARRY_FLARE * _parry
	_blade_core.emission_energy_multiplier = BLADE_ENERGY + flare
	_blade_glow.emission_energy_multiplier = 3.0 + flare * 0.6


## The guard just stopped a hit. Cosmetic only — Player has already decided what
## the block cost and whether it broke.
func parry() -> void:
	if _saber == null:
		return
	_parry = 1.0
	_parry_side = -_parry_side


## Called on each shot; strength scales the kick per weapon class.
func kick(strength: float) -> void:
	# A blade swings; it does not recoil. Alternating the side means a held
	# attack reads as a sequence of strikes crossing the body rather than the
	# same chop played over and over.
	if _saber != null:
		_swing = 1.0
		_swing_side = -_swing_side
		return
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

	# The guard is NOT `weapon.aiming`. Player forces that flag false for a melee
	# weapon — a blade has no sights — so reading it here left _aim_t pinned at 0
	# and the guard pose below never played at all. Ask the OWNER instead, which
	# is also the only thing that knows about the exhaustion pool, so the blade
	# drops back to rest the moment the guard breaks. Bots have no guard_up.
	var guarding: bool = _player != null and _player.has_method("guard_up") \
		and _player.guard_up()

	_aim_t = move_toward(_aim_t, 1.0 if (aiming or guarding) else 0.0, delta / AIM_TIME)
	_kick = move_toward(_kick, 0.0, delta * RECOIL_DECAY)

	# Walk bob, damped while aiming and only on the ground.
	var speed := 0.0
	if _player and _player.is_on_floor():
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob_t += delta * (4.0 + speed * 1.6)
	var bob_amp := 0.011 * clampf(speed / 5.0, 0.0, 1.0) * (1.0 - 0.75 * _aim_t)
	var bob := Vector3(cos(_bob_t) * bob_amp, absf(sin(_bob_t)) * bob_amp, 0.0)

	# A blade has its own motion: it swings on its pivot instead of kicking the
	# whole viewmodel, and raising the guard is a pose rather than a sight slide.
	if _saber != null:
		_animate_saber(delta, bob)
		return

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
