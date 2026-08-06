extends Node3D
## GETTING OUT, STOPPING, AND LOSING A CONTROLLER — the three ways a match ends
## that are not winning it.
##
##   godot --headless --path godot tests/match_exit.tscn
##
## All three of these were missing, and all three fail SILENTLY when they break
## again, which is why they are worth a test rather than a play-through:
##
##   LEAVING   there was no way out of a match short of killing the process. A
##             regression here looks like nothing — the row is still on screen,
##             it just stops doing anything.
##   PAUSING   solo. If the hold is taken and not released the game is frozen
##             forever; if it is released and not taken there is no pause. Both
##             look like "the button did nothing".
##   A PAD     falling out. The whole failure is that the game says nothing, so a
##             broken version of this feature is indistinguishable from not
##             having it. Nothing but an assertion can tell them apart.
##
## The hold SET is what most of this is really testing. Two things can stop the
## match and they overlap — unplug a pad while the menu is up — so the property
## that matters is that the match resumes when the LAST holder lets go and not
## when the first one does.

const MAIN := preload("res://scenes/main.tscn")
const OVERLAY := preload("res://scripts/settings_overlay.gd")

var _fails: Array[String] = []
var _done := {}
var _main: Node
## THE TREE, HELD DIRECTLY. The last check leaves the match for real, which
## replaces the scene this test is part of — and a freed node's `get_tree()`
## returns null, so every read after that point would abort on a null instance
## (house rule 6) and the run would report nothing while appearing to hang.
## The SceneTree itself outlives the scene, so a captured reference keeps working.
var _tree: SceneTree


func _ready() -> void:
	_tree = get_tree()
	GameState.reset_match()
	Quality.governor_enabled = false
	GameState.human_players = 1
	GameState.team_size = 2
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	_main = MAIN.instantiate()
	add_child(_main)
	await _tree.create_timer(1.0).timeout

	_check_holds()
	await _check_pause()
	await _check_pad()
	await _check_spare()
	await _check_quit()

	for name in ["holds", "pause", "pad", "spare", "quit"]:
		if not _done.has(name):
			_fails.append("the `%s` section did not run to the end — something in "
				% name + "it errored and the rest of its checks were skipped")
	print("")
	if _fails.is_empty():
		print("==== YOU CAN GET OUT ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	_tree.quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## THE HOLD SET, on its own, before anything real uses it. It is a set and not a
## boolean specifically so two holders cannot clear each other, and that is the
## one property no amount of playing would ever surface — you would have to
## unplug a controller while a menu was open and notice that the game resumed
## underneath it.
func _check_holds() -> void:
	print("== the hold set ==")
	# BEFORE ANYTHING RELEASES ANYTHING. A match that has just booted must be
	# RUNNING, and this run has no controllers attached at all — which is exactly
	# the state a player is in when they start the game before plugging one in.
	# Routing the startup check through the disconnect handler made a solo match
	# pause itself on its own first frame, against a pad that had never existed,
	# and the only symptom was every other test that boots a match timing out.
	# A pad that was never there is a SETUP problem, not an interruption.
	_ok(not _tree.paused,
		"a match booted with no controllers attached and stopped itself — an absent pad is a setup problem, not an interruption")
	GameState.release_all_holds()
	_ok(not _tree.paused, "the tree started held")
	GameState.hold("a", true)
	_ok(_tree.paused, "one hold did not stop the match")
	GameState.hold("b", true)
	GameState.hold("a", false)
	_ok(_tree.paused,
		"the match resumed while a SECOND hold was still out — a boolean would do this and a set must not")
	GameState.hold("b", false)
	_ok(not _tree.paused, "the match stayed held after the last holder let go")
	# Releasing something that was never held is a no-op, which is what lets the
	# overlay release unconditionally in `_close()`.
	GameState.hold("never", false)
	_ok(not _tree.paused, "releasing an unheld reason stopped the match")
	GameState.release_all_holds()
	print("  one holder, two holders, and letting go out of order: all correct")
	_done["holds"] = true


## SOLO, THE SETTINGS SCREEN IS A REAL PAUSE. At more than one human it must not
## be — the design is that one player's screen is their own — so both halves are
## checked, and the second is the one that regresses quietly, because a pause
## that leaks into split screen still "works" for whoever opened it.
func _check_pause() -> void:
	print("\n== pausing, and not pausing ==")
	var overlay := _find_overlay()
	if overlay == null:
		_ok(false, "no settings overlay was built for the player")
		return

	_ok(GameState.may_pause(), "a solo match says it may not pause")
	overlay._show()
	_ok(_tree.paused, "opening the settings screen solo did not stop the match")
	# AND THE SCREEN ITSELF KEEPS RUNNING, or it is the one control that can undo
	# the pause and it has been frozen by it.
	_ok(overlay.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the settings overlay is pausable — solo it would freeze itself and the match could never be resumed")
	overlay._close()
	_ok(not _tree.paused, "closing the settings screen left the match stopped")
	print("  solo: opens paused, closes running")

	# NOW AS A SPLIT SCREEN. Same overlay, same calls, opposite answer.
	var was: int = GameState.human_players
	GameState.human_players = 3
	_ok(not GameState.may_pause(), "a three-player match says it may pause")
	overlay._show()
	_ok(not _tree.paused,
		"one player opening their settings screen froze a three-player match — the other two are still playing")
	overlay._close()
	GameState.human_players = was
	print("  split screen: opens WITHOUT stopping the other players")
	GameState.release_all_holds()
	await _tree.process_frame
	_done["pause"] = true


## A PAD FALLING OUT. Driven through the same handler the engine signal calls,
## and the WIRING is checked separately — a perfect handler nothing is connected
## to is the exact shape this bug had before.
func _check_pad() -> void:
	print("\n== losing a controller ==")
	_ok(Input.joy_connection_changed.is_connected(_main._on_pad_changed),
		"nothing is listening for a controller connecting or disconnecting")

	var player := _find_player()
	if player == null:
		_ok(false, "no player to lose a pad")
		return
	# The harness's player is on the keyboard under `--headless`, so give it a
	# pad to lose. This is the state a real match is in for every one of its
	# players (Main deals P1..P4 to pads 0..3).
	player.input_device = 0
	for entry in _main._pad_banners:
		entry["player"] = player

	_main._on_pad_changed(0, false)
	var banner: Label = _main._pad_banners[0]["label"] if not _main._pad_banners.is_empty() \
		else null
	_ok(banner != null and banner.visible,
		"a controller fell out and the player was told nothing")
	_ok(_tree.paused,
		"a solo player's controller fell out and the match carried on without them")
	# THE BANNER HAS TO BE READABLE WHILE THE TREE IS STOPPED, which is exactly
	# when it is shown.
	_ok(banner != null and banner.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the disconnect banner is pausable — it would be frozen by the pause it is explaining")

	# ...AND PLUGGING IT BACK IN CLEARS IT, with no press required.
	_main._on_pad_changed(0, true)
	_ok(banner != null and not banner.visible,
		"the pad came back and the banner stayed up")
	_ok(not _tree.paused, "the pad came back and the match stayed stopped")
	print("  disconnect: banner up, match held  ·  reconnect: banner gone, match running")

	# THE OVERLAP. This is the case the hold SET exists for, and the one nobody
	# would ever find by playing: a pad dropping while the menu is open, then
	# coming back, must NOT resume a match the player is still reading a menu over.
	var overlay := _find_overlay()
	if overlay != null:
		overlay._show()
		_main._on_pad_changed(0, false)
		_main._on_pad_changed(0, true)
		_ok(_tree.paused,
			"a pad reconnecting resumed the match while the settings screen was still open over it")
		overlay._close()
		_ok(not _tree.paused, "closing the last holder left the match stopped")
		print("  pad lost and regained WITH the menu open: still held, as it must be")
	GameState.release_all_holds()
	await _tree.process_frame
	_done["pad"] = true


## PICKING UP A DIFFERENT CONTROLLER. Godot usually hands a reconnected pad its
## old index back, so the ordinary path needs none of this — what needs it is the
## case that actually happens at a couch, where the batteries died and somebody
## reached for the spare.
##
## THE TRAP THIS EXISTS FOR is the hold key. The match is stopped against the
## DEAD device's id, and adopting a new pad must release THAT one — releasing the
## new device's id instead leaves the match held forever by a controller that is
## never coming back, and the symptom is a frozen game with a working pad in your
## hands and no banner on screen explaining it.
func _check_spare() -> void:
	print("\n== picking up a different controller ==")
	var player := _find_player()
	if player == null:
		_ok(false, "no player for the spare-pad check")
		return
	var overlay := _find_overlay()
	player.input_device = 0
	if overlay != null:
		overlay.device = 0

	# Pad 0 dies. Solo, that stops the match.
	_main._on_pad_changed(0, false)
	_ok(_tree.paused, "the pad died and the match carried on")

	# ...and a DIFFERENT pad arrives. In a real match `Input.get_connected_joypads`
	# would no longer list 0; headless it lists nothing at all, which is the same
	# answer for the branch being exercised.
	_main._on_pad_changed(3, true)
	_ok(player.input_device == 3,
		"a spare controller was plugged in and the player without one was not given it (still on device %d)"
			% player.input_device)
	_ok(not _tree.paused,
		"the player was handed a working controller and the match stayed stopped — the hold was released against the wrong device")
	if overlay != null:
		_ok(overlay.device == 3,
			"the settings screen is still editing the dead pad's bindings (device %d)"
				% overlay.device)
	var banner: Label = _main._pad_banners[0]["label"] if not _main._pad_banners.is_empty() \
		else null
	_ok(banner != null and not banner.visible,
		"the player has a working controller and is still being told they do not")
	print("  pad 0 dies, pad 3 arrives: player adopts it, match resumes, screen follows")

	# A SECOND SPARE MUST NOT BE STOLEN from a player who is already fine.
	_main._on_pad_changed(2, true)
	_ok(player.input_device == 3,
		"a player who already had a working pad was moved onto a newly connected one")
	print("  a further pad arriving does not move a player who is already playing")
	player.input_device = 0
	if overlay != null:
		overlay.device = 0
	GameState.release_all_holds()
	await _tree.process_frame
	_done["spare"] = true


## LEAVING. The row exists, it is guarded, backing out of the guard returns you
## to the match, and going through with it releases every hold — because a scene
## loaded into a stopped tree never runs its first frame.
func _check_quit() -> void:
	print("\n== leaving the match ==")
	var overlay := _find_overlay()
	if overlay == null:
		_ok(false, "no settings overlay to quit from")
		return
	overlay._show()
	var quit_row := -1
	for i in overlay._rows.size():
		if overlay._rows[i]["kind"] == OVERLAY.Kind.QUIT:
			quit_row = i
	_ok(quit_row >= 0, "there is no way out of a match on the pause screen")
	if quit_row < 0:
		return

	overlay._row = quit_row
	overlay._activate()
	_ok(overlay._mode == OVERLAY.Mode.CONFIRM,
		"quitting a match is not behind a confirm — the row list wraps, so it is one press from the top row")

	# BACKING OUT PUTS YOU BACK IN THE MATCH, not out of the menu entirely.
	overlay._confirm_input({"back": true, "toggle": false, "accept": false})
	_ok(overlay._mode == OVERLAY.Mode.NAV, "backing out of the confirm did not return to the menu")
	# ...and START does it too, because that button has closed this screen from
	# every other mode since it was written.
	overlay._activate()
	overlay._confirm_input({"back": false, "toggle": true, "accept": false})
	_ok(overlay._mode == OVERLAY.Mode.NAV, "START did not back out of the confirm")

	# WHERE IT GOES, asked without going there — see `exit_scene()`.
	_ok(overlay.exit_scene().ends_with("front.tscn"),
		"leaving an offline match goes to `%s` rather than the front screen"
			% overlay.exit_scene())

	# AND GOING THROUGH WITH IT, FOR REAL. This replaces the scene this test is
	# part of, so it is deliberately the LAST thing that happens and everything
	# after it reads `_tree` rather than `get_tree()`.
	overlay._activate()
	GameState.hold("something-else", true)
	overlay._confirm_input({"back": false, "toggle": false, "accept": true})
	_ok(not _tree.paused,
		"leaving a match left the tree stopped — the next scene would never run its first frame")
	_ok(not overlay._open, "leaving a match left the settings screen open")
	print("  QUIT TO MENU: guarded, escapable, and releases every hold on the way out")
	_done["quit"] = true


func _find_player() -> Player:
	for n in _main.find_children("*", "CharacterBody3D", true, false):
		if n is Player:
			return n
	return null


func _find_overlay() -> Node:
	for n in _main.find_children("*", "Control", true, false):
		if n.get_script() == OVERLAY:
			return n
	return null
