extends Node

## What a frame actually COSTS TO DRAW, which tests/perf.tscn cannot tell you:
## that one runs headless, where the renderer does nothing at all. Every visual
## change — anti-aliasing, a light per muzzle, a shadow setting — is invisible to
## it and lands entirely here.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/render_cost.tscn
##
## WINDOWED, and it disables vsync itself. Leave vsync on and every configuration
## measures at exactly the refresh rate, which looks like "no cost" for anything
## that fits inside a frame — the first version of this reported 60 fps for all
## four MSAA levels.
##
## It sweeps MSAA because that is the setting with a real dial on it; set
## QS_MSAA to pin one level instead. Read it as a RATIO between rows on one
## machine, not as an absolute: the Pi 5 is the target and its tile-based GPU
## does not have to scale the same way a desktop one does.
##
## Measured on an Intel UHD 620, 4 viewports, 12 combatants, Silva:
##   off 12.03 ms | 2x 13.87 | 4x 14.32 | 8x 16.78   (budget is 16.7)
## 2x ships at MEDIUM (see `Quality`). 4x costs almost nothing over it here.

const MAIN := preload("res://scenes/main.tscn")
const SETTLE_FRAMES := 90     # bots deploy, shadow splits warm up
## After the match goes live: long enough for the bots to walk off their spawns
## and find each other. Measuring the first second of a match measures a crowd
## standing still, which is the thing this harness was accidentally doing.
const LIVE_FRAMES := 420
const SAMPLE_FRAMES := 240
const BUDGET_MS := 1000.0 / 60.0

## The heaviest thing the game can be asked to draw: a full couch on the biggest
## forest map. If this fits, everything else does.
const MAP := "SILVA"


func _ready() -> void:
	# QS_SMOOTH is the one mode that leaves vsync and the frame cap ALONE, because
	# it is not asking what anything costs — it is asking whether the game is
	# smooth, and smoothness is a property of the configuration as shipped. Every
	# other mode here has to defeat both or it measures the refresh rate.
	if not OS.has_environment("QS_SMOOTH"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		# A governor moving the render scale in the middle of a cost measurement
		# corrupts the measurement — and with vsync and the cap both off it would
		# see every frame as a miss and wind the scale down to its floor. Every mode
		# here except QS_SMOOTH is asking what something costs, so: off.
		Quality.governor_enabled = false
	GameState.human_players = 4
	GameState.team_size = 3
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = _map_index(MAP)
	# QS_UNIVERSE picks the setting, because they are not the same scene to draw:
	# an Order carries pauldrons, a power pack, an aquila, gauntlets, greaves
	# and thigh plates that a legionary trooper does not, and every one of those is a
	# draw call twelve bodies and four viewports deep.
	# ...and QS_TEAM / QS_TEAMS pick the ROSTER, because a 4-team match with six
	# AI a side is two dozen bodies rather than twelve, and that is a question
	# only this test can answer: perf.tscn is headless and draws none of them.
	if OS.has_environment("QS_TEAM"):
		GameState.team_size = int(OS.get_environment("QS_TEAM"))
	if OS.has_environment("QS_TEAMS"):
		GameState.team_count = int(OS.get_environment("QS_TEAMS"))
	# QS_MASSIVE prices the 50v50 mode, which is the only configuration in the
	# game where the body count is the whole question.
	# QS_VIEWS: how many split screens. Four is the worst case and the default,
	# but a massive battle is most often played by one or two people.
	if OS.has_environment("QS_VIEWS"):
		GameState.human_players = int(OS.get_environment("QS_VIEWS"))
	if OS.has_environment("QS_MASSIVE"):
		GameState.mode = GameState.Mode.MASSIVE
		GameState.team_count = 2
		GameState.team_size = int(OS.get_environment("QS_MASSIVE"))
		GameState.map_index = GameState.procedural_map_index()
	if OS.has_environment("QS_UNIVERSE"):
		GameState.universe = int(OS.get_environment("QS_UNIVERSE"))
		GameState.class_mode = GameState.ClassMode.FACTION
	# QS_NIGHT prices a night match on the generated world, which is a genuinely
	# different frame and not just a darker one: every shooter's muzzle flash
	# reaches three times as far and every round landing claims one of Impact's
	# pooled lights, so a night firefight is a dozen-odd extra dynamic lights
	# over a scene that has exactly one by day. It forces the generated map,
	# because that is the only map with a night.
	# QS_NIGHT=0 is the control and not a no-op: it forces the generated world by
	# DAY, so night can be priced against the same map rather than against a
	# hand-laid one, which would be measuring the map and calling it the mode.
	# QS_NIGHT=2 is the CEILING: night with every light the mode can produce lit
	# at once. A quiet night match measures as free because nothing is firing,
	# which is the one state a firefight is never in — this is the number that
	# says whether the mode is affordable.
	if OS.has_environment("QS_NIGHT"):
		if int(OS.get_environment("QS_NIGHT")) != 0:
			GameState.time_of_day = GameState.TimeOfDay.NIGHT
		GameState.map_index = GameState.procedural_map_index()

	# QS_VEHICLE prices A VEHICLE'S VIEWPOINT before any vehicle is written, which
	# is the one question that decides whether the feature is affordable at all.
	# It forces the generated world by day, because that is both the worst map in
	# the game to draw and the only one a vehicle would be sensible on.
	if OS.has_environment("QS_ABLATE") or OS.has_environment("QS_SMOOTH") \
			or OS.has_environment("QS_BOTS"):
		# All three price the generated world with a full roster, because it is
		# the worst map to draw AND the one the game opens on. Measuring smoothness
		# on the cheap map is how a game ships feeling fine to whoever tested it.
		# QS_MASSIVE and QS_TEAM both already said what the roster is, so neither is
		# overridden — the first version of this quietly turned a 100-body massive
		# battle back into a 12-body deathmatch and then reported it as smooth.
		GameState.map_index = GameState.procedural_map_index()
		if not OS.has_environment("QS_TEAM") \
				and not OS.has_environment("QS_MASSIVE"):
			GameState.team_size = 6

	if OS.has_environment("QS_VEHICLE"):
		GameState.map_index = GameState.procedural_map_index()
		# A REPRESENTATIVE ROSTER, not a thin one. The default team_size of 3 leaves
		# six bodies on a 4-viewport match, and a vehicle would be driven into a
		# busy one — the bodies are not where the cost is (that is on record) but
		# measuring a viewpoint against half a match invites the comparison to be
		# dismissed. QS_TEAM still overrides.
		if not OS.has_environment("QS_TEAM"):
			GameState.team_size = 6

	var main: Node = MAIN.instantiate()
	add_child(main)
	# AND AGAIN AFTER MAIN EXISTS. Main applies the player's quality settings on the
	# way up, and one of those is the frame cap — which defeats this harness for
	# exactly the reason vsync does, one line further down the same trap: capped,
	# every configuration measures at the cap and reads as costing nothing.
	if not OS.has_environment("QS_SMOOTH"):
		Engine.max_fps = 0
	await _frames(SETTLE_FRAMES)
	# DEPLOY EVERYONE AND START THE MATCH, or this whole file measures a LOBBY.
	# `match_live` is false until every human has pressed deploy and the countdown
	# has run, and Player/Bot/Turret all check it before moving or firing — so
	# without this the bots stand on their spawn markers for the entire run. Every
	# rendering number this harness ever produced was taken that way: no walking,
	# no shooting, no muzzle flashes, no impacts, no corpses, and four buy screens
	# up over the top of it. `perf.gd` has always done this and says why in one
	# line; this test is the one that draws, and it is the one that had it missing.
	for p in main.find_children("*", "Player", true, false):
		if not p.is_alive():
			p._respawn()
	GameState.match_live = true
	# Long enough for the bots to leave their spawns and make contact, so what
	# follows is measured over a firefight and not over the walk to one.
	await _frames(LIVE_FRAMES)
	if int(OS.get_environment("QS_NIGHT")) == 2:
		_light_everything(main)
	var views := main.find_children("*", "SubViewport", true, false)

	if OS.has_environment("QS_VEHICLE"):
		# QS_HULLS=1 skips the viewpoint sweep (~1440 frames) and prices only the
		# hulls. The two answer different questions and the second one is the one
		# you re-run after touching a vehicle model, so it is worth being able to
		# ask it on its own — but it then has to do its own warm-up, which the
		# sweep would otherwise have done for it.
		if OS.has_environment("QS_HULLS"):
			print("  warming up to the throttled steady state...")
			await _frames(WARMUP_FRAMES)
		else:
			await _measure_viewpoints(main, views)
		await _measure_vehicle_hulls(main, views)
		get_tree().quit()
		return
	if OS.has_environment("QS_ABLATE"):
		await _measure_ablations(main, views)
		get_tree().quit()
		return
	if OS.has_environment("QS_SMOOTH"):
		await _measure_smoothness(main, views)
		get_tree().quit()
		return
	if OS.has_environment("QS_BOTS"):
		await _measure_bodies(main, views)
		get_tree().quit()
		return

	var levels := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		Viewport.MSAA_8X]
	if OS.has_environment("QS_MSAA"):
		levels = [int(OS.get_environment("QS_MSAA"))]
	# The MAP CONSTANT is not necessarily what is being drawn — QS_MASSIVE forces
	# the generated world — so the heading reports the roster it actually built.
	print("\n== render cost: %d viewports, %d bodies, %s, %s ==" % [
		GameState.human_players, GameState.combatants.size(),
		GameState.MAPS[GameState.map_index]["name"],
		Loadout.UNIVERSES[GameState.universe]["name"]])
	for msaa in levels:
		for v in views:
			v.msaa_3d = msaa
		await _frames(30)                      # let the resize settle
		var ms := await _measure()
		# DRAW CALLS as well as milliseconds. On a game made of thirty-odd boxes
		# per body drawn once per viewport plus a shadow pass, the call count IS
		# the frame — and unlike the timing it is stable run to run, so it is the
		# number to optimise against.
		print("  draws %d   primitives %d" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		print("  msaa %-9s %6.2f ms/frame   %3.0f fps   %s" % [
			_msaa_name(msaa), ms, 1000.0 / ms,
			"OK" if ms <= BUDGET_MS else "OVER BUDGET"])
	get_tree().quit()


## --- WHERE THE FRAME ACTUALLY GOES -------------------------------------------
##
## A FILL-BOUND FRAME DOES NOT TELL YOU WHICH PIXELS COST THE MONEY, and every
## number in this file up to now says only how much a whole configuration costs.
## "The frame is fill-bound" is a diagnosis, not an address.
##
## So this turns ONE THING OFF AT A TIME on a real match and reports what each is
## worth. Read the SAVING column: anything under about 1.5 ms is inside this
## machine's run-to-run spread and should be treated as zero however plausible the
## thing sounded. The camera follows the same deterministic path for every row, so
## the rows are comparable to each other and not just to the baseline.
##
##   QS_ABLATE=1 godot --path godot --display-driver x11 tests/render_cost.tscn
##
## Restores each change before the next, so the rows do not compound.
func _measure_ablations(main: Node, views: Array) -> void:
	var msaa: int = Quality.settings(GameState.human_players)["msaa"]
	for v in views:
		v.msaa_3d = msaa
	var cams := _take_cameras(views)
	var level: Node = main.level
	var reach: float = minf(GameState.map_extents.x, GameState.map_extents.y) * 0.85
	var foot: Dictionary = VIEWPOINTS[0]

	# The pieces an ablation needs to reach: the environment, the sun, and the
	# terrain skin (found by its material, since nothing names the node).
	var env: Environment = null
	for wn in main.find_children("*", "WorldEnvironment", true, false):
		env = wn.environment
	var sun: DirectionalLight3D = null
	for l in main.find_children("*", "DirectionalLight3D", true, false):
		sun = l
	var terrain: Array[MeshInstance3D] = []
	for mi in main.find_children("*", "MeshInstance3D", true, false):
		if mi.get_active_material(0) is ShaderMaterial:
			terrain.append(mi)
	var plain := StandardMaterial3D.new()
	plain.albedo_color = Color(0.35, 0.30, 0.24)
	plain.roughness = 0.9

	print("\n== where the frame goes: %d viewports, %d bodies, %s, msaa %s ==" % [
		GameState.human_players, GameState.combatants.size(),
		GameState.MAPS[GameState.map_index]["name"], _msaa_name(msaa)])
	print("  %d shader-material meshes found (the terrain skin and the ground)"
		% terrain.size())
	# WARM UP TO THE STEADY STATE FIRST. The first version of this measured a cool
	# GPU at 24 ms and then everything after it at ~40, and duly reported that
	# turning MSAA OFF cost 16 ms — this laptop throttles hard under a sustained
	# 4-viewport load, so the only honest baseline is the throttled one. Which is
	# also the one a player experiences, a minute into a match.
	print("  warming up to the throttled steady state...")
	await _frames(WARMUP_FRAMES)

	# The transparent sweep needs its subjects on the field before the first
	# control is taken, and needs them to have GROWN before they are frozen.
	var was_paused := get_tree().paused
	if OS.get_environment("QS_ABLATE") == "4":
		_spawn_smoke(level)
		await _frames(90)          # let the clouds billow out to full radius
		_spawn_flashes(level)      # ...and only then the short-lived ones
		_freeze_transparency(level)
		print("  held: %d clouds, %d blast spheres, %d tracers" % [
			_fx["smoke"].size(), _fx["blast"].size(), _fx["bolt"].size()])
		# THE MATCH IS PAUSED FOR THIS SWEEP, exactly as the hull comparison is
		# and for exactly the reason recorded there. These deltas are one to three
		# milliseconds; twelve bots walking, firing and dying between the A and B
		# windows move the scene by more than that on their own. The first run of
		# this reported hiding six blast spheres as costing 6.17 ms — a negative
		# saving, which is impossible, and the giveaway that the thing being
		# measured was never the spheres.
		process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true

	for row in _ablations(views, env, sun, terrain, plain, msaa):
		# A / B / A. Each ablation is measured between two controls taken either
		# side of it and compared against their MEAN, which cancels drift whatever
		# is causing it — thermal, or the shader recompile that a render-state
		# change touches off and that lands in the frames just after it. A single
		# baseline taken once at the top cannot survive either, and did not.
		var a1 := await _control(cams, level, foot, reach)
		(row["on"] as Callable).call()
		await _frames(ABLATE_SETTLE)
		var r := await _sweep(cams, level, foot, reach, true, ABLATE_FRAMES)
		(row["off"] as Callable).call()
		var a2 := await _control(cams, level, foot, reach)
		var control := (a1 + a2) * 0.5
		var saved: float = control - r["avg"]
		print("  %-34s %6.2f vs %6.2f  %6.2f ms saved%s" % [
			row["name"], r["avg"], control, saved,
			"" if absf(saved) >= NOISE_MS else "   (noise)"])
		# The two controls printed together, so the reader can see whether the
		# method held for this row rather than taking the saving on trust.
		print("      %-30s controls %.2f / %.2f, drift %.2f ms" % [
			"", a1, a2, a2 - a1])

	get_tree().paused = was_paused
	print("\n  Anything under %.1f ms saved is noise on this machine. The budget is" % NOISE_MS)
	print("  %.2f ms and a miss is presented at 33 ms with vsync on, so what is" % BUDGET_MS)
	print("  wanted is not 16.6 but real headroom under it.")


## --- the transparent half -----------------------------------------------------

const SMOKE_SCENE := preload("res://scenes/fx/smoke_cloud.tscn")
const BOLT_SCENE := preload("res://scenes/fx/blaster_bolt.tscn")
## A HEAVY BUT REACHABLE fight: a Saurian's smoke on the position, a couple of
## grenades and a rocket going off, and four people firing. Deliberately not a
## pathological number — the question is what a bad moment in a real match costs,
## not what a thousand spheres cost.
const SMOKE_COUNT := 3
const BLAST_COUNT := 6
const BOLT_COUNT := 24

var _fx := {"smoke": [], "blast": [], "bolt": []}


## Put the effects on the field and STOP them ageing. Every one of these is
## transient by design — smoke lives 9 s, a blast 0.18 s — so measuring them as
## they happen would time a different scene on every row. `PROCESS_MODE_DISABLED`
## freezes them mid-life, which is the same trick `QS_NIGHT=2` uses to hold every
## light on at once: price the worst instant, not the average of a fight.
func _spawn_smoke(level: Node) -> void:
	var centre: Vector3 = GameState.map_center
	var ground := func(x: float, z: float) -> float:
		return level.height_at(x, z) if level.has_method("height_at") else 0.0
	for i in SMOKE_COUNT:
		var a := TAU * float(i) / float(SMOKE_COUNT)
		var x: float = centre.x + cos(a) * 9.0
		var z: float = centre.z + sin(a) * 9.0
		var cloud: Node3D = SMOKE_SCENE.instantiate()
		level.add_child(cloud)
		cloud.global_position = Vector3(x, ground.call(x, z) + 1.4, z)
		# Let it build and billow to full size for a frame, THEN freeze — a cloud
		# frozen at birth is a dot and would price nothing.
		_fx["smoke"].append(cloud)


## The short-lived half, spawned LAST and frozen immediately. A tracer's whole
## flight is a fraction of a second and a blast lasts 0.18 s, so anything spawned
## before the clouds had finished billowing was already gone.
func _spawn_flashes(level: Node) -> void:
	var centre: Vector3 = GameState.map_center
	var ground := func(x: float, z: float) -> float:
		return level.height_at(x, z) if level.has_method("height_at") else 0.0
	# THE BLAST SPHERES ARE BUILT HERE RATHER THAN THROUGH `Blast.pop`, and not
	# for convenience: a real blast frees itself after `Blast.LIFE` (0.18 s), so
	# by the time the clouds had finished billowing there were none left to
	# measure — the first run of this reported "0 blast spheres hidden". Same
	# mesh, same additive material, same size; this one just does not expire.
	for i in BLAST_COUNT:
		var a := TAU * float(i) / float(BLAST_COUNT)
		var x: float = centre.x + cos(a) * 14.0
		var z: float = centre.z + sin(a) * 14.0
		var flash := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 5.0 * 0.6      # a frag's splash x Blast's own ball fraction
		ball.height = ball.radius * 2.0
		flash.mesh = ball
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1.0, 0.62, 0.25, 0.75)
		flash.material_override = mat
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(flash)
		flash.global_position = Vector3(x, ground.call(x, z) + 1.2, z)
		_fx["blast"].append(flash)
	for i in BOLT_COUNT:
		var a := TAU * float(i) / float(BOLT_COUNT)
		var from := centre + Vector3(cos(a) * 4.0, 1.5, sin(a) * 4.0)
		var to := centre + Vector3(cos(a) * 34.0, 2.2, sin(a) * 34.0)
		var bolt: Node3D = BOLT_SCENE.instantiate()
		level.add_child(bolt)
		bolt.launch(from, to, Color(1.0, 0.35, 0.15))
		_fx["bolt"].append(bolt)


## Stop everything ageing, and DROP anything that already died on the way here —
## a tracer's flight is short and some will not have survived the billow wait.
## Holding a freed handle is what produced "Trying to assign invalid previously
## freed instance" once per row per node.
func _freeze_transparency(_level: Node) -> void:
	for group in _fx:
		var live: Array = []
		for n: Node in _fx[group]:
			if is_instance_valid(n):
				n.process_mode = Node.PROCESS_MODE_DISABLED
				live.append(n)
		_fx[group] = live


func _show_fx(group: String, on: bool) -> void:
	for n: Node in _fx[group]:
		if is_instance_valid(n) and n is Node3D:
			(n as Node3D).visible = on


func _transparency_rows() -> Array:
	return [
		{"name": "%d smoke clouds hidden" % _fx["smoke"].size(),
			"on": func() -> void: _show_fx("smoke", false),
			"off": func() -> void: _show_fx("smoke", true)},
		{"name": "%d blast spheres hidden" % _fx["blast"].size(),
			"on": func() -> void: _show_fx("blast", false),
			"off": func() -> void: _show_fx("blast", true)},
		{"name": "%d bolt tracers hidden" % _fx["bolt"].size(),
			"on": func() -> void: _show_fx("bolt", false),
			"off": func() -> void: _show_fx("bolt", true)},
		{"name": "ALL transparency hidden", "on": func() -> void:
			for g in _fx:
				_show_fx(g, false),
			"off": func() -> void:
			for g in _fx:
				_show_fx(g, true)},
	]


func _control(cams: Array[Camera3D], level: Node, vp: Dictionary,
		reach: float) -> float:
	await _frames(ABLATE_SETTLE)
	var r := await _sweep(cams, level, vp, reach, true, ABLATE_FRAMES)
	return r["avg"]


## QS_ABLATE=1 is the broad hunt: is it geometry, the shaders, the shadows or the
## pixels? QS_ABLATE=2 follows up on whatever 1 pointed at, and each row here is
## in the file because a round of 1 sent it there.
func _ablations(views: Array, env: Environment, sun: DirectionalLight3D,
		terrain: Array[MeshInstance3D], plain: StandardMaterial3D,
		msaa: int) -> Array:
	var dist: float = sun.directional_shadow_max_distance if sun else 80.0
	if OS.get_environment("QS_ABLATE") == "4":
		# THE TRANSPARENT HALF OF THE FRAME, which nothing here had ever measured.
		#
		# Every other row in this file prices an OPAQUE surface, and opaque
		# surfaces are the ones a depth buffer protects you from: draw a wall in
		# front of a hill and the hill's pixels are never shaded. Transparency
		# gets none of that. It is shaded in full, in draw order, and it stacks —
		# so on a frame that is already fill-bound it is the highest cost per
		# pixel in the game, and the one category with no measurement behind it.
		#
		# The three suspects, in the order they are likely to matter:
		#   SMOKE  a 5.2 m alpha sphere you can stand inside. Near it, one cloud
		#          is a full-screen quad's worth of blending, four viewports deep.
		#   BLASTS an additive sphere per explosion, and a busy fight has several.
		#   BOLTS  unshaded tracers, 13 a second per shooter, up to twelve of them.
		#
		# MEASURED, and the answer is NO — all three are at or under the noise
		# floor (3 clouds 1.17 ms, 6 blasts -0.25, 24 tracers 1.59, against a
		# 1.5 ms floor). The prime suspect was innocent, exactly as the terrain and
		# sky shaders were. Keep the sweep: the reason it is cheap is that these
		# maps are lit by one directional light and the transparent surfaces are
		# unshaded, and any of that changing puts the cost straight back.
		#
		# WHAT IT DOES NOT PRICE: standing INSIDE a cloud. The clouds sit 9 m off
		# the map centre and the camera sweeps past them, so this is a cloud at
		# fighting distance, not one filling the whole viewport. That case is the
		# genuine worst case and is still unmeasured.
		return _transparency_rows()
	if OS.get_environment("QS_ABLATE") == "3":
		# WHAT SHIPPING THE QUALITY TIERS ACTUALLY BOUGHT, measured against the
		# settings the game had before them rather than against a hypothetical. The
		# baseline here is the DEFAULT tier, so the first row should come back
		# NEGATIVE — restoring the old settings costs, it does not save.
		return [
			{"name": "the OLD settings, restored", "on": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(4096, true)
				RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
				if sun: sun.directional_shadow_blend_splits = true,
				"off": func() -> void:
				Quality.apply_global()
				Quality.apply_to_light(sun)},
			{"name": "tier LOW instead of the default", "on": func() -> void:
				_force_tier(views, sun, Quality.Tier.LOW), "off": func() -> void:
				_force_tier(views, sun, -1)},
			{"name": "tier HIGH instead of the default", "on": func() -> void:
				_force_tier(views, sun, Quality.Tier.HIGH), "off": func() -> void:
				_force_tier(views, sun, -1)},
		]
	if OS.get_environment("QS_ABLATE") == "2":
		return [
			# Round 1 said the shadow map is the single biggest item in the frame,
			# so this asks how far down it can go and what else in the shadow path
			# is worth the same look. 4096 over a 960x540 quadrant is ~7 shadow
			# texels per screen pixel, which is paying for detail no quadrant of
			# this size can resolve.
			{"name": "shadow map 2048", "on": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(2048, true),
				"off": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(4096, true)},
			{"name": "shadow map 1024", "on": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(1024, true),
				"off": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(4096, true)},
			# Blend splits samples BOTH maps across the band where they meet.
			{"name": "split blending off", "on": func() -> void:
				if sun: sun.directional_shadow_blend_splits = false,
				"off": func() -> void:
				if sun: sun.directional_shadow_blend_splits = true},
			{"name": "1 split instead of 2", "on": func() -> void:
				if sun: sun.directional_shadow_mode = \
					DirectionalLight3D.SHADOW_ORTHOGONAL, "off": func() -> void:
				if sun: sun.directional_shadow_mode = \
					DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS},
			{"name": "shadow distance %d -> 45" % int(dist), "on": func() -> void:
				if sun: sun.directional_shadow_max_distance = 45.0,
				"off": func() -> void:
				if sun: sun.directional_shadow_max_distance = dist},
			{"name": "3D render scale 0.80", "on": func() -> void:
				for v in views:
					v.scaling_3d_scale = 0.80, "off": func() -> void:
				for v in views:
					v.scaling_3d_scale = 1.0},
			# THE ONE THAT MATTERS: everything round 1 and 2 found, together. The
			# individual savings do not add up, because each is a share of the same
			# fill, so the combination has to be measured as a combination.
			{"name": "ALL: shadow 2048 + no blend + filter low", "on": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(2048, true)
				RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_LOW)
				if sun:
					sun.directional_shadow_blend_splits = false
					sun.directional_shadow_max_distance = 60.0,
				"off": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(4096, true)
				RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
				if sun:
					sun.directional_shadow_blend_splits = true
					sun.directional_shadow_max_distance = dist},
			{"name": "ALL + msaa off + scale 0.80", "on": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(2048, true)
				RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_LOW)
				if sun:
					sun.directional_shadow_blend_splits = false
					sun.directional_shadow_max_distance = 60.0
				for v in views:
					v.msaa_3d = Viewport.MSAA_DISABLED
					v.scaling_3d_scale = 0.80, "off": func() -> void:
				RenderingServer.directional_shadow_atlas_set_size(4096, true)
				RenderingServer.directional_soft_shadow_filter_set_quality(
					RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
				if sun:
					sun.directional_shadow_blend_splits = true
					sun.directional_shadow_max_distance = dist
				for v in views:
					v.msaa_3d = msaa
					v.scaling_3d_scale = 1.0},
		]
	return [
		# The prime suspect, and the reason this sweep was written: three separate
		# four-octave FBMs per fragment, each octave four sin-based hashes, over the
		# geometry that fills most of the screen four viewports deep. It was WRONG —
		# 0.07 ms — which is the whole argument for owning a harness like this.
		{"name": "terrain/ground shader -> plain", "on": func() -> void:
			for mi in terrain:
				mi.material_override = plain,
			"off": func() -> void:
			for mi in terrain:
				mi.material_override = null},
		{"name": "sky shader -> flat colour", "on": func() -> void:
			if env: env.background_mode = Environment.BG_COLOR,
			"off": func() -> void:
			if env: env.background_mode = Environment.BG_SKY},
		{"name": "sun shadows off entirely", "on": func() -> void:
			if sun: sun.shadow_enabled = false,
			"off": func() -> void:
			if sun: sun.shadow_enabled = true},
		# Soft shadow filtering is a multi-tap PCF per shadowed pixel, and
		# project.godot ships it at 4 (Soft High) for the directional light. On
		# flat-shaded boxes that is a lot of taps to hide an edge nobody studies.
		{"name": "soft shadow filter -> hard", "on": func() -> void:
			RenderingServer.directional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_HARD)
			RenderingServer.positional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_HARD), "off": func() -> void:
			RenderingServer.directional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
			RenderingServer.positional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)},
		{"name": "shadow map 4096 -> 2048", "on": func() -> void:
			RenderingServer.directional_shadow_atlas_set_size(2048, true),
			"off": func() -> void:
			RenderingServer.directional_shadow_atlas_set_size(4096, true)},
		{"name": "glow off", "on": func() -> void:
			if env: env.glow_enabled = false,
			"off": func() -> void:
			if env: env.glow_enabled = true},
		{"name": "msaa off", "on": func() -> void:
			for v in views:
				v.msaa_3d = Viewport.MSAA_DISABLED,
			"off": func() -> void:
			for v in views:
				v.msaa_3d = msaa},
		# THE BLUNT INSTRUMENT, and the one that always works on a fill-bound
		# frame: render 3D at a fraction of the viewport and upscale. Listed last
		# because it is what you reach for when nothing above was the answer.
		{"name": "3D render scale 0.60", "on": func() -> void:
			for v in views:
				v.scaling_3d_scale = 0.60, "off": func() -> void:
			for v in views:
				v.scaling_3d_scale = 1.0},
	]


## --- IS IT SMOOTH ------------------------------------------------------------
##
## EVERY OTHER MEASUREMENT IN THIS FILE IS AN AVERAGE, AND SMOOTHNESS IS A
## PROPERTY OF THE WORST FRAMES. A scene averaging 15 ms with one frame in twenty
## at 40 ms reads as juddery; the same scene pinned at a flat 33 reads as smooth,
## and its average is worse. So this leaves vsync and the frame cap exactly as the
## game ships them and reports the DISTRIBUTION plus how much of it missed.
##
## The pass mark is not an average. It is that essentially nothing lands past the
## cap's own interval, because with vsync a frame that misses is not slightly late
## — it is held to the next refresh, and the player sees a hitch.
##
##   QS_SMOOTH=1 [QS_VIEWS=n] godot --path godot --display-driver x11 tests/render_cost.tscn
func _measure_smoothness(main: Node, views: Array) -> void:
	var cams := _take_cameras(views)
	var level: Node = main.level
	var reach: float = minf(GameState.map_extents.x, GameState.map_extents.y) * 0.85
	# QS_TIER / QS_CAP try a configuration WITHOUT storing it. Deliberately not via
	# `Controls.set_*`: every mutating Controls call saves to user://controls.cfg,
	# and a test that rewrites the machine's real settings is a test that has to be
	# apologised for once.
	var of := -1
	if OS.has_environment("QS_TIER"):
		of = int(OS.get_environment("QS_TIER"))
		var sun: DirectionalLight3D = null
		for l in main.find_children("*", "DirectionalLight3D", true, false):
			sun = l
		_force_tier(views, sun, of)
	var q := Quality.settings(-1, of)
	var cap := Controls.fps_cap()
	if OS.has_environment("QS_CAP"):
		cap = int(OS.get_environment("QS_CAP"))
		Engine.max_fps = cap
	# The interval a frame has to arrive inside. With a cap that is the cap; with
	# no cap it is the refresh, which we cannot ask for portably, so assume 60.
	var interval := 1000.0 / float(cap if cap > 0 else 60)

	print("\n== is it smooth: %d viewports, %d bodies, %s ==" % [
		GameState.human_players, GameState.combatants.size(),
		GameState.MAPS[GameState.map_index]["name"]])
	print("  quality %s   shadow map %d   msaa %s   render scale %.2f" % [
		q["name"], int(q["shadow"]), _msaa_name(int(q["msaa"])), float(q["scale"])])
	print("  frame cap %s   vsync %d   target interval %.2f ms" % [
		"DISPLAY" if cap == 0 else str(cap),
		DisplayServer.window_get_vsync_mode(), interval])
	# Long enough to cross the map and to get hot. A smoothness result from a cold
	# GPU is the one number this machine will always pass and never deserve.
	# Warm up AND let the governor settle. Both matter and they are the same wait:
	# the chip needs time to reach the speed it will actually run at, and the
	# governor needs time to find the configuration that holds at that speed.
	# Measuring either before it has settled measures a transient.
	print("  warming up and letting the governor settle...")
	await _frames(WARMUP_FRAMES)
	var settled: FrameGovernor = main.governor
	if settled != null:
		# WAIT FOR IT TO ACTUALLY CONVERGE, rather than for a fixed number of
		# frames. Measuring while the governor is still walking down charges it for
		# the frames it is in the middle of fixing, which is the transient and not
		# the state the player spends a match in. Give up after a while: on the
		# hardest case it may genuinely never stop hunting by a step, and that is a
		# result worth printing rather than waiting forever for.
		# Both the scale AND the frame rate have to have stopped moving. Watching
		# only the scale exited early on the 100-body case: it had been sitting at
		# the floor for three windows and was about to drop a rung, so the interval
		# every frame was then judged against was one the governor had already
		# abandoned, and a perfectly smooth 30 fps was reported as 74% late.
		var last := -1.0
		var last_fps := -1
		var stable := 0
		for _i in 40:
			await _frames(45)
			if is_equal_approx(settled.scale(), last) \
					and settled.target_fps() == last_fps:
				stable += 1
				if stable >= 3:
					break
			else:
				stable = 0
			last = settled.scale()
			last_fps = settled.target_fps()
		interval = 1000.0 / float(settled.target_fps())
		print("  governor settled on %d fps at render scale %.2f (%d drops, %d raises)" % [
			settled.target_fps(), settled.scale(), settled.drops, settled.raises])
	var r := await _sweep(cams, level, foot_view(), reach, true, SWEEP_FRAMES)

	# WITH VSYNC THERE IS NO SUCH THING AS SLIGHTLY LATE. A frame that misses the
	# refresh is held to the next one, so anything meaningfully past a single
	# interval has already cost a whole one — hence 1.25 rather than a generous
	# 1.5. Past two intervals is a hitch a player can point at.
	var over := 0
	var bad := 0
	for s in r["samples"]:
		if s > interval * 1.25:
			over += 1
		if s > interval * 2.0:
			bad += 1
	var n: int = r["samples"].size()
	print("  p50 %6.2f   p95 %6.2f   p99 %6.2f   worst %6.2f ms" % [
		r["p50"], r["p95"], r["p99"], r["worst"]])
	print("  effective %.1f fps" % (1000.0 / maxf(r["p50"], 0.01)))
	print("  frames past one interval:  %d of %d (%.1f%%)" % [
		over, n, 100.0 * over / float(n)])
	print("  frames past two:           %d of %d (%.1f%%)   <- a visible hitch" % [
		bad, n, 100.0 * bad / float(n)])
	# WHAT THE GOVERNOR DID, which is most of the story on a machine whose speed
	# depends on its temperature: the interesting result is not the scale it ended
	# on but that it moved at all, and in which direction.
	var gov: FrameGovernor = main.governor
	if gov != null:
		print("  governor: render scale now %.2f after %d drops and %d raises" % [
			gov.scale(), gov.drops, gov.raises])
	else:
		print("  governor: not running (an explicit tier is chosen, not AUTO)")
	if over * 20 <= n:
		print("\n  SMOOTH: the frame is holding its interval.")
	else:
		print("\n  NOT SMOOTH: too much of the distribution is missing the interval.")
		print("  Drop a quality tier, or cap lower — an even 30 beats a floating 45.")


## --- ARE THE BOTS THE PROBLEM ------------------------------------------------
##
## "IT GETS LAGGY WHEN THERE ARE BOTS" IS A CLAIM ABOUT THREE DIFFERENT COSTS AND
## THEY HAVE TO BE SEPARATED, because the fix for each is unrelated to the other
## two. A body costs (1) THINKING — a bot's own physics tick, its senses, its aim
## and its routing; (2) DRAWING — thirty-odd meshes once per viewport plus a
## shadow pass; and (3) EVENTS — the frames on which one DIES, which build a
## ragdoll and a whole character model, or RESPAWNS, which rebuilds its style.
##
## The averages already on record say (1) and (2) are small, and that is exactly
## why the complaint deserves this test rather than a restatement of them: an
## average is the one statistic that cannot see (3). A death is ~9 ms landing on a
## single frame, so at 60 fps it does not make the average worse in any way you
## would notice — it turns one frame into a dropped one. Bots die constantly and
## players do not, so "laggy with bots" is precisely the signature of an event
## cost, and no amount of steady-state measurement will ever find it.
##
## Sweeping the ROSTER by restarting the process cannot answer this either: I
## tried, and each successive run started hotter and settled the governor lower,
## which made twelve bodies measure SMOOTHER than two. So thinking and drawing are
## ablated in one process against controls either side (the A/B/A already used for
## the render dials), and the event cost is measured by ATTRIBUTION — every frame
## in one window is labelled with whether a body changed state on it, and the two
## populations are compared. That comparison is immune to drift by construction:
## both halves come from the same window, interleaved.
##
##   QS_BOTS=1 [QS_VIEWS=n] [QS_TEAM=n] godot --path godot --display-driver x11 tests/render_cost.tscn
func _measure_bodies(main: Node, views: Array) -> void:
	var cams := _take_cameras(views)
	var level: Node = main.level
	var reach: float = minf(GameState.map_extents.x, GameState.map_extents.y) * 0.85
	var foot := foot_view()
	var bots: Array[Node] = []
	for b in level.find_children("*", "Bot", true, false):
		bots.append(b)

	print("\n== are the bots the problem: %d viewports, %d bodies (%d bots), %s ==" % [
		GameState.human_players, GameState.combatants.size(), bots.size(),
		GameState.MAPS[GameState.map_index]["name"]])
	print("  warming up to the throttled steady state...")
	await _frames(WARMUP_FRAMES)

	print("\n  -- what a body costs every frame (A/B/A against controls) --")
	for row in [
		# THINKING. Everything a bot decides: senses, target choice, aim, the
		# recoil it eats, the route it follows, the trigger. Switching off physics
		# processing stops all of it and leaves the body standing there to be
		# drawn, which is what isolates this from the row below.
		{"name": "bot thinking off (CPU)", "on": func() -> void:
			for b in bots:
				if is_instance_valid(b): b.set_physics_process(false),
			"off": func() -> void:
			for b in bots:
				if is_instance_valid(b): b.set_physics_process(true)},
		# DRAWING. The model only — the bot keeps thinking, shooting and being
		# shot, so this is the render cost of the bodies and nothing else.
		{"name": "bot bodies hidden (GPU)", "on": func() -> void:
			for b in bots:
				if is_instance_valid(b) and b.model: b.model.visible = false,
			"off": func() -> void:
			for b in bots:
				if is_instance_valid(b) and b.model: b.model.visible = true},
		# BOTH, because the two shares come out of the same frame and there is no
		# reason to expect them to add up.
		{"name": "both: no thinking, no bodies", "on": func() -> void:
			for b in bots:
				if is_instance_valid(b):
					b.set_physics_process(false)
					if b.model: b.model.visible = false,
			"off": func() -> void:
			for b in bots:
				if is_instance_valid(b):
					b.set_physics_process(true)
					if b.model: b.model.visible = true},
	]:
		var a1 := await _control(cams, level, foot, reach)
		(row["on"] as Callable).call()
		await _frames(ABLATE_SETTLE)
		var r := await _sweep(cams, level, foot, reach, true, ABLATE_FRAMES)
		(row["off"] as Callable).call()
		var a2 := await _control(cams, level, foot, reach)
		var control := (a1 + a2) * 0.5
		var saved: float = control - r["avg"]
		var per := saved / float(maxi(bots.size(), 1))
		print("  %-30s %6.2f vs %6.2f  %6.2f ms saved%s" % [
			row["name"], r["avg"], control, saved,
			"" if absf(saved) >= NOISE_MS else "   (noise)"])
		print("      %-26s controls %.2f / %.2f, drift %.2f   %.3f ms per bot" % [
			"", a1, a2, a2 - a1, per])

	await _measure_death_spikes(cams, level, foot, reach)


## THE FRAMES A BODY DIES ON, against the frames it does not. Both come out of one
## window, interleaved, so nothing about the machine's temperature or clock can
## favour one population over the other — which is what makes this the one number
## in this file that needs no control run at all.
func _measure_death_spikes(cams: Array[Camera3D], level: Node, vp: Dictionary,
		reach: float) -> void:
	print("\n  -- what a DEATH costs, by attribution --")
	# Long enough for a real number of deaths to land. At 12 bodies a match
	# produces roughly one every second or two, so this is tens of events.
	var frames := SPIKE_FRAMES
	var was_alive := {}
	var quiet := PackedFloat32Array()
	var eventful := PackedFloat32Array()
	var deaths := 0
	var respawns := 0
	var up: float = vp["up"]
	var span: float = reach * 2.0
	for f in frames:
		var t := float(f) / 60.0
		for i in cams.size():
			var head: float = TAU * float(i) / float(maxi(cams.size(), 1))
			var dir := Vector3(sin(head), 0.0, cos(head))
			var along: float = fposmod(float(vp["speed"]) * t, span) - reach
			var at: Vector3 = GameState.map_center + dir * along
			at.y = _ground(level, at) + up
			cams[i].global_position = at
			cams[i].rotation = Vector3(deg_to_rad(vp["pitch"]), head + PI, 0.0)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		# LABEL THE FRAME, then bucket it. A transition either way is an event: a
		# death builds a ragdoll and a respawn rebuilds a style, and both land on
		# one frame.
		var events := 0
		for b in GameState.combatants:
			if not is_instance_valid(b):
				continue
			var alive: bool = b.is_alive()
			if was_alive.has(b) and was_alive[b] != alive:
				events += 1
				if alive:
					respawns += 1
				else:
					deaths += 1
			was_alive[b] = alive
		if f < 30:
			continue                      # settle, and seed `was_alive`
		if events > 0:
			eventful.append(ms)
		else:
			quiet.append(ms)

	var q := _stats(quiet)
	var e := _stats(eventful)
	print("  %d deaths and %d respawns in %.1f s" % [
		deaths, respawns, float(frames) / 60.0])
	print("  %-18s %5s %8s %8s %8s" % ["population", "n", "p50", "p95", "worst"])
	print("  %-18s %5d %8.2f %8.2f %8.2f" % [
		"quiet frames", quiet.size(), q["p50"], q["p95"], q["worst"]])
	print("  %-18s %5d %8.2f %8.2f %8.2f" % [
		"a body changed", eventful.size(), e["p50"], e["p95"], e["worst"]])
	if eventful.size() > 0 and quiet.size() > 0:
		print("  an event frame costs %.2f ms more at the median, %.2f at p95" % [
			e["p50"] - q["p50"], e["p95"] - q["p95"]])
		print("  events land on %.1f%% of frames" % [
			100.0 * eventful.size() / float(quiet.size() + eventful.size())])
	print("\n  READ THE p95 OF THE EVENT ROW AGAINST THE BUDGET, not the medians.")
	print("  A cost that lands on one frame in fifty cannot move an average and is")
	print("  the only thing in this file a player would call a stutter.")


## Long enough to collect tens of deaths at an ordinary roster.
const SPIKE_FRAMES := 900


func _stats(s: PackedFloat32Array) -> Dictionary:
	if s.is_empty():
		return {"p50": 0.0, "p95": 0.0, "worst": 0.0}
	var sorted := Array(s)
	sorted.sort()
	var n := sorted.size()
	return {
		"p50": sorted[int(n * 0.50)],
		"p95": sorted[mini(int(n * 0.95), n - 1)],
		"worst": sorted[n - 1],
	}


func foot_view() -> Dictionary:
	return VIEWPOINTS[0]


## Put the whole renderer on one tier, or back on the player's own choice (-1).
## Reaches every place a tier lands — the global shadow state, each viewport, the
## sun — because a tier measured half-applied is not that tier.
func _force_tier(views: Array, sun: DirectionalLight3D, of: int) -> void:
	var n := GameState.human_players
	var q := Quality.settings(n, of) if of >= 0 else Quality.settings(n)
	RenderingServer.directional_shadow_atlas_set_size(int(q["shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(q["filter"])
	if sun:
		sun.directional_shadow_blend_splits = q["blend_splits"]
	for v in views:
		v.msaa_3d = q["msaa"]
		v.scaling_3d_scale = float(q["scale"])


## Replace each viewport's camera with one we drive, copying the player camera's
## CULL MASK — a default mask would draw four bodies and four first-person weapons
## that no real viewport ever sees, and inflate every number here.
func _take_cameras(views: Array) -> Array[Camera3D]:
	var cams: Array[Camera3D] = []
	for v in views:
		var theirs: Camera3D = null
		for c in v.find_children("*", "Camera3D", true, false):
			theirs = c
			break
		var mine := Camera3D.new()
		if theirs != null:
			mine.cull_mask = theirs.cull_mask
			mine.fov = theirs.fov
			mine.near = theirs.near
			mine.far = theirs.far
		mine.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		v.add_child(mine)
		mine.current = true
		cams.append(mine)
	return cams


## --- WHAT A VEHICLE'S VIEWPOINT COSTS ----------------------------------------
##
## THE THING THIS IS NOT MEASURING IS SPEED. A camera moving at 35 m/s and one
## crawling at 5 m/s cost exactly the same to draw from the same pose — the
## renderer is handed a frustum, not a velocity. Measure "fast camera against slow
## camera" and it reports that vehicles are free, which is the wrong answer to a
## question that was never asked.
##
## What a vehicle actually changes is WHERE THE CAMERA IS AND THEREFORE WHAT IS IN
## FRONT OF IT. An infantryman is at eye height with cover between him and most of
## the map; a speeder is above the scrub crossing open ground down the long sight
## lines, and anything that flies looks across the whole level at once. That is
## more geometry in frustum, and — the part that matters here — it is geometry
## PAST the distances the per-part visibility ranges were tuned at, which is what
## bought the frame back under budget in the first place.
##
## So each viewpoint is measured BOTH parked and moving. Parked isolates what the
## pose costs; the difference between the two is whatever the motion itself adds
## (objects entering frustum, the shadow splits re-fitting), which is the only part
## where velocity can honestly show up.
##
## Height is above the GROUND, not absolute: the generated world has real relief
## and an absolute altitude would fly into a hill on one seed and hold 40 m over a
## basin on the next.
const VIEWPOINTS: Array[Dictionary] = [
	{"name": "INFANTRY", "up": 1.6, "speed": 6.0, "pitch": -2.0},
	{"name": "SPEEDER", "up": 2.8, "speed": 35.0, "pitch": -4.0},
	# What anything airborne sees, and the ceiling for this whole question: a
	# gunship at 20 m looking down and out has more of the map in frustum than
	# any other camera the game can produce.
	{"name": "GUNSHIP", "up": 20.0, "speed": 45.0, "pitch": -18.0},
]

## Long enough to cross a generated world at speeder pace and average over what
## is actually out there, rather than over one lucky stretch of empty ground.
const SWEEP_FRAMES := 240
## The ablation sweep runs three windows per row, so its windows are shorter — the
## A/B/A pairing buys back more accuracy than a longer window would.
const ABLATE_FRAMES := 110
## After any render-state change: long enough for a shader recompile to land, so
## its cost is not charged to the measurement that follows it.
const ABLATE_SETTLE := 55
## Get to the throttled steady state before measuring anything at all.
const WARMUP_FRAMES := 420
## Below this, a difference is not distinguishable from run-to-run spread here.
const NOISE_MS := 1.5


## --- WHAT THE SPEEDERS THEMSELVES COST ---------------------------------------
##
## The viewpoint sweep above answers "does a vehicle CAMERA blow the budget", and
## it was written before any vehicle existed. This answers the other half, which
## only became askable once they did: what do the four hulls cost to have on the
## map at all.
##
## They are cheap by construction and this is here to keep them that way. Four
## speeders is four chamfered-box models — a couple of dozen meshes each against a
## character's thirty-odd, and there are twelve characters. The number to watch is
## not the milliseconds (which sit inside this machine's +/-1.5 ms spread and
## always will) but the DRAWS, which are stable run to run and are what a later
## "just one more greeble per vehicle" actually spends.
##
## Measured A/B/A like every other GPU row in this file, and for the same reason:
## a straight before/after on a throttling laptop reports whichever ran later as
## more expensive.
func _measure_vehicle_hulls(main: Node, views: Array) -> void:
	# COLLECTED FRESH AND RE-CHECKED ON THE WAY OUT. A speeder is a combatant, so
	# the firefight this harness deliberately runs before measuring will have shot
	# some of them: a list gathered at the top and used after two 110-frame sweeps
	# is a list of freed instances. Exactly the trap already on record for the
	# massive-battle roster, one feature further out — and the first version of
	# this function died on it, which is also the cleanest proof that bots really
	# do treat a vehicle as a target.
	var hulls: Array[Node3D] = []
	for h in main.find_children("*", "Vehicle", true, false):
		if is_instance_valid(h) and h.is_alive():
			hulls.append(h)
	print("\n== what the hulls cost: %d live vehicle(s) on the map ==" % hulls.size())
	if hulls.is_empty():
		# Not a failure. Only THE COMPACT WARS fields vehicles, and royale and massive
		# field none in any universe — an empty run here is those rules holding.
		print("  none placed (universe %d, mode %d) — nothing to price."
			% [Loadout.active_universe, GameState.mode])
		return
	for h in hulls:
		print("  %-22s team %d" % [h.label(), h.team])

	var cams := _take_cameras(views)
	var level: Node = main.level
	var reach: float = minf(GameState.map_extents.x, GameState.map_extents.y) * 0.85
	var foot: Dictionary = VIEWPOINTS[0]
	# NO WARM-UP HERE. This section always runs directly after the viewpoint sweeps,
	# which are ~1440 frames of exactly this scene — the GPU is already at its
	# throttled steady state, and a second 420-frame warm-up is seven seconds of
	# nothing that pushed the whole run past its timeout.

	# WORST CASE, ON PURPOSE: all four gathered onto the camera's own path, so
	# every one of them is in frustum for the whole window. Parked at four
	# different spawns they are mostly behind somebody, which measures as free and
	# tells you nothing about what they cost when they matter — which is when a
	# player can see them.
	# THE WHOLE MATCH IS FROZEN FOR THIS, not just the speeders. The first version
	# only stopped the vehicles ticking and measured across a live firefight — and
	# duly reported that HIDING two vehicles INCREASED the triangle count, which is
	# the giveaway: twelve bots walking, shooting and dying between the A and B
	# windows move the scene far more than four hulls do, so the difference being
	# measured was never the vehicles. Pausing makes the two windows the same scene
	# with one thing changed, which is the only way a delta this small is readable
	# at all. This node processes ALWAYS so the camera sweep still runs.
	var was_paused := get_tree().paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true

	var a1 := await _control(cams, level, foot, reach)
	var gy := _ground(level, GameState.map_center) + 2.0
	for i in hulls.size():
		_place(hulls, i, Vector3(GameState.map_center.x + (i - 1.5) * 6.0, gy,
			GameState.map_center.z))
	await _frames(ABLATE_SETTLE)
	var lit := await _sweep(cams, level, foot, reach, true, ABLATE_FRAMES)
	_show(hulls, false)
	await _frames(ABLATE_SETTLE)
	var dark := await _sweep(cams, level, foot, reach, true, ABLATE_FRAMES)
	_show(hulls, true)
	var a2 := await _control(cams, level, foot, reach)
	get_tree().paused = was_paused

	var per := maxf(float(_live(hulls).size()), 1.0)
	print("\n  %-22s %7s %8s %9s" % ["state", "ms", "draws", "tris"])
	print("  %-22s %7.2f %8.0f %9.0f" % ["all %d in frustum" % hulls.size(),
		lit["avg"], lit["draws"], lit["tris"]])
	print("  %-22s %7.2f %8.0f %9.0f" % ["hidden", dark["avg"], dark["draws"], dark["tris"]])
	print("  %-22s %7.2f %8.1f %9.1f" % ["cost of all %d" % hulls.size(),
		lit["avg"] - dark["avg"], lit["draws"] - dark["draws"],
		lit["tris"] - dark["tris"]])
	print("  %-22s %7.2f %8.1f %9.1f" % ["cost of ONE",
		(lit["avg"] - dark["avg"]) / per, (lit["draws"] - dark["draws"]) / per,
		(lit["tris"] - dark["tris"]) / per])
	print("      controls %.2f / %.2f, drift %.2f ms" % [a1, a2, a2 - a1])
	print("\n  READ THE DRAWS COLUMN AND IGNORE TRIS. Draws is a clean per-object")
	print("  count and comes back stable; the triangle total is dominated by the")
	print("  terrain's own LOD shifting under a moving camera, which is far larger")
	print("  than four hulls and is why that column can come back NEGATIVE. It is")
	print("  measuring the map, not the speeders.")
	if absf(lit["avg"] - dark["avg"]) < NOISE_MS:
		print("  The millisecond figure is INSIDE this machine's %.1f ms spread, so" % NOISE_MS)
		print("  read it as 'not measurable here' rather than as zero.")


## Every helper below re-validates. See the note at the top of this function: the
## match is live and a speeder can be shot between any two awaits.
func _live(hulls: Array[Node3D]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for h in hulls:
		if is_instance_valid(h):
			out.append(h)
	return out


func _show(hulls: Array[Node3D], on: bool) -> void:
	for h in _live(hulls):
		h.visible = on


func _place(hulls: Array[Node3D], i: int, at: Vector3) -> void:
	if i >= hulls.size() or not is_instance_valid(hulls[i]):
		return
	hulls[i].global_position = at
	hulls[i].reset_physics_interpolation()


func _measure_viewpoints(main: Node, views: Array) -> void:
	# main.gd has no class_name (only main.tscn instances it), so what SHIPS is
	# reached through the script resource — same as impact.gd below.
	var msaa: int = Quality.settings(GameState.human_players)["msaa"]
	if OS.has_environment("QS_MSAA"):
		msaa = int(OS.get_environment("QS_MSAA"))
	for v in views:
		v.msaa_3d = msaa
	var cams := _take_cameras(views)
	var level: Node = main.level
	var extents: Vector2 = GameState.map_extents
	var reach: float = minf(extents.x, extents.y) * 0.85
	print("\n== vehicle viewpoint cost: %d viewports, %d bodies, %s, msaa %s ==" % [
		GameState.human_players, GameState.combatants.size(),
		GameState.MAPS[GameState.map_index]["name"], _msaa_name(msaa)])
	print("  (speed is here to place the camera, not to be measured — see the note)")
	print("  %-9s %-7s %7s %7s %7s %8s %9s %8s" % [
		"viewpoint", "state", "ms", "p95", "p99", "draws", "tris", "vs foot"])

	var baseline := 0.0
	var base_tris := 0.0
	for vp in VIEWPOINTS:
		for moving in [false, true]:
			var r := await _sweep(cams, level, vp, reach, moving)
			# Everything is read against an infantryman ON FOOT AND MOVING, because
			# that is the frame the game already ships and holds.
			if vp["name"] == "INFANTRY" and moving:
				baseline = r["avg"]
				base_tris = r["tris"]
			print("  %-9s %-7s %7.2f %7.2f %7.2f %8.0f %9.0f %8s" % [
				vp["name"], "moving" if moving else "parked",
				r["avg"], r["p95"], r["p99"], r["draws"], r["tris"],
				"%.2fx" % (r["avg"] / baseline) if baseline > 0.0 else "-"])

	if base_tris > 0.0:
		print("\n  READ THE GEOMETRY COLUMNS FIRST. On this GPU the millisecond")
		print("  figures carry about +/-1.5 ms of run-to-run spread, which is the")
		print("  same size as the effect being looked for; draws and tris are stable")
		print("  run to run and are what actually answers 'does this viewpoint put")
		print("  more of the map in front of the camera'.")
	print("\n  budget %.2f ms. A frame over it does not arrive slightly late with" % BUDGET_MS)
	print("  vsync on — it is held and presented at 33 ms, so read p95/p99 rather")
	print("  than the average: the average is what looks fine while it stutters.")


## Fly all four cameras across the map on different headings and time every frame.
## Different headings because a real match is four different views — pointing them
## all the same way measures one frustum four times and flatters the shadow atlas.
func _sweep(cams: Array[Camera3D], level: Node, vp: Dictionary,
		reach: float, moving: bool, frames := SWEEP_FRAMES) -> Dictionary:
	var up: float = vp["up"]
	var speed: float = vp["speed"] if moving else 0.0
	var span: float = reach * 2.0
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var draws := 0.0
	var tris := 0.0
	# Place them before timing anything, then give the shadow splits and the
	# visibility ranges a moment to settle at the new altitude.
	for f in frames + 20:
		var t := float(f) / 60.0
		for i in cams.size():
			var head: float = TAU * float(i) / float(maxi(cams.size(), 1))
			var dir := Vector3(sin(head), 0.0, cos(head))
			# PARKED IS NOT "ALL FOUR ON THE SAME SPOT". The first version put every
			# camera at map_center, so parked measured four frusta radiating from one
			# point in the densest part of the map while moving measured four spread
			# across it — the two rows differed by WHERE THEY STOOD as much as by the
			# motion, which is the one thing this pair exists to separate. Parked now
			# sits at the same mean offset along its own heading that the moving run
			# spends its time at.
			var along: float = fposmod(speed * t, span) - reach if moving \
				else reach * 0.4
			var at: Vector3 = GameState.map_center + dir * along
			at.y = _ground(level, at) + up
			cams[i].global_position = at
			cams[i].rotation = Vector3(deg_to_rad(vp["pitch"]), head + PI, 0.0)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		if f >= 20:
			samples[f - 20] = float(Time.get_ticks_usec() - t0) / 1000.0
			# AVERAGED, not sampled at the end. Read once after the loop it is
			# whatever the last frame happened to be looking at, which on a moving
			# camera is a random pose — that reported the gunship drawing less than
			# the infantryman, i.e. exactly backwards.
			draws += Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			tris += Performance.get_monitor(
				Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var sorted := Array(samples)
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	return {
		"avg": total / float(frames),
		"p50": sorted[int(frames * 0.50)],
		"p95": sorted[int(frames * 0.95)],
		"p99": sorted[int(frames * 0.99)],
		"worst": sorted[frames - 1],
		"samples": samples,
		"draws": draws / float(frames),
		"tris": tris / float(frames),
	}


## The generated world's analytic surface, which is the one thing that knows where
## the ground is. A hand-laid arena has no such function and is flat anyway.
func _ground(level: Node, at: Vector3) -> float:
	if level != null and level.has_method("height_at"):
		return level.height_at(at.x, at.z)
	return 0.0


## Wall clock over a fixed number of frames. Deliberately not the engine's
## TIME_PROCESS monitor: the project already has it recorded that those swing
## 14-27 ms across identical runs, which is wider than anything worth measuring.
func _measure() -> float:
	var t0 := Time.get_ticks_usec()
	await _frames(SAMPLE_FRAMES)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(SAMPLE_FRAMES)


## THE WORST FRAME A NIGHT MATCH CAN PRODUCE: Impact's whole pool lit at once
## plus a muzzle flash on every shooter, held on rather than decaying. Scattered
## through the bodies, because a light nobody's viewport can see costs nothing
## and would flatter the number.
func _light_everything(main: Node) -> void:
	var live: Array = []
	for c in GameState.combatants:
		if is_instance_valid(c):
			live.append(c.global_position + Vector3.UP)
	if live.is_empty():
		return
	# impact.gd has no class_name (nothing instances it but Weapon), so the
	# constants are reached through the script resource.
	var impact := load("res://scripts/impact.gd")
	var lights: Array = []
	for i in impact.NIGHT_LIGHTS:
		lights.append([impact.NIGHT_LIGHT_RANGE, impact.NIGHT_LIGHT_ENERGY])
	for i in live.size():
		lights.append([Weapon.FLASH_RANGE * Weapon.NIGHT_FLASH_RANGE,
			Weapon.FLASH_ENERGY * Weapon.NIGHT_FLASH_ENERGY])
	for i in lights.size():
		var l := OmniLight3D.new()
		l.omni_range = lights[i][0]
		l.light_energy = lights[i][1]
		l.light_color = Weapon.FLASH_DEFAULT
		l.shadow_enabled = false
		main.add_child(l)
		# Spread along the roster and offset, so they land on different bodies
		# and different ground rather than stacking on one spot.
		l.global_position = live[i % live.size()] \
			+ Vector3(fmod(i * 2.7, 9.0) - 4.5, 0.4, fmod(i * 4.3, 9.0) - 4.5)
	print("  (ceiling: %d dynamic lights held on)" % lights.size())


func _map_index(wanted: String) -> int:
	for i in GameState.MAPS.size():
		if GameState.MAPS[i]["name"] == wanted:
			return i
	return 0


func _msaa_name(msaa: int) -> String:
	match msaa:
		Viewport.MSAA_2X: return "2x"
		Viewport.MSAA_4X: return "4x"
		Viewport.MSAA_8X: return "8x"
		_: return "off"


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
