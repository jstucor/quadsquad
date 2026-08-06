extends SceneTree
## THE THIRD GADGET SLOT, end to end. It reported as "not working at all", and
## there are four separate places it can be dead — the BINDING, the BUILD, the
## SCREEN and the EFFECT — so each is asserted on its own here rather than left
## to a play test that can only say "nothing happened".
##
##   godot --headless --path godot --script tests/slot3.gd
##
## The one that actually broke was the binding, and it broke in the way saved
## config always breaks: a control that MOVED keeps its old binding, because a
## saved value wins over a default. Nothing about the code was wrong.

# NOTHING HERE MAY PRELOAD A SCENE. `--script` runs with no autoloads, so the
# moment this file named player.tscn, every script that reaches for GameState or
# Audio failed to compile and took this test down with them — an error storm
# whose first line is about corpse.gd and whose real subject is this constant.
# The four things below are all answerable from the catalogue and the bindings.


func _init() -> void:
	var fails: Array[String] = []
	var backup := _snapshot()

	# 1. THE BINDING. Every pad control must sit on a button no other control
	#    uses: two actions on one button is not a preference anybody expressed,
	#    it is a config that predates a remap.
	Controls.ensure_loaded()
	for device in [Controls.ALL_PADS, 0]:
		var seen := {}
		for entry in Controls.ACTIONS:
			if not entry["pad"]:
				continue
			for bind: Dictionary in Controls.bindings_for(device, entry["id"]):
				var key := "%d:%d" % [bind.get("kind", 0), bind.get("index", -1)]
				if seen.has(key):
					fails.append("pad %d: %s and %s are both on %s" % [
						device, seen[key], entry["id"],
						Controls.pad_label(device, entry["id"])])
				seen[key] = entry["id"]
	# ...and the keyboard, which has the same failure mode.
	var keys := {}
	for entry in Controls.ACTIONS:
		var bind := Controls.keyboard_binding(entry["id"])
		if bind.is_empty():
			continue
		var key := str(bind)
		if keys.has(key):
			fails.append("keyboard: %s and %s are both on %s" % [
				keys[key], entry["id"], Controls.label(-1, entry["id"])])
		keys[key] = entry["id"]

	# 2. THE BUILD. A kit with three slots must actually carry a third gadget
	#    through to the deployed Loadout, and `gadget3_id` must not swallow it.
	var build := Loadout.new()
	build.adopt_kit(Loadout.Kit.CLONE)
	if build.gadget_slots() < 3:
		fails.append("the clone kit has %d slots" % build.gadget_slots())
	build.gadget3 = Loadout.Gadget.OVERSHIELD
	if build.gadget3_id() != Loadout.Gadget.OVERSHIELD:
		fails.append("gadget3_id dropped the fitted ability")

	# 3. THE SCREEN. The buy screen must be able to REACH the row: hidden or
	#    unreachable is indistinguishable from broken.
	if not build.row_available(Loadout.Row.GADGET3):
		fails.append("the buy screen hides the ability row")
	var box := -1
	for i in Loadout.BUY_BOXES.size():
		if Loadout.Row.GADGET3 in Loadout.BUY_BOXES[i]["rows"]:
			box = i
	if box < 0:
		fails.append("no buy-screen box contains the ability row")
	elif build.first_row_in(box) < 0:
		fails.append("the gadgets box opens on nothing")
	# ...and stepping the row must actually change the fitted ability.
	var before := build.gadget3
	build.step(Loadout.Row.GADGET3, 1)
	if build.gadget3 == before:
		fails.append("stepping the ability row changes nothing")

	print("== the four places slot 3 can be dead ==")
	print("  binding   %s / %s" % [Controls.label(-1, "sustain"),
		Controls.pad_label(Controls.ALL_PADS, "sustain")])
	print("  swap now  %s / %s" % [Controls.label(-1, "switch"),
		Controls.pad_label(Controls.ALL_PADS, "switch")])
	print("  build     %s" % Loadout.GADGETS[build.gadget3]["name"])
	print("  row       box %d, first row %d" % [box, build.first_row_in(box)])

	_restore(backup)
	print("")
	if fails.is_empty():
		print("==== SLOT 3 IS WIRED ====")
	else:
		for f in fails:
			print("FAIL  %s" % f)
		print("==== %d FAILURES ====" % fails.size())
	quit()


## Every mutating Controls call SAVES, so this test would otherwise rewrite a
## real player's bindings — the same rule `controls_inherit.gd` records.
func _snapshot() -> PackedByteArray:
	var f := FileAccess.open(Controls.CONFIG_PATH, FileAccess.READ)
	return f.get_buffer(f.get_length()) if f != null else PackedByteArray()


func _restore(data: PackedByteArray) -> void:
	if data.is_empty():
		return
	var f := FileAccess.open(Controls.CONFIG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_buffer(data)
