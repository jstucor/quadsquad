extends Node
## KILL STREAK REWARDS.
##
## Most of what this protects is a GATE holding — that a Spartan cannot call down
## a LAAT, that a Wookiee is not offered a Force master's saber, that a reward
## fires ONCE. Gates are the part that fails silently: a reward wrongly available
## still works perfectly, it is just somebody else's.
##
## The rest is the one thing a transformation is most likely to get wrong. A
## BECOME reward runs `_apply_loadout`, which is also what a fresh DEPLOY runs —
## so it resets the kill counter and the taken-set unless something puts them
## back, and a Juggernaut that re-earns itself heals to full on every kill.

const PLAYER := preload("res://scenes/actors/player.tscn")

var _fails: Array[String] = []
## Which check functions reached their last line — see the note in `_ready`.
var _done := {}


func _ready() -> void:
	print("\n==== kill streak rewards ====")
	if GameState == null or not GameState.has_method("crowded"):
		print("  FAIL: GameState did not load — every check below would be hollow")
		print("==== 1 FAILURES ====")
		get_tree().quit(1)
		return
	_check_table()
	_check_gates()
	_check_thresholds()
	await _check_become()
	# EVERY SECTION MUST HAVE FINISHED. A GDScript error aborts the enclosing
	# function silently (house rule 6), so a bad call halfway down a check skips
	# the rest of its assertions and the run still reports success — which is
	# exactly what happened here the first time, on a mistyped GameState call.
	# Each check signs off at its own end and this counts the signatures.
	var want := ["table", "gates", "thresholds", "become"]
	for name in want:
		if not _done.has(name):
			_fails.append("the `%s` checks did not run to the end — something in "
				% name + "them errored, and every assertion after it was skipped")
	print("")
	if _fails.is_empty():
		print("==== STREAKS HOLD ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## Every row has to state the keys the granting switch reads, or a reward is
## earned and nothing happens — which reads as a bug in the streak counter.
func _check_table() -> void:
	print("\n-- every row is grantable --")
	for row in Streaks.REWARDS:
		var name: String = str(row.get("name", "?"))
		for key in ["name", "kills", "kind", "blurb"]:
			_ok(row.has(key), "%s has no `%s`" % [name, key])
		match int(row.get("kind", -1)):
			Streaks.Kind.VEHICLE:
				var id: String = str(row.get("vehicle", ""))
				_ok(Vehicle.STREAK_VEHICLES.has(id),
					"%s names vehicle `%s`, which is not in Vehicle.STREAK_VEHICLES"
						% [name, id])
			Streaks.Kind.BECOME:
				_ok(row.has("preset"), "%s is a BECOME with no preset" % name)
			Streaks.Kind.RECON, Streaks.Kind.BOMBARDMENT:
				_ok(row.has("duration"), "%s has no duration" % name)
			_:
				_fails.append("%s has an unknown kind" % name)
		print("  %-16s %2d kills  %s" % [name, int(row.get("kills", 0)),
			Streaks.Kind.keys()[int(row.get("kind", 0))]])
	# A BECOME PRESET MUST DEPLOY THE GUN IT NAMES. Same strict question
	# kit_rules asks of every AI preset: `weapon_index` answers NO_PRIMARY for a
	# gun the catalogue does not sell, which is legal and completely wrong.
	for row in Streaks.REWARDS:
		if int(row.get("kind", -1)) != Streaks.Kind.BECOME:
			continue
		var built := Loadout.preset_build(row["preset"])
		var want: int = int(row["preset"]["primary"])
		_ok(built.deploy_class() == want,
			"%s asked for weapon class %d and deployed %d — silently disarmed"
				% [str(row["name"]), want, built.deploy_class()])
	_done["table"] = true


## THE GATES. Checked from both directions: the owner gets it and nobody else
## does. Only the second direction catches a `kits` key that was never read.
func _check_gates() -> void:
	print("\n-- a gated reward belongs to somebody in particular --")
	GameState.universe = Loadout.Universe.STAR_WARS

	var force := _names(Streaks.available(Loadout.Kit.FORCE, 0))
	var clone := _names(Streaks.available(Loadout.Kit.CLONE, 0))
	var wook := _names(Streaks.available(Loadout.Kit.WOOKIEE, 0))
	print("  republic force adept : %s" % str(force))
	print("  republic clone       : %s" % str(clone))
	print("  republic wookiee     : %s" % str(wook))

	_ok(force.has("FORCE MASTER"), "the Force adept cannot earn a Force master")
	_ok(not clone.has("FORCE MASTER"), "a clone was offered a Force master")
	_ok(wook.has("JUGGERNAUT"), "the Wookiee cannot earn a Juggernaut")
	_ok(not force.has("JUGGERNAUT"), "the Force adept was offered a Juggernaut")
	# Everybody reaches the two universal ones, or the reward is a class perk.
	for who in [force, clone, wook]:
		_ok(who.has("RECON SWEEP") and who.has("ORBITAL STRIKE"),
			"a class cannot reach the universal rewards: %s" % str(who))

	# TEAM gating: the Republic flies a gunship, the Empire walks.
	_ok(clone.has("LAAT GUNSHIP"), "the Republic cannot earn its gunship")
	_ok(not clone.has("AT-ST WALKER"), "the Republic was offered an AT-ST")
	var imp := _names(Streaks.available(Loadout.Kit.CLONE, 2))
	_ok(imp.has("AT-ST WALKER"), "the Empire cannot earn its walker")
	_ok(not imp.has("LAAT GUNSHIP"), "the Empire was offered a LAAT")
	print("  empire               : %s" % str(imp))

	# UNIVERSE gating, which is the one a team index alone cannot express: team 0
	# is the Republic in Star Wars and somebody else entirely in Halo.
	GameState.universe = Loadout.Universe.HALO
	var spartan := _names(Streaks.available(Loadout.Kit.SPARTAN, 0))
	print("  halo spartan         : %s" % str(spartan))
	_ok(not spartan.has("LAAT GUNSHIP"),
		"a Spartan on team 0 was offered a Republic gunship")
	_ok(not spartan.has("FORCE MASTER"), "a Spartan was offered the Force")
	_ok(spartan.has("RECON SWEEP"), "a Spartan cannot earn a recon sweep")
	GameState.universe = Loadout.Universe.STAR_WARS
	_done["gates"] = true


func _names(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for r in rows:
		out.append(str(r["name"]))
	return out


## ONE REWARD PER KILL, and the thresholds are crossed rather than reached — a
## body already past a threshold when the list is built must not collect it.
func _check_thresholds() -> void:
	print("\n-- thresholds are crossed, one at a time --")
	var rows := Streaks.available(Loadout.Kit.CLONE, 0)
	_ok(Streaks.earned(rows, 3, 4).get("name", "") == "RECON SWEEP",
		"crossing 4 kills did not pay the recon sweep")
	_ok(Streaks.earned(rows, 4, 5).is_empty(),
		"a kill between thresholds paid a reward")
	_ok(Streaks.earned(rows, 0, 4).get("name", "") == "RECON SWEEP",
		"jumping straight to 4 did not pay")
	# Two thresholds crossed at once pays the LOWER, so the announcements stay
	# one to a kill rather than stacking.
	var both := Streaks.earned(rows, 3, 99)
	_ok(both.get("name", "") == "RECON SWEEP",
		"crossing every threshold at once paid `%s`, not the lowest"
			% str(both.get("name", "-")))
	print("  3->4 %s   4->5 %s   3->99 %s" % [
		Streaks.earned(rows, 3, 4).get("name", "-"),
		Streaks.earned(rows, 4, 5).get("name", "-"),
		both.get("name", "-")])
	_done["thresholds"] = true


## The transformation, on a real Player. This is the half that would regress
## silently: everything still WORKS if the counter resets, it just quietly
## becomes impossible to climb past the first BECOME reward you earn.
func _check_become() -> void:
	print("\n-- becoming something else keeps the streak --")
	GameState.match_live = true
	var p: Player = PLAYER.instantiate()
	add_child(p)
	await get_tree().process_frame
	p.team = 0
	p.pending = Loadout.new()
	p.pending.adopt_kit(Loadout.Kit.WOOKIEE)
	p._apply_loadout()
	await get_tree().process_frame

	var before_health := p.max_health
	for i in 6:
		p.credit_kill()
	await get_tree().process_frame

	_ok(p.kills_this_life == 6,
		"the streak was reset by the transformation: %d, want 6" % p.kills_this_life)
	_ok(p.loadout.build_name == "JUGGERNAUT",
		"6 kills on a Wookiee did not become a Juggernaut (got `%s`)"
			% p.loadout.build_name)
	_ok(p.max_health > before_health,
		"the Juggernaut is not tougher than what it replaced (%.0f vs %.0f)"
			% [p.max_health, before_health])
	_ok(p.overshield_left() > 0.0, "the Juggernaut got no overshield")
	_ok(is_finite(p.overshield_left()),
		"the overshield lifetime is not finite — the HUD gauge reads it directly")
	print("  6 kills: %s, %.0f HP (was %.0f), overshield %.0f for %.0fs"
		% [p.loadout.build_name, p.max_health, before_health,
			p._over_pool, p.overshield_left()])

	# AND IT MUST NOT RE-EARN ITSELF. Another kill past the threshold would
	# re-run `_apply_loadout` — healing to full and re-issuing the shield.
	p.health = 10.0
	p.credit_kill()
	await get_tree().process_frame
	_ok(p.health == 10.0,
		"a Juggernaut re-earned itself and healed to %.0f" % p.health)
	print("  a 7th kill does not re-issue it (health stayed %.0f)" % p.health)
	p.queue_free()
	_done["become"] = true
