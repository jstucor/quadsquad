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
const SHADOW_OPACITY := 0.92  # SSIL and SSAO now carry most of the bounce
const SHADOW_BLUR := 1.0
## --- Forward+ only ------------------------------------------------------------
## Everything below needs the clustered renderer. The project ran on GL
## Compatibility for the Raspberry Pi 5, which has none of it; dropping that
## target is what these cost.
const SSAO_RADIUS := 1.6          # metres of contact darkening
const SSAO_INTENSITY := 2.4
const SSIL_RADIUS := 6.0          # metres a surface throws its colour
const SSIL_INTENSITY := 1.1
## Volumetric density is FAR more sensitive than depth fog: 0.012 turned a 280 m
## forest into an opaque green soup with the ground lost in it. Outdoor vistas
## want thousandths. A map that wants weather (Mustafar's ash, Hoth's blizzard)
## passes its own.
const VOLUMETRIC_DENSITY := 0.0022
const FOG_ANISOTROPY := 0.55      # >0 scatters forward, which is what makes rays
## Softness of the sun's shadow edge, in degrees of angular diameter. The real
## sun is about 0.5; more than that reads as overcast, and it is also the dial
## that hides the shadow map's resolution.
const SUN_ANGULAR := 1.1


## The five things that separate "a lit diorama" from "a photograph", none of
## which need a renderer feature GL Compatibility does not have.
static func apply(env: Environment, exposure := EXPOSURE,
		fog_density := VOLUMETRIC_DENSITY) -> void:
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
	# ...but whether glow runs AT ALL is a cost decision, so `Quality` gets to veto
	# it before this configures it. Measured at the edge of noise (1.3 ms), which is
	# why only the LOW tier takes it — and on the night maps the glow IS the muzzle
	# flash, so it is not a saving to reach for casually.
	Quality.apply_to_environment(env)
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

	# 6-8. THE FORWARD+ HALF. None of this exists under GL Compatibility, and
	#      dropping the Raspberry Pi target is what bought it. These three are
	#      the difference between "lit" and "shaded".
	#
	#      GUARDED, because the project can still be run on either renderer (see
	#      the [rendering] block in project.godot for the measured trade). Setting
	#      any of them under Compatibility does not fail quietly — it raises an
	#      error per environment per call, which buried the real output of every
	#      look test in fog warnings. `get_rendering_device()` is null on exactly
	#      the renderers that lack these, so it is the honest question to ask.
	if RenderingServer.get_rendering_device() == null:
		return
	#
	# SSAO: contact darkening where surfaces meet. On a game built out of boxes
	# standing on ground this is the single biggest one — without it every object
	# floats, because nothing ever darkens where it touches anything else.
	env.ssao_enabled = true
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.08
	env.ssao_light_affect = 0.15   # a little, so shadows do not go pure black

	# SSIL: colour bleeding between surfaces. Red rock throws red into the
	# shadow beside it; lava throws orange up the wall above it. It is what makes
	# a palette look like it belongs to one place rather than being painted on.
	env.ssil_enabled = true
	env.ssil_radius = SSIL_RADIUS
	env.ssil_intensity = SSIL_INTENSITY
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	# VOLUMETRIC FOG: actual air. Depth fog tints distance; volumetric fog is a
	# medium the sun shines THROUGH, so it gives god rays under a canopy, glow
	# over lava and a real blizzard — and it is lit by every light in the scene,
	# which is why the lava and the city windows now do something to the sky
	# above them instead of only to the ground below.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = env.fog_light_color
	env.volumetric_fog_emission = Color.BLACK
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_anisotropy = FOG_ANISOTROPY
	env.volumetric_fog_length = 260.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.9


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
	# A real penumbra: the shadow edge softens with distance from what casts it,
	# the way a sun-cast shadow actually does. Forward+ only.
	l.light_angular_distance = SUN_ANGULAR
	# ...and the light has to be told to light the FOG as well as the surfaces,
	# or the volumetric layer sits there unlit and just greys the picture down.
	l.light_volumetric_fog_energy = 1.0
	# Two splits. These maps run to 260 m and one split over that distance is what
	# makes near-ground shadows crawl — measured, going to one split saves nothing
	# anyway, so there is no argument for it in either direction.
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Whether the two splits are BLENDED across their boundary is a cost decision
	# (3 ms at a four-way split) rather than a look decision, so `Quality` owns it.
	# Everything else here is free and stays stated in this file.
	Quality.apply_to_light(l)
	# Normal bias rather than depth bias: depth bias detaches a shadow from the
	# thing casting it (peter-panning), which on boxes standing on a flat floor
	# is exactly the artifact you notice.
	l.shadow_normal_bias = 1.4
	l.shadow_bias = 0.03


## Grade every environment and directional light under `root`. What Arena calls
## on itself, and what a test scene calls so its screenshots match the game.
static func apply_to(root: Node, exposure := EXPOSURE,
		fog_density := VOLUMETRIC_DENSITY) -> void:
	for child in root.get_children():
		if child is WorldEnvironment:
			apply(child.environment, exposure, fog_density)
		elif child is DirectionalLight3D:
			light(child)
