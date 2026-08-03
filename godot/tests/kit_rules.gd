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

## A TABLE INDEXED BY AN ENUM MUST BE THE SAME LENGTH AND IN THE SAME ORDER AS
## THAT ENUM, and nothing was checking it. `gadget_action` does `GADGETS[id]`
## with `id` a Gadget, so a row appended to the end of the table while its enum
## entry went in the middle shifts every row below it by one — which is exactly
## what SMOKE_LAUNCHER did: twelve gadgets, OVERSHIELD through PULSE_SCAN, each
## silently took the NEXT one's behaviour, cooldown, price and displayed name.
## Every one of the results was a legal gadget, so nothing errored and nothing
## looked wrong until a thrown thermal detonator turned out to be a scan pulse.
##
## The names are compared too, not just the count. A count check alone passes
## the moment somebody appends a row AND adds an enum entry in the middle, which
## is the one sequence that causes this.
func check_enum_tables(L, fails: Array) -> void:
	print("\n-- every enum-indexed table lines up with its enum --")
	for spec in [["Gadget", L.Gadget, L.GADGETS]]:
		var keys: Array = spec[1].keys()
		var table: Array = spec[2]
		if keys.size() != table.size():
			fails.append("%s has %d entries but its table has %d rows"
				% [spec[0], keys.size(), table.size()])
			continue
		for i in keys.size():
			# The displayed name is PROSE and the enum entry is not: CABLE is
			# "WRIST CABLE", GRENADE_FRAG is "FRAG GRENADE", SENTRY_TURRET is
			# "AUTOSENTRY". So the test is that at least one real word of the
			# enum entry turns up somewhere in the row's name — loose enough for
			# every one of those, and still tight enough to catch a shift, which
			# lands a row on a name with nothing in common at all.
			var row_name: String = String(table[i].get("name", "?"))
			var matched := false
			for word in String(keys[i]).split("_", false):
				if word.length() >= 4 and word in row_name:
					matched = true
					break
			if not matched:
				fails.append("%s[%d] is %s but the table row there is %s"
					% [spec[0], i, keys[i], row_name])
		print("  %s: %d entries, in step with its table" % [spec[0], keys.size()])


## EVERY SIDE HAS A BOLT COLOUR, AND EVERY BOLT COLOUR IS ACTUALLY BRIGHT.
##
## Two failures, both silent. A universe added without a `bolts` row takes
## GameState's universe setter down on a missing key at the moment the setting
## changes — the arrays are assigned side by side, so this must be as long as
## `teams` and not merely present. And a DARK bolt is not a dim bolt, it is no
## tracer at all: the mesh is black albedo with all of its colour in the emission,
## so a colour with no lit channel renders as a black capsule against the map.
## Same shape of check, and the same reason, as night_palette's ground floor.
const BOLT_MIN_CHANNEL := 0.6


func check_bolt_colors(L, fails: Array) -> void:
	print("\n-- every side's gunfire has a colour, and it is a bright one --")
	for u in L.UNIVERSES.size():
		var row: Dictionary = L.UNIVERSES[u]
		var name: String = row.get("name", "?")
		var teams: Array = row.get("teams", [])
		var bolts: Array = row.get("bolts", [])
		if bolts.size() != teams.size():
			fails.append("%s fields %d sides but states %d bolt colours"
				% [name, teams.size(), bolts.size()])
			continue
		for t in bolts.size():
			var col: Color = bolts[t]
			var peak: float = maxf(col.r, maxf(col.g, col.b))
			if peak < BOLT_MIN_CHANNEL:
				fails.append("%s / %s fires a bolt whose brightest channel is %.2f — it will render as a black capsule"
					% [name, teams[t], peak])
		print("  %s: %d sides, %d bolt colours" % [name, teams.size(), bolts.size()])


## A FIELD THAT `_copy_from` DOES NOT COPY IS A FIELD THAT DOES NOT EXIST, and
## nothing said so until the third gadget slot spent its whole life not working.
## Nothing in the game reads a Loadout without duplicating it first — `step()`
## trials a copy and copies the result back, `_apply_loadout` deploys
## `pending.duplicate_loadout()` — so a var left out of that one function is
## silently reset to its default on the way to the body, however carefully the
## buy screen or a faction preset set it.
##
## Checked GENERICALLY, off the property list, rather than by naming the fields:
## naming them is how the omission happened in the first place. Faction builds
## are the sample because they set the most fields of anything in the file.
func check_copy_fidelity(L, fails: Array) -> void:
	print("\n-- a duplicated build is the same build --")
	var checked := 0
	for i in L.FACTION_BUILDS.size():
		var original = L.faction_build(i)
		var copy = original.duplicate_loadout()
		for prop in original.get_property_list():
			if not (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
				continue
			var name: String = prop["name"]
			if original.get(name) != copy.get(name):
				fails.append("%s: duplicating the build loses `%s` (%s becomes %s) — _copy_from does not copy it"
					% [L.FACTION_BUILDS[i].get("name", "?"), name,
						original.get(name), copy.get(name)])
			checked += 1
	print("  %d fields across %d authored classes survive a duplicate"
		% [checked, L.FACTION_BUILDS.size()])


## AND EVERY ROW THE BUY SCREEN OFFERS MUST ACTUALLY MOVE. `step()` refuses any
## change that `_same_as` reports as no change, so a field missing from THAT
## function is a row you can press forever with nothing happening — which is what
## the ABILITY row and the FRONT GRIP row both did. Same failure to the player as
## the copy bug above, from the opposite direction, so both are checked.
## Two things this has to get right, both learned by getting them wrong: each row
## is driven on its OWN fresh build, because walking every row of one build to
## the right spends the whole budget and then refuses the last few rows for a
## perfectly good reason; and the active universe is set to the KIT'S universe,
## because the CLASS row is walked within the current setting, so a Spartan
## examined under Star Wars correctly cannot step anywhere.
func check_rows_move(L, fails: Array) -> void:
	print("\n-- every row the buy screen shows can be changed --")
	var was = L.active_universe
	var moved_rows := 0
	for k in L.KITS.size():
		L.active_universe = L.kit_universe(k)
		for row in L.Row.values():
			if row == L.Row.KIT:
				continue   # covered by the per-universe class walk below
			var b = L.new()
			b.adopt_kit(k)
			if not b.row_available(row):
				continue
			var before = b.row_value(row)
			# A row with only one legal option for this kit is allowed to sit
			# still — that is the allow-list doing its job. Count first, on a
			# build of its own, since walking mutates what it measures.
			var probe = L.new()
			probe.adopt_kit(k)
			if walk(probe, row).size() <= 1:
				continue
			if b.step(row, 1) or b.step(row, -1):
				moved_rows += 1
				continue
			fails.append("%s: the %s row offers more than one option but will not step off `%s`"
				% [b.kit_name(), b.row_label(row), before])
	L.active_universe = was
	print("  %d rows across %d classes step when pressed" % [moved_rows, L.KITS.size()])


func _init() -> void:
	var L = load("res://scripts/loadout.gd")
	var fails := []
	var kit_names := ["CLONE", "MANDALORIAN", "FORCE", "WOOKIEE", "TRANDOSHAN"]
	check_enum_tables(L, fails)
	check_bolt_colors(L, fails)
	check_copy_fidelity(L, fails)
	check_rows_move(L, fails)

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
			if b.gadget_slots() != 3:
				fails.append("%s: needs three gadget slots" % name)
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
		var sustains := []
		for i in L.GADGETS.size():
			if b.allows(L.Row.GADGET3, i):
				sustains.append(str(L.GADGETS[i]["name"]))
		# Grenades: the two kits built around a full gadget bar go without.
		# THREE SLOTS: two deployables and one SUSTAINED ability. Every class has
		# something to put up — an empty third slot is a class that was forgotten
		# rather than one that chose nothing.
		if b.gadget_slots() != 3:
			fails.append("%s should have three gadget slots, has %d" % [name, b.gadget_slots()])
		if sustains.size() < 2:
			fails.append("%s has no sustained ability to put in slot 3: %s" % [
				name, sustains])
		# ...and the two kinds must not bleed into each other: a barrier or a
		# cloak is a slot-3 ability now and must not still be fittable as a
		# deployable, or the class gets it twice on two buttons.
		for i in L.GADGETS.size():
			if b.allows(L.Row.GADGET3, i) and i != L.Gadget.NONE \
					and b.allows(L.Row.GADGET, i):
				fails.append("%s can fit %s in BOTH a deployable slot and slot 3"
					% [name, L.GADGETS[i]["name"]])
		if not ("FRAG GRENADE" in gads and "STICKY GRENADE" in gads):
			fails.append("%s cannot fit a frag/sticky grenade gadget: %s" % [name, gads])

		# --- the Wookiee owns the heavy weapons, the bowcaster and the barrier --
		var heavies := ["T-21 HMG", "PLX-1 RPG"]
		if k == 3:
			if guns != heavies:
				fails.append("WOOKIEE should hold the heavy guns ALONE, got %s" % str(guns))
			if sides != ["Bowcaster"]:
				fails.append("WOOKIEE should carry the bowcaster alone, got %s" % str(sides))
			if not ("FRONT SHIELD" in sustains):
				fails.append("WOOKIEE cannot put up the FRONT SHIELD (slot 3): %s"
					% str(sustains))
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
			if "FRONT SHIELD" in gads or "FRONT SHIELD" in sustains:
				fails.append("%s can take the FRONT SHIELD; that is the Wookiee's" % name)
		if not b.row_available(L.Row.GADGET2):
			fails.append("%s should have a second gadget row" % name)

		# --- the Trandoshan owns SMOKE, the thermal sight, cloak and dash ------
		if k == 4:
			if not ("SMOKE GRENADE" in gads):
				fails.append("TRANDOSHAN cannot fit SMOKE, its signature grenade")
			if not ("THERMAL HOLO" in sights):
				fails.append("TRANDOSHAN cannot fit its THERMAL HOLO")
			if not ("CLOAK" in sustains and "SPRINT DASH" in gads):
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

	fails += _universe_rules(L)

	print("\n==== %s ====" % ("ALL RULES HOLD" if fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [fails.size(), "\n  ".join(fails)]))
	quit()


## Every universe on its own terms: the classes it offers, the guns and gadgets
## those classes can reach, its AI presets and its royale crates.
##
## The rule this is really here to protect is ISOLATION. Weapons, gadgets and
## bodies all share one enum each across every setting, which is what makes
## adding a universe cheap — and also what would let a bolter turn up on a clone
## trooper's buy screen if a single allow-list were written wrong. So every walk
## is checked against the set of names that universe is allowed to contain, not
## against a list of specific mistakes somebody thought of.
func _universe_rules(L) -> Array:
	var fails := []
	var was = L.active_universe

	# A preset that NAMES a gun the catalogue does not sell in that slot is a
	# silent disarm, not an error: weapon_index answers NO_PRIMARY and
	# secondary_index answers 0, so the class deploys with the free pistol and
	# nothing anywhere says so. Two reinforcements shipped like that (the Death
	# Trooper and the Brute Stalker, both naming a SIDEARM as their primary),
	# and the existing "deploys unarmed" check passed them because the fallback
	# pistol IS a weapon. This asks the stricter question: did you get the gun
	# you asked for?
	print("\n-- every preset gets the gun it names --")
	for table in [L.FACTION_BUILDS, L.BOT_BUILDS]:
		for preset: Dictionary in table:
			var who: String = preset.get("name", "?")
			if preset.has("primary") and L.weapon_index(preset["primary"]) == L.NO_PRIMARY:
				fails.append("%s names a primary the WEAPONS table does not sell" % who)
			if preset.has("sidearm"):
				var got: int = L.secondary_index(preset["sidearm"])
				if L.SECONDARIES[got]["class"] != preset["sidearm"]:
					fails.append("%s names a sidearm SECONDARIES does not sell" % who)
	print("  checked %d faction + %d AI presets"
		% [L.FACTION_BUILDS.size(), L.BOT_BUILDS.size()])

	# AN AUTHORED CLASS MUST NAME ITS SIDEARM, not index one. `secondary: 0`
	# means "the cheapest row", which is the DL-44 — so all thirty-two Star Wars
	# classes drew Han Solo's pistol, B1 battle droids and the Emperor's Royal
	# Guard included, and no test could see it because index 0 is a perfectly
	# valid sidearm. Halo and Warhammer never had the bug purely because they
	# were written later and named theirs. Naming is also what makes the
	# "gets the gun it names" check above able to see the row at all.
	#
	# The AI presets are exempt: those are SHOP BUILDS, where picking the free
	# row is a budget decision and index 0 means exactly what it says.
	print("\n-- every authored class names its sidearm --")
	var unnamed := []
	for preset: Dictionary in L.FACTION_BUILDS:
		if not preset.has("sidearm"):
			unnamed.append(preset.get("name", "?"))
	if unnamed.is_empty():
		print("  all %d classes name theirs" % L.FACTION_BUILDS.size())
	else:
		fails.append("%d authored classes index their sidearm instead of naming it: %s"
			% [unnamed.size(), str(unnamed)])

	for u in L.UNIVERSES.size():
		L.active_universe = u
		var uni: Dictionary = L.UNIVERSES[u]
		print("\n\n######## %s ########" % uni["name"])

		# What this universe is ALLOWED to contain, by weapon display name.
		var legal_guns := {}
		for row in L.WEAPONS + L.SECONDARIES:
			if row["class"] >= 0 and L.in_universe(row, u):
				legal_guns[Weapon.PROFILES[row["class"]]["name"]] = true
		var legal_gear := {}
		for i in L.GADGETS.size():
			if L.in_universe(L.GADGETS[i], u):
				legal_gear[L.GADGETS[i]["name"]] = true

		var kits: Array = L.universe_kits()
		if kits.is_empty():
			fails.append("%s offers no classes at all" % uni["name"])
			continue
		for k in kits:
			var b = L.new()
			b.adopt_kit(k)
			var name: String = b.kit_name()
			var kit_guns := walk(b, L.Row.WEAPON)
			b.adopt_kit(k)
			var kit_sides := walk(b, L.Row.SECONDARY)
			b.adopt_kit(k)
			var kit_gear := walk(b, L.Row.GADGET)
			b.adopt_kit(k)
			print("\n== %s ==" % name)
			print("  primaries : %s" % str(kit_guns))
			print("  sidearms  : %s" % str(kit_sides))
			print("  gadgets   : %s" % str(kit_gear))
			for g in kit_guns + kit_sides:
				if g != "none" and not legal_guns.has(g):
					fails.append("%s (%s) can reach %s, which is not in this universe"
						% [name, uni["name"], g])
			for g in kit_gear:
				if not legal_gear.has(g):
					fails.append("%s (%s) can fit %s, which is not in this universe"
						% [name, uni["name"], g])
			# A class has to deploy ARMED and inside budget with no shopping done.
			if b.cost() > L.BUDGET:
				fails.append("%s opens at %d tokens, over budget" % [name, b.cost()])
			if not b.has_primary() and b.secondary_name() == "":
				fails.append("%s adopts its kit holding nothing" % name)
			# ...and the cursor must never stop on a row it does not have.
			for r in L.Row.size():
				if not b.row_available(b.next_row(r, 1)):
					fails.append("%s: next_row landed on an unavailable row from %d"
						% [name, r])

		# Every AI preset in this universe: legal for its own kit, inside budget.
		print("\n-- AI presets --")
		var presets: Array = L.universe_builds()
		if presets.is_empty():
			fails.append("%s has no AI presets, so team fill has nothing to deploy"
				% uni["name"])
		for n in presets.size():
			var preset: Dictionary = L.BOT_BUILDS[presets[n]]
			var b2 = L.bot_build(n)
			var why := []
			if b2.cost() > L.BUDGET:
				why.append("costs %d" % b2.cost())
			for pair in [[L.Row.WEAPON, b2.weapon], [L.Row.GADGET, b2.gadget],
					[L.Row.GADGET2, b2.gadget2], [L.Row.ARMOR, b2.armor],
					[L.Row.SECONDARY, b2.secondary],
					[L.Row.SECONDARY_MOD, b2.secondary_mod]]:
				if not b2.allows(pair[0], pair[1]):
					why.append("row %d holds %d, which its kit forbids" % [pair[0], pair[1]])
			print("  %-18s %-14s %3d tokens  %s" % [preset["name"], b2.kit_name(),
				b2.cost(), "OK" if why.is_empty() else str(why)])
			if not why.is_empty():
				fails.append("preset %s: %s" % [preset["name"], str(why)])

		# Every FACTION class this universe's sides deploy off the character
		# select. These ignore the allow-lists by design (they are authored, not
		# shopped), so what is checked is that they exist, are armed, and wear a
		# class from this universe.
		print("\n-- faction rosters --")
		for team in L.FACTION_ROSTERS[u].size():
			var line := []
			for slot in L.faction_classes(team):
				var f = L.faction_build(slot)
				line.append(L.FACTION_BUILDS[slot]["name"])
				if L.kit_universe(f.kit) != u:
					fails.append("%s roster %d slot %d wears a class from another universe"
						% [uni["name"], team, slot])
				if not f.has_primary() and f.secondary_name() == "":
					fails.append("%s: faction class %s deploys unarmed"
						% [uni["name"], L.FACTION_BUILDS[slot]["name"]])
			print("  %-14s %s" % [str(uni["teams"][team]), str(line)])

		# Royale crates: this universe's gear only.
		var crate_guns: Array = L.royale_items(L.WEAPONS, 1)
		for i in crate_guns:
			var gname: String = Weapon.PROFILES[L.WEAPONS[i]["class"]]["name"]
			if not legal_guns.has(gname):
				fails.append("%s royale crates can hold %s" % [uni["name"], gname])
		if L.kit_universe(L.royale_start().kit) != u:
			fails.append("%s royale drops you in wearing another universe's body"
				% uni["name"])
	L.active_universe = was
	return fails
