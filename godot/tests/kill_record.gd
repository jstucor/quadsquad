extends Node
## THE RECORD: the killfeed's entries and the post-match table.
##
## Everything here is about a fact SURVIVING a death, which is the one thing this
## area gets wrong: the killer is usually freed by the time anybody draws the
## line about them, and a bot is a different instance every life. So the test
## kills real bodies through the real `take_damage` path and then asks the
## questions a HUD asks, rather than checking that a function was called.

var _fails: Array[String] = []


func _ready() -> void:
	print("\n==== the kill record ====")
	# A TEST THAT CANNOT REACH WHAT IT TESTS MUST FAIL, NOT PASS. Every check
	# below reads GameState, and a GDScript error ABORTS the enclosing function
	# (house rule 6) — so when a parse error upstream left the autoload nil, each
	# check died on its first line, no `_ok` ever ran, and this printed "THE
	# RECORD HOLDS" while verifying nothing at all. That is the worst failure a
	# test can have, so it is the first thing asserted.
	if GameState == null or not GameState.has_method("log_kill"):
		print("  FAIL: GameState did not load — every check below would be hollow")
		print("==== 1 FAILURES ====")
		get_tree().quit(1)
		return
	_check_feed_shape()
	_check_stats_accumulate()
	_check_teamkill_and_suicide()
	_check_names()
	_check_sorting()
	_check_reset()
	print("")
	if _fails.is_empty():
		print("==== THE RECORD HOLDS ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _fresh() -> void:
	GameState.kill_feed.clear()
	GameState.player_stats.clear()


## An entry states both sides, both teams, and how it happened. The HUD reads
## every one of these keys, so a missing key is a killfeed that draws nothing.
func _check_feed_shape() -> void:
	print("\n-- an entry carries what a feed draws --")
	_fresh()
	GameState.log_kill({
		"killer": "PLAYER 1", "killer_team": 0, "victim": "B1 BATTLE DROID",
		"victim_team": 1, "headshot": true, "suicide": false, "killer_index": 0,
	})
	_ok(GameState.kill_feed.size() == 1, "an entry did not reach the feed")
	var e: Dictionary = GameState.kill_feed[0]
	for key in ["killer", "killer_team", "victim", "victim_team", "headshot", "suicide"]:
		_ok(e.has(key), "the feed entry has no `%s` — the HUD reads it" % key)
	print("  entry keys: %s" % str(e.keys()))

	# THE FEED IS A RING. A long match is thousands of deaths and the widget draws
	# five of them; an unbounded log is a leak that only shows up in a soak.
	_fresh()
	for i in GameState.KILL_FEED_MAX + 12:
		GameState.log_kill({"killer": "A", "killer_team": 0, "victim": "B",
			"victim_team": 1, "headshot": false, "suicide": false})
	_ok(GameState.kill_feed.size() == GameState.KILL_FEED_MAX,
		"the feed grew past KILL_FEED_MAX (%d entries) — it is a ring, not a log"
			% GameState.kill_feed.size())
	print("  %d kills logged, %d kept" % [GameState.KILL_FEED_MAX + 12,
		GameState.kill_feed.size()])


func _check_stats_accumulate() -> void:
	print("\n-- a human's row accumulates across lives --")
	_fresh()
	for i in 3:
		GameState.log_kill({"killer": "PLAYER 1", "killer_team": 0,
			"victim": "TROOPER", "victim_team": 1, "headshot": i == 0,
			"suicide": false, "killer_index": 0})
	GameState.log_kill({"killer": "TROOPER", "killer_team": 1,
		"victim": "PLAYER 1", "victim_team": 0, "headshot": false,
		"suicide": false, "victim_index": 0})
	var row: Dictionary = GameState.stats_for(0)
	_ok(int(row["kills"]) == 3, "3 kills recorded as %d" % int(row["kills"]))
	_ok(int(row["deaths"]) == 1, "1 death recorded as %d" % int(row["deaths"]))
	_ok(int(row["headshots"]) == 1, "1 headshot recorded as %d" % int(row["headshots"]))
	# THE STREAK IS PER LIFE and the BEST is per match: dying ends the run but
	# must not erase what it was, or the table's most interesting column is
	# always whatever happened since the last death.
	_ok(int(row["best_streak"]) == 3,
		"best streak should survive the death that ended it, got %d"
			% int(row["best_streak"]))
	_ok(int(row["streak"]) == 0, "the live streak should reset on death, got %d"
		% int(row["streak"]))
	print("  kills %d  deaths %d  head %d  best run %d" % [int(row["kills"]),
		int(row["deaths"]), int(row["headshots"]), int(row["best_streak"])])


## THE QUICKEST ROUTE UP A SCOREBOARD MUST NOT BE A GRENADE AT YOUR OWN FEET.
## Both of these cost a death and pay no kill.
func _check_teamkill_and_suicide() -> void:
	print("\n-- a teamkill and a suicide pay nothing --")
	_fresh()
	GameState.log_kill({"killer": "PLAYER 2", "killer_team": 0,
		"victim": "PLAYER 1", "victim_team": 0, "headshot": false,
		"suicide": false, "killer_index": 1, "victim_index": 0})
	_ok(int(GameState.stats_for(1)["kills"]) == 0,
		"a teamkill paid a kill — the fastest way up the table is your own side")
	_ok(int(GameState.stats_for(0)["deaths"]) == 1,
		"a teamkill did not cost the victim a death")

	_fresh()
	GameState.log_kill({"killer": "", "killer_team": -1, "victim": "PLAYER 1",
		"victim_team": 0, "headshot": false, "suicide": true, "victim_index": 0})
	_ok(int(GameState.stats_for(0)["kills"]) == 0, "a suicide paid a kill")
	_ok(int(GameState.stats_for(0)["deaths"]) == 1, "a suicide cost no death")
	print("  teamkill: 0 kills, 1 death.  suicide: 0 kills, 1 death.")


## A name has to survive its body. `combatant_name` is ASKED, not required, so a
## combatant that never grew one still gets a line rather than aborting the whole
## record (house rule 6).
func _check_names() -> void:
	print("\n-- everything on the field can be named --")
	var plain := Node3D.new()
	add_child(plain)
	var name := GameState.combatant_name(plain)
	_ok(name != "", "a combatant with no `combatant_name` got an empty name")
	print("  a bare Node3D falls back to: %s" % name)
	_ok(GameState.combatant_name(null) == "?", "a null killer must still name")
	plain.queue_free()

	# The one that actually bit: a freed body. The feed draws a line about a
	# killer who is often dead by the time it is read.
	var gone := Node3D.new()
	add_child(gone)
	gone.free()
	_ok(GameState.combatant_name(gone) == "?",
		"a FREED body must name safely — the feed outlives its subjects")
	print("  a freed body names safely")


func _check_sorting() -> void:
	print("\n-- the table is ordered by kills, then by what they cost --")
	_fresh()
	# Two players on two kills, separated only by deaths.
	for i in 2:
		GameState.log_kill({"killer": "P", "killer_team": 0, "victim": "T",
			"victim_team": 1, "headshot": false, "suicide": false, "killer_index": 0})
		GameState.log_kill({"killer": "P", "killer_team": 0, "victim": "T",
			"victim_team": 1, "headshot": false, "suicide": false, "killer_index": 1})
	for i in 3:
		GameState.log_kill({"killer": "T", "killer_team": 1, "victim": "P",
			"victim_team": 0, "headshot": false, "suicide": false, "victim_index": 0})
	var rows := GameState.score_table()
	_ok(rows.size() == 2, "expected 2 rows, got %d" % rows.size())
	if rows.size() == 2:
		_ok(int(rows[0]["index"]) == 1,
			"on equal kills the player with FEWER deaths must come first")
		for r in rows:
			print("  %-10s %d kills  %d deaths" % [str(r["name"]),
				int(r["kills"]), int(r["deaths"])])


## The record is PER MATCH. Without this the rotation's second map opens with the
## first map's table already on it.
func _check_reset() -> void:
	print("\n-- a new match starts from nothing --")
	GameState.log_kill({"killer": "A", "killer_team": 0, "victim": "B",
		"victim_team": 1, "headshot": false, "suicide": false, "killer_index": 0})
	GameState.reset_match()
	_ok(GameState.kill_feed.is_empty(),
		"reset_match left %d entries in the feed" % GameState.kill_feed.size())
	_ok(GameState.player_stats.is_empty(),
		"reset_match left %d stat rows" % GameState.player_stats.size())
	print("  feed and stats both empty after reset_match")
