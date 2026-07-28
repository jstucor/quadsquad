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
## Measured on an Intel UHD 620, 4 viewports, 12 combatants, Kashyyyk:
##   off 12.03 ms | 2x 13.87 | 4x 14.32 | 8x 16.78   (budget is 16.7)
## 2x ships (Main.MSAA). 4x costs almost nothing over it on that GPU.

const MAIN := preload("res://scenes/main.tscn")
const SETTLE_FRAMES := 90     # bots deploy, shadow splits warm up
const SAMPLE_FRAMES := 240
const BUDGET_MS := 1000.0 / 60.0

## The heaviest thing the game can be asked to draw: a full couch on the biggest
## forest map. If this fits, everything else does.
const MAP := "KASHYYYK"


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	GameState.human_players = 4
	GameState.team_size = 3
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = _map_index(MAP)
	# QS_UNIVERSE picks the setting, because they are not the same scene to draw:
	# an Astartes carries pauldrons, a power pack, an aquila, gauntlets, greaves
	# and thigh plates that a clone trooper does not, and every one of those is a
	# draw call twelve bodies and four viewports deep.
	if OS.has_environment("QS_UNIVERSE"):
		GameState.universe = int(OS.get_environment("QS_UNIVERSE"))
		GameState.class_mode = GameState.ClassMode.FACTION

	var main: Node = MAIN.instantiate()
	add_child(main)
	await _frames(SETTLE_FRAMES)
	var views := main.find_children("*", "SubViewport", true, false)

	var levels := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
		Viewport.MSAA_8X]
	if OS.has_environment("QS_MSAA"):
		levels = [int(OS.get_environment("QS_MSAA"))]
	print("\n== render cost: %d viewports, %s, %s ==" % [GameState.human_players, MAP,
		Loadout.UNIVERSES[GameState.universe]["name"]])
	for msaa in levels:
		for v in views:
			v.msaa_3d = msaa
		await _frames(30)                      # let the resize settle
		var ms := await _measure()
		print("  msaa %-9s %6.2f ms/frame   %3.0f fps   %s" % [
			_msaa_name(msaa), ms, 1000.0 / ms,
			"OK" if ms <= BUDGET_MS else "OVER BUDGET"])
	get_tree().quit()


## Wall clock over a fixed number of frames. Deliberately not the engine's
## TIME_PROCESS monitor: the project already has it recorded that those swing
## 14-27 ms across identical runs, which is wider than anything worth measuring.
func _measure() -> float:
	var t0 := Time.get_ticks_usec()
	await _frames(SAMPLE_FRAMES)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(SAMPLE_FRAMES)


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
