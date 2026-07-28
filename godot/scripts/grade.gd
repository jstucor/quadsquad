class_name Grade
extends RefCounted
## THE GRADE: how light is RENDERED in this game, in one place.
##
## A map builds its own environment and its own lights, because the sky, the fog
## colour and the direction the sun comes from ARE the map's identity — a night
## landing zone and a daylight jungle have nothing to say to each other about
## those. But the response curve, the ambient model, the glow threshold and the
## shadow settings are not per-map decisions, and they had been copy-pasted into
## thirteen `_build_environment` overrides that then drifted apart.
##
## So this is applied OVER whatever built the environment: the caller keeps every
## colour it chose, and the renderer settings live here. Arena calls it for every
## map; the look tests call it so what they photograph is what ships.
##
## All static, no autoload — same shape as Controls, for the same reason: it has
## to be callable from anywhere, including scenes that are not Arenas.
##
## Everything here is environment state, not per-frame work, so the whole grade
## is free at runtime. That matters on the Pi, where the scene is drawn four
## times a frame already.

## AgX sits a good deal darker than the Filmic curve these maps were lit under,
## so this puts the mid-tones back. Measured rather than guessed: rendered at
## 1.15 / 1.6 / 2.0 against the darkest map (Crossfire at night) and the
## brightest (Overgrowth at noon), 1.6 is the only value where the night map's
## cover boxes stay readable AND the daylight map's pale cover keeps a face on
## it. A map that should sit darker or brighter sets `grade_exposure`.
const EXPOSURE := 1.6
const WHITE := 8.0            # how far above white the roll-off reaches
const CONTRAST := 1.10        # AgX is deliberately flat and wants grading after
const SATURATION := 1.12
## How much of the ambient comes from the SKY rather than from the authored
## ambient colour. Deliberately a MINORITY share: the sky is here to add
## DIRECTION to the ambient, not to supply it. Several maps are lit by a
## near-black starfield, and at 0.55 those lost half their fill — cover boxes
## went to unreadable black, which is a gameplay bug and not just a dark picture.
const SKY_AMBIENT := 0.3
const GLOW_THRESHOLD := 1.0   # only genuinely bright things bloom
const FOG_AERIAL := 0.8       # how much distance takes the colour of the sky
const FOG_HEIGHT := 12.0      # metres: above this the ground haze thins out
const FOG_HEIGHT_DENSITY := 0.012
const SHADOW_OPACITY := 0.82  # a shadow is not a hole; something bounces in
const SHADOW_BLUR := 1.3


## The five things that separate "a lit diorama" from "a photograph", none of
## which need a renderer feature GL Compatibility does not have.
static func apply(env: Environment, exposure := EXPOSURE) -> void:
	if env == null:
		return
	# 1. TONEMAPPING. Without it anything brighter than white simply clips —
	#    which is why a pale cover box in daylight rendered as a flat white
	#    silhouette with no face left on it. AgX rolls highlights off instead of
	#    cutting them, and is the single biggest change in this function.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = exposure
	env.tonemap_white = WHITE

	# 2. SKY-SOURCED AMBIENT. A flat ambient colour lights every surface
	#    identically whichever way it faces, which is the loudest "this is a
	#    model" cue there is. Sourcing it from the sky gives it direction for
	#    free: a face pointed at the horizon glow is lit differently from one
	#    pointed at the zenith.
	#
	#    BLENDED, not replaced, and that is the important part. Several maps have
	#    a near-black sky and pure sky ambient on those is pure black, so the
	#    authored ambient colour stays as a FLOOR under it: a night map keeps the
	#    lift it was tuned with and gains the directional variance on top. It also
	#    fixes the metallic gotcha at its source — a surface now has a real graded
	#    environment to reflect instead of a void.
	if env.ambient_light_source != Environment.AMBIENT_SOURCE_DISABLED \
			and env.sky != null:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = SKY_AMBIENT
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# 3. GLOW ON A THRESHOLD. `glow_bloom` lifts the WHOLE image into the glow
	#    pass, which reads as a dirty lens rather than as a bright object. Zero it
	#    and let the HDR threshold decide: only genuinely bright things — bolts,
	#    blades, photoreceptors, lamp housings — bloom, which is what makes an
	#    energy weapon look like it is emitting rather than painted.
	if env.glow_enabled:
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = GLOW_THRESHOLD
		env.glow_hdr_scale = 1.0
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		# WEIGHTED TOWARD THE SMALL LEVELS, which is the whole difference between
		# a halo and a wash. The big levels are wide blurs: leaning on them (1.0
		# at level 3, 0.6 at level 4) turned a muzzle flash lighting the floor
		# into a white pool the size of the arena, because the lit ground crossed
		# the HDR threshold and then got smeared across ten metres. A tight
		# falloff still says "this is emitting" without eating the picture.
		env.set_glow_level(1, 0.65)
		env.set_glow_level(2, 0.45)
		env.set_glow_level(3, 0.20)
		env.set_glow_level(4, 0.06)
		env.set_glow_level(5, 0.0)

	# 4. AERIAL PERSPECTIVE. Distance reads as distance because far things take
	#    the colour of the air between you and them. Without it every trunk on a
	#    220 m map is the same green at 5 m and at 150 m and the map looks like a
	#    tabletop. This tints the fog by the SKY rather than by a fixed colour, so
	#    it is automatically right for whatever sky the map has.
	if env.fog_enabled:
		env.fog_aerial_perspective = FOG_AERIAL
		env.fog_sky_affect = maxf(env.fog_sky_affect, 0.25)
		# A shallow ground haze on top of the depth fog. Real air is denser near
		# the ground, and it is what separates a far silhouette from the sky.
		env.fog_height = FOG_HEIGHT
		env.fog_height_density = FOG_HEIGHT_DENSITY

	# 5. A little contrast and saturation back. AgX is deliberately flat — that
	#    is what stops it clipping — so it wants grading afterwards, exactly as
	#    film does.
	env.adjustment_enabled = true
	env.adjustment_contrast = CONTRAST
	env.adjustment_saturation = SATURATION


## Shadow quality, per directional light. Two separate problems, both visible in
## the same screenshot: shadows that are BLACK (nothing bounces into them, so a
## tree casts a hole in the ground) and shadows that are ALIASED.
static func light(l: DirectionalLight3D) -> void:
	if l == null or not l.shadow_enabled:
		return
	# A shadow is the absence of the KEY light, not the absence of all light.
	# shadow_opacity is the cheapest possible stand-in for bounce: it costs
	# nothing and it is the difference between a shadow and a hole.
	l.shadow_opacity = SHADOW_OPACITY
	l.shadow_blur = SHADOW_BLUR
	# Four splits with blending across them. These maps run to 260 m, and one
	# split over that distance is what makes near-ground shadows crawl.
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	l.directional_shadow_blend_splits = true
	# Normal bias rather than depth bias: depth bias detaches a shadow from the
	# thing casting it (peter-panning), which on boxes standing on a flat floor
	# is exactly the artifact you notice.
	l.shadow_normal_bias = 1.4
	l.shadow_bias = 0.03


## Grade every environment and directional light under `root`. What Arena calls
## on itself, and what a test scene calls so its screenshots match the game.
static func apply_to(root: Node, exposure := EXPOSURE) -> void:
	for child in root.get_children():
		if child is WorldEnvironment:
			apply(child.environment, exposure)
		elif child is DirectionalLight3D:
			light(child)
