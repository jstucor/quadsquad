extends Node3D
## Team-deathmatch bootstrap: loads the current map from the rotation, builds a
## SubViewport per human player, fills both teams up to the chosen size with AI,
## spawns everyone at their team's spawn points, wires each viewport's camera +
## HUD, and rotates to the next map when a team hits the score limit. The map
## itself (scenes/levels/*) registers its per-team spawn points before anyone
## spawns. Player count, team size and AI skill all come from the menu.

const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const BOT_SCENE := preload("res://scenes/actors/bot.tscn")
const ZONE_SCENE := preload("res://scenes/fx/zone.tscn")
# Hit confirmation: a marker per HUD (each player only sees their own hits) and
# one shared pool of clicks (audio isn't split four ways the way the screen is).
const HIT_MARKER := preload("res://scripts/hit_marker.gd")
const HIT_TICK := preload("res://scripts/hit_tick.gd")
const MAP_VIEW := preload("res://scripts/map_view.gd")
const MENU_SCENE := "res://scenes/menu.tscn"
const AI_RESPAWN_DELAY := 4.0  # team AI come back, unlike a player's bought squad
const MATCH_START_COUNTDOWN := 3  # seconds of GET READY once everyone has deployed
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3),
	Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4),
	Color(0.95, 0.8, 0.3),
]
const MATCH_END_DELAY := 4.5  # seconds of victory banner before the next map

# HUD palette.
const HEAT_COOL_COLOR := Color(0.4, 0.8, 1.0, 0.9)
const HEAT_OVER_COLOR := Color(1.0, 0.3, 0.2, 0.95)
const ELIMINATED_COLOR := Color(1.0, 0.4, 0.35)
const DEATH_DIM := Color(0.16, 0.0, 0.0, 0.5)
const DEPLOY_DIM := Color(0.0, 0.0, 0.0, 0.55)
const DAMAGE_FLASH_COLOR := Color(0.85, 0.05, 0.05)
const KILL_STREAK_COLOR := Color(1.0, 0.35, 0.3)

var level: Node3D

# The four viewports' copies of the shared readouts. GameState is an autoload
# that outlives the map, so its signals are wired ONCE to a method of this node
# and fan out to these — never to per-HUD lambdas. Godot only drops a connection
# when its target object is freed, and a lambda that doesn't touch `self` has no
# target, so the old map's HUD would keep firing into freed labels after a
# rotation. Player/weapon signals are exempt: they die with the same scene.
var _score_labels: Array[Label] = []
var _victory_banners: Array[Label] = []
var _next_build := 0
var _countdown_labels: Array[Label] = []
var _zone_labels: Array[Label] = []
var _deployed := {}          # players who have finished their loadout at least once
var _countdown_running := false
var _hit_tick: Node          # the shared click pool


func _ready() -> void:
	GameState.reset_match()
	level = GameState.MAPS[GameState.map_index]["scene"].instantiate()
	add_child(level)  # its _ready registers the team spawn points
	# ...and now that its geometry exists, take the map screen's picture of it.
	GameState.scan_map_geometry(level)

	_hit_tick = HIT_TICK.new()
	_hit_tick.name = "HitTick"
	add_child(_hit_tick)

	var grid := GridContainer.new()
	# One human is full-screen, two split left/right, three or four go 2x2.
	grid.columns = 1 if GameState.human_players == 1 else 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid)

	for i in GameState.human_players:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(container)

		# own_world_3d stays false: all four viewports render the root
		# viewport's world, where the level lives.
		var viewport := SubViewport.new()
		container.add_child(viewport)

		var camera := Camera3D.new()
		viewport.add_child(camera)

		var player: Player = PLAYER_SCENE.instantiate()
		player.player_index = i
		player.input_device = i - 1  # P1 keyboard/mouse; P2..P4 joypads 0..2
		player.team = GameState.team_for_player(i)
		level.add_child(player)
		var spawn := GameState.get_spawn_point(player.team, _team_slot(i))
		if spawn:
			player.global_transform = spawn.global_transform
		player.bind_camera(camera)
		player.model.set_team_color(GameState.TEAM_COLORS[player.team])

		viewport.add_child(_build_hud(player))
		# The match waits for everyone's first deploy, so watch for it.
		player.respawned.connect(_on_player_deployed.bind(player))
		player.begin_deploy()  # after the HUD exists, so it sees the select screen

	_fill_teams_with_ai()
	if GameState.mode == GameState.Mode.ZONES:
		var zone := ZONE_SCENE.instantiate()
		zone.setup(level)
		level.add_child(zone)  # placed after the map, so its ground rays hit
	GameState.match_countdown.connect(_show_countdown)
	GameState.zone_state.connect(_refresh_zone)
	GameState.zone_moved.connect(_announce_zone_move)
	GameState.score_changed.connect(_refresh_scores)
	GameState.match_won.connect(_show_victory)
	GameState.match_won.connect(_on_match_won)
	_refresh_scores()


## Nobody fights until every human has bought a loadout and deployed. The last
## one in starts a short countdown, and only then does GameState.match_live go
## true — which is what unfreezes players, bots and turrets alike.
func _on_player_deployed(player: Player) -> void:
	if GameState.match_live or _countdown_running:
		return
	_deployed[player] = true
	if _deployed.size() < GameState.human_players:
		return
	_countdown_running = true
	_tick_countdown(MATCH_START_COUNTDOWN)


func _tick_countdown(seconds: int) -> void:
	GameState.match_countdown.emit(seconds)
	if seconds <= 0:
		GameState.match_live = true
		GameState.match_began.emit()
		return
	get_tree().create_timer(1.0).timeout.connect(_tick_countdown.bind(seconds - 1))


## How many earlier players share this player's team (its spawn index).
func _team_slot(index: int) -> int:
	var slot := 0
	for j in index:
		if GameState.team_for_player(j) == GameState.team_for_player(index):
			slot += 1
	return slot


## Bring both teams up to the chosen size with AI. These are the match's own
## bots, not a player's bought squad: they have no owner and they respawn, so a
## 1v1 with a team size of 4 stays a 4v4 all match.
func _fill_teams_with_ai() -> void:
	for team in GameState.active_teams():
		for n in GameState.ai_needed(team):
			_spawn_team_bot(team)


func _spawn_team_bot(team: int) -> void:
	if level == null or not is_instance_valid(level):
		return
	var bot: Bot = BOT_SCENE.instantiate()
	level.add_child(bot)
	# Deal the presets out in order so a team fields a mix rather than seven
	# rolls of the same dice.
	bot.setup(null, team, GameState.ai_skill, _next_build)
	_next_build += 1
	var spawn := GameState.get_spawn_point(team)
	if spawn:
		bot.global_transform = GameState.clear_of_bodies(spawn.global_transform)
	bot.tree_exited.connect(_on_team_bot_lost.bind(team))


func _on_team_bot_lost(team: int) -> void:
	# Also fires while the scene is being torn down, when there's no tree to
	# schedule against and nothing left to reinforce.
	if not is_inside_tree() or GameState.match_over:
		return
	get_tree().create_timer(AI_RESPAWN_DELAY).timeout.connect(_spawn_team_bot.bind(team))


func _on_match_won(_team: int) -> void:
	get_tree().create_timer(MATCH_END_DELAY).timeout.connect(_next_map)


## After the victory banner: rotation mode moves to the next map on the roster,
## a single-map pick drops back to the menu so someone can choose again.
func _next_map() -> void:
	if not GameState.rotate_maps:
		get_tree().change_scene_to_file(MENU_SCENE)
		return
	GameState.map_index = (GameState.map_index + 1) % GameState.MAPS.size()
	get_tree().reload_current_scene()


## Per-viewport HUD. Each piece is built by its own function and wires itself
## to the player's signals, so nothing here has to be kept in sync by hand.
func _build_hud(player: Player) -> Control:
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var color: Color = PLAYER_COLORS[player.player_index]

	_add_player_tag(hud, player, color)
	_add_reticle(hud, player)
	_add_scoreboard(hud)
	_add_health(hud, player, color)
	_add_weapon_readout(hud, player, color)
	_add_gear_readout(hud, player, color)
	_add_kill_streak(hud, player)
	_add_damage_flash(hud, player)
	_add_map(hud, player)
	hud.add_child(_build_buy_screen(player, color))
	_add_victory_banner(hud)
	_add_countdown(hud)
	if GameState.mode == GameState.Mode.ZONES:
		_add_zone_readout(hud)
	return hud


func _add_player_tag(hud: Control, player: Player, color: Color) -> void:
	var tag := Label.new()
	tag.text = "P%d" % (player.player_index + 1)
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", color)
	tag.position = Vector2(14, 8)
	hud.add_child(tag)


## The map screen: hidden until this player opens it, and drawn over the rest of
## the HUD but under the buy screen (dying closes the map anyway).
func _add_map(hud: Control, player: Player) -> void:
	var map: Control = MAP_VIEW.new()
	hud.add_child(map)
	map.setup(player)


## Crosshair and scope overlay, built together because they are mutually
## exclusive: the bloom crosshair is the hip-fire reticle, the scope replaces it
## on scoped weapons, and neither belongs on screen while you're dead.
func _add_reticle(hud: Control, player: Player) -> void:
	# Four ticks whose gap tracks the live spread cone (grows as you spray,
	# recovers when you stop, tight when aimed).
	var crosshair := Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_bloom.bind(crosshair, player))
	get_tree().process_frame.connect(crosshair.queue_redraw)
	hud.add_child(crosshair)

	var scope := Control.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.draw.connect(_draw_scope.bind(scope))
	scope.resized.connect(scope.queue_redraw)
	hud.add_child(scope)

	# The holo ring: a hollow reticle you aim through, with the world still
	# visible around it — the whole point of buying it over a scope.
	var holo := Control.new()
	holo.set_anchors_preset(Control.PRESET_FULL_RECT)
	holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holo.draw.connect(_draw_holo.bind(holo))
	holo.resized.connect(holo.queue_redraw)
	hud.add_child(holo)

	# Added LAST so it draws over every reticle — it has to show through the
	# scope blackout too, or a sniper never gets told they connected. Each HUD
	# only ever confirms its own player's hits; the click is shared.
	var marker: Control = HIT_MARKER.new()
	hud.add_child(marker)
	player.hit_confirmed.connect(func(headshot: bool, killed: bool) -> void:
		marker.flash(headshot, killed)
		_hit_tick.play(headshot, killed))

	var refresh := func() -> void:
		var live := player.is_alive()
		var scoped: bool = player.weapon.aiming and player.weapon.has_scope()
		var ringed: bool = player.weapon.aiming and player.weapon.has_holo()
		scope.visible = scoped and live
		holo.visible = ringed and live
		crosshair.visible = not scoped and not ringed and live
	player.aim_changed.connect(func(_aiming: bool) -> void: refresh.call())
	player.weapon_changed.connect(func(_name: String) -> void: refresh.call())
	player.died.connect(func(_eliminated: bool) -> void: refresh.call())
	player.respawned.connect(func() -> void: refresh.call())
	refresh.call()


## The score line, top-centre. Filled in by _refresh_scores.
##
## The font shrinks with the number of sides: four team names across a quarter
## of the screen at 20 px runs off both ends of the viewport.
func _add_scoreboard(hud: Control) -> void:
	var sizes := {2: 20, 3: 16, 4: 13}
	var score := _full_rect_label("", sizes.get(GameState.active_teams(), 13),
		Color(1, 1, 1, 0.95))
	score.offset_top = 8.0
	hud.add_child(score)
	_score_labels.append(score)


## Every side's score on one line. Written as a list rather than "A n : m B"
## because there can be up to four of them now.
func _refresh_scores(_team := 0, _score := 0) -> void:
	var parts := PackedStringArray()
	for team in GameState.active_teams():
		parts.append("%s  %d" % [
			GameState.TEAM_NAMES[team], int(GameState.scores.get(team, 0))])
	var text := ("     " if GameState.active_teams() <= 2 else "   ").join(parts)
	for label in _score_labels:
		label.text = text


func _add_health(hud: Control, player: Player, color: Color) -> void:
	var health := Label.new()
	health.add_theme_font_size_override("font_size", 22)
	health.add_theme_color_override("font_color", color)
	health.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health.offset_left = 14.0
	health.offset_top = -40.0
	hud.add_child(health)
	var refresh := func(hp: float) -> void:
		health.text = "HP %d" % maxi(roundi(hp), 0)
	player.health_changed.connect(refresh)
	refresh.call(player.health)


## Weapon name plus the heat bar that stands in for ammo.
func _add_weapon_readout(hud: Control, player: Player, color: Color) -> void:
	var name_label := Label.new()
	name_label.text = player.weapon.display_name()
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", color)
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_label.offset_left = -220.0
	name_label.offset_top = -44.0
	name_label.offset_right = -14.0
	name_label.offset_bottom = -22.0
	hud.add_child(name_label)
	player.weapon_changed.connect(func(n: String) -> void: name_label.text = n)

	var heat_bg := ColorRect.new()
	heat_bg.color = Color(1, 1, 1, 0.15)
	heat_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	heat_bg.offset_left = -140.0
	heat_bg.offset_top = -20.0
	heat_bg.offset_right = -14.0
	heat_bg.offset_bottom = -12.0
	hud.add_child(heat_bg)

	var heat_fill := ColorRect.new()
	heat_fill.color = HEAT_COOL_COLOR
	heat_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heat_fill.anchor_right = 0.0
	heat_fill.anchor_bottom = 1.0
	heat_bg.add_child(heat_fill)
	player.weapon.heat_changed.connect(func(heat: float, over: bool) -> void:
		heat_fill.anchor_right = heat
		heat_fill.color = HEAT_OVER_COLOR if over else HEAT_COOL_COLOR)


## The GET READY / FIGHT call at the start of a match. Like the scoreboard, it
## is fed by ONE connection to the autoload rather than a lambda per viewport.
func _add_countdown(hud: Control) -> void:
	var label := _full_rect_label("", 44, Color(1, 0.93, 0.6))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset_top = -60.0
	label.visible = false
	hud.add_child(label)
	_countdown_labels.append(label)


func _show_countdown(seconds: int) -> void:
	for label in _countdown_labels:
		label.visible = true
		label.text = "GET READY   %d" % seconds if seconds > 0 else "FIGHT!"
	if seconds <= 0:
		# Let FIGHT! sit for a beat, then clear it.
		get_tree().create_timer(0.9).timeout.connect(_hide_countdown)


func _hide_countdown() -> void:
	for label in _countdown_labels:
		label.visible = false


## Who holds the capture area and how long until it moves. One connection to
## the autoload, fanned out to every viewport (see _add_scoreboard).
func _add_zone_readout(hud: Control) -> void:
	var label := _full_rect_label("", 17, Color(0.9, 0.92, 0.96))
	label.offset_top = 34.0
	hud.add_child(label)
	_zone_labels.append(label)


func _refresh_zone(holder: int, contested: bool, seconds_left: int) -> void:
	var state := "ZONE NEUTRAL"
	var tint := Color(0.85, 0.87, 0.92)
	if contested:
		state = "ZONE CONTESTED"
		tint = Color(1.0, 0.95, 0.6)
	elif holder != -1:
		state = "%s HOLDS THE ZONE" % GameState.TEAM_NAMES[holder]
		tint = GameState.TEAM_COLORS[holder]
	for label in _zone_labels:
		label.text = "%s     moves in %ds" % [state, seconds_left]
		label.add_theme_color_override("font_color", tint)


func _announce_zone_move(_point: Vector3) -> void:
	for label in _zone_labels:
		label.text = "NEW ZONE"
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))


## Hidden until a team wins, then shown in every viewport by _show_victory.
## Kills on this life, under the player tag. It only appears once you're on the
## board, so a clean life has no dead HUD text. Getting a kill pops the label
## rather than washing the screen — the red wash means YOU are being hit.
func _add_kill_streak(hud: Control, player: Player) -> void:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", KILL_STREAK_COLOR)
	label.position = Vector2(14, 42)
	label.pivot_offset = Vector2(0, 10)
	label.visible = false
	hud.add_child(label)

	player.killed_someone.connect(func(streak: int) -> void:
		label.visible = true
		label.text = "%d KILL%s" % [streak, "" if streak == 1 else "S"]
		label.scale = Vector2(1.45, 1.45)
		var pop := hud.create_tween()
		pop.tween_property(label, "scale", Vector2.ONE, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	player.respawned.connect(func() -> void:
		label.visible = false
		label.scale = Vector2.ONE)


## The damage indicator: the screen washes red when YOU get hit, harder the
## bigger the hit, so a sniper round reads very differently from a stray pellet.
func _add_damage_flash(hud: Control, player: Player) -> void:
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = DAMAGE_FLASH_COLOR
	flash.modulate.a = 0.0
	hud.add_child(flash)

	player.damaged.connect(func(amount: float) -> void:
		var share: float = amount / maxf(player.max_health, 1.0)
		flash.modulate.a = clampf(0.16 + share * 0.7, 0.16, 0.62)
		var fade := hud.create_tween()
		fade.tween_property(flash, "modulate:a", 0.0, 0.4))
	player.respawned.connect(func() -> void: flash.modulate.a = 0.0)


## Consumables you're carrying, above the weapon name. Hidden when you bought
## none, so a gun-only build has no dead HUD text.
func _add_gear_readout(hud: Control, player: Player, color: Color) -> void:
	var gear := Label.new()
	gear.add_theme_font_size_override("font_size", 15)
	gear.add_theme_color_override("font_color", Color(color, 0.85))
	gear.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gear.offset_left = -220.0
	gear.offset_top = -64.0
	gear.offset_right = -14.0
	gear.offset_bottom = -46.0
	hud.add_child(gear)
	var refresh := func() -> void:
		var parts: Array[String] = []
		if player.gadget == Loadout.Gadget.JETPACK:
			parts.append("JET %d%%" % roundi(player.jet_fuel * 100.0))
		elif player.gadget == Loadout.Gadget.CABLE:
			var cd := player.cable_cooldown()
			parts.append("CABLE READY" if cd <= 0.0 else "CABLE %ds" % ceili(cd))
		elif player.gadget != Loadout.Gadget.NONE:
			parts.append(Loadout.GADGETS[player.gadget]["name"])
		if player.grenades_left > 0:
			parts.append("GRENADE x%d" % player.grenades_left)
		if player.medkits_left > 0:
			parts.append("MEDKIT x%d" % player.medkits_left)
		if player.squad.size() > 0:
			parts.append("SQUAD x%d" % player.squad.size())
		gear.text = "   ".join(parts)
	player.gear_changed.connect(func(_g: int, _m: int) -> void: refresh.call())
	player.squad_changed.connect(func(_alive: int) -> void: refresh.call())
	refresh.call()


func _add_victory_banner(hud: Control) -> void:
	var banner := _full_rect_label("", 40, Color(1, 1, 1, 1))
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.visible = false
	hud.add_child(banner)
	_victory_banners.append(banner)


func _show_victory(team: int) -> void:
	for banner in _victory_banners:
		banner.text = "%s WINS" % GameState.TEAM_NAMES[team]
		banner.add_theme_color_override("font_color", GameState.TEAM_COLORS[team])
		banner.visible = true


## The buy screen for one viewport: a dimmed backdrop, the budget, one row per
## purchasable thing with the cursor on the active row, a blurb for whatever the
## cursor is on, and the deploy prompt. Shown at match start (DEPLOY) and after
## every death (ELIMINATED). Each player drives their own quadrant, so all four
## shop at once; nobody spawns until they press deploy.
## How the buy screen is grouped into boxes: a heading, and the Loadout rows
## that live inside it. Every row still belongs to exactly one box, so the
## cursor walks the same flat row list it always did — the boxes are how it is
## LAID OUT, not a change to how it is driven. That matters because four players
## shop at once on one screen: only P1 has a mouse, so navigation has to stay on
## each player's own stick or keys.
const BUY_BOXES: Array[Dictionary] = [
	{"name": "PRIMARY", "rows": [Loadout.Row.WEAPON, Loadout.Row.SIGHT,
		Loadout.Row.COOLING, Loadout.Row.GRIP]},
	{"name": "SIDEARM", "rows": [Loadout.Row.SECONDARY, Loadout.Row.SECONDARY_MOD]},
	{"name": "GRENADES", "rows": [Loadout.Row.GRENADE_TYPE, Loadout.Row.GRENADES]},
	{"name": "GADGET", "rows": [Loadout.Row.GADGET]},
	{"name": "ARMOUR", "rows": [Loadout.Row.ARMOR]},
	{"name": "HEALTH", "rows": [Loadout.Row.MEDKITS]},
	{"name": "AI SQUAD", "rows": [Loadout.Row.SQUAD, Loadout.Row.SQUAD_SKILL]},
]
const BUY_COLUMNS := 2
## The boxes have to fit whatever slice of the screen this player owns. At four
## players a viewport is a quarter of the window, and the full-size layout runs
## off both edges of it, so the whole screen is measured off the player count.
const BUY_WIDE := {"name": 150, "value": 150, "text": 14, "head": 12, "title": 22}
const BUY_TIGHT := {"name": 104, "value": 96, "text": 11, "head": 9, "title": 16}
const BUY_BOX_EDGE := Color(0.26, 0.30, 0.36)
const BUY_BOX_BG := Color(0.07, 0.08, 0.11, 0.92)


## The buy screen for one viewport: a grid of category boxes, the budget above
## them, a blurb for whatever the cursor is on, and the deploy prompt. Shown at
## match start (DEPLOY) and after every death (ELIMINATED). Each player drives
## their own quadrant, so all four shop at once; nobody spawns until they press
## deploy.
func _build_buy_screen(player: Player, color: Color) -> Control:
	var panel := Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = DEATH_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(dim)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	var m: Dictionary = BUY_WIDE if GameState.human_players == 1 else BUY_TIGHT
	var title := _centred_label("ELIMINATED", m["title"], ELIMINATED_COLOR)
	column.add_child(title)
	var budget := _centred_label("", m["head"] + 2, Color(1, 1, 1, 0.9))
	column.add_child(budget)
	column.add_child(_spacer(4))

	# One panel per category, laid out in a grid. Row labels are kept in a flat
	# array indexed by Loadout.Row, so _refresh_buy_screen can address any row
	# without knowing which box it ended up in.
	var grid := GridContainer.new()
	grid.columns = BUY_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	column.add_child(grid)

	var names: Array[Label] = []
	var values: Array[Label] = []
	var frames: Array[PanelContainer] = []
	names.resize(Loadout.Row.size())
	values.resize(Loadout.Row.size())
	frames.resize(Loadout.Row.size())
	for box in BUY_BOXES:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", _buy_panel(BUY_BOX_EDGE))
		grid.add_child(frame)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 1)
		frame.add_child(inner)
		inner.add_child(_centred_label(box["name"], m["head"], Color(0.55, 0.60, 0.68)))
		for row in box["rows"]:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 10)
			var name_label := _centred_label("", m["text"], Color(1, 1, 1, 0.85))
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_label.custom_minimum_size = Vector2(m["name"], 0)
			line.add_child(name_label)
			var value_label := _centred_label("", m["text"], Color(1, 1, 1, 0.85))
			value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			value_label.custom_minimum_size = Vector2(m["value"], 0)
			line.add_child(value_label)
			inner.add_child(line)
			names[row] = name_label
			values[row] = value_label
			frames[row] = frame

	column.add_child(_spacer(4))
	var blurb := _centred_label("", m["head"] + 1, Color(0.7, 0.74, 0.8))
	column.add_child(blurb)
	var prompt := _centred_label("", m["head"] + 3, Color(0.62, 0.66, 0.72))
	column.add_child(prompt)
	column.add_child(_centred_label(
		"up / down pick a line     left / right change it",
		m["head"], Color(0.5, 0.54, 0.6)))

	var refresh := func() -> void:
		_refresh_buy_screen(player, color, names, values, frames, budget, blurb, prompt)
	player.buy_changed.connect(func(_row: int) -> void: refresh.call())
	player.deploy_ready.connect(func() -> void: refresh.call())
	player.died.connect(func(eliminated: bool) -> void:
		title.text = "ELIMINATED" if eliminated else "DEPLOY"
		title.add_theme_color_override("font_color",
			ELIMINATED_COLOR if eliminated else color)
		dim.color = DEATH_DIM if eliminated else DEPLOY_DIM
		panel.visible = true
		refresh.call())
	player.respawned.connect(func() -> void: panel.visible = false)
	refresh.call()
	return panel


func _buy_panel(edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BUY_BOX_BG
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	return sb


## Rewrite the buy screen's text for the player's current pending build. The
## cursor row is bracketed and tinted, and the BOX holding it takes the player's
## colour on its border — so which category you are in reads at a glance even
## from the far side of a four-way split.
func _refresh_buy_screen(player: Player, color: Color, names: Array[Label],
		values: Array[Label], frames: Array[PanelContainer],
		budget: Label, blurb: Label, prompt: Label) -> void:
	var build := player.pending
	budget.text = "TOKENS  %d spent   %d left of %d" % [
		build.cost(), build.remaining(), Loadout.BUDGET]
	var active: PanelContainer = frames[player.buy_row]
	for i in names.size():
		var selected := i == player.buy_row
		var tint := color if selected else Color(1, 1, 1, 0.72)
		names[i].text = "%s %s" % ["\u25b8" if selected else " ", build.row_label(i)]
		var cost := build.row_cost(i)
		values[i].text = build.row_value(i)
		if cost > 0:
			values[i].text += "   %d" % cost
		names[i].add_theme_color_override("font_color", tint)
		values[i].add_theme_color_override("font_color", tint)
	for frame in frames:
		if frame != null:
			frame.add_theme_stylebox_override("panel",
				_buy_panel(color if frame == active else BUY_BOX_EDGE))
	blurb.text = build.row_blurb(player.buy_row, player.input_device)
	# Count the lock down out loud: a silent "standby" for five seconds reads
	# exactly like a match that has failed to start.
	prompt.text = "%s  to deploy" % player.deploy_button_name() \
		if player.deploy_armed() else "ready in %d..." % ceili(player.deploy_wait())
	prompt.add_theme_color_override("font_color",
		Color(0.85, 0.95, 0.8) if player.deploy_armed() else Color(0.55, 0.58, 0.62))


## Bloom crosshair: four ticks at a radius that maps the weapon's current
## spread cone (half-angle) to screen pixels through the camera FOV.
func _draw_bloom(c: Control, player: Player) -> void:
	if not c.visible or c.size.y <= 0.0:
		return
	var spread := deg_to_rad(player.weapon.current_spread_deg())
	var fov := deg_to_rad(player.view_fov())
	var half_h := c.size.y * 0.5
	var radius := half_h * tan(spread) / maxf(tan(fov * 0.5), 0.001)
	radius = clampf(radius, 4.0, half_h * 0.92)
	var center := c.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	var tick := 7.0
	c.draw_line(center + Vector2(0, -radius), center + Vector2(0, -radius - tick), col, 2.0)
	c.draw_line(center + Vector2(0, radius), center + Vector2(0, radius + tick), col, 2.0)
	c.draw_line(center + Vector2(-radius, 0), center + Vector2(-radius - tick, 0), col, 2.0)
	c.draw_line(center + Vector2(radius, 0), center + Vector2(radius + tick, 0), col, 2.0)
	c.draw_circle(center, 1.5, col)


## A hollow ring with a centre dot. Unlike the scope it draws no blackout, so
## you keep your peripheral vision while aimed.
func _draw_holo(c: Control) -> void:
	var center := c.size * 0.5
	var r: float = minf(c.size.x, c.size.y) * 0.13
	c.draw_arc(center, r, 0.0, TAU, 48, Color(1.0, 0.3, 0.22, 0.9), 2.0, true)
	c.draw_arc(center, r * 0.06, 0.0, TAU, 12, Color(1.0, 0.45, 0.3, 1.0), 3.0, true)
	# Small ticks at the cardinals, so the ring reads as a sight not a circle.
	for i in 4:
		var dir := Vector2.RIGHT.rotated(TAU * i / 4.0)
		c.draw_line(center + dir * r * 0.72, center + dir * r * 0.92,
			Color(1.0, 0.3, 0.22, 0.75), 2.0)


func _draw_scope(c: Control) -> void:
	var s := c.size
	var center := s * 0.5
	var r: float = minf(s.x, s.y) * 0.42
	var diag := s.length()
	c.draw_arc(center, r + diag * 0.5, 0.0, TAU, 96, Color(0, 0, 0, 1.0), diag, false)
	c.draw_arc(center, r, 0.0, TAU, 96, Color(0, 0, 0, 0.9), 2.0, true)
	c.draw_line(Vector2(center.x, center.y - r), Vector2(center.x, center.y + r), Color(0, 0, 0, 0.5), 1.0)
	c.draw_line(Vector2(center.x - r, center.y), Vector2(center.x + r, center.y), Color(0, 0, 0, 0.5), 1.0)
	c.draw_circle(center, 2.0, Color(1, 0.25, 0.18))


## A row inside a VBox, as opposed to _full_rect_label which positions itself
## across the whole viewport.
func _centred_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _full_rect_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
