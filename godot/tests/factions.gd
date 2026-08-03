extends Node
## PICKING A SIDE INDEPENDENTLY OF THE SETTING, and choosing what colour it wears.
##
## The change this protects: a match used to HAVE a universe, and now it has up
## to four sides that each name one. The failure mode is a side whose ROSTER, and
## whose CHIP, and whose TRACER disagree about who it is — every one of those is
## resolved from a different place and all three are silent when wrong. UNSC
## troopers in Republic blue firing Covenant plasma is a legal-looking match.
##
## The second half is the tint: purple clones have to fire purple, or it is half
## a setting.

var _fails: Array[String] = []
var _done := {}


func _ready() -> void:
	print("\n==== factions and colours ====")
	if GameState == null or not GameState.has_method("refresh_sides"):
		print("  FAIL: GameState did not load — every check below would be hollow")
		print("==== 1 FAILURES ====")
		get_tree().quit(1)
		return
	_check_flat_list()
	_check_universe_deals_sides()
	_check_cross_universe()
	_check_tints()
	for name in ["list", "deal", "cross", "tints"]:
		if not _done.has(name):
			_fails.append("the `%s` checks did not run to the end — something in "
				% name + "them errored and the rest were skipped")
	print("")
	if _fails.is_empty():
		print("==== FACTIONS HOLD ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## The flat list is DERIVED from UNIVERSES, so the thing to check is that it
## derived the right number of them — Halo names four sides and authors two
## rosters, and a side you can select but cannot field is worse than absent.
func _check_flat_list() -> void:
	print("\n-- every playable side, in one list --")
	var all := Loadout.factions()
	for f in all:
		var roster: Array = Loadout.faction_classes(int(f["side"]), int(f["universe"]))
		_ok(roster.size() > 0,
			"%s has no classes — it must not be selectable" % f["name"])
		print("  %-18s %-18s %d classes" % [f["universe_name"], f["name"], roster.size()])
	_ok(all.size() == 10, "expected 10 playable factions, got %d" % all.size())
	# NO DUPLICATES. A derived list that emitted a side twice would give two teams
	# the same roster and nothing would report it.
	var seen := {}
	for f in all:
		var key: String = "%s/%s" % [f["universe_name"], f["name"]]
		_ok(not seen.has(key), "%s appears twice in the flat list" % key)
		seen[key] = true
	_done["list"] = true


## The UNIVERSE dropdown still has to mean what it always meant.
func _check_universe_deals_sides() -> void:
	print("\n-- picking a setting deals its own sides --")
	for u: int in [Loadout.Universe.STAR_WARS, Loadout.Universe.HALO,
			Loadout.Universe.WARHAMMER]:
		GameState.universe = u
		GameState.team_count = 2
		var names: Array = []
		for t in 2:
			names.append(GameState.team_names[t])
			_ok(GameState.team_universe(t) == u,
				"choosing %s left side %d in universe %d"
					% [Loadout.UNIVERSES[u]["name"], t, GameState.team_universe(t)])
		_ok(not GameState.mixed_universes(),
			"a single-setting match reported as mixed")
		print("  %-18s -> %s" % [Loadout.UNIVERSES[u]["name"], str(names)])
	_done["deal"] = true


## THE ONE THAT WAS ASKED FOR: UNSC against the Republic.
func _check_cross_universe() -> void:
	print("\n-- UNSC against the Republic --")
	GameState.universe = Loadout.Universe.STAR_WARS
	GameState.team_count = 2
	# Side 0 stays Republic; side 1 becomes UNSC.
	var unsc := -1
	for i in Loadout.factions().size():
		var f := Loadout.faction(i)
		if str(f["name"]) == "UNSC":
			unsc = i
	_ok(unsc >= 0, "there is no UNSC in the flat list")
	if unsc < 0:
		return
	GameState.team_faction[1] = unsc
	GameState.refresh_sides()

	_ok(GameState.mixed_universes(), "a cross-setting match did not report as mixed")
	_ok(str(GameState.team_names[0]) == "REPUBLIC",
		"side 0 should be REPUBLIC, is %s" % GameState.team_names[0])
	_ok(str(GameState.team_names[1]) == "UNSC",
		"side 1 should be UNSC, is %s" % GameState.team_names[1])
	_ok(GameState.team_universe(1) == Loadout.Universe.HALO,
		"UNSC is not in the Halo universe")

	# AND THE ROSTERS FOLLOW. This is the half that would silently break: the
	# names and colours come from the flat list, but the CLASSES come from
	# FACTION_ROSTERS keyed by universe AND slot, and the slot is the faction's
	# own — not the team number. Wrapping team 1 into Halo's two rosters would
	# quietly field the Covenant.
	var rep := GameState.classes_for(0)
	var un := GameState.classes_for(1)
	_ok(rep.size() > 0 and un.size() > 0, "a side in a mixed match fields no classes")
	_ok(rep != un, "both sides field the same roster")
	var rep_name := str(Loadout.FACTION_BUILDS[rep[0]]["name"])
	var un_name := str(Loadout.FACTION_BUILDS[un[0]]["name"])
	print("  REPUBLIC first class: %s" % rep_name)
	print("  UNSC     first class: %s" % un_name)
	# The Republic's roster must still be clones and the UNSC's must not be.
	_ok(rep_name != un_name, "both sides deploy the same first class")

	# A BUILD FROM EACH, because `team_build_for` is the path a bot actually
	# takes and it resolves the pair separately from `classes_for`.
	for t in 2:
		var build := GameState.team_build_for(t, 0)
		_ok(build != null and build.build_name != "",
			"side %d could not build its first class" % t)
	# Streak rewards follow the faction too, or a UNSC side is offered a LAAT.
	var f1 := Loadout.faction(GameState.team_faction[1])
	var rewards := Streaks.available(int(f1["side"]), int(f1["universe"]))
	var names := []
	for r in rewards:
		names.append(str(r["name"]))
	_ok(names.has("SPARTAN HEADHUNTER"),
		"UNSC in a mixed match cannot earn its own signature: %s" % str(names))
	_ok(not names.has("LAAT GUNSHIP"),
		"UNSC in a mixed match was offered the Republic's gunship")
	print("  UNSC rewards: %s" % str(names))

	# NO SIGNATURE MAY SHARE A NAME WITH AN ORDINARY CLASS. The UNSC's was
	# "SPARTAN-II", which is also FACTION_BUILDS index 8 — so the reward for ten
	# kills was a thing that side already deploys at zero.
	var class_names := {}
	for b in Loadout.FACTION_BUILDS:
		class_names[str(b.get("name", ""))] = true
	for row in Streaks.REWARDS:
		var rn := str(row["name"])
		_ok(not class_names.has(rn),
			"the reward `%s` is also an ordinary class — a signature has to be a step ABOVE the roster" % rn)
		if row.has("preset"):
			var pn := str(row["preset"].get("name", ""))
			_ok(not class_names.has(pn),
				"the reward preset `%s` is also an ordinary class" % pn)
	_done["cross"] = true


## PURPLE CLONES FIRE PURPLE. The chip and the tracer are separate arrays on
## purpose (a grey chip would be no tracer at all), so the check is that a chosen
## tint reaches BOTH and that the tracer stays legible.
func _check_tints() -> void:
	print("\n-- choosing a colour moves the armour and the bolt together --")
	GameState.universe = Loadout.Universe.STAR_WARS
	GameState.team_count = 2
	var stock_chip: Color = GameState.team_colors[0]
	var stock_bolt: Color = GameState.bolt_colors[0]

	var purple := -1
	for i in Loadout.TEAM_TINTS.size():
		if str(Loadout.TEAM_TINTS[i]["name"]) == "PURPLE":
			purple = i
	_ok(purple > 0, "there is no PURPLE tint")
	GameState.team_tint[0] = purple
	GameState.refresh_sides()
	var chip: Color = GameState.team_colors[0]
	var bolt: Color = GameState.bolt_colors[0]
	_ok(chip != stock_chip, "the chosen tint did not reach the armour")
	_ok(bolt != stock_bolt, "the chosen tint did not reach the BOLT")
	# The two have to be recognisably the same colour, or the tracer is somebody
	# else's side. Hue is the thing that carries that; value deliberately differs.
	_ok(absf(wrapf(chip.h - bolt.h, -0.5, 0.5)) < 0.06,
		"chip hue %.2f and bolt hue %.2f are different colours" % [chip.h, bolt.h])
	print("  purple: chip %s, bolt %s" % [chip.to_html(false), bolt.to_html(false)])

	# BLACK IS THE ONE THAT BREAKS A NAIVE DERIVATION. As a chip it is fine; as a
	# tracer it would be invisible, which is why `tint_bolt` has a value FLOOR
	# rather than a multiplier.
	var black := -1
	for i in Loadout.TEAM_TINTS.size():
		if str(Loadout.TEAM_TINTS[i]["name"]) == "BLACK":
			black = i
	GameState.team_tint[0] = black
	GameState.refresh_sides()
	_ok(GameState.bolt_colors[0].v > 0.6,
		"a BLACK side fires a bolt at value %.2f — nobody can see that"
			% GameState.bolt_colors[0].v)
	print("  black:  chip %s, bolt %s" % [GameState.team_colors[0].to_html(false),
		GameState.bolt_colors[0].to_html(false)])

	# ...and 0 means "leave it alone", which is what not touching the row gives.
	GameState.team_tint[0] = 0
	GameState.refresh_sides()
	_ok(GameState.team_colors[0] == stock_chip,
		"clearing the tint did not restore the faction's own colour")
	_ok(GameState.bolt_colors[0] == stock_bolt,
		"clearing the tint did not restore the faction's own bolt")
	print("  cleared: back to %s" % GameState.team_colors[0].to_html(false))
	_done["tints"] = true
