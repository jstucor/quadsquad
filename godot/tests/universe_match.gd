extends Node

## Boots a REAL match in every universe, in both class modes, and checks that
## everybody who deployed is holding something legal.
##
##   godot --headless --path godot tests/universe_match.tscn
##
## The catalogue tests (kit_rules) prove the tables agree with each other. This
## proves the game can actually be played out of them: that Main builds the
## viewports, that team fill finds AI presets for the universe, that the faction
## rosters resolve to bodies and weapons, and that nothing along the way reaches
## for a The Compact Wars default that is no longer there.

const MAIN := preload("res://scenes/main.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	for u in Loadout.UNIVERSES.size():
		for faction in [false, true]:
			await _run(u, faction)
	await _ttk_check()
	print("\n==== %s ====" % ("EVERY UNIVERSE PLAYS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _run(universe: int, faction: bool) -> void:
	GameState.universe = universe
	GameState.class_mode = GameState.ClassMode.FACTION if faction \
		else GameState.ClassMode.CUSTOM
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.human_players = 1
	GameState.team_size = 2
	GameState.team_count = 2
	GameState.map_index = 0
	GameState.chosen_teams = []

	var main: Node = MAIN.instantiate()
	add_child(main)
	await _frames(40)

	var label := "%s / %s" % [Loadout.UNIVERSES[universe]["name"],
		"faction" if faction else "custom"]
	var bodies := GameState.combatants.duplicate()
	if bodies.size() < 4:
		_fails.append("%s: only %d combatants on the field" % [label, bodies.size()])
	var seen := {}
	for c in bodies:
		if not is_instance_valid(c) or c.loadout == null:
			continue
		var kit_u: int = Loadout.kit_universe(c.loadout.kit)
		if kit_u != universe:
			_fails.append("%s: a %s deployed from another universe"
				% [label, c.loadout.kit_name()])
		# ...and it is holding a real weapon, not an index that fell off the end.
		var cls: int = c.loadout.deploy_class()
		if not Weapon.PROFILES.has(cls):
			_fails.append("%s: %s deployed holding class %d, which has no profile"
				% [label, c.loadout.kit_name(), cls])
		seen[Weapon.PROFILES[cls]["name"] if Weapon.PROFILES.has(cls) else "?"] = true
	print("%-34s %2d bodies   %s" % [label, bodies.size(), str(seen.keys())])

	remove_child(main)
	main.queue_free()
	await _frames(4)


## TIME TO KILL scales health and nothing else, so what has to be true is that
## the setting reaches the BODY — not just Loadout's arithmetic. Deploys a real
## match at each setting and reads the health the player actually spawned with.
func _ttk_check() -> void:
	print("\n== time to kill ==")
	GameState.universe = Loadout.Universe.COMPACT
	GameState.class_mode = GameState.ClassMode.CUSTOM
	var base := 0.0
	for t in GameState.TTK_NAMES.size():
		GameState.ttk = t
		var main: Node = MAIN.instantiate()
		add_child(main)
		await _frames(30)
		var player: Player = null
		for c in GameState.combatants:
			if c is Player:
				player = c
				break
		var want: float = float(GameState.TTK_HEALTH[t])
		if player == null:
			_fails.append("TTK %s: no player deployed" % GameState.TTK_NAMES[t])
		else:
			print("  %-10s %6.1f HP" % [GameState.TTK_NAMES[t], player.max_health])
			if t == GameState.Ttk.MEDIUM and not is_equal_approx(want, 1.0):
				_fails.append("MEDIUM must be the game unchanged, not x%.2f" % want)
			if base > 0.0 and not is_equal_approx(player.max_health / base, want):
				_fails.append("TTK %s gave x%.2f health, expected x%.2f" % [
					GameState.TTK_NAMES[t], player.max_health / base, want])
			if base == 0.0:
				base = player.max_health / want
		remove_child(main)
		main.queue_free()
		await _frames(4)
	GameState.ttk = GameState.Ttk.MEDIUM


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
