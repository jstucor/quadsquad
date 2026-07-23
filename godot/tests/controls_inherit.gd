extends SceneTree
## Pad 1's layout is every other pad's layout.
##
## Four pads at one couch are four copies of the same controller: somebody who
## rebinds a control because the default is wrong for them has fixed it for
## players 2, 3 and 4 as well, and making each of them repeat the rebind is
## asking four times for one decision. A pad with its OWN binding still keeps it.
##
##   godot --headless --path godot --script tests/controls_inherit.gd
##
## WARNING WORTH KEEPING: every mutating call in Controls SAVES, so this test
## writes to the player's real user://controls.cfg. It therefore snapshots the
## file first and puts it back at the end — an earlier version did not, called
## reset_defaults(), and wiped a real rebind off a real machine.

const CONFIG := "user://controls.cfg"


func _init() -> void:
	var C = load("res://scripts/controls.gd")
	var fails := []
	var backup := ""
	if FileAccess.file_exists(CONFIG):
		backup = FileAccess.get_file_as_string(CONFIG)

	C.reset_defaults()
	var base: String = C.pad_label(1, "crouch")
	print("default crouch on pad 2: %s" % base)

	# P1 rebinds crouch to the right stick, as this project's own config does.
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = JOY_BUTTON_RIGHT_STICK
	ev.pressed = true
	C.bind_pad(0, "crouch", ev)
	print("after P1 rebinds: P1 %s | P2 %s | P4 %s | ALL PADS %s" % [
		C.pad_label(0, "crouch"), C.pad_label(1, "crouch"),
		C.pad_label(3, "crouch"), C.pad_label(C.ALL_PADS, "crouch")])
	if C.pad_label(1, "crouch") != C.pad_label(0, "crouch"):
		fails.append("pad 2 did not inherit P1's rebind")
	if C.pad_label(3, "crouch") != C.pad_label(0, "crouch"):
		fails.append("pad 4 did not inherit P1's rebind")
	if C.has_override(1, "crouch"):
		fails.append("inheriting P1 must not count as pad 2's OWN override")

	# ...and a pad that has been given its own keeps it.
	var own := InputEventJoypadButton.new()
	own.device = 1
	own.button_index = JOY_BUTTON_LEFT_SHOULDER
	own.pressed = true
	C.bind_pad(1, "crouch", own)
	print("after P2 rebinds itself: P1 %s | P2 %s | P3 %s" % [
		C.pad_label(0, "crouch"), C.pad_label(1, "crouch"), C.pad_label(2, "crouch")])
	if C.pad_label(1, "crouch") == C.pad_label(0, "crouch"):
		fails.append("pad 2's own binding was overwritten by P1's")
	if C.pad_label(2, "crouch") != C.pad_label(0, "crouch"):
		fails.append("pad 3 stopped following P1")
	if not C.has_override(1, "crouch"):
		fails.append("pad 2's own binding is not marked as an override")

	# Clearing it drops back to P1, not to the factory default.
	C.clear_override(1, "crouch")
	print("after P2 clears: P2 %s (P1 is %s)" % [
		C.pad_label(1, "crouch"), C.pad_label(0, "crouch")])
	if C.pad_label(1, "crouch") != C.pad_label(0, "crouch"):
		fails.append("clearing pad 2's override did not fall back to P1")

	# Put the player's own bindings back exactly as they were.
	if backup != "":
		var f := FileAccess.open(CONFIG, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	print("\n==== %s ====" % ("P1 IS THE HOUSE LAYOUT" if fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [fails.size(), "\n  ".join(fails)]))
	quit(0 if fails.is_empty() else 1)
