extends Node3D

## What range each AI skill tier fights at, per weapon.
##
##   godot --headless --path godot tests/bot_range.tscn
##
## The engagement range is DERIVED (Bot._hit_reach / _hold_range) rather than a
## flat number per tier, so this prints the whole table and checks the
## properties that derivation is supposed to guarantee: a tier never fights
## closer than it used to, better aim fights further out, a scoped rifle opens
## the range right up, and a weapon that cannot reach still closes to arm's
## length.

const BOT := preload("res://scenes/actors/bot.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	var guns := [
		["DC-15 rifle", Weapon.Class.SOLDIER, {}],
		["A280 semi", Weapon.Class.SEMI, {}],
		["NT-242 sniper", Weapon.Class.SNIPER, {"sight": Loadout.Sight.SCOPE}],
		["Z-6 repeater", Weapon.Class.HEAVY, {}],
		["scattergun", Weapon.Class.SCATTERGUN, {}],
		["lightsaber", Weapon.Class.SABER, {}],
	]
	print("== stand-off by skill tier (metres) ==")
	print("  weapon             recruit  regular  veteran  elite")
	for row in guns:
		var line := "  %-18s" % row[0]
		var holds: Array[float] = []
		for tier in Bot.SKILLS.size():
			var bot := _bot(tier, row[1], row[2])
			holds.append(bot._hold_range())
			line += "  %6.1f " % holds[tier]
			bot.queue_free()
		print(line)
		# Better aim never fights closer with the same gun in its hands.
		for t in range(1, holds.size()):
			_expect(holds[t] >= holds[t - 1] - 0.01,
				"%s: tier %d holds at least as far as tier %d" % [row[0], t, t - 1])
		# ...and nothing closes further than the tier's own floor used to.
		for t in holds.size():
			var floor_m: float = minf(float(Bot.SKILLS[t]["hold"]),
				Weapon.PROFILES[row[1]]["range"] * 0.8)
			_expect(holds[t] >= floor_m - 0.01,
				"%s: tier %d never closes inside its old stand-off" % [row[0], t])

	# The headline: the top tiers must actually open the range up with a scoped
	# rifle, which is the whole point of deriving this.
	var elite_sniper := _bot(3, Weapon.Class.SNIPER, {"sight": Loadout.Sight.SCOPE})
	var elite_rifle := _bot(3, Weapon.Class.SOLDIER, {})
	print("\n== the marksman check ==")
	print("  elite + scoped sniper holds at %.1f m, sees to %.1f m" % [
		elite_sniper._hold_range(), elite_sniper._sight_range()])
	print("  elite + plain rifle   holds at %.1f m" % elite_rifle._hold_range())
	_expect(elite_sniper._hold_range() > 45.0,
		"an elite behind a scope fights past 45 m")
	_expect(elite_sniper._hold_range() > elite_rifle._hold_range() + 10.0,
		"...and much further than the same bot with an iron-sighted rifle")
	_expect(elite_sniper._sight_range() > float(Bot.SKILLS[3]["sight"]),
		"a scope also spots further, so it has something to shoot at out there")

	# A weapon that cannot reach still walks in. This is the cap that keeps a
	# saber bot from standing at range swinging at the air.
	var saber := _bot(3, Weapon.Class.SABER, {})
	print("  elite + lightsaber    holds at %.1f m" % saber._hold_range())
	_expect(saber._hold_range() <= Weapon.PROFILES[Weapon.Class.SABER]["range"],
		"a saber bot still closes inside the blade's reach")

	print("")
	if _fails.is_empty():
		print("PASS  bot engagement ranges")
	else:
		for f in _fails:
			print("FAIL  ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)


## A bot wired up far enough to answer range questions: it needs a skill row and
## a weapon, and nothing else on it is consulted.
func _bot(tier: int, gun: Weapon.Class, mods: Dictionary) -> Bot:
	var bot: Bot = BOT.instantiate()
	add_child(bot)
	bot._skill = Bot.SKILLS[tier]
	bot.weapon.set_class(gun, mods)
	return bot


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
