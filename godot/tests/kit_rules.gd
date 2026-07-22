extends SceneTree
## Checks every character-class rule against the catalogue, and every AI preset
## against its own kit. Run it after touching KITS, WEAPONS, GADGETS or
## BOT_BUILDS -- the allow-lists are the only thing stopping a preset or a buy
## screen offering a class something it should not have, and nothing else fails
## loudly when they drift.
##
##   godot --headless --path godot --script tests/kit_rules.gd
##
## The engine prints a wall of "Identifier not found: GameState" while it loads:
## --script mode has no autoloads, so every script that names GameState fails to
## compile. Loadout itself does not, which is why this can still run. Read the
## verdict at the bottom, not the noise.

func walk(b, row: int) -> Array:
	# Drive the row exactly as the buy screen does: hold left to the end, then
	# step right one at a time and record everything it lands on.
	for i in 40:
		b.step(row, -1)
	var seen := [b.row_value(row)]
	for i in 40:
		if b.step(row, 1):
			seen.append(b.row_value(row))
	return seen

func _init() -> void:
	var L = load("res://scripts/loadout.gd")
	var fails := []
	var kit_names := ["CLONE", "MANDALORIAN", "FORCE"]

	for k in 3:
		var b = L.new()
		b.adopt_kit(k)
		var name: String = b.kit_name()
		print("\n== %s (default armour %s, %d gadget slot(s)) ==" % [
			name, b.row_value(L.Row.ARMOR), b.gadget_slots()])

		var guns := walk(b, L.Row.WEAPON)
		print("  primaries : %s" % str(guns))
		b.adopt_kit(k)
		var gads := walk(b, L.Row.GADGET)
		print("  gadgets   : %s" % str(gads))
		b.adopt_kit(k)
		var mods := walk(b, L.Row.SECONDARY_MOD)
		print("  sidearm   : %s" % str(mods))
		b.adopt_kit(k)
		var arm := walk(b, L.Row.ARMOR)
		print("  armour    : %s" % str(arm))
		b.adopt_kit(k)
		print("  grenades  : %s   gadget2 row: %s" % [
			b.row_available(L.Row.GRENADES), b.row_available(L.Row.GADGET2)])

		# --- the rules the user asked for --------------------------------
		var saber_ok: bool = "Lightsaber" in guns
		if k == 2:
			if guns != ["Lightsaber"]:
				fails.append("%s: primary should be the saber ALONE, got %s" % [name, guns])
			if not ("FORCE PUSH" in gads and "FORCE PULL" in gads and "FORCE LEAP" in gads):
				fails.append("%s: missing a force gadget: %s" % [name, gads])
		else:
			if saber_ok:
				fails.append("%s can reach the lightsaber" % name)
		if k == 1:
			if not ("JETPACK" in gads and "WRIST CABLE" in gads):
				fails.append("%s: needs jetpack AND cable, got %s" % [name, gads])
			if not ("DUAL WIELD" in mods):
				fails.append("%s: must be able to dual wield" % name)
			if b.gadget_slots() != 2:
				fails.append("%s: needs two gadget slots" % name)
			if b.row_value(L.Row.ARMOR) != "LIGHT FRAME":
				fails.append("%s: default armour should be lighter, got %s" % [
					name, b.row_value(L.Row.ARMOR)])
		else:
			if "DUAL WIELD" in mods:
				fails.append("%s can dual wield; only the Mandalorian may" % name)
			if b.gadget_slots() != 1:
				fails.append("%s should have one gadget slot" % name)
		if k == 0:
			for need in ["MORTAR", "TURRET", "ROTARY CANNON"]:
				if not (need in gads):
					fails.append("CLONE cannot take %s" % need)
		else:
			for banned in ["MORTAR", "TURRET", "ROTARY CANNON"]:
				if banned in gads:
					fails.append("%s can take %s; that is the clone's" % [name, banned])
			if b.row_available(L.Row.GRENADES):
				fails.append("%s should carry no grenades" % name)
		if k != 1 and b.row_available(L.Row.GADGET2):
			fails.append("%s should not have a second gadget row" % name)

		# The cursor must never stop on a row this class does not have.
		for r in L.Row.size():
			if not b.row_available(b.next_row(r, 1)):
				fails.append("%s: next_row landed on an unavailable row from %d" % [name, r])

	# --- two slots must never hold the same gadget -----------------------
	var m = L.new()
	m.adopt_kit(1)
	for i in 20:
		m.step(L.Row.GADGET, 1)
	for i in 20:
		m.step(L.Row.GADGET2, 1)
	print("\n== Mandalorian both slots: %s + %s ==" % [
		m.row_value(L.Row.GADGET), m.row_value(L.Row.GADGET2)])
	if m.row_value(L.Row.GADGET) == m.row_value(L.Row.GADGET2):
		fails.append("both gadget slots hold the same thing")

	# --- every AI preset must be legal for its own kit and inside budget --
	print("\n== bot presets ==")
	for i in L.BOT_BUILDS.size():
		var preset: Dictionary = L.BOT_BUILDS[i]
		var b2 = L.bot_build(i)
		var why := []
		if b2.cost() > L.BUDGET:
			why.append("costs %d" % b2.cost())
		for pair in [[L.Row.WEAPON, b2.weapon], [L.Row.GADGET, b2.gadget],
				[L.Row.GADGET2, b2.gadget2], [L.Row.ARMOR, b2.armor],
				[L.Row.SECONDARY_MOD, b2.secondary_mod]]:
			if not b2.allows(pair[0], pair[1]):
				why.append("row %d holds %d, which its kit forbids" % [pair[0], pair[1]])
		if b2.grenades > 0 and not b2.has_grenades():
			why.append("carries grenades its kit has none of")
		print("  %-14s %-14s %3d tokens  %s" % [preset["name"], b2.kit_name(),
			b2.cost(), "OK" if why.is_empty() else str(why)])
		if not why.is_empty():
			fails.append("preset %s: %s" % [preset["name"], str(why)])

	print("\n==== %s ====" % ("ALL RULES HOLD" if fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [fails.size(), "\n  ".join(fails)]))
	quit()
