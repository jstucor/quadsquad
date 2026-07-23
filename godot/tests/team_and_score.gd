extends Node
## The configurable victory threshold and the team-select wiring.
##
##   godot --headless --path godot tests/team_and_score.tscn

func _ready() -> void:
	await get_tree().process_frame
	var G := GameState
	var fails := []

	# --- configurable victory threshold ----------------------------------
	print("== victory threshold ==")
	G.mode = G.Mode.DEATHMATCH
	print("  default deathmatch limit: %d" % G.score_limit())
	if G.score_limit() != 25:
		fails.append("deathmatch default should be 25, got %d" % G.score_limit())
	G.score_targets[G.Mode.DEATHMATCH] = 100
	print("  raised to: %d" % G.score_limit())
	if G.score_limit() != 100:
		fails.append("raising the deathmatch limit did not take")

	G.mode = G.Mode.ZONES
	G.score_targets[G.Mode.ZONES] = 200
	print("  zones limit: %d, blurb: %s" % [G.score_limit(), G.mode_blurb()])
	if G.score_limit() != 200:
		fails.append("zones limit did not take")
	if not ("200" in G.mode_blurb()):
		fails.append("the mode blurb does not reflect the chosen limit")

	# Royale is not tunable and stays at its fixed one-point award.
	G.mode = G.Mode.ROYALE
	if G.score_limit() != 1:
		fails.append("royale should stay last-side-standing (1)")

	# --- team selection overrides the round-robin ------------------------
	print("\n== chosen teams ==")
	G.mode = G.Mode.DEATHMATCH
	G.free_for_all = false
	G.team_count = 2
	G.human_players = 4
	# Round-robin by default: P0->0, P1->1, P2->0, P3->1.
	var rr := []
	for i in 4:
		rr.append(G.team_for_player(i))
	print("  round-robin: %s" % str(rr))
	if rr != [0, 1, 0, 1]:
		fails.append("default round-robin wrong: %s" % str(rr))

	# Everyone piles onto team 0: their picks win, and AI fill accounts for it.
	var t0: Array[int] = [0, 0, 0, 0]
	G.chosen_teams = t0
	var picked := []
	for i in 4:
		picked.append(G.team_for_player(i))
	print("  all chose team 0: %s   team1 humans %d, AI needed %d" % [
		str(picked), G.humans_on_team(1), G.ai_needed(1)])
	if picked != [0, 0, 0, 0]:
		fails.append("chosen teams not honoured: %s" % str(picked))
	if G.humans_on_team(0) != 4 or G.humans_on_team(1) != 0:
		fails.append("humans_on_team ignores the picks")
	if G.ai_needed(1) != G.team_size:
		fails.append("AI fill did not follow the picks: %d" % G.ai_needed(1))

	# A pick that is out of range for the current team count falls back safely.
	G.team_count = 2
	var t3: Array[int] = [3, 3, 3, 3]   # team 3 does not exist in a 2-team match
	G.chosen_teams = t3
	print("  out-of-range picks fall back: %d" % G.team_for_player(0))
	if G.team_for_player(0) >= G.active_teams():
		fails.append("an out-of-range pick was not clamped to a real team")

	print("\n==== %s ====" % ("TEAMS AND SCORE WORK" if fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [fails.size(), "\n  ".join(fails)]))
	get_tree().quit(0 if fails.is_empty() else 1)
