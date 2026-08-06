extends Node3D

## THE PLAY-TEST BENCH: what every authored class actually feels like, in numbers.
##
##   godot --headless --path godot tests/roster_feel.tscn
##   QS_FEEL_UNIVERSE=0 godot --headless --path godot tests/roster_feel.tscn
##
## A class's FEEL is four things you can measure and one you cannot. The four:
## how fast it moves, how long it lives, how fast it kills, and how big a target
## it is. This prints all four for every class in every universe, side by side,
## because that comparison is the entire balance surface of the roster and until
## now it existed nowhere — you could only find out that the Royal Guard was the
## fastest unit in the game by playing as one and noticing.
##
## Two numbers carry most of it, and they are a PAIR:
##   TTK OUT — how long this class needs to kill a standard trooper.
##   TTK IN  — how long a standard trooper needs to kill this class.
## A reinforcement earns its slot by winning that trade; a line class sits near
## 1.0 on both; and anything that wins both by a wide margin is not a character,
## it is the only class anyone will pick.
##
## What it cannot measure is whether the class is FUN, so the assertions here are
## deliberately outer guard rails — absurdity checks, not taste. They catch the
## things that are wrong by inspection: a body nobody can kill, a body that dies
## to one round, a unit that is quicker AND tougher AND hits harder than the
## yardstick, and a class deployed with fewer abilities than its neighbours.

# The gun a "standard trooper" shoots back with, for the TTK IN column. The E-11
# is the most-fired weapon in The Compact Wars and sits mid-table on damage, which is
# what makes it a fair yardstick rather than a flattering one.
const YARDSTICK_GUN := Weapon.Class.DK11
const YARDSTICK_HEALTH := 100.0   # ARMOR[1] "NONE", which is what a line class wears

# Guard rails. Wide on purpose: this is asking "is this absurd", not "is this
# balanced" — taste is what the game is for.
const TTK_IN_MIN := 0.45    # seconds. Below this a body dies before it reacts.
const TTK_IN_MAX := 5.00    # above this nobody can be dislodged from a doorway.
const STATURE_MIN := 0.55
const STATURE_MAX := 1.20   # see the ceiling note in FACTION_BUILDS
const SPEED_MIN := 0.55
const SPEED_MAX := 1.55

# THE TRADE CEILING: how many times longer a class may take to kill than it takes
# to be killed, against a standard rifleman. A reinforcement is meant to win this
# trade — that is what a reinforcement IS — so the rail is set well above where
# any line class sits (around 1.0) and above where the heavies sit (2-3.5). What
# it catches is a class that wins by so much that picking anything else is a
# mistake: the three flamers were at 4.2-4.9, top of all three rosters, killing
# in under a third of a second.
const TRADE_MAX := 4.0
# A KILL FASTER THAN THIS IS NOT A FIGHT. Human reaction is around a quarter of
# a second before you have even begun to turn, so a weapon that empties a full
# health bar in less reads to the victim as having simply been deleted. It is a
# floor on the whole game's time-to-kill, not a balance number.
const TTK_OUT_MIN := 0.35

# What "closes ground" means, resolved through gadget_action() so an alias
# counts: a thruster pack, a grav lift, a dimensional bound, a Waaagh! and a
# jump pack are five names for four behaviours, and every one of them answers
# the question a melee class has to be able to answer.
const CLOSERS := [Loadout.Gadget.DASH, Loadout.Gadget.JETPACK,
	Loadout.Gadget.KINETIC_LEAP, Loadout.Gadget.CABLE, Loadout.Gadget.FURY]

var _fails: Array[String] = []


func _ready() -> void:
	var only := -1
	if OS.has_environment("QS_FEEL_UNIVERSE"):
		only = int(OS.get_environment("QS_FEEL_UNIVERSE"))
	for u in Loadout.UNIVERSES.size():
		if only >= 0 and u != only:
			continue
		_report_universe(u)
	_cross_checks()

	print("")
	if _fails.is_empty():
		print("PASS  roster feel")
	else:
		for f in _fails:
			print("FAIL  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## Every class of one universe, as one table.
func _report_universe(universe: int) -> void:
	var rows := _rows_for(universe)
	if rows.is_empty():
		return
	print("\n== %s ==" % Loadout.UNIVERSES[universe]["name"])
	print("  class               HP   walk  jump  tall   TTK    TTK    TTK   trade  rnds  reach  abil  weapon")
	print("                          (m/s)  (m)   (m)   out    hot     in                       (m)")
	for r in rows:
		print("  %-18s %4d  %4.1f  %4.2f  %4.2f  %5s  %5s  %5s  %5.2f  %3d  %5.0f   %d   %s" % [
			r["name"], roundi(r["hp"]), r["walk"], r["jump"],
			r["tall"], _secs(r["ttk_out"]), _secs(r["ttk_hot"]),
			_secs(r["ttk_in"]), r["trade"], r["shots"], r["reach"],
			r["abilities"], r["gun"]])
		_check_row(r)
	_report_extremes(rows)


## The measured picture of one class. Everything here is read through the same
## functions the game itself deploys with (Loadout.max_health / move_speed /
## jump_power / stature), so a number that is wrong here is wrong in the match.
func _row(index: int) -> Dictionary:
	var build := Loadout.faction_build(index)
	var preset: Dictionary = Loadout.FACTION_BUILDS[index]
	var gun: int = build.deploy_class()
	var profile: Dictionary = Weapon.PROFILES[gun]
	var hp: float = build.max_health()
	var dps := _dps(profile)
	var yard: float = _dps(Weapon.PROFILES[YARDSTICK_GUN])
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var jump_v: float = Player.JUMP_VELOCITY * build.jump_power()
	return {
		"name": preset.get("name", "?"),
		"hp": hp,
		"walk": Player.WALK_SPEED * build.move_speed(),
		"sprint": Player.SPRINT_SPEED * build.move_speed(),
		"jump": jump_v * jump_v / (2.0 * gravity),
		"tall": GameState.TROOPER_HEIGHT * build.stature(),
		"speed_mult": build.move_speed(),
		"ttk_out": YARDSTICK_HEALTH / dps if dps > 0.0 else INF,
		"ttk_hot": YARDSTICK_HEALTH / _dps(profile, true) if dps > 0.0 else INF,
		"ttk_in": hp / yard,
		# HOW THIS CLASS TRADES with a standard rifleman: how many times longer it
		# takes to kill than it takes to be killed. 1.0 is an even fight, and a
		# line class should sit near it. A reinforcement is SUPPOSED to win this —
		# that is what a reinforcement is — but the number is what says whether it
		# wins it by being strong or by being the only thing anybody picks.
		"trade": (hp / yard) / (YARDSTICK_HEALTH / dps) if dps > 0.0 else 0.0,
		# ROUNDS TO KILL is the number a player actually feels. Nobody counts
		# milliseconds, everybody notices that the sniper is one shot and the SMG
		# is nine — and it is the number that says whether a gun's damage is a
		# breakpoint or a rounding error, which a DPS figure hides completely.
		"shots": ceili(YARDSTICK_HEALTH / _per_shot(profile)),
		"abilities": _ability_count(preset),
		"gun": profile.get("name", "?"),
		"melee": profile.get("melee", false),
		"reach": profile.get("range", 0.0),
		"closer": _has_closer(preset),
		"stature": build.stature(),
	}


## Does this build carry anything that CLOSES GROUND? A melee class that is
## slower than a rifleman and has no answer to that is not a hard matchup, it is
## an impossible one — it can be walked backwards away from, forever, by every
## gun in the game. Four classes shipped like that (the Brute Chieftain, the
## Vanguard Veteran, the Unsleeping Lord and, before its roll, the Aegis Drone).
func _has_closer(preset: Dictionary) -> bool:
	for key in ["gadget", "gadget2", "gadget3"]:
		var g: int = int(preset.get(key, 0))
		if g != Loadout.Gadget.NONE and Loadout.gadget_action(g) in CLOSERS:
			return true
	return false


## Damage per second, in the two forms that actually decide a fight.
##
## BURST is rate x damage x pellets — how hard the first second hits, which is
## what kills somebody and therefore what TTK is measured from.
##
## SUSTAINED is what the heat model allows once the gun is hot: a weapon can only
## keep firing at `cool_rate / heat_per_shot` shots a second, so a gun that empties
## its heat pool in half a second is a far smaller gun than its burst number says.
## Heat used to be left out here on the grounds that it "decides how long a burst
## lasts, not how hard it hits" — which is true and was still the wrong call,
## because it is precisely the thing balancing every heavy weapon in the game.
## Leaving it out reported the T-21 and the DC-17m as the two hardest-hitting guns
## on the Concord roster, and neither can hold its trigger for a full second.
func _dps(profile: Dictionary, sustained := false) -> float:
	var interval: float = maxf(float(profile.get("fire_interval", 1.0)), 0.001)
	var pellets: int = profile.get("pellets", 1)
	var rate := 1.0 / interval
	# A BURST weapon fires `burst_count` rounds at `fire_interval` and then waits
	# `burst_interval`, so its real rate is the whole cycle — the DC-17m looked
	# like a 13-per-second rifle and is a three-round burst you cannot rush.
	var burst: int = profile.get("burst_count", 0)
	if burst > 1:
		rate = burst / (burst * interval + float(profile.get("burst_interval", 0.0)))
	if sustained:
		var heat: float = float(profile.get("heat_per_shot", 0.0))
		if heat > 0.0:
			rate = minf(rate, float(profile.get("cool_rate", 0.0)) / heat)
	# A LAUNCHER DOES ALL ITS DAMAGE WITH SPLASH and carries `damage: 0.0`, so
	# reading the direct number alone reported the Rocketeer, the Tankbusta and
	# the Grunt Heavy as dealing NO damage at all — three classes the harness was
	# silently declining to measure, which is worse than measuring them roughly.
	# Full splash damage assumes a direct hit; that is the shot those weapons are
	# aimed for and the one their TTK should be quoted at.
	return _per_shot(profile) * rate


## What ONE trigger pull puts on one body: every pellet, or the splash if that is
## all the weapon has. Deliberately not direct PLUS splash — a launcher's blast is
## shared with whoever else is standing there and a direct hit is the shot it is
## aimed for, so taking the larger of the two is the honest single number.
func _per_shot(profile: Dictionary) -> float:
	var direct: float = float(profile["damage"]) * int(profile.get("pellets", 1))
	return maxf(direct, float(profile.get("splash_damage", 0.0)))


## How many of the three gadget slots this class actually deploys with. A class
## carrying one where its neighbours carry three is not a design decision, it is
## a row somebody stopped filling in — which is exactly what the Compact Wars
## rosters were before this pass.
func _ability_count(preset: Dictionary) -> int:
	var n := 0
	for key in ["gadget", "gadget2", "gadget3"]:
		if int(preset.get(key, 0)) != Loadout.Gadget.NONE:
			n += 1
	return n


func _check_row(r: Dictionary) -> void:
	var who: String = r["name"]
	# TTK IN is checked against the EFFECTIVE figure, not the raw one. A body is
	# scaled in height only, so the target a shooter has to track is smaller in
	# proportion to its stature and takes correspondingly longer to empty — an
	# Kobb's 48 HP is not the 0.32 s it looks like on paper. Without this the
	# floor would forbid exactly the units that are supposed to be tiny.
	var eff: float = r["ttk_in"] / r["stature"]
	_expect(eff >= TTK_IN_MIN,
		"%s dies in %.2fs (%.2f allowing for its size) to a standard rifle — too soft to play" % [
			who, r["ttk_in"], eff])
	_expect(r["ttk_in"] <= TTK_IN_MAX,
		"%s takes %.2fs to kill with a standard rifle — nothing shifts it" % [who, r["ttk_in"]])
	_expect(r["stature"] >= STATURE_MIN and r["stature"] <= STATURE_MAX,
		"%s stands %.2f m — outside the range the maps and cover were built for" % [who, r["tall"]])
	_expect(r["speed_mult"] >= SPEED_MIN and r["speed_mult"] <= SPEED_MAX,
		"%s moves at x%.2f — outside what the animations and nav grid expect" % [who, r["speed_mult"]])
	_expect(r["abilities"] >= 2,
		"%s deploys with only %d ability slots filled" % [who, r["abilities"]])
	_expect(r["trade"] <= TRADE_MAX,
		"%s trades at x%.2f against a rifleman (kills in %.2fs, dies in %.2fs) — nothing else on its roster is worth picking" % [
			who, r["trade"], r["ttk_out"], r["ttk_in"]])
	_expect(r["ttk_out"] >= TTK_OUT_MIN,
		"%s empties a trooper in %.2fs with the %s — under reaction time, so being killed by it is not a fight" % [
			who, r["ttk_out"], r["gun"]])
	# A short-reach melee class must either out-run a rifleman or carry
	# something that closes the gap. Neither is fine on its own; NEITHER is a
	# class that can be kited to death by anybody holding a trigger.
	if r["melee"] and r["reach"] < 6.0:
		_expect(r["speed_mult"] >= 1.0 or r["closer"],
			"%s fights at %.1f m, moves at x%.2f and carries nothing that closes ground" % [
				who, r["reach"], r["speed_mult"]])


## The two ends of each table, which is where a roster goes wrong first.
func _report_extremes(rows: Array) -> void:
	var by_speed := rows.duplicate()
	by_speed.sort_custom(func(a, b): return a["speed_mult"] > b["speed_mult"])
	var by_hp := rows.duplicate()
	by_hp.sort_custom(func(a, b): return a["hp"] > b["hp"])
	print("  fastest: %-18s x%.2f      toughest: %-18s %d HP" % [
		by_speed[0]["name"], by_speed[0]["speed_mult"],
		by_hp[0]["name"], roundi(by_hp[0]["hp"])])
	print("  slowest: %-18s x%.2f      softest:  %-18s %d HP" % [
		by_speed[-1]["name"], by_speed[-1]["speed_mult"],
		by_hp[-1]["name"], roundi(by_hp[-1]["hp"])])
	# THE ONE THAT MATTERS: nothing may top both columns. A unit that is the
	# fastest AND the hardest to kill is not a class, it is the answer to the
	# question "which class should I pick", and every other row becomes scenery.
	# The Royal Guard was doing exactly this before it had a physique of its own
	# — it inherited Kinesis kit's x1.2 speed on top of heavy plate.
	_expect(by_speed[0]["name"] != by_hp[0]["name"],
		"%s is both the fastest and the toughest class on its roster" % by_speed[0]["name"])


## Properties that are about the roster as a whole rather than one class.
func _cross_checks() -> void:
	print("\n== across every roster ==")
	var spread := {}
	var statures: Array[float] = []
	for i in Loadout.FACTION_BUILDS.size():
		var r := _row(i)
		statures.append(r["tall"])
		var key: String = "%.2f|%.2f" % [r["speed_mult"], r["hp"]]
		if not spread.has(key):
			spread[key] = []
		spread[key].append(r["name"])
	statures.sort()
	print("  %d classes, standing %.2f m to %.2f m" % [
		Loadout.FACTION_BUILDS.size(), statures[0], statures[-1]])
	# Bodies that are byte-identical are the symptom this whole physique table
	# exists to cure: before it, every class on the default kit wearing the same
	# armour frame was the same body, and "which one am I" was answered only by
	# the colour. A few duplicates are fine — two officers should feel alike —
	# but a roster where most classes share a body has no roster.
	var dupes := 0
	for key in spread:
		if spread[key].size() > 1:
			dupes += spread[key].size() - 1
	var distinct: int = Loadout.FACTION_BUILDS.size() - dupes
	print("  %d distinct bodies (speed x health) out of %d classes" % [
		distinct, Loadout.FACTION_BUILDS.size()])
	_expect(float(distinct) / Loadout.FACTION_BUILDS.size() >= 0.5,
		"only %d of %d classes have a body of their own" % [
			distinct, Loadout.FACTION_BUILDS.size()])


## The FACTION_BUILDS indices belonging to one universe, via its own rosters.
func _rows_for(universe: int) -> Array:
	var seen := {}
	var out := []
	for roster in Loadout.FACTION_ROSTERS.get(universe, []):
		for index in roster:
			if seen.has(index):
				continue
			seen[index] = true
			out.append(_row(index))
	return out


func _secs(v: float) -> String:
	return "  inf" if is_inf(v) else "%5.2f" % v


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
