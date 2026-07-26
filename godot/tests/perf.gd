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
	GameState.map_index = 10   # KASHYYYK: 220 m, heavily decorated
	# Knobs for bisecting a regression, off by default:
	#   QS_PERF_TEAM=1   run with no AI fill, to separate players from bots
	#   QS_PERF_NONAV=1  make routing fall back to straight lines
	#   QS_PERF_MAP=n    a different map
	if OS.get_environment("QS_PERF_TEAM") != "":
		GameState.team_size = int(OS.get_environment("QS_PERF_TEAM"))
	if OS.get_environment("QS_PERF_MAP") != "":
		GameState.map_index = int(OS.get_environment("QS_PERF_MAP"))
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
	_frames += 1
	if _frames < SAMPLE:
		return
	set_process(false)
	_report()


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
	_report_nav()
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
