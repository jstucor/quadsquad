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
const VEHICLE_SCENE := preload("res://scenes/actors/vehicle.tscn")
# Hit confirmation: a marker per HUD (each player only sees their own hits) and
# one shared pool of clicks (audio isn't split four ways the way the screen is).
const HIT_MARKER := preload("res://scripts/hit_marker.gd")
const HIT_TICK := preload("res://scripts/hit_tick.gd")

const MAP_VIEW := preload("res://scripts/map_view.gd")
const MINIMAP := preload("res://scripts/minimap.gd")
const KILL_FEED := preload("res://scripts/kill_feed.gd")
const SETTINGS_OVERLAY := preload("res://scripts/settings_overlay.gd")
const SPAWN_SCREEN := preload("res://scripts/spawn_screen.gd")
const CONQUEST := preload("res://scripts/conquest.gd")
const STORM := preload("res://scripts/storm.gd")
const PICKUP := preload("res://scripts/pickup.gd")
# Battle royale. You deploy with a sidearm and nothing else, and everything
# worth having is on the ground — the count scales with the map so a 300 m
# basin is not as bare as a 34 m corridor.
const ROYALE_PICKUPS_PER_HA := 9.0   # items per hectare of playable ground
const ROYALE_MIN_PICKUPS := 24
const ROYALE_MAX_PICKUPS := 220
const MENU_SCENE := "res://scenes/menu.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const AI_RESPAWN_DELAY := 4.0  # team AI come back, unlike a player's bought squad
const MATCH_START_COUNTDOWN := 3  # seconds of GET READY once everyone has deployed
const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.3, 0.3),
	Color(0.3, 0.6, 0.9),
	Color(0.4, 0.85, 0.4),
	Color(0.95, 0.8, 0.3),
]
## Seconds of victory banner + post-match table before the next map. It was 4.5,
## which was enough for a banner and is not enough for a scoreboard: at a couch
## the end-of-round table is the thing four people actually talk about, and a
## screen that clears itself before anybody has finished reading it may as well
## not be drawn. The rotation is not in a hurry.
const MATCH_END_DELAY := 11.0

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
var _score_tables: Array[Label] = []
var _killed_by: Array[Dictionary] = []
var _next_build := 0
var _countdown_labels: Array[Label] = []
var _zone_labels: Array[Label] = []
var _deployed := {}          # players who have finished their loadout at least once
var _countdown_running := false
var _hit_tick: Node          # the shared click pool
var storm: Node3D            # the royale storm, when there is one
var governor: FrameGovernor  # holds the frame to its interval; null unless AUTO
var sync: NetSync            # the replication pump; null unless the match is online
var zone: Node3D             # the ZONES capture area, when there is one


func _ready() -> void:
	GameState.reset_match()
	# HOW MANY WAYS THE FRAME IS ABOUT TO BE SPLIT, before anything that spends it
	# is built. Four cameras each render the whole world AND their own shadow map
	# into a quarter of the screen, so the viewport count is an input to nearly
	# every cost decision in `Quality` — and the level's own `_ready` grades its
	# sun, which asks.
	Quality.active_views = GameState.human_players
	Quality.apply_global()
	# Audio is an autoload and outlives the scene, so a looping voice whose owner
	# went away with the last map would play for the rest of the session. Every
	# owner releases its own on the way out; this is the backstop.
	Audio.stop_all_loops()
	# MASSIVE IS PROCEDURAL-MAP ONLY, enforced here as well as on the menu: the
	# hand-laid arenas are built for eight bodies and a hundred of them in
	# Catwalk's corridors is a traffic jam, where a generated world is a couple
	# of hundred metres of open ground with cover scattered across it. Doing it
	# here too means map ROTATION cannot walk a massive battle onto Hangar.
	if GameState.massive():
		GameState.map_index = GameState.procedural_map_index()
	level = GameState.MAPS[GameState.map_index]["scene"].instantiate()
	add_child(level)  # its _ready registers the team spawn points
	# ...and now that its geometry exists, take the map screen's picture of it.
	GameState.scan_map_geometry(level)
	# A three- or four-way match needs a corner each; two-team layouts are the
	# map author's and are left alone. Must run after scan_map_geometry, which
	# is what establishes the extents the corners are measured from.
	GameState.place_corner_spawns(level)
	# ...and the same footprints become the grid the AI walks on. After the scan
	# for the obvious reason, and after the spawns so a corner spawn is inside
	# the area the grid covers.
	GameState.nav.build(GameState.map_center, GameState.map_extents, GameState.map_shapes)

	_hit_tick = HIT_TICK.new()
	_hit_tick.name = "HitTick"
	add_child(_hit_tick)

	# THE PUMP, and it goes in before any body does. Its node PATH is what routes
	# every RPC in the game (`/root/Main/NetSync`), so it has to exist on both
	# machines before either one sends anything — a packet arriving for a node
	# that is not there yet is dropped with an error naming the path and nothing
	# about the cause. Nothing else here is aware of it: bodies register with it,
	# and it does the rest.
	if Net.online():
		sync = NetSync.new()
		add_child(sync)
		if Net.is_host():
			sync.all_deployed.connect(_begin_countdown)

	var grid := GridContainer.new()
	# One human is full-screen, two split left/right, three or four go 2x2.
	grid.columns = 1 if GameState.human_players == 1 else 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(grid)
	var viewports: Array[SubViewport] = []

	for i in GameState.human_players:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(container)

		# own_world_3d stays false: all four viewports render the root
		# viewport's world, where the level lives.
		var viewport := SubViewport.new()
		# ANTI-ALIASING and RENDER SCALE, and they have to be set HERE: the project
		# settings only reach the root viewport, and the game never renders anything
		# into that — every pixel a player sees comes out of one of these.
		#
		# `Quality` owns the numbers, and it is handed the viewport COUNT because
		# every one of them is a share of the same frame: four cameras each render
		# the whole world and their own shadow map into a quarter of the screen, so
		# what one player at 1080p can afford is not what four can. See the
		# measurements in that file.
		Quality.apply_to_viewport(viewport, GameState.human_players)
		container.add_child(viewport)
		viewports.append(viewport)

		var camera := Camera3D.new()
		viewport.add_child(camera)

		var player: Player = PLAYER_SCENE.instantiate()
		player.player_index = i
		# Everyone is on a pad: P1..P4 are joypads 0..3. The one exception is the
		# debug flag (`-- --debug`), which puts P1 on the keyboard and mouse so
		# the game can be played at a desk with no controller plugged in.
		player.input_device = -1 if (GameState.debug_kbm and i == 0) else i
		player.team = GameState.team_for_player(i)
		level.add_child(player)
		var spawn := GameState.get_spawn_point(player.team, _team_slot(i))
		if spawn:
			player.global_transform = spawn.global_transform
			player.reset_physics_interpolation()   # placed, not walked
		player.bind_camera(camera)
		player.model.set_team_color(GameState.team_colors[player.team])

		# THE BODY'S NAME ON THE WIRE, taken from this machine's share of the
		# roster in viewport order. Registered before the HUD, so the first
		# `_apply_loadout` (which announces what unit this is) has an id to
		# announce it under.
		if sync != null:
			var mine := Net.local_ids()
			if i < mine.size():
				sync.own(player, mine[i])

		viewport.add_child(_build_hud(player))
		# The match waits for everyone's first deploy, so watch for it.
		player.respawned.connect(_on_player_deployed.bind(player))
		player.begin_deploy()  # after the HUD exists, so it sees the select screen

	# EVERYTHING BELOW IS THE MATCH RUNNING ITSELF, AND IT RUNS ON ONE MACHINE.
	# Bots, the zone and the royale furniture all act on their own every physics
	# frame; two machines doing that is two matches. `Net.authority()` is true
	# offline, so the single-player path and the host path are the same path and
	# there is no second version of any of this to keep in step.
	if Net.authority():
		_fill_teams_with_ai()
		_place_vehicles()
		if GameState.mode == GameState.Mode.ROYALE:
			_start_royale()
	if GameState.mode == GameState.Mode.ZONES:
		# Built on EVERY machine — it is a thing you can see and stand in — but
		# only the host's decides where it goes and who is holding it. The
		# reference is kept because NetSync addresses it by name.
		zone = ZONE_SCENE.instantiate()
		zone.setup(level)
		level.add_child(zone)  # placed after the map, so its ground rays hit
	if GameState.mode == GameState.Mode.CONQUEST:
		var cq := CONQUEST.new()
		cq.name = "Conquest"
		cq.setup(level)
		level.add_child(cq)   # lays the command posts on its first physics frame
		GameState.conquest = cq
	# THE FRAME GOVERNOR, which only runs under AUTO — naming a tier is the player
	# saying what they want, and moving the resolution under that would be ignoring
	# them. Its ceiling is the tier's own scale, so it can give picture back but
	# never take more than was asked for.
	if Quality.governs():
		governor = FrameGovernor.new()
		governor.name = "FrameGovernor"
		governor.setup(viewports, float(Quality.settings()["scale"]))
		add_child(governor)
		# Stopped OUTRIGHT for a screenshot: the look tests and the map screen judge
		# appearance, and a resolution that moves while a picture is being taken is
		# the one thing that would make those tests unrepeatable.
		governor.process_mode = Node.PROCESS_MODE_PAUSABLE
	# One tick for every viewport's overlays. A METHOD of this node, like the
	# score/victory wiring below, so the connection dies with the map instead of
	# outliving it the way a lambda would.
	get_tree().process_frame.connect(_tick_overlays)
	GameState.match_countdown.connect(_show_countdown)
	GameState.zone_state.connect(_refresh_zone)
	GameState.zone_moved.connect(_announce_zone_move)
	GameState.score_changed.connect(_refresh_scores)
	GameState.match_won.connect(_show_victory)
	GameState.match_won.connect(_on_match_won)
	_refresh_scores()


## ONE SPEEDER PER SIDE, PARKED AT THAT SIDE'S SPAWN — and only in STAR WARS.
## `Vehicle.spawns_for` is the single place that rule lives, so this loop is
## simply empty in Halo and Warhammer and no caller tests the universe itself.
##
## Parked at the spawn rather than scattered on the map, for two reasons. It is
## the side's OWN vehicle (the mount check refuses an enemy's), so anywhere else
## is either a walk nobody makes or a gift to whoever spawns nearest it; and a
## speeder sitting where you deploy makes taking it a decision you make every
## life rather than a thing you find once.
##
## ROYALE gets none: everybody drops in as a plain trooper with what they can
## scavenge, and a faction speeder is neither. MASSIVE gets none either — a
## hundred bodies is already the whole frame budget, and that mode is about being
## one rifle in a crowd, not about outrunning it.
func _place_vehicles() -> void:
	if GameState.mode == GameState.Mode.ROYALE or GameState.massive():
		return
	# NOT ONLINE, YET. A vehicle is a combatant that a player climbs INSIDE — its
	# position, its hull health, whether it is occupied and by whom are all state
	# that would have to be replicated and arbitrated, and none of it is. Placed
	# on the host alone (which is what `Net.authority()` above would give) it is
	# worse than absent: the host would drive a speeder the client cannot see, and
	# get shot at by a machine that does not know why.
	if Net.online():
		return
	var teams: Array = Vehicle.spawns_for(Loadout.active_universe)
	for t: int in teams:
		if t >= GameState.active_teams():
			continue   # a 2-team match fields two speeders, not four
		var spawn := GameState.get_spawn_point(t)
		if spawn == null:
			continue
		var v: Vehicle = VEHICLE_SCENE.instantiate()
		level.add_child(v)
		v.setup(t)
		# Off to the side of the marker and lifted clear: a speeder standing ON a
		# spawn point is a body-blocked spawn every respawn, and one dropped at
		# the exact analytic ground height starts inside the collision mesh (the
		# heightfield sag this map's SPAWN_LIFT already exists for).
		var side := spawn.global_transform.basis.x.normalized()
		v.global_position = spawn.global_position + side * VEHICLE_SPAWN_OFFSET \
			+ Vector3.UP * VEHICLE_SPAWN_LIFT
		v.rotation.y = spawn.global_rotation.y
		v.reset_physics_interpolation()   # placed, not driven


## Far enough from the marker that it never blocks a deploy, close enough that it
## is obviously yours.
const VEHICLE_SPAWN_OFFSET := 4.0
const VEHICLE_SPAWN_LIFT := 1.0


## Battle royale setup: the storm, and the gear to fight over. Both go in the
## level rather than under Main so they are torn down with the map.
func _start_royale() -> void:
	storm = STORM.new()
	storm.name = "Storm"
	level.add_child(storm)
	storm.setup(int(Time.get_unix_time_from_system()))
	_scatter_pickups()


## Gear on the ground. Weighted so guns are the common find and gadgets the rare
## one, and placed on the map's own ground height so nothing floats over a dune
## or sinks into a mesa.
func _scatter_pickups() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_unix_time_from_system()) ^ 0x5eed
	var extents := GameState.map_extents
	var hectares := (extents.x * 2.0) * (extents.y * 2.0) / 10000.0
	var count := clampi(roundi(hectares * ROYALE_PICKUPS_PER_HA),
		ROYALE_MIN_PICKUPS, ROYALE_MAX_PICKUPS)
	for i in count:
		var spot := _royale_spot(rng, extents)
		var item: Pickup = PICKUP.new()
		level.add_child(item)
		item.global_position = spot
		_roll_pickup(item, rng)


func _royale_spot(rng: RandomNumberGenerator, extents: Vector2) -> Vector3:
	var margin := 6.0
	var x := GameState.map_center.x + rng.randf_range(-extents.x + margin, extents.x - margin)
	var z := GameState.map_center.z + rng.randf_range(-extents.y + margin, extents.y - margin)
	var y := 0.0
	if level.has_method("height_at"):
		y = level.height_at(x, z)
	# Same reason spawns are lifted: the collision mesh sits above the analytic
	# curve across a hollow, and a crate at the exact height sinks into it.
	return Vector3(x, y + 0.6, z)


## What a given crate turns out to be. Guns dominate because a royale where you
## cannot find a rifle is just a pistol duel; gadgets are rare because they are
## the strongest single thing you can pick up.
## ROYALE HAS NO CLASSES, so a crate can only hold class-free kit. Rolling an
## index across the whole table would scatter lightsabers and Force powers over
## a map full of plain troopers — a saber with no guard behind it, and powers on
## a button a class-free build does not use. royale_items filters them out.
func _roll_pickup(item: Pickup, rng: RandomNumberGenerator) -> void:
	var roll := rng.randf()
	if roll < 0.42:
		# `from` 1 skips the "no primary" row: a crate has to hold an actual gun.
		var guns := Loadout.royale_items(Loadout.WEAPONS, 1)
		item.setup(Pickup.Kind.PRIMARY, guns[rng.randi_range(0, guns.size() - 1)])
	elif roll < 0.58:
		item.setup(Pickup.Kind.SIDEARM, rng.randi_range(0, Loadout.SECONDARIES.size() - 1))
	else:
		# Gadgets, grenades included (they are gadgets now) — royale_items keeps a
		# class's signature gear out, but the ordinary grenades stay in.
		var gear := Loadout.royale_items(Loadout.GADGETS, 1)
		item.setup(Pickup.Kind.GADGET, gear[rng.randi_range(0, gear.size() - 1)])


## Nobody fights until every human has bought a loadout and deployed. The last
## one in starts a short countdown, and only then does GameState.match_live go
## true — which is what unfreezes players, bots and turrets alike.
func _on_player_deployed(player: Player) -> void:
	if GameState.match_live or _countdown_running:
		return
	_deployed[player] = true
	# NETWORKED: the match waits for everyone in the SESSION, not for everyone on
	# this sofa — otherwise the first machine to finish shopping starts fighting
	# while the others are still on the buy screen. A machine reports its players
	# in and then waits: the host's tally is what fires `_begin_countdown`, and
	# the countdown itself is broadcast from there (see NetSync).
	if Net.online():
		if sync != null:
			sync.report_deploy(sync.id_of(player))
		return
	if _deployed.size() < GameState.human_players:
		return
	_begin_countdown()


func _begin_countdown() -> void:
	if GameState.match_live or _countdown_running:
		return
	_countdown_running = true
	_tick_countdown(MATCH_START_COUNTDOWN)


func _tick_countdown(seconds: int) -> void:
	GameState.match_countdown.emit(seconds)
	if seconds <= 0:
		GameState.match_live = true
		GameState.match_began.emit()
		# The battle track starts when the match does, not when the map loads:
		# the buy screen and the countdown belong to the menu's calm, and the
		# cut on "GO" is worth more than a few seconds of extra music.
		Audio.play_music("battle")
		Audio.play("ui_accept", 4.0)
		return
	Audio.play("countdown")
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
	if GameState.massive():
		_fill_massive()
		return
	# A BIG ROSTER IS DEALT OVER FRAMES TOO, for exactly the reason MASSIVE is:
	# a character model is ~0.6 ms to build, so a 20v20 filling in one go is a
	# 24 ms freeze on the frame the map opens. The batching was written for a
	# hundred bodies and costs nothing at twelve, so the only question is whether
	# the queue is worth starting — below CROWD_AT it plainly is not.
	if GameState.crowded():
		_fill_massive()
		return
	for team in GameState.active_teams():
		for n in GameState.ai_needed(team):
			_spawn_team_bot(team)


## HOW MANY OF THE HUNDRED ARE PROPER BOTS. The crowd is line troopers, but a
## battle of nothing but line troopers has no texture — nobody digs in, nobody
## drops a turret, nothing ever gets shelled. A few per side carry the ordinary
## presets and behave like the AI everywhere else in the game.
const MASSIVE_VETERANS := 3


## A HUNDRED BODIES CANNOT BE BUILT ON ONE FRAME. Each one is a character model
## (thirty-odd meshes) plus a weapon, and `tests/perf.tscn` prices that at about
## 0.6 ms — so a hundred at once is a sixty-millisecond freeze right where the
## match starts, which is the single most noticeable place to put one.
##
## They are dealt out over frames instead, a batch at a time. Nothing waits on
## them: `match_live` is already gated on the humans deploying and the countdown
## (which is three seconds), so the crowd finishes assembling while the countdown
## runs and nobody ever sees a half-empty field.
const SPAWN_BATCH := 6


func _fill_massive() -> void:
	var want: Array[int] = []
	for team in GameState.active_teams():
		for n in GameState.ai_needed(team):
			want.append(team)
	_massive_queue = want
	_deal_massive()


var _massive_queue: Array[int] = []
var _massive_done := 0


func _deal_massive() -> void:
	if not is_inside_tree() or level == null or not is_instance_valid(level):
		return
	for i in mini(SPAWN_BATCH, _massive_queue.size()):
		var team: int = _massive_queue.pop_front()
		# The veterans come off the FRONT of each side's share, so a side always
		# has its handful even if the match ends before the crowd is finished.
		#
		# ONLY MASSIVE DEALS LINE TROOPERS. The other modes use this same queue for
		# its batching (see _fill_teams_with_ai) and every body they deal is an
		# ordinary bot — a 20v20 deathmatch fought by stripped riflemen would have
		# thrown away the roster to buy frames it does not need.
		_spawn_team_bot(team, GameState.massive()
			and _massive_done >= GameState.active_teams() * MASSIVE_VETERANS)
		_massive_done += 1
	if not _massive_queue.is_empty():
		get_tree().process_frame.connect(_deal_massive, CONNECT_ONE_SHOT)


func _spawn_team_bot(team: int, as_line := false) -> void:
	if level == null or not is_instance_valid(level):
		return
	var bot: Bot = BOT_SCENE.instantiate()
	level.add_child(bot)
	# Deal the presets out in order so a team fields a mix rather than seven
	# rolls of the same dice.
	bot.setup(null, team, GameState.ai_skill, _next_build, as_line)
	_next_build += 1
	var spawn := GameState.get_spawn_point(team)
	if spawn:
		bot.global_transform = GameState.clear_of_bodies(spawn.global_transform)
		bot.reset_physics_interpolation()
	# AFTER setup, because `own_bot` immediately announces what unit this is and
	# the answer comes from the loadout setup just built.
	if sync != null:
		sync.own_bot(bot)
	bot.tree_exited.connect(_on_team_bot_lost.bind(team))


func _on_team_bot_lost(team: int) -> void:
	# Also fires while the scene is being torn down, when there's no tree to
	# schedule against and nothing left to reinforce.
	if not is_inside_tree() or GameState.match_over:
		return
	# Royale has no reinforcements of any kind. Without this the team-fill AI
	# keep coming back while the humans stay dead, and the last side standing
	# can never be decided.
	if GameState.mode == GameState.Mode.ROYALE:
		return
	# In a massive battle every REPLACEMENT is a line trooper, whatever it
	# replaced: the handful of veterans are a seasoning dealt at the start, not a
	# quota to maintain, and a side that has been fighting for two minutes should
	# be down to riflemen.
	get_tree().create_timer(AI_RESPAWN_DELAY).timeout.connect(
		_spawn_team_bot.bind(team, GameState.massive()))


func _on_match_won(_team: int) -> void:
	get_tree().create_timer(MATCH_END_DELAY).timeout.connect(_next_map)


## After the victory banner: rotation mode moves to the next map on the roster,
## a single-map pick drops back to the menu so someone can choose again.
func _next_map() -> void:
	# NETWORKED, EVERYBODY GOES BACK TO THE LOBBY. Rotating would need all four
	# machines to load the same next map at the same moment and re-handshake
	# every body on it, which is the whole match-start sequence run again with
	# nobody watching for it to fail. The lobby already does that sequence, and
	# it does it with a screen in front of it saying so.
	if Net.online():
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return
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

	_add_minimap(hud, player, color)
	_add_player_tag(hud, player, color)
	_add_reticle(hud, player)
	_add_scoreboard(hud)
	_add_health(hud, player, color)
	_add_weapon_readout(hud, player, color)
	_add_gear_readout(hud, player, color)
	_add_kill_streak(hud, player)
	_add_streak_reward(hud, player)
	_add_killed_by(hud, player)
	_add_damage_flash(hud, player)
	_add_kill_feed(hud)
	if GameState.mode == GameState.Mode.ROYALE:
		_add_storm_readout(hud, player)
		_add_pickup_prompt(hud, player)
	_add_map(hud, player)
	_add_scan(hud, player)
	# Which deploy screen this match uses is the CLASS SETTING's call, not the
	# mode's: faction rosters are pickable in deathmatch and the buy screen works
	# in Conquest. Both are the same box mechanic (see BoxScreen).
	if GameState.faction_classes():
		var spawn: Control = SPAWN_SCREEN.new()
		spawn.setup(player, color)
		hud.add_child(spawn)
	else:
		hud.add_child(_build_buy_screen(player, color))
	_add_victory_banner(hud)
	_add_score_table(hud)
	_add_countdown(hud)
	if GameState.mode == GameState.Mode.ZONES:
		_add_zone_readout(hud)
	# The in-game START overlay goes on last so it draws over the rest of the HUD.
	var settings: Control = SETTINGS_OVERLAY.new()
	settings.setup(player)
	hud.add_child(settings)
	return hud


## The minimap owns the top-left corner now, and the player tag moves BELOW it
## rather than beside it: the scoreboard is a centred full-rect label, so on a
## quarter-screen viewport at 13pt it starts far enough left that a tag pushed
## sideways runs straight into "REPUBLIC 0". Under the map there is nothing.
func _add_minimap(hud: Control, player: Player, color: Color) -> void:
	var map: Control = MINIMAP.new()
	hud.add_child(map)
	map.setup(player, color)
	_minimaps.append(map)


func _add_player_tag(hud: Control, player: Player, color: Color) -> void:
	var tag := Label.new()
	tag.text = "P%d" % (player.player_index + 1)
	tag.add_theme_font_size_override("font_size", 28)
	tag.add_theme_color_override("font_color", color)
	var below: float = MINIMAP.INSET.y + float(MINIMAP.SIZES.get(
		GameState.human_players, 116.0)) + 2.0
	tag.position = Vector2(MINIMAP.INSET.x, below)
	hud.add_child(tag)


## Storm readout: whether it is closing, how long until it moves, and a warning
## while you are actually standing in it. Polled rather than driven by a signal
## because the storm changes every frame while it closes.
func _add_storm_readout(hud: Control, player: Player) -> void:
	var label := _full_rect_label("", 17, Color(0.7, 0.8, 1.0))
	label.offset_top = 34.0
	hud.add_child(label)
	label.draw.connect(func() -> void:
		if storm == null or not is_instance_valid(storm):
			return
		var flat := Vector2(player.global_position.x - storm.centre.x,
			player.global_position.z - storm.centre.z)
		var outside: bool = flat.length() > storm.radius
		if outside:
			label.text = "IN THE STORM  —  %.0f dps  —  RUN" % storm.damage_rate()
			label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		elif storm.is_closing():
			label.text = "STORM CLOSING  %ds" % storm.seconds_left()
			label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.45))
		else:
			label.text = "STORM MOVES IN  %ds" % storm.seconds_left()
			label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0)))
	# Everything it prints is a whole second or a rounded rate, so it rides the
	# slow group rather than rebuilding the same string sixty times a second.
	_slow_labels.append({"label": label})


## "PRESS E TO TAKE WEAPON", shown only while a crate is actually in reach. The
## control is named through Controls, so it follows a rebind and reads correctly
## for a pad player and a keyboard player sitting side by side.
func _add_pickup_prompt(hud: Control, player: Player) -> void:
	var label := _full_rect_label("", 19, Color(1.0, 0.92, 0.6))
	label.offset_top = 120.0
	hud.add_child(label)
	label.draw.connect(func() -> void:
		var crate = player.pickup_in_reach
		if crate == null or not is_instance_valid(crate) or not player.is_alive():
			label.text = ""
			return
		label.text = "%s  to take  %s" % [
			Controls.label(player.input_device, "interact"), crate.label()])
	# Same: whether a crate is in reach changes as you walk, not per frame, and
	# the prompt builds a string and a control label every time it draws.
	_slow_labels.append({"label": label})


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
	# Redrawn only when the cone it draws has actually MOVED, not every frame.
	# The crosshair is four ticks and a dot; re-recording it 60 times a second
	# for all four viewports to draw the identical picture is the cost, and a
	# settled spread is the normal case — you are not firing most of the time.
	_bloom_ticks.append({"c": crosshair, "player": player, "at": -1.0})
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

	# The red dot: the same clear-view aim as the ring, but a crisp centre dot
	# instead of a ring around it.
	var reddot := Control.new()
	reddot.set_anchors_preset(Control.PRESET_FULL_RECT)
	reddot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reddot.draw.connect(_draw_reddot.bind(reddot))
	reddot.resized.connect(reddot.queue_redraw)
	hud.add_child(reddot)

	# The thermal read: while the Trandoshan aims their heat holo, a box is
	# drawn over every enemy in front of them — through smoke, because a normal
	# raycast ignores smoke (it has no collider), which is the whole combo with
	# their smoke grenades. Walls still block it, so it is a heat SCOPE, not a
	# wallhack of the map.
	var thermal := Control.new()
	thermal.set_anchors_preset(Control.PRESET_FULL_RECT)
	thermal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thermal.draw.connect(_draw_thermal.bind(thermal, player))
	# Only while somebody is actually looking through a heat sight, plus the one
	# frame after they lower it so what was drawn gets cleared — the same rule
	# the scan overlay follows (see _tick_overlays). One class in the game has
	# this sight, so left on process_frame it re-recorded four canvas items a
	# frame, all match, to draw nothing at all.
	_thermal_overlays.append({"c": thermal, "player": player})
	hud.add_child(thermal)

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
		# A red dot is a holo under the hood (has_holo true), so split it out
		# FIRST: dot gets the dot reticle, everything else holo gets the ring.
		var dotted: bool = player.weapon.aiming and player.weapon.has_reddot()
		var ringed: bool = player.weapon.aiming and player.weapon.has_holo() and not dotted
		scope.visible = scoped and live
		holo.visible = ringed and live
		reddot.visible = dotted and live
		crosshair.visible = not scoped and not ringed and not dotted and live
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
			GameState.team_names[team], int(GameState.scores.get(team, 0))])
	var text := ("     " if GameState.active_teams() <= 2 else "   ").join(parts)
	for label in _score_labels:
		label.text = text


## Health, bottom left: the NUMBER and the BAR together (`HealthGauge`). It was
## the number alone, which is exact and unreadable — the thing that actually gets
## looked at here is looked at from the corner of the eye, mid-fight, on a
## quarter of a screen, and a bar is the only form that survives that.
func _add_health(hud: Control, player: Player, color: Color) -> void:
	var gauge := HealthGauge.new()
	gauge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	gauge.offset_left = 14.0
	gauge.offset_top = -42.0
	gauge.offset_right = 14.0 + 190.0
	gauge.offset_bottom = -42.0 + HealthGauge.BAR_H
	hud.add_child(gauge)
	gauge.setup(player, color)


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
		state = "%s HOLDS THE ZONE" % GameState.team_names[holder]
		tint = GameState.team_colors[holder]
	for label in _zone_labels:
		label.text = "%s     moves in %ds" % [state, seconds_left]
		label.add_theme_color_override("font_color", tint)


func _announce_zone_move(_point: Vector3) -> void:
	for label in _zone_labels:
		label.text = "NEW ZONE"
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))


## A KILL STREAK REWARD LANDING. Two lines in the upper middle of that player's
## own quadrant: the NAME big, because that is what they repeat to the room, and
## the blurb under it small, because "what did I just get" has to be answerable
## without leaving the fight.
##
## It goes in the UPPER MIDDLE and not with the streak counter under the player
## tag. The counter is a running number you glance at; this is an event, and an
## event announced in the corner of a quarter screen is an event nobody notices.
## Well clear of the crosshair for the reason the saber blade is: a banner across
## the middle blinds you exactly when you are in the fight that earned it.
const STREAK_BANNER_TIME := 3.2


func _add_streak_reward(hud: Control, player: Player) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_top = 16.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.visible = false
	hud.add_child(box)

	var title := Label.new()
	title.add_theme_font_size_override("font_size",
		30 if GameState.human_players == 1 else 19)
	title.add_theme_color_override("font_color", KILL_STREAK_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var blurb := Label.new()
	blurb.add_theme_font_size_override("font_size",
		16 if GameState.human_players == 1 else 12)
	blurb.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(blurb)

	# THE PROMPT NAMES ITS BUTTONS THROUGH `Controls.label` and never in text, so
	# it follows a rebind instead of going stale (house rule 16). `label()` is
	# player-facing and takes the device, so player 3's pad says what player 3's
	# pad is actually bound to.
	var keys := Label.new()
	keys.add_theme_font_size_override("font_size",
		15 if GameState.human_players == 1 else 11)
	keys.add_theme_color_override("font_color", Color(0.78, 0.86, 1.0))
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)

	# A METHOD-BOUND handler would need per-player state to find its own labels,
	# so this is a lambda — legal here because the signal belongs to the PLAYER,
	# which is freed with the scene, not to an autoload (house rule 11).
	player.streak_offered.connect(func(name: String, text: String) -> void:
		# An EMPTY name means the offer was resolved — accepted or declined — and
		# the prompt takes itself down. One signal for both edges, because the HUD
		# does not care which answer was given.
		if name == "":
			box.visible = false
			return
		title.text = name
		blurb.text = text
		keys.text = "%s  TAKE     %s  DECLINE" % [
			Controls.label(player.input_device, "reward_accept"),
			Controls.label(player.input_device, "reward_decline")]
		box.visible = true
		box.modulate.a = 1.0
		box.scale = Vector2(1.18, 1.18)
		box.pivot_offset = box.size * 0.5
		var pop := hud.create_tween()
		pop.tween_property(box, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


## THE DEATH CAM'S CAPTION. The camera swings onto your killer on its own
## (`Player._track_killer`); this is what names them, and it carries a bar for the
## health you left them on — which is the whole difference between "I was
## outclassed" and "one more shot".
##
## Placed high and centred, ABOVE the crosshair line, because the buy screen owns
## the middle and bottom of a dead player's viewport and the two must not overlap.
## Driven off `died`/`respawned` rather than polled: it is the only readout whose
## content is fixed for the entire time it is up.
func _add_killed_by(hud: Control, player: Player) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.offset_top = 54.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.visible = false
	hud.add_child(box)

	var line := Label.new()
	line.add_theme_font_size_override("font_size",
		22 if GameState.human_players == 1 else 15)
	line.add_theme_color_override("font_color", Color(1.0, 0.86, 0.86))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)

	# The killer's remaining health, as a bar rather than a number for exactly the
	# reason the health gauge is: a number has to be read, and this one is up for
	# two seconds while you are also shopping.
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(
		132.0 if GameState.human_players == 1 else 96.0, 6.0)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(bar)

	_killed_by.append({"player": player, "box": box, "line": line, "bar": bar})


## The death caption is REPOINTED every frame while it is up, because the one
## thing on it that moves is the killer's health — they are still in a fight.
## Ticked from `_tick_overlays` with the rest of the HUD rather than as its own
## process, so the per-frame cost of the whole HUD stays visible in one place.
func _tick_killed_by() -> void:
	for row in _killed_by:
		var player: Player = row["player"]
		if not is_instance_valid(player):
			continue
		var box: Control = row["box"]
		var text: String = player.killer_line()
		if text == "":
			box.visible = false
			continue
		box.visible = true
		var line: Label = row["line"]
		if line.text != text:
			line.text = text     # assigning re-shapes glyphs, so only when it moved
		var bar: ProgressBar = row["bar"]
		var frac := player.killer_health()
		bar.visible = frac >= 0.0
		if frac >= 0.0:
			bar.value = frac


func _add_kill_feed(hud: Control) -> void:
	var feed: Control = KILL_FEED.new()
	hud.add_child(feed)


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


## WHAT YOU CAN DO RIGHT NOW, as a row of round gauges above the weapon name
## rather than as a line of text. Both gadget slots (a Mandalorian carries two,
## and reporting only slot 0 hid half of what they bought), plus the dash and the
## saber guard, which are not gadgets but are read exactly the same way by a
## player and so get the same widget rather than a second kind of readout.
##
## The gauges are rebuilt on a WEAPON SWAP and a deploy rather than kept in step,
## because what a player is carrying only changes at those two moments — and the
## guard gauge exists only while a blade is in hand.
##
## SQUAD stays as text: it is a count of bought AI, not an ability, and it has no
## charge state to draw.
func _add_gear_readout(hud: Control, player: Player, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.offset_left = -260.0
	row.offset_top = -46.0 - AbilityGauge.DIAM
	row.offset_right = -14.0
	row.offset_bottom = -46.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(row)

	var squad := Label.new()
	squad.add_theme_font_size_override("font_size", 15)
	squad.add_theme_color_override("font_color", Color(color, 0.85))
	squad.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	squad.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	squad.offset_left = -220.0
	squad.offset_top = -64.0 - AbilityGauge.DIAM
	squad.offset_right = -14.0
	squad.offset_bottom = -46.0 - AbilityGauge.DIAM
	hud.add_child(squad)

	var rebuild := func() -> void:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
		for slot in 3:
			if Loadout.gadget_action(player.gadget_in(slot)) == Loadout.Gadget.NONE:
				continue
			var g := AbilityGauge.new()
			row.add_child(g)
			g.setup(player, color, AbilityGauge.KIND_GADGET, slot)
		if player.loadout.can_dash():
			var d := AbilityGauge.new()
			row.add_child(d)
			d.setup(player, color, AbilityGauge.KIND_DASH)
		if player.weapon.is_melee():
			var b := AbilityGauge.new()
			row.add_child(b)
			b.setup(player, color, AbilityGauge.KIND_GUARD)
		squad.text = "" if player.squad.is_empty() \
			else "SQUAD x%d" % player.squad.size()
	player.squad_changed.connect(func(_alive: int) -> void: rebuild.call())
	player.weapon_changed.connect(func(_n: String) -> void: rebuild.call())
	player.respawned.connect(func() -> void: rebuild.call())
	rebuild.call()


func _add_victory_banner(hud: Control) -> void:
	var banner := _full_rect_label("", 40, Color(1, 1, 1, 1))
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.visible = false
	hud.add_child(banner)
	_victory_banners.append(banner)


## THE POST-MATCH TABLE. The banner says which side won, which is the one thing
## everybody already knows — it was on the scoreboard all match. What nobody
## knows is how each PERSON did, and at a couch that is the entire conversation
## after a round.
##
## HUMANS ONLY, for the reason `GameState.player_stats` states: a bot is freed on
## death, so there is nothing stable to accumulate into. Team totals are already
## on the scoreboard above it.
##
## Built once and filled on victory rather than rebuilt per frame — it is up for
## MATCH_END_DELAY and its contents cannot change, the match being over.
func _add_score_table(hud: Control) -> void:
	var panel := _full_rect_label("", _table_font_size(), Color(0.92, 0.92, 0.92))
	panel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_theme_constant_override("line_spacing", 4)
	panel.visible = false
	hud.add_child(panel)
	_score_tables.append(panel)


func _table_font_size() -> int:
	return 20 if GameState.human_players == 1 else 13


## The table's text, built once for every viewport. Monospaced by PADDING rather
## than by font, since the HUD has one font and it is proportional — the columns
## only have to look like columns.
func _score_table_text() -> String:
	var rows := GameState.score_table()
	if rows.is_empty():
		return ""
	var out := "\n\n\n\n"     # clear of the WINS banner, which is centred
	out += "%-12s %5s %7s %6s %8s\n" % ["", "KILLS", "DEATHS", "HEAD", "BEST RUN"]
	for row in rows:
		var name: String = str(row["name"])
		out += "%-12s %5d %7d %6d %8d\n" % [name, int(row["kills"]),
			int(row["deaths"]), int(row["headshots"]), int(row["best_streak"])]
	return out


func _show_victory(team: int) -> void:
	# WHOSE victory decides the sting, and with four players at one couch there
	# is no single answer — so it asks the humans: if any of them is on the
	# winning side the room hears the fanfare, and if none is, it hears the other
	# one. Music stops either way; a banner over a battle loop reads as a bug.
	Audio.play_music("")
	var ours := false
	for c in GameState.combatants:
		if c is Player and is_instance_valid(c) and c.team == team:
			ours = true
	Audio.play("victory" if ours else "defeat")
	for banner in _victory_banners:
		banner.text = "%s WINS" % GameState.team_names[team]
		banner.add_theme_color_override("font_color", GameState.team_colors[team])
		banner.visible = true
	var table := _score_table_text()
	for panel in _score_tables:
		panel.text = table
		panel.visible = table != ""


## The buy screen for one viewport: a dimmed backdrop, the budget, one row per
## purchasable thing with the cursor on the active row, a blurb for whatever the
## cursor is on, and the deploy prompt. Shown at match start (DEPLOY) and after
## every death (ELIMINATED). Each player drives their own quadrant, so all four
## shop at once; nobody spawns until they press deploy.
## Boxes come from Loadout.BUY_BOXES — the grouping drives INPUT as well as
## layout now (the selector moves box to box, and entering one scopes the rows
## you can edit), so it belongs with the catalogue rather than with the screen
## that happens to draw it.
## The box furniture — metrics, panel style, the cursor and its arena — is
## BoxScreen's, shared with the character-select screen so the two cannot drift
## apart.
const BUY_COLUMNS := Player.BUY_GRID_COLUMNS


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

	var m := BoxScreen.metrics()
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
	# Panels indexed by BOX, not by row: the selector lives on a box now, so the
	# highlight has to be addressable the same way the input is.
	var boxes: Array[PanelContainer] = []
	names.resize(Loadout.Row.size())
	values.resize(Loadout.Row.size())
	for box in Loadout.BUY_BOXES:
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", BoxScreen.panel(BoxScreen.EDGE))
		grid.add_child(frame)
		boxes.append(frame)
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

	# THE SPAWN BOX. A box of its own, under the grid and as wide as it, because
	# deploying is now a thing you aim at rather than a button that fires from
	# wherever the selector happens to be. It is also where the selector starts,
	# so the ordinary respawn is still one press.
	column.add_child(_spacer(4))
	var spawn_frame := PanelContainer.new()
	spawn_frame.add_theme_stylebox_override("panel", BoxScreen.panel(BoxScreen.EDGE))
	column.add_child(spawn_frame)
	boxes.append(spawn_frame)
	var spawn_label := _centred_label("", m["head"] + 4, Color(0.85, 0.95, 0.8))
	spawn_frame.add_child(spawn_label)

	# THE DEPLOY POST BOX, Conquest only (hidden everywhere else, which also
	# takes it out of the cursor's reach). Choosing where you come back in is a
	# Conquest rule rather than a shopping one, so it belongs on this screen too
	# and not only on the character select — otherwise picking CUSTOM classes in
	# Conquest would quietly take the mode's own mechanic away from you.
	var post_frame := PanelContainer.new()
	post_frame.add_theme_stylebox_override("panel", BoxScreen.panel(BoxScreen.EDGE))
	post_frame.visible = GameState.mode == GameState.Mode.CONQUEST
	column.add_child(post_frame)
	boxes.append(post_frame)
	var post_label := _centred_label("", m["head"], Color(1, 1, 1, 0.8))
	post_frame.add_child(post_label)

	column.add_child(_spacer(4))
	var blurb := _centred_label("", m["head"] + 1, Color(0.7, 0.74, 0.8))
	column.add_child(blurb)
	var prompt := _centred_label("", m["head"] + 2, Color(0.62, 0.66, 0.72))
	column.add_child(prompt)

	# The cursor overlay: a reticle drawn on top of the boxes, plus a per-frame
	# resolver that turns the player's normalised cursor into "which box is it
	# over" and writes that back. It has to read the REAL box rects (hidden boxes
	# reflow the grid, so nothing analytic can know where a box actually landed),
	# which is why it takes them as an argument.
	var cursor := Control.new()
	cursor.set_anchors_preset(Control.PRESET_FULL_RECT)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.draw.connect(func() -> void:
		BoxScreen.draw_cursor(cursor, player, boxes, color))
	panel.add_child(cursor)

	var refresh := func() -> void:
		_refresh_buy_screen(player, color, names, values, boxes, budget, blurb,
			prompt, spawn_label, post_label)
	# Resolve the cursor -> box every frame while the screen is up, and redraw the
	# reticle. Only re-runs the text refresh when the box under the cursor
	# actually changes, so a still cursor costs one has_point sweep and no more.
	#
	# Registered for Main's own per-frame tick rather than connected to
	# process_frame as a lambda. A lambda that never touches `self` has no target
	# object, so the SceneTree keeps the connection alive after the match is torn
	# down and it goes on reading `panel.visible` off a freed panel every frame
	# on the menu — the same leak the autoload signals were fixed for, one signal
	# further out. This array dies with Main.
	_buy_screens.append({"panel": panel, "cursor": cursor, "player": player,
		"boxes": boxes, "refresh": refresh})
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


## Rewrite the buy screen for the player's current pending build.
##
## Three states have to be told apart at a glance from the far side of a
## four-way split, so each gets a different signal rather than a different shade
## of the same one:
##
##   the selector is ON a box      its border takes the player's colour
##   the box is OPEN               ...and it fills with that colour, dimmed
##   neither                       plain grey edge, no row caret at all
##
## The caret only exists inside an open box. That is deliberate: a caret sitting
## on a line you cannot currently change is exactly the lie the old screen told.
func _refresh_buy_screen(player: Player, color: Color, names: Array[Label],
		values: Array[Label], boxes: Array[PanelContainer],
		budget: Label, blurb: Label, prompt: Label, spawn: Label,
		post: Label) -> void:
	var build := player.pending
	budget.text = "TOKENS  %d spent   %d left of %d" % [
		build.cost(), build.remaining(), Loadout.BUDGET]
	for i in names.size():
		# A row this class does not have is hidden outright rather than shown
		# dead: the selector already skips it, and a line you cannot move reads
		# as a broken screen from across a four-way split.
		var available := build.row_available(i)
		names[i].get_parent().visible = available
		if not available:
			continue
		var selected := player.buy_inside and i == player.buy_row
		var tint := color if selected else Color(1, 1, 1, 0.72)
		names[i].text = "%s %s" % ["\u25b8" if selected else " ", build.row_label(i)]
		var cost := build.row_cost(i)
		values[i].text = build.row_value(i)
		if cost > 0:
			values[i].text += "   %d" % cost
		names[i].add_theme_color_override("font_color", tint)
		values[i].add_theme_color_override("font_color", tint)

	for bi in boxes.size():
		# A box with nothing left in it goes, so a Mandalorian's screen has no
		# empty GRENADES panel sitting on it. SPAWN is always there, and the post
		# box only in Conquest.
		if bi == Player.SPAWN_BOX:
			boxes[bi].visible = true
		elif bi == Player.POST_BOX:
			boxes[bi].visible = GameState.mode == GameState.Mode.CONQUEST
		else:
			boxes[bi].visible = build.box_available(bi)
	BoxScreen.paint(boxes, player.buy_box, player.buy_inside, color)

	post.text = _deploy_post_line(player)

	# The blurb explains whatever the selector is pointing at: the open row, or
	# the box you are about to open.
	if player.buy_inside and player.buy_box == Player.POST_BOX:
		blurb.text = "up / down to choose where you come back in"
	elif player.buy_inside:
		blurb.text = build.row_blurb(player.buy_row, player.input_device)
	elif player.buy_box == Player.SPAWN_BOX:
		blurb.text = "Everything above is what you will deploy with"
	elif player.buy_box == Player.POST_BOX:
		blurb.text = "Where you come back in"
	else:
		blurb.text = str(Loadout.BUY_BOXES[player.buy_box]["name"])

	# Count the lock-down out loud: a silent "standby" for five seconds reads
	# exactly like a match that has failed to start.
	var a := player.buy_accept_name()
	if player.deploy_armed():
		spawn.text = "SPAWN     %s" % a
		spawn.add_theme_color_override("font_color", Color(0.85, 0.95, 0.8))
	else:
		spawn.text = "ready in %d..." % ceili(player.deploy_wait())
		spawn.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))

	# ...and the prompt says what the buttons do RIGHT NOW, because the same two
	# buttons do different things in the two states.
	if player.buy_inside:
		prompt.text = "%s change     %s back" % [a, player.buy_back_name()]
	else:
		prompt.text = "move the cursor     %s to modify" % a


## The Conquest deploy-post box's one line: which post you will come back in on,
## out of the ones your side still holds. One line rather than the select
## screen's list, because this box sits under a full buy grid and has no room.
func _deploy_post_line(player: Player) -> String:
	if GameState.mode != GameState.Mode.CONQUEST:
		return ""
	var owned := GameState.owned_posts(player.team)
	if owned.is_empty():
		return "DEPLOY POST     — none held, deploying at base —"
	var sel := clampi(player.spawn_post, 0, owned.size() - 1)
	return "DEPLOY POST     ◂ %s ▸     (%d of %d)" % [
		owned[sel].post_name, sel + 1, owned.size()]


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


## The thermal read: a heat box over every enemy the aiming Trandoshan can see,
## smoke included. Projected onto THIS player's own viewport, so it is a scope
## they look through and never a shared tracker — the design rule the map screen
## follows for the same reason.
##
## What it shows: living enemies within THERMAL_RANGE and roughly in front, with
## a clear line to them THROUGH SMOKE (the raycast is world-layer only, and
## smoke has no collider, so a wall blocks it and a cloud does not). The point of
## the class is throwing smoke and then reading bodies inside it that nobody else
## can see.
const THERMAL_RANGE := 90.0
const THERMAL_HEAT := Color(1.0, 0.45, 0.15)


## The scan-dart reveal: a marker over every enemy currently pinged to this
## player's team, drawn THROUGH walls (that is the recon value) as long as it is
## roughly in front. A per-viewport overlay like the thermal read, so it is not a
## shared tracker — each player sees their own side's scans.
const SCAN_MARK := Color(0.55, 0.9, 1.0)


## The scan overlay is empty for almost the whole match — a dart has to be in the
## air and biting for it to draw anything — so it is redrawn only while a scan is
## live, plus the one frame after the last mark expires so what was drawn gets
## cleared. Left on `process_frame` it re-recorded a canvas item per viewport per
## frame, four times over, to draw nothing.
##
## Ticked once for all viewports (see _tick_scans) rather than per overlay: the
## "is anything live" answer is global, so a per-overlay check would let the
## first viewport flip the flag and the other three miss their clearing redraw.
func _add_scan(hud: Control, player: Player) -> void:
	var scan := Control.new()
	scan.set_anchors_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scan.draw.connect(_draw_scan.bind(scan, player))
	_scan_overlays.append(scan)
	hud.add_child(scan)


var _scan_overlays: Array[Control] = []
var _scan_was_live := false
var _minimaps: Array = []              # [Control] — untyped so should_redraw() dispatches
## Overlays and readouts that would otherwise sit on process_frame redrawing
## themselves sixty times a second to produce the same picture. See _tick_overlays.
var _thermal_overlays: Array = []      # [{c: Control, player: Player}]
var _thermal_was_live := false
var _bloom_ticks: Array = []           # [{c: Control, player: Player, at: float}]
var _slow_labels: Array = []           # [{label: Label, at: int}] — royale readouts
## The deploy screens, one per human. Held here rather than each connecting its
## own lambda to process_frame, so they are torn down with the match.
var _buy_screens: Array = []           # [{panel, cursor, player, boxes, refresh}]
## How often the slow group refreshes. They print whole seconds and a rounded
## damage figure, so sixty times a second was fifty-four wasted string builds.
const SLOW_TICK := 6                   # every 6th frame — 10 Hz at 60 fps


## ONE per-frame tick for every viewport's overlays, rather than a connection
## each. Two reasons it is shared: "is anything live" is a GLOBAL answer, so a
## per-overlay check would let the first viewport flip the flag and the other
## three miss their clearing redraw; and this is the only place in the HUD that
## runs every frame regardless, so keeping it in one function makes the cost
## visible instead of scattered across six closures.
func _tick_overlays() -> void:
	_tick_scans()
	_tick_thermal()
	_tick_bloom()
	_tick_minimaps()
	_tick_buy_screens()
	_tick_killed_by()
	if Engine.get_process_frames() % SLOW_TICK == 0:
		for entry in _slow_labels:
			var label: Label = entry["label"]
			if is_instance_valid(label):
				label.queue_redraw()


## Each deploy screen that is currently up: redraw its cursor, and re-run the
## text refresh only when the cursor has actually crossed into another box.
func _tick_buy_screens() -> void:
	for entry in _buy_screens:
		var panel: Control = entry["panel"]
		if not is_instance_valid(panel) or not panel.visible:
			continue
		var cursor: Control = entry["cursor"]
		if is_instance_valid(cursor):
			cursor.queue_redraw()
		if BoxScreen.resolve(entry["player"], entry["boxes"]):
			(entry["refresh"] as Callable).call()


## PER VIEWPORT, not globally, and that is the opposite of the scan overlay
## deliberately: the scan's "is anything live" is one answer for everybody, where
## a minimap's picture moves when ITS OWN player moves. One player sprinting must
## not cost the other three a redraw of a picture that has not changed.
func _tick_minimaps() -> void:
	for m in _minimaps:
		if is_instance_valid(m) and m.should_redraw():
			m.queue_redraw()


func _tick_scans() -> void:
	var live := not GameState.scanned.is_empty()
	if not live and not _scan_was_live:
		return
	_scan_was_live = live
	for c in _scan_overlays:
		if is_instance_valid(c):
			c.queue_redraw()


func _tick_thermal() -> void:
	var live := false
	for entry in _thermal_overlays:
		var player: Player = entry["player"]
		if is_instance_valid(player) and player.thermal_active():
			live = true
			break
	if not live and not _thermal_was_live:
		return
	_thermal_was_live = live
	for entry in _thermal_overlays:
		var c: Control = entry["c"]
		if is_instance_valid(c):
			c.queue_redraw()


## The bloom crosshair, redrawn per viewport only when that player's own cone has
## moved. Per viewport rather than globally because the cone is personal — one
## player spraying must not cost the other three a redraw.
func _tick_bloom() -> void:
	for entry in _bloom_ticks:
		var c: Control = entry["c"]
		if not is_instance_valid(c) or not c.visible:
			continue
		var player: Player = entry["player"]
		var now: float = player.weapon.current_spread_deg()
		if absf(now - float(entry["at"])) < 0.005:
			continue
		entry["at"] = now
		c.queue_redraw()


func _draw_scan(c: Control, player: Player) -> void:
	if c.size.y <= 0.0 or GameState.scanned.is_empty() or player.camera() == null:
		return
	var cam := player.camera()
	for body in GameState.combatants:
		if not is_instance_valid(body) or body == player:
			continue
		if not ("team" in body and body.team != player.team):
			continue
		if body.has_method("is_alive") and not body.is_alive():
			continue
		if not GameState.is_scanned_for(body, player.team):
			continue
		var chest: Vector3 = body.global_position + Vector3.UP * 1.0
		if cam.is_position_behind(chest):
			continue
		# Through walls on purpose — a scan is a ping, not a line of sight.
		var head := cam.unproject_position(body.global_position + Vector3.UP * 1.8)
		var feet := cam.unproject_position(body.global_position)
		var h := absf(feet.y - head.y)
		var w := maxf(h * 0.5, 6.0)
		var rect := Rect2(Vector2(head.x - w * 0.5, head.y), Vector2(w, maxf(h, 8.0)))
		c.draw_rect(rect, SCAN_MARK, false, 2.0)
		# A caret above the head, so a scanned enemy reads even at a glance.
		var tip := Vector2(head.x, head.y - 8.0)
		c.draw_colored_polygon(PackedVector2Array([
			tip, tip + Vector2(-5, -8), tip + Vector2(5, -8)]), SCAN_MARK)


func _draw_thermal(c: Control, player: Player) -> void:
	if c.size.y <= 0.0 or not player.thermal_active():
		return
	var cam := player.camera()
	if cam == null:
		return
	var space := cam.get_world_3d().direct_space_state
	for body in GameState.combatants:
		if not is_instance_valid(body) or body == player:
			continue
		if not ("team" in body and body.team != player.team):
			continue
		if body.has_method("is_alive") and not body.is_alive():
			continue
		var chest: Vector3 = body.global_position + Vector3.UP * 1.0
		if cam.global_position.distance_to(chest) > THERMAL_RANGE:
			continue
		if cam.is_position_behind(chest):
			continue
		# Line of sight through smoke: world layer only, so a wall stops the ray
		# and a smoke cloud (no collider) does not.
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, chest)
		q.collision_mask = 1
		q.exclude = [player.get_rid()]
		if not space.intersect_ray(q).is_empty():
			continue
		# Project head and feet so the box scales with distance the way the body
		# on screen does.
		var head := cam.unproject_position(body.global_position + Vector3.UP * 1.8)
		var feet := cam.unproject_position(body.global_position)
		var h := absf(feet.y - head.y)
		var w := maxf(h * 0.5, 6.0)
		var top := Vector2(head.x - w * 0.5, head.y)
		var rect := Rect2(top, Vector2(w, maxf(h, 8.0)))
		c.draw_rect(rect, Color(THERMAL_HEAT, 0.9), false, 2.0)
		c.draw_rect(rect, Color(THERMAL_HEAT, 0.12), true)


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


## The reflex dot: a crisp centre dot with a soft halo, no ring, no blackout —
## the fastest sight picture to read, which is the reflex sight's whole point.
func _draw_reddot(c: Control) -> void:
	var center := c.size * 0.5
	c.draw_circle(center, 6.0, Color(1.0, 0.25, 0.18, 0.28))
	c.draw_circle(center, 2.6, Color(1.0, 0.3, 0.22, 1.0))


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
