extends Node3D
## CONQUEST logic: faction builds, command-post capture, reinforcement bleed and
## defeat, and where a chosen post actually spawns you. The input-driven bits of
## the spawn screen can't be polled headlessly, so those are exercised by calling
## the same methods the poll would (spawn_post/spawn_class + _conquest_spawn_*).
##
##   godot --headless --path godot tests/conquest.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")
const POST := preload("res://scripts/command_post.gd")

var _fails: Array[String] = []


## A minimal combatant: enough for a CommandPost's head count (team, is_alive,
## global_position). Real players work too but are far heavier to place.
class Dummy extends Node3D:
	var team := 0
	func is_alive() -> bool: return true


func _ready() -> void:
	GameState.mode = GameState.Mode.CONQUEST
	GameState.team_count = 2
	GameState.free_for_all = false
	GameState.score_targets[GameState.Mode.CONQUEST] = 10  # small pool, quick to drain
	GameState.reset_match()
	GameState.match_live = true

	_test_faction_builds()
	_test_capture()
	_test_tickets_and_defeat()
	await _test_spawn_transform()

	print("\n==== %s ====" % ("CONQUEST WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _test_faction_builds() -> void:
	print("== faction builds ==")
	_expect(Loadout.FACTION_BUILDS.size() == 8, "eight faction classes")
	for i in Loadout.FACTION_BUILDS.size():
		var b := Loadout.faction_build(i)
		var cls: int = b.deploy_class()
		var ok: bool = Weapon.PROFILES.has(cls)
		_expect(ok, "%s deploys a real weapon (%d)" % [Loadout.FACTION_BUILDS[i]["name"], cls])
	# The two rosters, and the Super Battle Droid's wrist cannon (a gun the shop
	# does not sell, reached via primary_override).
	_expect(Loadout.faction_classes(0).size() == 4, "Republic has four classes")
	_expect(Loadout.faction_classes(1).size() == 4, "Separatist has four classes")
	var sbd := Loadout.team_build(1, 1)   # Separatist slot 1 = Super Battle Droid
	_expect(sbd.deploy_class() == Weapon.Class.WRIST_CANNON,
		"the Super Battle Droid carries the wrist cannon, got %s" % sbd.weapon_name())
	var tac := Loadout.team_build(1, 3)   # Tactical Droid: no primary, revolver sidearm
	_expect(not tac.has_primary(), "the Tactical Droid has no primary")
	_expect(tac.secondary_class() == Weapon.Class.REVOLVER, "...and a revolver sidearm")


func _test_capture() -> void:
	print("\n== capturing a post ==")
	var post: CommandPost = POST.new()
	add_child(post)
	post.setup(Vector3(30, 0, 0), -1, "ALPHA")   # neutral
	# Two of team 1 stand on it; nobody else.
	for k in 2:
		var d := Dummy.new()
		d.team = 1
		add_child(d)
		d.global_position = Vector3(30 + k * 0.5, 0, 0)
		GameState.register_combatant(d)
	_expect(post.owner_team == -1, "starts neutral")
	# Step it past CAPTURE_TIME.
	var steps := int(CommandPost.CAPTURE_TIME / 0.1) + 4
	for s in steps:
		post._physics_process(0.1)
	_expect(post.owner_team == 1, "team 1 captured it after holding it, owner=%d" % post.owner_team)
	_expect(GameState.owned_posts(1).has(post), "and GameState reports team 1 owns it")
	_expect(GameState.posts_held(1) == 1 and GameState.posts_held(0) == 0,
		"post tally: team1=%d team0=%d" % [GameState.posts_held(1), GameState.posts_held(0)])


func _test_tickets_and_defeat() -> void:
	print("\n== tickets & defeat ==")
	var start0: int = int(GameState.tickets[0])
	_expect(start0 == 10, "team 0 seeded to the chosen 10 reinforcements, got %d" % start0)
	GameState.report_death(0)          # a death spends one
	_expect(int(GameState.tickets[0]) == 9, "a death costs a reinforcement")
	GameState.conquest_bleed(0, 3)     # holding fewer posts bleeds more
	_expect(int(GameState.tickets[0]) == 6, "a bleed drains the deficit")
	var won := {"team": -1}
	GameState.match_won.connect(func(t: int) -> void: won["team"] = t)
	GameState.conquest_bleed(0, 99)    # run team 0 dry
	_expect(int(GameState.tickets[0]) == 0, "reinforcements floor at zero")
	_expect(GameState.match_over, "the match ends when a side runs out")
	_expect(won["team"] == 1, "and the side with reinforcements (team 1) wins, got %d" % won["team"])


func _test_spawn_transform() -> void:
	print("\n== spawn on a chosen post ==")
	# A fresh match so match_over/tickets don't interfere.
	GameState.reset_match()
	GameState.match_live = true
	var a: CommandPost = POST.new(); add_child(a); a.setup(Vector3(-20, 0, 5), 0, "HQ")
	var b: CommandPost = POST.new(); add_child(b); b.setup(Vector3(20, 0, -5), 0, "BRAVO")
	var p: Player = PLAYER.instantiate()
	p.input_device = 0
	p.team = 0
	add_child(p)
	await get_tree().physics_frame
	var owned := GameState.owned_posts(0)
	_expect(owned.size() == 2, "team 0 holds both its posts, got %d" % owned.size())
	# Selecting post index 1 must land you on that post.
	p.spawn_post = owned.find(b)
	var xform := p._conquest_spawn_transform()
	_expect(xform.origin.distance_to(b.spawn_transform().origin) < 0.01,
		"deploy lands on the selected post")
	# And the chosen class becomes the deployed loadout.
	p.spawn_class = 2   # Republic slot 2 = Clone Heavy (the T-21 HMG)
	p.pending = Loadout.team_build(p.team, p.spawn_class)
	_expect(p.pending.weapon_class() == Weapon.Class.HMG,
		"the selected class is what deploys (Clone Heavy = HMG)")

	# --- Conquest with CUSTOM classes ------------------------------------
	#
	# The class source is a setting now, so Conquest can be played off the buy
	# screen. Choosing where you come back in is a CONQUEST rule rather than a
	# character-select one, so the buy screen has to carry the post box too —
	# otherwise picking custom classes would quietly take the mode's own
	# mechanic away from you.
	print("\n== Conquest on the buy screen ==")
	GameState.class_mode = GameState.ClassMode.CUSTOM
	_expect(not GameState.faction_classes(), "Conquest can be played on custom classes")
	p.buy_box = Player.POST_BOX
	p.buy_inside = false
	p.apply_buy_input(Vector2i.ZERO, true, false)
	_expect(p.buy_inside, "the deploy-post box opens on the buy screen")
	var post_before := p.spawn_post
	p.apply_buy_input(Vector2i.DOWN, false, false)
	_expect(p.spawn_post != post_before, "and walks the posts your side holds")
	var build_before := p.pending.weapon_class()
	p.apply_buy_input(Vector2i.DOWN, false, false)
	_expect(p.pending.weapon_class() == build_before,
		"...while changing nothing about the build")
	GameState.class_mode = GameState.ClassMode.FACTION


func _expect(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
