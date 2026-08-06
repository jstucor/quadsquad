extends Node
## THE NEW FRONT END, PHOTOGRAPHED — sign-in and playlist, in the states they are
## actually read in.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/frontend_look.tscn
##
## WHY THESE HAVE TO BE PICTURES. Everything `tests/playlist.tscn` asserts is
## behaviour, and every one of these screens can pass all of it while being
## unusable: four seat cards that fit at one player and run off the edge at four,
## a three-column layout whose middle column is taller than the panel holding it,
## a queue column that says nothing when it is empty. Layout is a property of the
## WHOLE SCREEN and none of it has a number.
##
## THE STATES ARE CHOSEN AS THE ONES THAT DIFFER, not as a gallery. A sign-in
## with nobody in it and a sign-in with everybody in it are two different screens
## made of the same controls, and the interesting one is the MIXED case in the
## middle — one player still reading the account list while another is typing a
## name — because that is the state the card sizes have to survive and it is the
## only one where all three card layouts are on screen at once.
##
## It writes accounts, so it snapshots the real config and puts it back — the same
## warning `controls_inherit` carries and for the same reason.

const SIGN_IN := preload("res://scenes/sign_in.tscn")
const PLAYLIST := preload("res://scenes/playlist.tscn")
const FACTIONS := preload("res://scenes/faction_select.tscn")
const ACCOUNTS_CFG := "user://accounts.cfg"
const CONTROLS_CFG := "user://controls.cfg"
## The playlist screen SAVES as it changes and LOADS when it opens, so this test
## both writes the player's setup and photographs whatever they last set up.
## Snapshotted like the other two, and a known one is written for the shots — a
## screenshot suite whose contents depend on what the machine last played is a
## suite whose pictures cannot be compared between runs.
const SETUP_CFG := "user://setup.cfg"


func _ready() -> void:
	var accounts_backup := _snapshot(ACCOUNTS_CFG)
	var controls_backup := _snapshot(CONTROLS_CFG)
	var setup_backup := _snapshot(SETUP_CFG)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETUP_CFG))
	_seed_accounts()
	_seed_settings()

	await _sign_in_shots()
	await _playlist_shots()
	await _faction_shots()

	_restore(ACCOUNTS_CFG, accounts_backup)
	_restore(CONTROLS_CFG, controls_backup)
	_restore(SETUP_CFG, setup_backup)
	Accounts._forget()
	print("front end rendered: user://signin_*.png, user://playlist_*.png")
	get_tree().quit()


## A machine that has been played on. An empty account list is the least
## interesting version of this screen and the one every other test already sees.
func _seed_accounts() -> void:
	Accounts._forget()
	for name in Accounts.names():
		Accounts.remove(name)
	for row in [["JACOB", 214, 143, 31], ["MARLOW", 88, 96, 12],
			["PIP", 402, 190, 55], ["SAM", 9, 21, 3]]:
		Accounts.create(str(row[0]))
		Accounts.record_match(str(row[0]),
			{"kills": int(row[1]), "deaths": int(row[2]), "headshots": int(row[3]),
			"best_streak": 9}, true)
		# ...and a few more matches, so the card's career line is a real one.
		for i in 6:
			Accounts.record_match(str(row[0]), {"kills": 12, "deaths": 9}, i % 3 == 0)


## A setup worth photographing: every row of the settings panel showing something
## other than its default, so the picture proves they are being READ rather than
## merely drawn.
func _seed_settings() -> void:
	GameState.team_size = 8
	GameState.ai_skill = 2
	GameState.aim_assist = GameState.AimAssist.EVERYONE
	GameState.ttk = GameState.Ttk.REALISTIC
	GameState.class_mode = GameState.ClassMode.FACTION
	GameState.friendly_fire = false
	GameState.time_of_day = GameState.TimeOfDay.NIGHT
	GameState.team_tint[1] = 3
	GameState.refresh_sides()
	GameState.save_setup()


func _sign_in_shots() -> void:
	GameState.human_players = 4
	GameState.clear_seats()
	var screen: Control = SIGN_IN.instantiate()
	add_child(screen)
	await _frames(6)
	await _grab("signin_empty")

	# THE MIXED CASE: one signed in, one reading the list, one typing a name, one
	# seat still empty. Every card layout the screen has, at once.
	screen._take_seat(0)
	screen._choose(0, "JACOB")
	screen._take_seat(1)
	screen._seats[1]["row"] = 2
	screen._take_seat(2)
	screen._choose(2, screen.NEW_ROW)
	screen._seats[2]["name"] = "NEW"
	screen._seats[2]["cursor"] = 3
	await _frames(4)
	await _grab("signin_mixed")

	screen._choose(1, "PIP")
	screen._seats[2]["state"] = screen.State.READY
	screen._seats[2]["name"] = "SAM"
	screen._take_seat(3)
	screen._choose(3, "MARLOW")
	await _frames(4)
	await _grab("signin_ready")
	screen.queue_free()
	await _frames(2)


func _playlist_shots() -> void:
	GameState.playlist.clear()
	GameState.playlist_index = -1
	GameState.human_players = 4
	GameState.player_devices = [0, 1, 2, 3]
	GameState.player_accounts = ["JACOB", "PIP", "SAM", "MARLOW"]
	var screen: Control = PLAYLIST.instantiate()
	add_child(screen)
	await _frames(6)
	await _grab("playlist_empty")

	# THE SETTINGS, which are behind a button now. Shot open over the screen they
	# are modal to, because the question a picture answers here is whether the
	# panel reads as being ON TOP of the columns rather than as part of them.
	screen._open_settings()
	await _frames(4)
	await _grab("playlist_settings")
	# ...and the top bar scrolled to ANOTHER mode's settings, which is the state
	# that says the bar is a selector rather than a heading.
	screen._step_editing_mode(1)
	await _frames(4)
	await _grab("playlist_mode_settings")
	screen._step_editing_mode(-1)
	await _frames(3)
	screen._close_settings()
	await _frames(3)

	# Step two and step three, which are the same column showing entirely
	# different things — and the faction-set list is the longest of the three.
	screen._show_step(screen.Step.MODE)
	await _frames(3)
	await _grab("playlist_mode")

	# ...and a night's play queued, which is what the right column is FOR and the
	# only state that shows whether it stays readable with something in it.
	GameState.map_index = 10
	GameState.mode = GameState.Mode.CONQUEST
	GameState.team_faction[0] = 0
	GameState.team_faction[1] = 1
	screen._add_round()
	GameState.map_index = 4
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.team_faction[0] = 2
	GameState.team_faction[1] = 3
	screen._add_round()
	GameState.map_index = 13
	GameState.mode = GameState.Mode.ROYALE
	screen._add_round()
	GameState.map_index = 9
	GameState.mode = GameState.Mode.MASSIVE
	GameState.team_faction[0] = 4
	GameState.team_faction[1] = 8
	screen._add_round()
	screen._show_step(screen.Step.MAP)
	await _frames(4)
	await _grab("playlist_queued")
	screen.queue_free()
	await _frames(2)


## WHO IS FIGHTING, asked once before every round. Shot because it is the last
## screen between the queue and the match and the only one whose job is a single
## question — if it does not read at a glance it is a speed bump.
func _faction_shots() -> void:
	GameState.team_count = 2
	GameState.free_for_all = false
	var screen: Control = FACTIONS.instantiate()
	add_child(screen)
	await _frames(6)
	await _grab("faction_select")
	screen.queue_free()
	await _frames(2)


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
