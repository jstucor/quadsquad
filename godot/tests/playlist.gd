extends Node
## THE FRONT-END FLOW: sign in, build a playlist, play it through.
##
##   godot --headless --path godot tests/playlist.tscn
##
## Three screens' worth of state and one piece of match plumbing, and almost
## every one of these fails SILENTLY when it breaks — which is why they are
## assertions rather than something to look at:
##
##   * A SEAT THAT DOES NOT REACH THE MATCH still plays perfectly. It just plays
##     with the wrong controller, which reads as "player 3's pad is broken".
##   * A PLAYLIST ENTRY THAT SHARES ITS ARRAYS looks completely right in the
##     queue column and then fields the wrong side in round one, because round
##     three re-wrote the sides underneath it.
##   * A SETTING MISSING FROM `MATCH_KEYS` is invisible in every screenshot: the
##     round plays with whatever the LAST round used, which looks like the screen
##     not having saved the choice.
##   * A CAREER STAT is one addition in one function, and a mistake there stays
##     at zero forever with nothing anywhere to say so.
##
## THE SCREENS ARE DRIVEN THROUGH THEIR OWN CONTROLS where there is one to press
## (a map row is a Button and is pressed by its signal, the way `front_look` does
## it) and through the seat functions where the input is a raw joypad button no
## headless run has. What is never done is reaching past a screen to write the
## thing it is supposed to produce — `commit_seats` and `play_destination` exist
## so the PRODUCT can be asserted without performing the navigation that follows
## it, which would free this test mid-run.

const SIGN_IN := preload("res://scenes/sign_in.tscn")
const PLAYLIST := preload("res://scenes/playlist.tscn")

const ACCOUNTS_CFG := "user://accounts.cfg"
const CONTROLS_CFG := "user://controls.cfg"
## ...and the SETUP, which this test both reads (the screens load it on open) and
## writes (every change saves). Snapshotted for the same reason as the other two,
## and with a sharper edge: a test that leaves a saved setup behind changes what
## the NEXT run of itself does, which is a suite that passes once and then starts
## failing for reasons nothing prints.
const SETUP_CFG := "user://setup.cfg"

var _fails: Array[String] = []
var _sections: Array[String] = []
var _accounts_backup := ""
var _controls_backup := ""
var _setup_backup := ""


func _ready() -> void:
	_accounts_backup = _snapshot(ACCOUNTS_CFG)
	_controls_backup = _snapshot(CONTROLS_CFG)
	_setup_backup = _snapshot(SETUP_CFG)
	_forget_setup()

	await _seats()
	await _sign_in_screen()
	_capture_and_apply()
	_queue()
	await _real_input()
	_planet_maps()
	_mode_settings()
	await _class_source()
	_persistence()
	await _playlist_screen()
	await _boot()
	_career()

	_restore(ACCOUNTS_CFG, _accounts_backup)
	_restore(CONTROLS_CFG, _controls_backup)
	_restore(SETUP_CFG, _setup_backup)
	Accounts._forget()
	# EVERY SECTION SIGNS OFF AT ITS OWN END, and the run fails if one did not
	# finish — a GDScript error aborts the function it happens in and takes the
	# rest of that section with it silently (house rule 6), so a test that only
	# counted failures would report success having checked nothing.
	var expected := ["seats", "sign-in", "input", "capture", "queue", "planets",
		"mode-settings", "class-source", "persistence", "screen", "boot", "career"]
	for s in expected:
		if not _sections.has(s):
			_fails.append("section `%s` never finished — it aborted part way" % s)
	print("\n==== %s ====" % ("THE FRONT END HOLDS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


## WHICH CONTROLLER DRIVES WHICH BODY. The fallback matters as much as the
## answer: tests, the lobby and `-- --debug` never pass through a sign-in, and
## every one of them has to keep dealing pads out the way it always did.
func _seats() -> void:
	print("== seats ==")
	GameState.clear_seats()
	GameState.debug_kbm = false
	_ok(GameState.device_for_player(0) == 0 and GameState.device_for_player(3) == 3,
		"with no sign-in, P1..P4 are still pads 0..3")
	_ok(GameState.account_for(0) == "", "...and nobody is signed in")
	GameState.debug_kbm = true
	_ok(GameState.device_for_player(0) == -1,
		"the debug flag still puts player 1 on the keyboard")
	GameState.debug_kbm = false

	# Somebody picked up pad 3 and somebody else the keyboard, which is exactly
	# the arrangement the old arithmetic could not express.
	GameState.player_devices = [2, -1]
	GameState.player_accounts = ["ZARA", "KIT"]
	_ok(GameState.device_for_player(0) == 2 and GameState.device_for_player(1) == -1,
		"a claimed seat drives the device it claimed")
	_ok(GameState.player_name(0) == "ZARA", "and the score table calls them by name")
	_ok(GameState.player_name(5) == "PLAYER 6",
		"a seat nobody signed into keeps its tag")
	GameState.clear_seats()
	_sections.append("seats")


## The sign-in screen's state machine. The START press itself is a raw joypad
## button, which a headless run has none of, so the seat is claimed through the
## same function that press calls — everything after it is the real path.
func _sign_in_screen() -> void:
	print("\n== the sign-in screen ==")
	_wipe_accounts()
	GameState.human_players = 2
	var screen: Control = SIGN_IN.instantiate()
	add_child(screen)
	await get_tree().process_frame

	_ok(screen._seats.size() == 2, "one card per player at the couch")
	_ok(not screen._all_ready(), "nobody is ready before anybody has signed in")

	screen._take_seat(1)      # somebody presses START on pad 2
	_ok(screen._seats[0]["claimed"] and int(screen._seats[0]["device"]) == 1,
		"the pad that pressed is the pad that takes the seat")
	_ok(int(screen._seats[0]["state"]) == screen.State.PICKING,
		"...and lands on the account list")

	# A NEW ACCOUNT, typed the way a pad types one: the last row of the list is
	# NEW, then letters onto the carousel.
	var rows: Array = screen._rows(0)
	_ok(str(rows[rows.size() - 1]) == screen.NEW_ROW,
		"the NEW ACCOUNT row is always last, so the list never moves under you")
	screen._choose(0, screen.NEW_ROW)
	_ok(int(screen._seats[0]["state"]) == screen.State.NAMING, "choosing NEW starts a name")
	# Up adds an A; up again steps to B. Right moves along and the next push adds
	# a second letter — which is the whole gesture, and it is worth asserting
	# because a carousel that cannot ADD a letter can only ever spell "A".
	screen._type(0, Vector2i.UP, false, false)
	screen._type(0, Vector2i.UP, false, false)
	screen._type(0, Vector2i.RIGHT, false, false)
	screen._type(0, Vector2i.UP, false, false)
	_ok(str(screen._seats[0]["name"]) == "BA",
		"the carousel spells: got `%s`" % screen._seats[0]["name"])
	screen._type(0, Vector2i.ZERO, true, false)     # A confirms
	_ok(int(screen._seats[0]["state"]) == screen.State.READY, "confirming signs them in")
	_ok(Accounts.exists("BA"), "...and the account is real from that moment")

	# THE SECOND PLAYER CANNOT BE THE FIRST ONE. A taken row is refused rather
	# than hidden, and refusing has to mean the seat does not move.
	screen._take_seat(0)
	screen._choose(1, "BA")
	_ok(int(screen._seats[1]["state"]) != screen.State.READY,
		"two seats cannot sign in as one account")
	Accounts.create("CO")
	screen._rebuild_all_rows()
	screen._choose(1, "CO")
	_ok(int(screen._seats[1]["state"]) == screen.State.READY, "a free account is taken")
	_ok(screen._all_ready(), "with everybody in, the screen is ready to continue")

	screen.commit_seats()
	_ok(GameState.player_accounts.size() == 2 and GameState.player_devices.size() == 2,
		"the seating reaches GameState, one entry per seat")
	_ok(GameState.account_for(0) == "BA" and GameState.account_for(1) == "CO",
		"...in seat order")
	_ok(GameState.device_for_player(0) == 1 and GameState.device_for_player(1) == 0,
		"...with the devices they actually claimed, not their seat numbers")

	# BACKING OUT of a ready seat goes to the account list, not out of the seat:
	# changing your mind about WHICH ACCOUNT is far commoner than changing your
	# mind about which controller is in your hands.
	screen._seats[0]["state"] = screen.State.PICKING
	_ok(not screen._all_ready(), "one player stepping back un-readies the screen")
	screen.queue_free()
	await get_tree().process_frame
	_sections.append("sign-in")


## THE SAME SCREEN, DRIVEN BY ACTUAL INPUT. Everything in the section above calls
## the functions a button press calls; this one presses the button.
##
## It matters because the part not covered by calling `_take_seat` directly is
## the part most likely to be wrong, and it has been wrong once already: the
## LATCHES. Claiming a seat, choosing a row and continuing are three edges read
## from two buttons by two different owners (`_claim_seats` and `_poll`), and a
## level read where an edge was meant is the difference between "press START" and
## "press START and immediately sign in as whatever the list opened on".
##
## The keyboard is the device used, because a headless run has no joypads to
## press — and `Input.parse_input_event` genuinely moves the state that
## `Input.is_key_pressed` reads, so what runs here is the shipping poll loop with
## nothing stubbed out.
func _real_input() -> void:
	print("\n== driven by real input ==")
	_wipe_accounts()
	Accounts.create("REAL")
	GameState.human_players = 1
	GameState.clear_seats()

	# HELD FROM BEFORE THE SCREEN EXISTED MUST NOT CLAIM, which is why the latch
	# is armed HELD rather than released. The button is pushed down FIRST and the
	# screen built under it — a player arriving here still holding the button
	# that got them here is the ordinary case, not a corner one.
	await _key(KEY_ENTER, true)
	var screen: Control = SIGN_IN.instantiate()
	add_child(screen)
	await _frames(3)
	_ok(not screen._seats[0]["claimed"],
		"a button already down when the screen opens does not claim a seat")

	await _key(KEY_ENTER, false)
	await _frames(2)
	await _key(KEY_ENTER, true)
	await _frames(2)
	await _key(KEY_ENTER, false)
	await _frames(1)
	_ok(screen._seats[0]["claimed"], "...but pressing it here does")
	_ok(int(screen._seats[0]["device"]) == -1,
		"...for the device that pressed it (the keyboard here)")
	_ok(int(screen._seats[0]["state"]) == screen.State.PICKING,
		"...landing on the account list")

	# A SEAT THAT SIGNS ITSELF IN IS THE FAULT THIS ARRANGEMENT EXISTS TO STOP.
	# The claim press must not also be read as "choose whatever is under the
	# cursor", which with one account in the list would be silent and instant.
	_ok(int(screen._seats[0]["state"]) != screen.State.READY,
		"the press that claimed the seat did not also pick an account")

	# Now choose one for real: A (space on the keyboard) on the first row.
	await _key(KEY_SPACE, true)
	await _frames(2)
	await _key(KEY_SPACE, false)
	await _frames(2)
	_ok(int(screen._seats[0]["state"]) == screen.State.READY,
		"pressing A signs the seat in as `%s`" % screen._seats[0]["name"])
	_ok(str(screen._seats[0]["name"]) == "REAL", "...the account under the cursor")
	_ok(screen._all_ready(), "and with one player at the couch, that is everybody")

	# B steps back to the list rather than out of the seat.
	await _key(KEY_ESCAPE, true)
	await _frames(2)
	await _key(KEY_ESCAPE, false)
	await _frames(2)
	_ok(int(screen._seats[0]["state"]) == screen.State.PICKING,
		"B from a finished seat goes back to the account list")
	_ok(screen._seats[0]["claimed"], "...and keeps the controller it claimed")
	screen.queue_free()
	await _frames(2)
	_sections.append("input")


## A real key event, pushed through the same path a keyboard pushes one.
func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)
	await get_tree().process_frame


## A PLAYLIST ENTRY IS A WHOLE MATCH, and this is the section that says so. Every
## key in `MATCH_KEYS` is changed away from what it was captured at and then put
## back by `apply_match` — a key missing from one of the two lists shows up here
## and nowhere else in the game.
func _capture_and_apply() -> void:
	print("\n== capture and apply ==")
	GameState.map_index = 10
	GameState.mode = GameState.Mode.CONQUEST
	GameState.ttk = GameState.Ttk.REALISTIC
	GameState.team_size = 8
	GameState.ai_skill = 2
	GameState.aim_assist = GameState.AimAssist.EVERYONE
	GameState.class_mode = GameState.ClassMode.FACTION
	GameState.friendly_fire = false
	GameState.time_of_day = GameState.TimeOfDay.NIGHT
	GameState.planet = 1
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.team_faction[0] = 4
	GameState.team_faction[1] = 5
	GameState.team_tint[1] = 3
	GameState.score_targets[GameState.Mode.CONQUEST] = 400
	var entry := GameState.capture_match()

	# Everything moved, including the two arrays and the mode-keyed threshold.
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.ttk = GameState.Ttk.HIGH
	GameState.team_size = 2
	GameState.ai_skill = 0
	GameState.aim_assist = GameState.AimAssist.OFF
	GameState.class_mode = GameState.ClassMode.CUSTOM
	GameState.friendly_fire = true
	GameState.time_of_day = GameState.TimeOfDay.DAY
	GameState.planet = GameState.RANDOM_PLANET
	GameState.team_faction[0] = 0
	GameState.team_faction[1] = 1
	GameState.team_tint[1] = 0
	GameState.score_targets[GameState.Mode.CONQUEST] = 75

	GameState.apply_match(entry)
	for key in GameState.MATCH_KEYS:
		_ok(GameState.get(key) == entry[key],
			"`%s` came back as it was queued (%s)" % [key, entry[key]])
	_ok(GameState.team_faction[0] == 4 and GameState.team_faction[1] == 5,
		"the sides came back")
	_ok(GameState.team_tint[1] == 3, "...and the colour they were given")
	_ok(GameState.score_limit() == 400, "...and what the round is played to")
	# The names and chips are DERIVED from the pair above rather than stored, so
	# applying an entry has to re-derive them or the scoreboard names last
	# round's sides.
	_ok(GameState.team_names[0] == str(Loadout.faction(4)["name"]),
		"applying an entry re-derives who the side IS, not just its index")
	_sections.append("capture")


## The queue itself: entries are independent, and it walks and ends.
func _queue() -> void:
	print("\n== the queue ==")
	GameState.playlist.clear()
	GameState.playlist_index = -1
	_ok(not GameState.playlist_begin(), "an empty playlist cannot be started")

	GameState.map_index = 1
	GameState.team_faction[0] = 0
	var first := GameState.capture_match()
	GameState.playlist.append(first)
	# Round two is set up completely differently, which is the entire difference
	# between a playlist and a map rotation.
	GameState.map_index = 5
	GameState.team_faction[0] = 6
	GameState.playlist.append(GameState.capture_match())
	_ok(int(first["map_index"]) == 1,
		"queuing a second round did not rewrite the first one's map")
	_ok(int((first["team_faction"] as Array)[0]) == 0,
		"...nor its sides: the arrays are copied, not shared")

	_ok(GameState.playlist_begin(), "the queue starts")
	_ok(GameState.playlist_active() and GameState.map_index == 1,
		"...on round one, with round one's settings applied")
	_ok(GameState.playlist_advance() and GameState.map_index == 5,
		"and advances onto round two")
	_ok(not GameState.playlist_advance(),
		"a finished playlist says so rather than looping forever")
	_ok(not GameState.playlist_active(), "...and stops being active")
	_sections.append("queue")


## EVERY GENERATED WORLD IS ITS OWN MAP ROW, and this is house rule 7: a table
## indexed by an enum must be checked against that enum, by NAME and not just by
## length. The rows carry their planet as a literal integer (naming
## `PlanetMap.Planet` from `game_state.gd` is a parse-time cycle), so nothing but
## this test stands between a row and the wrong world — and a row pointing one
## planet off would build a perfectly good map with somebody else's name on it,
## which no error and no screenshot would ever report.
func _planet_maps() -> void:
	print("\n== a planet is a map ==")
	var found := {}
	for i in GameState.MAPS.size():
		var row: Dictionary = GameState.MAPS[i]
		if not row.has("planet"):
			continue
		var planet := int(row["planet"])
		_ok(not found.has(planet), "planet %d has exactly one map row" % planet)
		found[planet] = i
		_ok(str(row["name"]).begins_with(str(PlanetMap.PLANET_NAMES[planet])),
			"row `%s` names planet %d, which is %s"
				% [row["name"], planet, PlanetMap.PLANET_NAMES[planet]])
		_ok(bool(row.get("procedural", false)), "...and is generated ground")
	_ok(found.size() == PlanetMap.PLANET_NAMES.size(),
		"every world has a row: %d of %d" % [found.size(), PlanetMap.PLANET_NAMES.size()])

	# What the map SAYS is what the generator BUILDS.
	for planet in found:
		GameState.map_index = int(found[planet])
		_ok(GameState.map_planet() == planet, "the row states its planet")
		_ok(GameState.chosen_planet() == planet,
			"...and that is the world the generator is asked for")
		_ok(not GameState.map_blurb().is_empty(),
			"...and it describes itself: `%s`" % GameState.map_blurb())
	# The ROLLED row still rolls, and the PLANET setting still steers that one —
	# it is the only row left that has anything to steer.
	GameState.map_index = GameState.MAPS.find(GameState.MAPS.filter(
		func(r: Dictionary) -> bool:
			return bool(r.get("procedural", false)) and not r.has("planet"))[0])
	_ok(GameState.map_planet() < 0, "the RANDOM WORLD row names no planet")
	GameState.planet = 2
	_ok(GameState.chosen_planet() == 2, "...so the PLANET setting still decides it")
	GameState.planet = GameState.RANDOM_PLANET

	# MASSIVE needs generated ground, not a ROLLED one — it must not throw away
	# the world somebody chose.
	GameState.map_index = int(found[PlanetMap.Planet.HOTH])
	_ok(GameState.procedural_map_index() == int(found[PlanetMap.Planet.HOTH]),
		"locking a massive battle to generated ground keeps the planet you picked")
	GameState.map_index = 0
	_ok(GameState.MAPS[GameState.procedural_map_index()].get("procedural", false),
		"...and from a hand-laid map it still finds one")
	_sections.append("planets")


## SETTINGS THAT BELONG TO A MODE ARE STORED PER MODE, which is the half that
## makes nesting them under the mode true rather than decorative. Fifty a side is
## the whole point of MASSIVE and absurd in Conquest; with one shared box the
## answer to "how many players" was whatever the last mode you looked at needed,
## and the game already carried a patch for the worst case of it.
func _mode_settings() -> void:
	print("\n== a setting that belongs to a mode ==")
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.team_size = 4
	GameState.score_targets[GameState.Mode.DEATHMATCH] = 50
	GameState.mode = GameState.Mode.CONQUEST
	GameState.team_size = 12
	GameState.score_targets[GameState.Mode.CONQUEST] = 400
	_ok(GameState.team_size == 12, "conquest keeps its own roster size")

	GameState.mode = GameState.Mode.DEATHMATCH
	_ok(GameState.team_size == 4,
		"...and going back to deathmatch restores ITS size, not the last one used")
	_ok(GameState.score_limit() == 50, "the victory threshold follows the same way")
	GameState.mode = GameState.Mode.CONQUEST
	_ok(GameState.team_size == 12 and GameState.score_limit() == 400,
		"and back again, both of conquest's numbers are still there")

	# THE ONE THIS FIXES OUTRIGHT. Leaving MASSIVE used to leave `team_size` at
	# fifty — over the ordinary ceiling, with no dropdown item matching it — and
	# `menu.gd` had to walk it back onto the ladder afterwards.
	GameState.mode = GameState.Mode.MASSIVE
	_ok(GameState.team_size == GameState.MASSIVE_DEFAULT,
		"massive opens at fifty a side, which is the whole point of it")
	GameState.mode = GameState.Mode.DEATHMATCH
	_ok(GameState.team_size <= GameState.MAX_TEAM_SIZE,
		"leaving massive cannot leave an ordinary mode over its own ceiling")
	_ok(GameState.TEAM_SIZES.has(GameState.team_size),
		"...and lands on a size the ladder actually offers (%d)" % GameState.team_size)
	_sections.append("mode-settings")


## WHERE THE GEAR COMES FROM, AND THE BUG THAT MADE THIS SECTION EXIST.
##
## Reported from play: choose FACTION ROSTERS, build a round, deploy — and get
## the CUSTOM buy screen. The MODE step of building a round wrote
## `default_class_mode` straight into the setting, so every round queued after
## choosing put it back. It was invisible: the setting lives behind a button now,
## so there was nothing on screen to watch being undone, and the only symptom was
## the wrong screen appearing one scene later.
##
## Walked through the real screen, in the order a player does it, because that
## ORDER is the bug — the setting and the thing that overwrote it were both
## individually correct.
func _class_source() -> void:
	print("\n== where the gear comes from ==")
	_forget_setup()
	GameState.human_players = 2
	GameState.class_mode_chosen = false
	var screen: Control = PLAYLIST.instantiate()
	add_child(screen)
	await get_tree().process_frame

	# A mode still SEEDS it while nobody has said otherwise — that part was right
	# and has to stay right.
	screen._pick_mode(GameState.Mode.CONQUEST)
	_ok(GameState.faction_classes(), "Conquest still opens on its faction rosters")
	screen._pick_mode(GameState.Mode.DEATHMATCH)
	_ok(GameState.class_mode == GameState.ClassMode.CUSTOM,
		"...and deathmatch still opens on the buy screen")

	# Now the player says otherwise, exactly as the CHARACTERS row does.
	GameState.choose_class_mode(GameState.ClassMode.FACTION)
	_ok(GameState.faction_classes(), "choosing FACTION ROSTERS takes")

	# ...and then builds a round. THIS is what used to undo it.
	screen._show_step(screen.Step.MAP)
	(screen._left_focus[0] as Button).emit_signal("pressed")
	await get_tree().process_frame
	(screen._left_focus[GameState.Mode.DEATHMATCH] as Button).emit_signal("pressed")
	await get_tree().process_frame
	_ok(GameState.faction_classes(),
		"picking a mode while building a round does NOT put it back to custom")
	(screen._left_focus[0] as Button).emit_signal("pressed")
	await get_tree().process_frame
	_ok(not GameState.playlist.is_empty(), "the round queued")
	if not GameState.playlist.is_empty():
		var entry: Dictionary = GameState.playlist[0]
		_ok(int(entry["class_mode"]) == GameState.ClassMode.FACTION,
			"...and it is QUEUED with the faction rosters, which is what deploys")

	# And the choice survives the round trip through disk, or it is un-remembered
	# on the next launch, which is the same bug one session further out.
	GameState.save_setup()
	GameState.class_mode = GameState.ClassMode.CUSTOM
	GameState.class_mode_chosen = false
	GameState.load_setup()
	_ok(GameState.faction_classes() and GameState.class_mode_chosen,
		"the choice is still there after a save and a load")
	screen.queue_free()
	await get_tree().process_frame
	GameState.class_mode_chosen = false
	_forget_setup()
	_sections.append("class-source")


## THE SETUP SURVIVES THE SESSION. Everything behind the settings button plus the
## queue itself, written as it changes and read back at launch.
func _persistence() -> void:
	print("\n== saved between sessions ==")
	_forget_setup()
	GameState.map_index = 3
	GameState.mode = GameState.Mode.ZONES
	GameState.ttk = GameState.Ttk.LOW
	GameState.team_size = 6
	GameState.ai_skill = 2
	GameState.friendly_fire = false
	GameState.team_tint[0] = 4
	GameState.playlist.append(GameState.capture_match())
	GameState.map_index = 7
	GameState.playlist.append(GameState.capture_match())
	GameState.save_setup()

	# Everything moves, as a fresh launch's defaults would have it...
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.ttk = GameState.Ttk.MEDIUM
	GameState.team_size = 2
	GameState.ai_skill = 0
	GameState.friendly_fire = true
	GameState.team_tint[0] = 0
	GameState.playlist.clear()
	# ...and comes back.
	GameState.load_setup()
	_ok(GameState.map_index == 7 and GameState.mode == GameState.Mode.ZONES,
		"the map and mode last set up come back")
	_ok(GameState.ttk == GameState.Ttk.LOW and GameState.team_size == 6
			and GameState.ai_skill == 2 and not GameState.friendly_fire,
		"...and every setting behind the SETTINGS button")
	_ok(GameState.team_tint[0] == 4, "...including what colour each side wears")
	_ok(GameState.playlist.size() == 2, "the QUEUE comes back too, in order")
	_ok(int(GameState.playlist[0]["map_index"]) == 3,
		"...with each round's own configuration intact")
	_ok(GameState.playlist_index == -1,
		"a restored queue is not mid-play, whatever the session that saved it was doing")

	# A CONFIG FROM ANOTHER BUILD MUST NOT TAKE THE GAME DOWN. The roster only
	# ever grows, so a stored map_index is meaningful against the roster it was
	# stored from and against nothing else — and an out-of-range index would abort
	# whatever function read it rather than merely picking the wrong map.
	var stale := GameState.capture_match()
	stale["map_index"] = 9999
	stale["mode"] = 42
	stale["team_count"] = 17
	GameState.apply_match(stale)
	_ok(GameState.map_index < GameState.MAPS.size(), "a stale map index is clamped, not fatal")
	_ok(GameState.mode < GameState.MODE_NAMES.size(), "...and a mode that no longer exists")
	_ok(GameState.team_count <= GameState.MAX_TEAMS, "...and a side count past the ceiling")
	_forget_setup()
	_sections.append("persistence")


## The screen that builds it, driven through its own buttons.
func _playlist_screen() -> void:
	print("\n== the playlist screen ==")
	GameState.playlist.clear()
	GameState.playlist_index = -1
	GameState.human_players = 2
	var screen: Control = PLAYLIST.instantiate()
	add_child(screen)
	await get_tree().process_frame

	_ok(screen._step == screen.Step.MAP, "it opens on the map, which is step one")
	_ok(screen._start.disabled, "and cannot be played with nothing queued")

	# THE SETTINGS ARE BEHIND A BUTTON, and the two things that matter about a
	# modal are that it is CLOSED to start with and that it can be closed again.
	# A panel that opens over the screen and cannot be dismissed is the same
	# failure as a rebind listen with no escape.
	_ok(not screen._overlay.visible, "the settings panel starts closed")
	_ok(screen._settings_line != null and not screen._settings_line.text.is_empty(),
		"...and the screen still SAYS what they are: `%s`" % screen._settings_line.text)
	screen._open_settings()
	await get_tree().process_frame
	_ok(screen._overlay.visible, "the button opens it")
	_ok(screen.get_viewport().gui_get_focus_owner() != null
			and screen._mid_focus.has(screen.get_viewport().gui_get_focus_owner()),
		"...and the highlight moves inside it, which on a pad is the only cursor")
	# THE TOP BAR PICKS WHOSE SETTINGS THESE ARE. It opens on the mode being
	# queued, scrolls through the others, and does NOT change the round — which is
	# the whole point of the settings being stored per mode.
	_ok(screen._editing_mode == GameState.mode,
		"the settings open on the mode the round is in")
	_ok(screen._mode_btn.text.contains(str(GameState.MODE_NAMES[GameState.mode])),
		"...and the top bar says which: `%s`" % screen._mode_btn.text)
	var was_mode: int = GameState.mode
	screen._step_editing_mode(1)
	await get_tree().process_frame
	_ok(screen._editing_mode != was_mode, "it scrolls to another mode's settings")
	_ok(GameState.mode == was_mode,
		"...without changing the round being built, which is a different question")
	# ...and editing that mode writes THAT mode's row, not the live one.
	var other: int = screen._editing_mode
	var before: int = GameState.mode_size(was_mode)
	GameState.set_mode_size(other, 8)
	_ok(GameState.mode_size(other) == 8, "editing the scrolled-to mode takes")
	_ok(GameState.mode_size(was_mode) == before,
		"...and leaves the mode you are queuing alone")
	screen._editing_mode = was_mode

	screen._close_settings()
	await get_tree().process_frame
	_ok(not screen._overlay.visible, "DONE closes it")
	_ok(screen.get_viewport().gui_get_focus_owner() == screen._settings_btn,
		"...and puts the highlight back on the button that opened it")
	_ok(screen._left_focus.size() == GameState.MAPS.size(),
		"every map is offered: %d rows for %d maps"
			% [screen._left_focus.size(), GameState.MAPS.size()])

	# Kashyyyk, Conquest, and the first faction set — the three presses that make
	# a round. Each is the button a player would land on, pressed by its signal.
	(screen._left_focus[10] as Button).emit_signal("pressed")
	await get_tree().process_frame
	_ok(screen._step == screen.Step.MODE, "choosing a map moves on to the mode")
	_ok(GameState.map_index == 10, "...and the map is chosen")
	(screen._left_focus[GameState.Mode.CONQUEST] as Button).emit_signal("pressed")
	await get_tree().process_frame
	_ok(GameState.class_mode == GameState.ClassMode.FACTION,
		"...and Conquest seeded its faction rosters")

	# TWO STEPS, NOT THREE: who is fighting is asked once before every round on
	# its own screen now, so choosing the MODE is what queues it.
	_ok(GameState.playlist.size() == 1, "choosing the mode is what queues the round")
	var entry: Dictionary = GameState.playlist[0]
	_ok(int(entry["map_index"]) == 10 and int(entry["mode"]) == GameState.Mode.CONQUEST,
		"the queued round is the one that was built")
	_ok(screen._step == screen.Step.MAP, "and the builder is back at step one for the next")
	_ok(not screen._start.disabled, "with something queued, it can be played")
	_ok(not GameState.match_sides(entry).is_empty(),
		"the queue column can name the sides: `%s`" % GameState.match_sides(entry))
	_ok(GameState.match_label(entry).contains("KASHYYYK"),
		"...and the round: `%s`" % GameState.match_label(entry))

	# A QUEUE YOU CANNOT TAKE FROM is one wrong press away from being rebuilt.
	(screen._right_focus[0] as Button).emit_signal("pressed")
	await get_tree().process_frame
	_ok(GameState.playlist.is_empty(), "a queued round can be removed again")
	_ok(screen._start.disabled, "...and an emptied queue disables PLAY again")

	# WHERE PLAYING GOES, asked without going there.
	GameState.playlist.append(GameState.capture_match())
	GameState.free_for_all = false
	# EVERY round goes through the faction screen first — that is what "once
	# before every game" means, and it is where team select is decided from.
	_ok(screen.play_destination().ends_with("faction_select.tscn"),
		"playing goes through the faction screen")
	screen.queue_free()
	await get_tree().process_frame
	_sections.append("screen")


## A REAL MATCH, TWICE — because everything above is the front end talking to
## itself, and what actually has to happen is that a queued round BOOTS as the
## round it was queued as.
##
## The two rounds are loaded the way a playlist loads them (advance, then build
## Main again) rather than by calling `Main._next_map`, which reloads the CURRENT
## scene — in a test that is this test, so it would free itself and restart on a
## loop. What is asserted is the pair either side of that one line: that round one
## boots on round one's map with round one's mode, and that after advancing, the
## next Main comes up on the next round's entirely different configuration.
func _boot() -> void:
	print("\n== a queued round actually boots ==")
	GameState.clear_seats()
	GameState.playlist.clear()
	GameState.playlist_index = -1
	GameState.human_players = 1
	GameState.team_size = 2
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.chosen_teams = []
	# Round one: Crossfire, deathmatch. Round two: Foundry, zones — a different
	# map AND a different rule set, which is the thing a map rotation cannot do.
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.playlist.append(GameState.capture_match())
	GameState.map_index = 1
	GameState.mode = GameState.Mode.ZONES
	GameState.playlist.append(GameState.capture_match())
	# ...and somebody is sitting at the couch on pad 3, which is what proves the
	# seat reaches the BODY rather than stopping at the menu.
	GameState.player_devices = [2]
	GameState.player_accounts = ["ZARA"]

	GameState.playlist_begin()
	var one := await _boot_round()
	_ok(str(one["map"]).contains("crossfire"),
		"round one booted on its own map: %s" % one["map"])
	_ok(int(one["mode"]) == GameState.Mode.DEATHMATCH, "...under its own rules")
	_ok(int(one["device"]) == 2,
		"...and the player is on the pad they claimed, not on pad 1")

	_ok(GameState.playlist_advance(), "the match ends and the queue moves on")
	var two := await _boot_round()
	_ok(str(two["map"]).contains("foundry"),
		"round two booted on a different map: %s" % two["map"])
	_ok(int(two["mode"]) == GameState.Mode.ZONES,
		"...and a different mode, which a map rotation could never do")
	_ok(not GameState.playlist_advance(), "and after the last round the queue is done")
	GameState.clear_seats()
	GameState.playlist.clear()
	_sections.append("boot")


## Build a real Main, let it settle, and report what came up.
func _boot_round() -> Dictionary:
	var main: Node = preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(40)
	var out := {
		"map": str(main.level.scene_file_path) if main.level != null else "",
		"mode": GameState.mode,
		"device": -99,
	}
	for p in main.find_children("*", "Player", true, false):
		out["device"] = p.input_device
		break
	main.queue_free()
	await _frames(6)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The career: what a match leaves behind on the people who played it.
func _career() -> void:
	print("\n== the career ==")
	_wipe_accounts()
	Accounts.create("WINNER")
	Accounts.create("LOSER")
	GameState.player_devices = [0, 1]
	GameState.player_accounts = ["WINNER", "LOSER"]
	GameState.player_stats.clear()
	var a := GameState.stats_for(0)
	a["kills"] = 9
	a["deaths"] = 2
	a["headshots"] = 3
	a["best_streak"] = 5
	a["team"] = 0
	var b := GameState.stats_for(1)
	b["kills"] = 2
	b["deaths"] = 9
	b["team"] = 1

	GameState.record_results(0)
	var w := Accounts.stats("WINNER")
	var l := Accounts.stats("LOSER")
	print("  winner %s\n  loser  %s" % [w, l])
	_ok(int(w["kills"]) == 9 and int(w["deaths"]) == 2, "the match's kills reach the account")
	_ok(int(w["wins"]) == 1, "the side that won is the account that won")
	_ok(int(l["matches"]) == 1 and int(l["wins"]) == 0,
		"...and the other one is credited a match and no win")

	# A SEAT WITH NO ACCOUNT WRITES NOTHING, which is what keeps every test in
	# this project — all of which boot matches with nobody signed in — from
	# inventing careers on the machine they run on.
	GameState.clear_seats()
	GameState.record_results(0)
	_ok(int(Accounts.stats("WINNER")["matches"]) == 1,
		"a match nobody signed into records nothing")
	_sections.append("career")


# --- harness ------------------------------------------------------------------

func _wipe_accounts() -> void:
	Accounts._forget()
	for name in Accounts.names():
		Accounts.remove(name)
	Accounts.ensure_loaded()


## Start the setup sections from nothing, without touching the player's file
## until something saves — which the screens then do.
func _forget_setup() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETUP_CFG))
	GameState.playlist.clear()
	GameState.playlist_index = -1


func _snapshot(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _restore(path: String, contents: String) -> void:
	if contents == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(contents)
		f.close()


func _ok(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)
