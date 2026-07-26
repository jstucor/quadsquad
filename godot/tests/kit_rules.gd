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
	var kit_names := ["CLONE", "MANDALORIAN", "FORCE", "WOOKIEE", "TRANDOSHAN"]

	for k in kit_names.size():
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
		var sides := walk(b, L.Row.SECONDARY)
		print("  sidearms  : %s" % str(sides))
		b.adopt_kit(k)
		var mods := walk(b, L.Row.SECONDARY_MOD)
		print("  side mods : %s" % str(mods))
		b.adopt_kit(k)
		var arm := walk(b, L.Row.ARMOR)
		print("  armour    : %s" % str(arm))
		b.adopt_kit(k)
		var sights := walk(b, L.Row.SIGHT)
		print("  sights    : %s" % str(sights))
		b.adopt_kit(k)
		var gads2 := walk(b, L.Row.GADGET2)
		print("  gadget 2  : %s" % str(gads2))
		b.adopt_kit(k)
		print("  slots     : %d" % b.gadget_slots())

		# --- the rules the user asked for --------------------------------
		# The Force adept wields the saber AND ordinary guns, while keeping every
		# Force power; only IT may reach the saber. It still may not take another
		# kit's signature heavies.
		var saber_ok: bool = "Lightsaber" in guns
		if k == 2:
			if not saber_ok:
				fails.append("FORCE ADEPT cannot reach its own lightsaber: %s" % guns)
			if not ("DC-15 Rifle" in guns):
				fails.append("FORCE ADEPT can no longer wield ordinary guns: %s" % guns)
			for heavy in ["T-21 HMG", "PLX-1 RPG"]:
				if heavy in guns:
					fails.append("FORCE ADEPT reached %s; that is the Wookiee's" % heavy)
			for power in ["FORCE PUSH", "FORCE PULL", "FORCE LEAP", "FORCE LIGHTNING"]:
				if not (power in gads):
					fails.append("%s: missing %s: %s" % [name, power, gads])
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
		if k == 0:
			for need in ["MORTAR", "TURRET", "ROTARY CANNON"]:
				if not (need in gads):
					fails.append("CLONE cannot take %s" % need)
		else:
			for banned in ["MORTAR", "TURRET", "ROTARY CANNON"]:
				if banned in gads:
					fails.append("%s can take %s; that is the clone's" % [name, banned])
		# Grenades: the two kits built around a full gadget bar go without.
		if b.gadget_slots() != 2:
			fails.append("%s should have two gadget slots now, has %d" % [name, b.gadget_slots()])
		if not ("FRAG GRENADE" in gads and "STICKY GRENADE" in gads):
			fails.append("%s cannot fit a frag/sticky grenade gadget: %s" % [name, gads])

		# --- the Wookiee owns the heavy weapons, the bowcaster and the barrier --
		var heavies := ["T-21 HMG", "PLX-1 RPG"]
		if k == 3:
			if guns != heavies:
				fails.append("WOOKIEE should hold the heavy guns ALONE, got %s" % str(guns))
			if sides != ["Bowcaster"]:
				fails.append("WOOKIEE should carry the bowcaster alone, got %s" % str(sides))
			if not ("FRONT SHIELD" in gads):
				fails.append("WOOKIEE cannot take the FRONT SHIELD")
			if "SCOPE" in mods:
				fails.append("WOOKIEE can scope a PELLET sidearm: 3 quarrels on one point")
			if arm != ["PLATED", "HEAVY PLATE"]:
				fails.append("WOOKIEE should wear plate or better, got %s" % str(arm))
		else:
			for heavy in heavies:
				if heavy in guns:
					fails.append("%s can reach %s; that is the Wookiee's" % [name, heavy])
			if "Bowcaster" in sides:
				fails.append("%s can carry the bowcaster; only the Wookiee may" % name)
			if "FRONT SHIELD" in gads:
				fails.append("%s can take the FRONT SHIELD; that is the Wookiee's" % name)
		if not b.row_available(L.Row.GADGET2):
			fails.append("%s should have a second gadget row" % name)

		# --- the Trandoshan owns SMOKE, the thermal sight, cloak and dash ------
		if k == 4:
			if not ("SMOKE GRENADE" in gads):
				fails.append("TRANDOSHAN cannot fit SMOKE, its signature grenade")
			if not ("THERMAL HOLO" in sights):
				fails.append("TRANDOSHAN cannot fit its THERMAL HOLO")
			if not ("CLOAK" in gads and "SPRINT DASH" in gads):
				fails.append("TRANDOSHAN needs CLOAK and DASH, got %s" % str(gads))
			var want := ["DC-15 Rifle", "A280 Semi", "Westar M5 SMG", "NT-242 Sniper"]
			for g in want:
				if not (g in guns):
					fails.append("TRANDOSHAN missing %s: %s" % [g, str(guns)])
		else:
			if "SMOKE GRENADE" in gads:
				fails.append("%s can fit SMOKE; that is the Trandoshan's" % name)
			if "THERMAL HOLO" in sights:
				fails.append("%s can fit the thermal holo; only the Trandoshan may" % name)
			if "CLOAK" in gads:
				fails.append("%s can cloak; that is the Trandoshan's" % name)
			# DASH is shared by the Trandoshan and the FORCE adept (k == 2), whose
			# dash is part of the class — it may fit it as an explicit gadget as well
			# as get it intrinsically from an empty slot. Nobody else may.
			if k != 2 and "SPRINT DASH" in gads:
				fails.append("%s can take the dash gadget; that is the Trandoshan's/adept's" % name)

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

		print("  %-14s %-14s %3d tokens  %s" % [preset["name"], b2.kit_name(),
			b2.cost(), "OK" if why.is_empty() else str(why)])
		if not why.is_empty():
			fails.append("preset %s: %s" % [preset["name"], str(why)])

	# --- royale is CLASS-FREE: no crate may hold a class's signature gear ----
	print("\n== battle royale crate contents ==")
	var guns: Array = L.royale_items(L.WEAPONS, 1)
	var gear: Array = L.royale_items(L.GADGETS, 1)
	var gun_names := []
	for i in guns:
		gun_names.append(Weapon.PROFILES[L.WEAPONS[i]["class"]]["name"])
	var gear_names := []
	for i in gear:
		gear_names.append(L.GADGETS[i]["name"])
	print("  guns   : %s" % str(gun_names))
	print("  gadgets: %s" % str(gear_names))
	if "Lightsaber" in gun_names:
		fails.append("royale crates can contain a lightsaber")
	if "Bowcaster" in gun_names:
		fails.append("royale crates can contain a bowcaster")
	# ...but the heavy guns and the barrier are a class's by BALANCE, not by
	# mechanism: they work fine for a plain trooper, so kit-locking them in the
	# shop must not empty them out of a mode that has no classes at all.
	for keep in ["T-21 HMG", "PLX-1 RPG"]:
		if not (keep in gun_names):
			fails.append("royale lost %s out of its crates" % keep)
	if not ("FRONT SHIELD" in gear_names):
		fails.append("royale lost the FRONT SHIELD out of its crates")
	for banned in ["FORCE PUSH", "FORCE PULL", "FORCE LEAP", "FORCE LIGHTNING"]:
		if banned in gear_names:
			fails.append("royale crates can contain %s" % banned)
	var start = L.royale_start()
	if start.kit != L.Kit.CLONE or start.can_dash():
		fails.append("royale should drop you in as a plain trooper")

	print("\n==== %s ====" % ("ALL RULES HOLD" if fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [fails.size(), "\n  ".join(fails)]))
	quit()
