class_name Blast
extends Object
## EVERY EXPLOSION IN THE GAME, in one place. A rocket, a grenade and a mortar
## shell were three copies of the same twenty lines that had already drifted
## apart — the rocket had grown a real light on the argument that a blast which
## does not illuminate the ground it goes off on reads as a decal pasted over the
## scene, and the other two had never been given one, so a frag at your feet lit
## nothing at all.
##
## It is a sphere of additive light plus an OmniLight3D, alive for a fifth of a
## second. Shadows off: four shadow passes for something over in twelve frames
## would be the most expensive frame of the match. That cost is worth paying for
## a blast and is deliberately NOT paid for a bullet — see `Impact`, which lights
## its hits from a fixed pool instead, and only at night.
##
## AT NIGHT THE BLAST IS THE ONLY THING LIGHTING THE MAP for a moment, so it
## reaches much further and burns brighter. This is the "bombs illuminate the
## battlefield" half of a night match: a mortar walking across a ridge should
## show you, in flashes, who is standing on it.

const RANGE_MULT := 3.0        # light reach as a multiple of the splash radius
const ENERGY := 8.0
const LIFE := 0.18
const CORE := Color(1.0, 0.55, 0.2, 0.8)
const GLOW := Color(1.0, 0.45, 0.15)
const LIGHT_COLOR := Color(1.0, 0.6, 0.25)

## Night multipliers. Reach goes up by more than brightness does, for the same
## reason the muzzle flash's does: what makes a flash useful in the dark is how
## much ground it shows you, not how white the middle of it is.
const NIGHT_RANGE := 2.4
const NIGHT_ENERGY := 1.5

## THE BALL COMES DOWN AT NIGHT, WHICH IS THE OPPOSITE OF WHAT YOU EXPECT. Its
## additive sphere was tuned against daylight, where it is competing with a sun
## and reads as a fireball; in the dark, at the same values, it saturates flat
## and comes back as an opaque orange DISC pasted over the map — a shape with a
## hard edge and no falloff inside it, which is exactly what an explosion is not.
## Turned down, the real light does the work and the ball becomes the hot core
## of it rather than the whole effect.
## ...and it is SMALLER, so the light reaches further than the ball does. An
## additive sphere has a hard silhouette wherever it crosses geometry, and in the
## dark that edge is the most visible thing about it — a dome with a clipping
## line drawn across the tower behind it. Pulled inside the light it throws, the
## edge lands on ground that is already lit and stops reading as an outline.
const NIGHT_CORE_ALPHA := 0.42
const NIGHT_GLOW_ENERGY := 2.2
const NIGHT_BALL := 0.62


## Set off a blast at `pos`. `splash` is the weapon's own damage radius, which is
## what everything here is sized from, so a frag and a mortar shell differ by one
## number rather than by twenty lines each.
static func pop(scene: Node, pos: Vector3, splash: float, ball := 0.6) -> void:
	if scene == null:
		return
	var night: bool = GameState.is_night()
	var flash := MeshInstance3D.new()
	var s := SphereMesh.new()
	var r := splash * ball * (NIGHT_BALL if night else 1.0)
	s.radius = r
	s.height = r * 2.0
	flash.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = CORE
	if night:
		mat.albedo_color.a = NIGHT_CORE_ALPHA
	mat.emission_enabled = true
	mat.emission = GLOW
	mat.emission_energy_multiplier = NIGHT_GLOW_ENERGY if night else 6.0
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var light := OmniLight3D.new()
	light.omni_range = splash * RANGE_MULT * (NIGHT_RANGE if night else 1.0)
	light.light_energy = ENERGY * (NIGHT_ENERGY if night else 1.0)
	light.light_color = LIGHT_COLOR
	light.shadow_enabled = false
	flash.add_child(light)

	# Added first, positioned after: global_position on a node outside the tree
	# is silently treated as local and errors.
	scene.add_child(flash)
	flash.global_position = pos
	scene.get_tree().create_timer(LIFE).timeout.connect(flash.queue_free)
