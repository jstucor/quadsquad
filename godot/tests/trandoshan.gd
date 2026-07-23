extends Node3D

## The TRANDOSHAN, deployed. kit_rules proves the allow-lists; this proves the
## behaviour those lists unlock: the cloak actually hides you from AI and drops
## when you fire, the dash gadget moves you, and the thermal sight raises.
##
##   godot --headless --path godot tests/trandoshan.tscn

const PLAYER := preload("res://scenes/actors/player.tscn")
const BOT := preload("res://scenes/actors/bot.tscn")

var _fails: Array[String] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()

	var tran := await _spawn(_build(Loadout.Gadget.CLOAK, Weapon.Class.SNIPER,
		Loadout.Sight.THERMAL), Vector3.ZERO, 0)
	await _frames(2)

	print("== deployed ==")
	print("  %s, %s + %s, sight %s" % [tran.loadout.kit_name(),
		tran.weapon.display_name(), tran.loadout.row_value(Loadout.Row.SECONDARY),
		tran.loadout.row_value(Loadout.Row.SIGHT)])
	_expect(tran.loadout.kit == Loadout.Kit.TRANDOSHAN, "it is a Trandoshan")
	_expect(tran.weapon.has_thermal(), "the thermal sight is fitted")

	# --- the cloak hides you from AI -------------------------------------
	print("\n== the cloak ==")
	var bot: Bot = BOT.instantiate()
	add_child(bot)
	bot.setup(null, 1, 3)              # an elite enemy bot
	bot.global_position = Vector3(0.0, 0.0, -14.0)
	await _frames(2)
	var seen_before := bot._can_see(tran)
	tran._use_gadget(0)               # cloak
	await _frames(2)
	print("  bot saw the Trandoshan: %s -> after cloak %s" % [
		seen_before, bot._can_see(tran)])
	_expect(seen_before, "the bot could see the Trandoshan before it cloaked")
	_expect(not bot._can_see(tran), "and cannot once it is cloaked")
	_expect(GameState.is_cloaked(tran), "GameState marks it cloaked")
	_expect(tran.cloak_left() > 0.0, "the HUD has a cloak timer to show")

	# --- firing drops it --------------------------------------------------
	print("\n== firing breaks the cloak ==")
	tran._on_weapon_fired(0.1, 0.0)   # the same signal a real shot raises
	await _frames(2)
	print("  after a shot: cloaked %s, bot sees %s" % [
		GameState.is_cloaked(tran), bot._can_see(tran)])
	_expect(not GameState.is_cloaked(tran), "a shot drops the cloak")
	_expect(bot._can_see(tran), "and the bot can see it again")

	# --- the cloak times out ---------------------------------------------
	print("\n== the cloak times out ==")
	tran._force_cd = [0.0, 0.0]
	tran._use_gadget(0)
	var waited := 0.0
	for _i in 600:
		await _frames(1)
		waited += get_physics_process_delta_time()
		if not GameState.is_cloaked(tran):
			break
	print("  lasted %.1fs (CLOAK_TIME %.1f)" % [waited, Player.CLOAK_TIME])
	_expect(not GameState.is_cloaked(tran), "the cloak ends on its own")
	_expect(tran.model.get_node("Hips").visible,
		"...and the model is left visible again")

	# --- the dash gadget moves you ---------------------------------------
	print("\n== the dash gadget ==")
	var rusher := await _spawn(_build(Loadout.Gadget.DASH, Weapon.Class.SMG,
		Loadout.Sight.NONE), Vector3(30.0, 1.0, 0.0), 0)
	await _frames(4)
	rusher.rotation.y = 0.0            # facing -Z
	var z0 := rusher.global_position.z
	rusher._use_gadget(0)
	for _i in 20:
		await _frames(1)
	var moved := z0 - rusher.global_position.z
	print("  dashed %.1f m forward" % moved)
	_expect(moved > 2.0, "the dash gadget carries you forward")

	# --- and only the Trandoshan throws smoke ----------------------------
	print("\n== smoke is theirs alone ==")
	var clone := Loadout.new()
	clone.adopt_kit(Loadout.Kit.CLONE)
	_expect(not clone.allows(Loadout.Row.GRENADE_TYPE, Loadout.GrenadeType.SMOKE),
		"a clone cannot select smoke")
	_expect(tran.pending == null or true, "")  # spacer, keeps output aligned
	var tload := Loadout.new()
	tload.adopt_kit(Loadout.Kit.TRANDOSHAN)
	_expect(tload.allows(Loadout.Row.GRENADE_TYPE, Loadout.GrenadeType.SMOKE),
		"...but the Trandoshan can")

	print("\n==== %s ====" % ("THE TRANDOSHAN WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _build(gadget: int, primary: int, sight: int) -> Loadout:
	var l := Loadout.new()
	l.adopt_kit(Loadout.Kit.TRANDOSHAN)
	l.weapon = Loadout.weapon_index(primary)
	l.gadget = gadget
	l.sight = sight
	return l


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 200.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.collision_layer = 1
	add_child(body)


func _spawn(build: Loadout, at: Vector3, team: int) -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	p.position = at
	p.team = team
	add_child(p)
	await get_tree().physics_frame
	p.pending = build
	p._apply_loadout()
	await get_tree().physics_frame
	return p


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame


func _expect(ok: bool, what: String) -> void:
	if what == "":
		return
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
