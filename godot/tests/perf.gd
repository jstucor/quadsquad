extends Node

## A LOADED MATCH, measured. Four viewports, four humans and a full complement
## of AI on one of the big maps, run for a few hundred frames with the frame
## costs sampled.
##
##   godot --headless --path godot tests/perf.tscn
##
## Headless uses the dummy renderer, so what this measures is SCRIPT and PHYSICS
## time — which is exactly the budget the Pi rules in CLAUDE.md are about, and
## the thing a per-frame allocation or an O(bodies x bodies) scan shows up in.
## It does not measure draw calls; that is what the shadow/material rules cover.
##
## Read it as a BEFORE/AFTER number when changing anything that runs every
## frame, not as an absolute: the laptop it runs on is not the Pi. And read the
## ROUTING section, not the frame averages — see the note on _wall_start.

const MAIN := preload("res://scenes/main.tscn")
const CORPSE := preload("res://scenes/fx/corpse.tscn")
const WARMUP := 60      # frames to let the map, nav grid and AI settle
const SAMPLE := 400     # ...and frames actually measured

var _frames := 0
var _process_us := 0
var _physics_us := 0
var _worst_process := 0
var _worst_physics := 0
var _main: Node
## Wall clock across the sample. Treat the engine's TIME_* monitors here with
## suspicion: measured across identical runs of this very scene they ranged from
## 14.6 to 27.1 ms, which is far too noisy to see a change of a few ms in. The
## loop is capped at 60 Hz, so what the wall clock actually tells you is whether
## the match KEPT UP, and the targeted measurements below are what tell you what
## anything costs.
var _wall_start := 0
var _tick_start := 0
var _last_frame_us := 0
var _deltas: PackedFloat32Array = PackedFloat32Array()
## What the WORST frames were doing, which is the only way to attribute a hitch:
## an average cannot tell you what happened on one frame. Each entry is the
## frame's cost plus how much the world CHANGED across it — nodes and objects
## built or freed, and A* searches run — because a spike is nearly always one
## frame that also had to make or destroy something.
var _spikes: Array = []
var _last_nodes := 0
var _last_objects := 0
var _last_plans := 0


func _ready() -> void:
	# The heaviest legal setup: four split screens, the biggest roster, a mode
	# that runs command posts and a reinforcement bleed on top of everything.
	GameState.human_players = 4
	GameState.team_size = 6
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.mode = GameState.Mode.CONQUEST
	GameState.class_mode = GameState.ClassMode.FACTION
	GameState.ai_skill = 3
	GameState.map_index = 10   # SILVA: 220 m, heavily decorated
	# Knobs for bisecting a regression, off by default:
	#   QS_PERF_TEAM=1   run with no AI fill, to separate players from bots
	#   QS_PERF_NONAV=1  make routing fall back to straight lines
	#   QS_PERF_MAP=n    a different map
	#   QS_PERF_TEAMS=n  how many SIDES (4 is the worst case: 4 x team_size bots)
	if OS.get_environment("QS_PERF_TEAM") != "":
		GameState.team_size = int(OS.get_environment("QS_PERF_TEAM"))
	if OS.get_environment("QS_PERF_MAP") != "":
		GameState.map_index = int(OS.get_environment("QS_PERF_MAP"))
	if OS.get_environment("QS_PERF_TEAMS") != "":
		GameState.team_count = int(OS.get_environment("QS_PERF_TEAMS"))
	#   QS_PERF_MASSIVE=1 the 50v50 mode, on its own generated map
	if OS.get_environment("QS_PERF_MASSIVE") != "":
		GameState.mode = GameState.Mode.MASSIVE
		GameState.class_mode = GameState.ClassMode.CUSTOM
		GameState.team_count = 2
		if OS.get_environment("QS_PERF_TEAM") == "":
			GameState.team_size = GameState.MASSIVE_DEFAULT
	_main = MAIN.instantiate()
	add_child(_main)
	# Deploy everyone and start the match, or the whole run measures a lobby.
	await _frames_passed(WARMUP)
	for p in _players(_main):
		if not p.is_alive():
			p._respawn()
	GameState.match_live = true
	if OS.get_environment("QS_PERF_NONAV") != "":
		GameState.nav.ready = false
	await _frames_passed(30)
	if OS.get_environment("QS_CPU") != "":
		await _report_cpu_share()
		get_tree().quit()
		return
	_wall_start = Time.get_ticks_usec()
	_tick_start = Engine.get_physics_frames()
	set_process(true)


func _process(_delta: float) -> void:
	var pr := int(Performance.get_monitor(Performance.TIME_PROCESS) * 1_000_000.0)
	var ph := int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0)
	_process_us += pr
	_physics_us += ph
	_worst_process = maxi(_worst_process, pr)
	_worst_physics = maxi(_worst_physics, ph)
	# THE SPIKE RECORD, which is a different question from the average and the
	# one a player actually feels. Wall clock per frame, not an engine monitor:
	# the monitors are averaged and far too noisy to see a single bad frame in
	# (see _wall_start). A hitch is one frame that took 60 ms, and it does not
	# move a 400-frame average enough to notice.
	var now := Time.get_ticks_usec()
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var plans: int = GameState.nav.plans_run if GameState.nav != null else 0
	if _last_frame_us > 0:
		var ms := (now - _last_frame_us) / 1000.0
		_deltas.append(ms)
		if ms > 16.7:
			_spikes.append({"ms": ms, "nodes": nodes - _last_nodes,
				"objects": objects - _last_objects, "plans": plans - _last_plans})
	_last_frame_us = now
	_last_nodes = nodes
	_last_objects = objects
	_last_plans = plans
	_frames += 1
	if _frames < SAMPLE:
		return
	set_process(false)
	_report()


## --- WHOSE MILLISECONDS ARE THEY ---------------------------------------------
##
## `TIME_PHYSICS_PROCESS` says the tick costs somewhere between 14 and 27 ms —
## this file's own header already warns that the engine monitors are useless at
## this resolution — and neither number tells you WHO is spending it.
##
## So the tick is BRACKETED by two marker nodes, one at either end of the physics
## priority order, which measures the real wall clock across every
## `_physics_process` in the tree (`move_and_slide` included, since that is called
## from inside one). Then each group of scripts is switched off in turn and the
## tick re-measured, A/B/A against controls either side so drift cancels.
##
##   QS_CPU=1 godot --headless --path godot tests/perf.tscn
class TickMark extends Node:
	var on_tick: Callable
	func _physics_process(_delta: float) -> void:
		on_tick.call()


var _tick_t0 := 0
var _tick_us := PackedFloat32Array()
var _tick_recording := false


func _report_cpu_share() -> void:
	# `_process` is live from the first frame because this script defines it, so
	# without this the ordinary 400-frame report fires in the middle of the
	# ablation and quits the run with two windows measured.
	set_process(false)
	# Lower priority runs first, so these bracket every other _physics_process in
	# the tree. They hang off the test root rather than the match, so an ablation
	# of the match cannot switch the instruments off with it.
	var a := TickMark.new()
	a.process_physics_priority = -10000
	a.on_tick = func() -> void: _tick_t0 = Time.get_ticks_usec()
	add_child(a)
	var b := TickMark.new()
	b.process_physics_priority = 10000
	b.on_tick = func() -> void:
		if _tick_recording and _tick_t0 > 0:
			_tick_us.append(float(Time.get_ticks_usec() - _tick_t0) / 1000.0)
	add_child(b)

	var bots := _of_type(_main, "Bot")
	var players := _players(_main)
	var weapons := _of_type(_main, "Weapon")
	var posts := _of_type(_main, "CommandPost")
	var models := _of_type(_main, "CharacterModel")
	var anims: Array[Node] = []
	for m in models:
		for ap in m.find_children("*", "AnimationPlayer", true, false):
			anims.append(ap)

	print("\n== whose milliseconds: %d bodies (%d bots, %d players), %s ==" % [
		GameState.combatants.size(), bots.size(), players.size(),
		GameState.MAPS[GameState.map_index]["name"]])
	print("  %d weapons, %d posts, %d models, %d animation players" % [
		weapons.size(), posts.size(), models.size(), anims.size()])

	for row in [
		{"name": "ALL bot scripts", "nodes": bots},
		{"name": "ALL player scripts", "nodes": players},
		{"name": "ALL weapon scripts", "nodes": weapons},
		{"name": "command posts", "nodes": posts},
		# The animation players are the one group NOT in the physics tick — they
		# run on the idle callback — so this row is expected to read as zero here
		# and to show up in TIME_PROCESS instead. It is measured anyway because
		# "the animation is free" is exactly the sort of thing that is assumed.
		{"name": "animation players (idle, not tick)", "nodes": anims},
	]:
		var nodes: Array = row["nodes"]
		var c1 := await _tick_window()
		_set_ticking(nodes, false)
		var off := await _tick_window()
		_set_ticking(nodes, true)
		var c2 := await _tick_window()
		var control := (c1 + c2) * 0.5
		print("  %-38s %6.3f vs %6.3f  %6.3f ms  (%.0f%%)" % [
			row["name"], off, control, control - off,
			100.0 * (control - off) / maxf(control, 0.001)])

	var full := await _tick_window()
	print("  %-38s %6.3f ms per tick" % ["EVERYTHING (the tick itself)", full])
	print("\n  The budget is 16.67 ms for the tick AND the frame it is drawn in.")


func _tick_window() -> float:
	_tick_us.clear()
	_tick_recording = true
	await _frames_passed(90)
	_tick_recording = false
	var s := Array(_tick_us)
	s.sort()
	return s[s.size() / 2] if not s.is_empty() else 0.0


func _set_ticking(nodes: Array, on: bool) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.set_physics_process(on)


func _of_type(root: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in root.find_children("*", cls, true, false):
		out.append(n)
	return out


## Sorted percentiles over the frame deltas, plus how many frames blew the
## budget. A dropped frame at 60 Hz is anything past ~16.7 ms; past 33 ms the
## player sees a stutter rather than a soft frame.
func _report_spikes() -> void:
	if _deltas.is_empty():
		return
	var sorted := Array(_deltas)
	sorted.sort()
	var n := sorted.size()
	var over_17 := 0
	var over_33 := 0
	var over_50 := 0
	for d: float in sorted:
		if d > 16.7:
			over_17 += 1
		if d > 33.0:
			over_33 += 1
		if d > 50.0:
			over_50 += 1
	print("== frame spikes over %d frames ==" % n)
	print("  p50 %6.2f ms   p95 %6.2f ms   p99 %6.2f ms   worst %6.2f ms" % [
		sorted[int(n * 0.50)], sorted[int(n * 0.95)],
		sorted[mini(int(n * 0.99), n - 1)], sorted[n - 1]])
	print("  frames over 16.7 ms: %d (%.1f%%)   over 33 ms: %d   over 50 ms: %d" % [
		over_17, 100.0 * over_17 / n, over_33, over_50])
	_spikes.sort_custom(func(a, b): return a["ms"] > b["ms"])
	for i in mini(6, _spikes.size()):
		var sp: Dictionary = _spikes[i]
		print("    %6.2f ms   nodes %+5d   objects %+5d   A* searches %d" % [
			sp["ms"], sp["nodes"], sp["objects"], sp["plans"]])


func _report() -> void:
	var bodies := GameState.combatants.size()
	print("== loaded match: %d viewports, %d combatants, %s ==" % [
		GameState.human_players, bodies,
		GameState.MAPS[GameState.map_index]["name"]])
	print("  process  avg %6.3f ms   worst %6.3f ms" % [
		_process_us / float(_frames) / 1000.0, _worst_process / 1000.0])
	print("  physics  avg %6.3f ms   worst %6.3f ms" % [
		_physics_us / float(_frames) / 1000.0, _worst_physics / 1000.0])
	var ticks := maxi(Engine.get_physics_frames() - _tick_start, 1)
	var wall := Time.get_ticks_usec() - _wall_start
	print("  wall     %6.3f ms per physics tick over %d ticks" % [
		wall / float(ticks) / 1000.0, ticks])
	print("           (the loop is capped at 60 Hz, so ~16.7 here means it KEPT UP;")
	print("            anything above it is the match failing to hold the budget)")
	# WHAT THE PHYSICS SERVER IS ACTUALLY CARRYING. TIME_PHYSICS_PROCESS covers
	# the solver as well as the scripts, so a rise in it means nothing until you
	# know whether the BODIES or the CODE grew. A ragdoll is six rigid bodies and
	# five joints EACH and it lives for nine seconds, so this is the number that
	# moves when a big roster starts dying at a big roster's rate.
	print("  active rigid bodies %d   collision pairs %d   islands %d" % [
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)])
	var corpses := 0
	for n in get_tree().current_scene.get_children():
		if n.has_method("freeze_all"):
			corpses += 1
	print("  ragdolls alive right now %d" % corpses)
	_report_spikes()
	_report_nav()
	_report_events()
	print("  objects %d   nodes %d" % [
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()


## What routing costs, measured on THIS map's real grid, plus how often the
## match actually asked for it.
##
## Two numbers rather than one because they answer different questions. How OFTEN
## a search runs is low-noise and is what the per-frame budget changed; what one
## search COSTS is directly timed here and is what makes a cluster of them
## expensive. The frame averages above are far too noisy to see either in.
func _report_nav() -> void:
	var nav: NavGrid = GameState.nav
	if not nav.ready:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var e := GameState.map_extents
	var from: Array[Vector3] = []
	var to: Array[Vector3] = []
	for i in 40:
		from.append(GameState.map_center + Vector3(
			rng.randf_range(-e.x, e.x), 0.0, rng.randf_range(-e.y, e.y)))
		to.append(GameState.map_center + Vector3(
			rng.randf_range(-e.x, e.x), 0.0, rng.randf_range(-e.y, e.y)))

	var seconds := float(Engine.get_physics_frames() - _tick_start) \
		/ float(Engine.physics_ticks_per_second)
	print("== routing during the match ==")
	print("  A* searches   %d in %.1fs  =  %.1f/s   (%d deferred to the next frame)" % [
		nav.plans_run, seconds, nav.plans_run / maxf(seconds, 0.001),
		nav.plans_refused])

	var t := Time.get_ticks_usec()
	var blocked := 0
	for i in from.size():
		if not nav.line_clear(from[i], to[i]):
			blocked += 1
	var clear_us := Time.get_ticks_usec() - t

	t = Time.get_ticks_usec()
	for i in from.size():
		nav.path(from[i], to[i])
	var path_us := Time.get_ticks_usec() - t

	print("== routing, %d journeys across the map ==" % from.size())
	print("  line_clear  %6.3f ms each   (%d of %d journeys had a wall on the line)" % [
		clear_us / float(from.size()) / 1000.0, blocked, from.size()])
	print("  A* path     %6.3f ms each" % [path_us / float(from.size()) / 1000.0])


func _players(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Player:
			out.append(c)
		out.append_array(_players(c))
	return out


func _frames_passed(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


## WHAT AN EVENT COSTS, as opposed to what a frame costs. A hitch is rarely the
## steady load — it is one frame that also had to do something big, and in a
## match with two dozen bots the big things happen on a schedule nobody set: a
## death builds a ragdoll wearing a freshly built body, and a respawn rebuilds
## the model it deploys with. Both are measured here directly, because neither
## shows up in an average that is dominated by the 399 frames where nobody died.
func _report_events() -> void:
	var n := 12
	var t := Time.get_ticks_usec()
	var made: Array[Node] = []
	for i in n:
		var c := CORPSE.instantiate()
		add_child(c)
		# FORCED, or the view-range rule in corpse.gd frees them unbuilt and this
		# measures an early-out rather than the work it is meant to price.
		c.launch(Transform3D.IDENTITY, Color.RED, Vector3.FORWARD,
			CharacterModel.Style.LEGION, true)
		made.append(c)
	var corpse_us := Time.get_ticks_usec() - t
	for c in made:
		c.queue_free()

	var model := CharacterModel.new()
	add_child(model)
	t = Time.get_ticks_usec()
	for i in n:
		model.set_style(CharacterModel.Style.LEGION if i % 2 == 0
			else CharacterModel.Style.LEGION_VANGUARD)
	var style_us := Time.get_ticks_usec() - t
	model.queue_free()

	print("== what one EVENT costs (these land on a single frame) ==")
	print("  a death  (ragdoll + a whole body built for it)  %6.2f ms" % [
		corpse_us / float(n) / 1000.0])
	print("  a respawn (set_style rebuilds the model)        %6.2f ms" % [
		style_us / float(n) / 1000.0])
