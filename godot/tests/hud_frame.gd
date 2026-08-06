extends Node3D

## A REAL MATCH, PHOTOGRAPHED. Everything else that shoots the HUD builds one
## widget against a backdrop, which is exactly the setup that cannot answer the
## only question worth asking about HUD LAYOUT: does this piece land on top of
## another one. Layout is a property of the whole screen, so this boots the
## actual scene — `main.tscn`, real map, real players, real scoreboard — and
## takes a picture of it.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/hud_frame.tscn
##   QS_VIEWS=1 ... tests/hud_frame.tscn      # and the single-viewport layout
##
## Windowed. Shots land in user://.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	GameState.reset_match()
	# NO GOVERNOR FOR A PHOTOGRAPH. It holds the frame to its interval by moving the
	# render scale, which means the resolution this shot is taken at would depend on
	# how warm the GPU happened to be — and a look test that is not repeatable is
	# not a test. The tier's own starting scale still applies, so what this
	# photographs is still the configuration the game ships at four viewports.
	Quality.governor_enabled = false
	GameState.human_players = 4
	if OS.has_environment("QS_VIEWS"):
		GameState.human_players = int(OS.get_environment("QS_VIEWS"))
	GameState.team_size = 3
	GameState.map_index = 0
	GameState.mode = GameState.Mode.DEATHMATCH
	add_child(MAIN.instantiate())
	# Let the deploy screens clear and the countdown finish, so the picture is of
	# a match being PLAYED rather than of four buy screens.
	await get_tree().create_timer(1.5).timeout
	# Nobody is pressing A, so deploy them directly. `_respawn` is what the
	# deploy button reaches anyway, whichever screen is up.
	#
	# On an AUTHORED CLASS rather than the bare starter build, because the point
	# of this shot is the HUD and the starter carries no gadgets at all — so the
	# ability gauges, which are most of the bottom right, would not be in the
	# picture. A legionary trooper has all three slots filled.
	for c in GameState.combatants:
		if c is Player and not c.is_alive():
			c.pending = Loadout.faction_build(c.team * 4)
			c._respawn()
	await get_tree().create_timer(0.6).timeout
	GameState.match_live = true
	# Light one side up on the other's scan, which is the state the minimap was
	# built for and the one nobody would otherwise photograph.
	for c in GameState.combatants:
		if is_instance_valid(c) and c.team == 1 and c.is_alive():
			GameState.mark_scanned(c, 0, 30.0)
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var tag := "%dup" % GameState.human_players
	var img := get_viewport().get_texture().get_image()
	var path := "user://hud_frame_%s.png" % tag
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
