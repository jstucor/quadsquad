extends Node

## Renders the CONTROLS screen, which is the tightest layout in the game: every
## rebindable row plus the chrome has to fit without scrolling, so anything
## added to it has to be looked at rather than assumed.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/settings_look.tscn
##
## Shot on the PAD profile (the default) and again on the keyboard, which adds
## the four movement rows and is therefore the worst case for height.
##
## Run it at 1920x1080 — that is the target this screen is budgeted against, and
## it fits there with room under BACK. At 720p it already overflowed before the
## DEATH STYLE row was added (the title clips and BACK falls off the bottom), so
## if this screen ever has to work on a small window it needs a ScrollContainer
## rather than one more row squeezed out of it.

const SETTINGS := preload("res://scenes/settings.tscn")

var _screen: Control


func _ready() -> void:
	_screen = SETTINGS.instantiate()
	add_child(_screen)
	await _frames(6)
	await _grab("settings_pads")

	# Walk the profile picker round to the keyboard, which is the tallest list.
	for _i in _screen.PROFILES.size():
		if _screen._is_keyboard():
			break
		_screen._cycle_profile()
	await _frames(6)
	await _grab("settings_keyboard")
	get_tree().quit()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % tag)
	print("wrote %s" % ProjectSettings.globalize_path("user://%s.png" % tag))


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
