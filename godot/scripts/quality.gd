extends RefCounted
class_name Quality

## QUALITY: what the picture is allowed to COST, in one place.
##
## The exact counterpart to `Grade`. Grade owns how light is RENDERED — the
## response curve, the ambient model, the glow threshold — and those are not
## per-map decisions. This owns how much of the frame that rendering may SPEND,
## which is not a per-map decision either, and had been three constants in three
## files (`Main.MSAA`, the shadow settings in `project.godot`, the split count in
## `Grade.light`) with nothing relating them to each other or to the budget.
##
## EVERY NUMBER BELOW WAS MEASURED, on the machine this game is developed on
## (Intel UHD 620, 4 viewports, generated world, 12 bodies), with one thing
## changed at a time against controls either side of it — `tests/render_cost.gd`
## with `QS_ABLATE`. What that found, in order of size:
##
##   shadow map 4096 -> 2048      2.2 ms      -> and 1024 is 5.0 ms
##   split blending off           3.0 ms
##   msaa 2x -> off               3.0 ms
##   soft shadow filter -> low    ~1 ms       (at the edge of noise)
##   3D render scale 0.60         8.7 ms
##   1 split instead of 2         nothing
##   shadow distance 100 -> 45    nothing
##
## And, just as usefully, what was CLEARED: the terrain shader — three four-octave
## FBMs per fragment, 48 sin-based hashes, over the geometry that fills most of
## the screen — costs **0.07 ms**, and the sky shader costs nothing at all. Both
## were the obvious suspects and both were innocent. The frame is not paying for
## clever fragments; it is paying for SHADOW MAP DEPTH FILL and for pixels.
##
## Two rules fall out of that, and they are the whole design here:
##
##   1. THE SHADOW BUDGET FOLLOWS THE VIEWPORT COUNT, because the shadow map is
##      rendered once per CAMERA while each camera gets a SMALLER share of the
##      screen. At a four-way split each quadrant is 960x540 and a 4096 map over
##      an 80 m split is roughly seven shadow texels per screen pixel — detail
##      that quadrant cannot resolve and is charged for anyway. One player at
##      1080p is the case that can actually use a big map.
##   2. PIXELS ARE THE LAST RESORT AND THE BIGGEST LEVER. Render scale always
##      works on a fill-bound frame and it is the only thing here that visibly
##      softens the image, so it is what the LOW tier spends and the tiers above
##      it do not touch.

## What a machine is asked to spend. The names are what a player picks from, so
## they are about the machine and not about a shadow map.
enum Tier {
	LOW,        ## integrated graphics, or four players on one
	MEDIUM,     ## the default, and what every look test photographs
	HIGH,       ## a discrete GPU with headroom to spare
}

## Per tier: the shadow map at 1 / 2 / 4 viewports, then everything that is not
## resolution-dependent. `shadow` is indexed by `_slot(views)`, not by the count.
const TIERS := {
	Tier.LOW: {
		"name": "LOW",
		"shadow": [1024, 1024, 512],
		"blend_splits": false,
		"filter": RenderingServer.SHADOW_QUALITY_HARD,
		"msaa": Viewport.MSAA_DISABLED,
		"scale": [1.0, 0.85, 0.70],
		"glow": false,
	},
	Tier.MEDIUM: {
		"name": "MEDIUM",
		"shadow": [2048, 2048, 1024],
		# Blending across the split boundary costs 3 ms and hides a seam that on
		# flat-shaded boxes under a 1.1-degree sun is genuinely hard to find. It
		# is the best ms-per-pixel-of-regret on the list.
		"blend_splits": false,
		"filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"msaa": Viewport.MSAA_2X,
		# A FOUR-WAY SPLIT STARTS LOWER, because it cannot start where one player
		# does: the same scene is drawn four times into quarter-size windows, and
		# measured here one player renders comfortably inside the budget while four
		# are at 25-42 ms. Under AUTO this is only the governor's STARTING point and
		# it will climb back to 1.0 if the machine allows — starting at 0.85 just
		# means a four-way match does not open with five seconds of stutter while the
		# governor walks down to where it was always going to end up.
		"scale": [1.0, 1.0, 0.85],
		"glow": true,
	},
	Tier.HIGH: {
		"name": "HIGH",
		"shadow": [4096, 4096, 2048],
		"blend_splits": true,
		"filter": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"msaa": Viewport.MSAA_2X,
		"scale": [1.0, 1.0, 1.0],
		"glow": true,
	},
}

## MSAA IS NOT THE FIRST THING TO CUT, even though it costs 3 ms. This scene is
## untextured flat-shaded boxes, so essentially all of its aliasing is geometric
## edges — exactly what MSAA fixes and exactly what a resolution drop makes
## worse. It survives into MEDIUM for that reason and only LOW gives it up.

## HOW MANY VIEWPORTS THE FRAME IS BEING SPLIT INTO, mirrored in here rather than
## read off GameState — the same trick and the same reason as
## `Loadout.active_universe` and `Loadout.ttk_health`. `Grade` is called from look
## tests that run without autoloads, so nothing on this path may name GameState.
## Main pushes it before it builds the viewports; 1 is the honest default for
## anything that never says (a look test photographing a single camera).
static var active_views := 1


## A tier's resolution-dependent entries are indexed through this rather than by
## the raw viewport count, so 3 players land somewhere sensible instead of off the
## end of a three-entry array.
static func _slot(views: int) -> int:
	if views <= 1:
		return 0
	if views <= 2:
		return 1
	return 2


## The tier actually in force. AUTO resolves to MEDIUM and then lets the GOVERNOR
## adapt, rather than picking a lower tier by viewport count.
##
## Both were built and the second is better, for a reason worth keeping: choosing
## LOW for a four-way split is a GUESS about the machine, and this machine changes
## its mind — the same LOW configuration measured 58.8 fps in one run and 42.6 in
## another with nothing different but the temperature. A guess cannot track that and
## a governor can, so having both meant two mechanisms adapting to the same thing
## and getting in each other's way: the tier had already spent the resolution the
## governor needed to give back after it halved the frame rate.
##
## So AUTO is MEDIUM — which keeps MSAA, and on flat-shaded untextured boxes MSAA is
## most of what the picture has — and the tier's render scale is only where the
## governor STARTS.
static func tier() -> Tier:
	var chosen := Controls.graphics_quality()
	if chosen == Controls.QUALITY_AUTO:
		return Tier.MEDIUM
	return chosen as Tier


## WHETHER THE GOVERNOR RUNS, and the rule is simply whether the player asked for
## a specific picture. AUTO means "keep it smooth and decide for me", which is
## exactly what a runtime governor does; naming a tier means "give me this", and
## quietly moving the resolution underneath that would be ignoring the setting.
## `tests/render_cost.gd` also turns it off for the ablation sweeps — a governor
## moving the scale mid-measurement corrupts the thing being measured.
static var governor_enabled := true


static func governs() -> bool:
	return governor_enabled and Controls.graphics_quality() == Controls.QUALITY_AUTO


## What to call the setting on screen. AUTO says what it resolved to as well as
## that it is automatic, because "AUTO" alone tells a player nothing about why
## their split screen looks softer than their solo game.
static func tier_label() -> String:
	var chosen := Controls.graphics_quality()
	if chosen == Controls.QUALITY_AUTO:
		return "AUTO (%s)" % TIERS[tier()]["name"]
	return TIERS[chosen]["name"]


static func settings(views := -1, of := -1) -> Dictionary:
	# AUTO is a legal stored value and is NOT a key here, so anything that is not
	# a real tier resolves through `tier()` rather than indexing off the end.
	var t: Dictionary = TIERS[of if TIERS.has(of) else tier()]
	var slot := _slot(active_views if views < 0 else views)
	return {
		"name": t["name"],
		"shadow": t["shadow"][slot],
		"blend_splits": t["blend_splits"],
		"filter": t["filter"],
		"msaa": t["msaa"],
		"scale": t["scale"][slot],
		"glow": t["glow"],
	}


## Everything that is set once for the whole renderer rather than per viewport:
## the directional shadow map, its filter, and the frame rate cap. Called by Main
## when a match starts and by the menu, so a quality change takes effect on the
## next screen either way without a restart.
static func apply_global(views := -1) -> void:
	var q := settings(views)
	# The DIRECTIONAL shadow atlas is a renderer-wide resource but it is rendered
	# once per camera per frame, which is why its size is the single biggest item
	# in a split-screen frame and why it is scaled by the viewport count.
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["filter"])
	# Positional shadows: the muzzle flash and the night impact lights cast none,
	# so this only ever costs and never shows. Hard, always.
	RenderingServer.positional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_HARD)
	apply_fps_cap()


## THE FRAME CAP IS A SMOOTHNESS SETTING, NOT A PERFORMANCE ONE, and it is the
## one lever here that can make the game feel better while making the numbers
## worse. Two reasons, both measured on this laptop:
##
##   EVEN PACING BEATS A HIGHER AVERAGE. With vsync on, a frame that misses the
##   refresh is not slightly late — it is held and presented at 33 ms. A scene
##   floating either side of the line therefore alternates 16 and 33 ms, which is
##   judder; the same scene locked at 30 presents every frame at exactly 33 ms,
##   which reads as smooth. The eye is far more sensitive to the variance than to
##   the mean.
##
##   AND AN UNCAPPED FRAME COOKS THE GPU. A 4-viewport match measured 26 ms cold
##   and 48 ms after two minutes at full tilt — this chip drops to a third of its
##   clock when hot, so leaving it pegged buys a fast first minute and a slow
##   match. Capping keeps it out of the throttle, and the cap is then a floor as
##   well as a ceiling.
##
## 60 is the default because it is free — it only ever stops the MENU spinning at
## 300 fps for nothing — and 30 is there for the machine that cannot hold 60,
## where it is the smoothest setting available rather than a concession.
static func apply_fps_cap() -> void:
	Engine.max_fps = Controls.fps_cap()


## Per viewport, and it has to be per viewport: the project settings only reach
## the ROOT viewport and the game never renders anything into that.
static func apply_to_viewport(vp: Viewport, views := -1) -> void:
	var q := settings(views)
	vp.msaa_3d = q["msaa"]
	# Debanding is a dither over a smooth sky gradient. It costs nothing and the
	# sky is the classic thing to band on an 8-bit target.
	vp.use_debanding = true
	var scale := float(q["scale"])
	if scale < 0.999:
		# Bilinear rather than FSR: FSR needs the RD renderers and this game ships
		# on Compatibility. Set the mode explicitly anyway, so a future switch to
		# Forward+ does not silently change what LOW looks like.
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale


## The shadow settings that live on the LIGHT rather than on the renderer. Called
## from `Grade.light`, so a map still gets its shadows graded in one place and
## this only supplies the numbers that have a price attached.
static func apply_to_light(l: DirectionalLight3D, views := -1) -> void:
	if l == null or not l.shadow_enabled:
		return
	var q := settings(views)
	l.directional_shadow_blend_splits = q["blend_splits"]


static func apply_to_environment(env: Environment, views := -1) -> void:
	if env == null:
		return
	var q := settings(views)
	# Glow measured at the edge of noise (1.3 ms), so this is not a saving worth
	# taking above LOW — and on the night maps the glow IS the muzzle flash.
	if not q["glow"]:
		env.glow_enabled = false
