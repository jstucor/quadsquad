extends Node

## Runs a busy match for a while and checks that nothing ACCUMULATES.
##
##   godot --headless --path godot tests/soak.tscn
##
## Every other test checks that something works once. This one exists because
## the expensive mistakes in this project are the ones that only show up over
## time: a node that is spawned per shot and never freed, a material created per
## bullet, a signal connection that outlives the map. None of those fail a
## single-frame assertion — they fail after two minutes of four bots shooting at
## each other, which is exactly the state nothing else here reproduces.
##
## It samples the OBJECT and NODE counts across a long match and fails if either
## is still climbing at the end. A match in steady state allocates and frees
## constantly (bolts, impacts, corpses) so the counts SWING; what must not happen
## is a trend.
##
## Read the printed table, not just the verdict: a slow leak shows as a rising
## last column long before it trips the threshold.
##
## It found one real bug on the way in — blaster_bolt duplicating its material
## per round, which created and destroyed hundreds of materials a second and made
## the rendering server log `Parameter "material" is null` about thirty times a
## match. A clean tree logged none. That is the shape of thing this catches.

const MAIN := preload("res://scenes/main.tscn")
const SETTLE := 90          # frames before the first sample: spawn-in churn
const WINDOW := 400         # frames per sample
const SAMPLES := 6
## How much the object count may drift across the whole run, as a fraction of the
## first settled sample. Generous: corpses live 9 s and pickups are never
## collected in deathmatch, so some growth is real and expected.
const GROWTH_LIMIT := 0.25

var _fails: Array[String] = []


func _ready() -> void:
	GameState.human_players = 2
	GameState.team_size = 4
	GameState.team_count = 2
	GameState.map_index = 0
	GameState.ai_skill = 3
	GameState.mode = GameState.Mode.DEATHMATCH
	add_child(MAIN.instantiate())
	await _frames(SETTLE)
	# Nobody presses deploy in a headless test, so the match would never go live
	# and the bots would stand still for the whole soak.
	GameState.match_live = true
	await _frames(SETTLE)

	print("\n%-8s %10s %10s %10s %8s" % ["sample", "objects", "nodes", "orphans", "engaged"])
	var first := Vector2.ZERO
	var last := Vector2.ZERO
	var fought := 0
	for i in SAMPLES:
		fought += await _frames_counting_contact(WINDOW)
		var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
		var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		print("%-8d %10d %10d %10d %8d" % [i, objects, nodes, orphans, fought])
		if i == 0:
			first = Vector2(objects, nodes)
		last = Vector2(objects, nodes)
		# An orphan is a node created and never added to the tree, or removed and
		# never freed. In steady state there should be none at a sample boundary.
		if orphans > 0:
			_fails.append("sample %d left %d orphaned node(s)" % [i, orphans])

	for pair in [["objects", first.x, last.x], ["nodes", first.y, last.y]]:
		var grew: float = (float(pair[2]) - float(pair[1])) / maxf(float(pair[1]), 1.0)
		print("  %-8s %+.1f%% across the run" % [pair[0], grew * 100.0])
		if grew > GROWTH_LIMIT:
			_fails.append("%s grew %.0f%% (limit %.0f%%) — something is accumulating"
				% [pair[0], grew * 100.0, GROWTH_LIMIT * 100.0])

	print("  scores %s   combatants %d   bot-frames in contact %d"
		% [GameState.scores, GameState.combatants.size(), fought])
	# A soak where nobody shot at anybody exercised none of the per-shot spawning
	# this test exists to watch, and would report "clean" for the wrong reason.
	if fought < WINDOW:
		_fails.append("the bots barely made contact (%d bot-frames) — this soak "
			% fought + "did not stress the thing it is meant to stress")
	print("\n==== %s ====" % ("SOAK IS CLEAN" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## ...and count how many bot-frames were spent actually in contact, so the
## verdict can say whether the soak fought or just jogged around an empty map.
func _frames_counting_contact(n: int) -> int:
	var contact := 0
	for _i in n:
		await get_tree().process_frame
		for c in GameState.combatants:
			if c is Bot and c.is_alive() and c._state == Bot.State.ENGAGE:
				contact += 1
	return contact
