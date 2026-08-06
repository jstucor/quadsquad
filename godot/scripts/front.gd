extends Control
## THE FRONT SCREEN — the first thing the game shows, and the door into it.
##
## WHAT IT REPLACED AND WHY. `menu.gd` was the front screen, and it is a good
## MATCH SETUP screen: fourteen labelled dropdowns on one four-column grid, every
## one of them a real decision. As the first thing anybody sees, it is a form.
## Four people sitting down to play were met with UNIVERSE, PLANET, TIME OF DAY,
## TIME TO KILL, VICTORY, AI SKILL, AIM ASSIST and four SIDE rows before they
## could establish that the game does split screen at all — and "we are two of us
## on one sofa, start it" was somewhere in the middle of that grid, as a dropdown
## called PLAYERS.
##
## So the two jobs are split. This screen answers WHAT ARE WE DOING; `menu.gd`
## still answers WHAT ARE THE RULES, unchanged, one press further in. That is the
## shape every shooter front end has converged on and it is not fashion: the
## first screen has to be readable by somebody who has not played before, and a
## settings grid never is.
##
## THE BACKGROUND IS THE GAME, RENDERED LIVE. A flat colour behind a menu says
## nothing about what is on the other side of the button, and this project has no
## art to put there — no key art, no textures, no imported anything. What it does
## have is a procedural character generator, a lighting grade and a materials
## system, all of which already produce the thing the key art would be OF. So the
## background is a real `CharacterModel` under the real `Grade`, playing the real
## idle clip, turning slowly on a camera that drifts. It costs one body and one
## light, and it is the only screen in the game that shows you what you are about
## to be before you pick it.

## LOCAL PLAY GOES TO THE SIGN-IN, not straight to the setup screen. Between
## "how many of us" and "what are we playing" there is a question the game used
## to answer by arithmetic and now asks out loud: which controller is each of you
## holding, and who are you (see `sign_in.gd`). The setup screen it leads to is
## `playlist.tscn`; `menu.tscn` is still the single-match setup and is what the
## lobby and the settings screen come back to.
const SIGN_IN_SCENE := "res://scenes/sign_in.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"
const FRONT_SCENE := "res://scenes/front.tscn"
const BOLT := preload("res://scenes/fx/blaster_bolt.tscn")

const BG_COLOR := Color(0.05, 0.06, 0.08)
const ACCENT := Color(0.45, 0.72, 1.0)
const DIM := Color(0.62, 0.66, 0.72)
const FAINT := Color(0.42, 0.46, 0.52)
const PANEL := Color(0.09, 0.11, 0.14, 0.86)
const PANEL_EDGE := Color(0.24, 0.30, 0.38)

## THE MENU IS CAPPED. A camera-less screen renders at whatever the machine can
## manage — `menu.gd` records three hundred frames a second — and this one has a
## 3D scene in it, so uncapped it would put the GPU into its thermal limit before
## the match that needs the clocks has started (see SMOOTHNESS: the same scene
## measured 26 ms cold and 48 ms after ten minutes). Sixty is far more than a
## menu needs.
const MENU_FPS := 60

## How far the entry list is indented from the left edge, in pixels. The fight
## happens on the RIGHT of the frame and the list sits down the left, so the two
## do not compete — a menu centred over a battle is a menu with somebody's head
## behind every third word.
const LIST_INDENT := 96

var _stage: SubViewport
var _rig: Node3D              # what the camera orbits
var _turn := 0.0
var _panel: VBoxContainer     # the LOCAL PLAY step, built once and shown/hidden
var _entries: VBoxContainer
var _players_label: Label


func _ready() -> void:
	# A match captures the pointer; coming back here it has to be free again.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Quality.active_views = 1
	Quality.apply_global()
	Engine.max_fps = MENU_FPS
	Audio.play_music("menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameState.chosen_teams = []   # a fresh visit re-picks teams from scratch
	# `-- --host` / `-- --join` walk straight into the lobby, already in a
	# session. DEFERRED for the reason `menu.gd` records: the tree is still
	# attaching this scene, and changing scene from inside `_ready` tries to
	# detach a parent that is busy attaching.
	if not Net.online() and Net.boot_from_cmdline():
		get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)
		return
	_build()


func _exit_tree() -> void:
	# Hand the cap back. A match sets its own (the governor's rung ladder owns
	# the rate from there), and leaving a menu's 60 on top of that would quietly
	# put a ceiling on every match played after visiting this screen.
	Engine.max_fps = 0


func _process(delta: float) -> void:
	# The drift. Slow enough that it never becomes the thing you are looking at —
	# a background that moves at a rate you can follow stops being a background.
	_turn += delta * 0.06
	if _rig != null:
		_rig.rotation.y = sin(_turn) * 0.16
	_tick_battle(delta)


func _build() -> void:
	_build_stage()

	# A WASH OVER THE 3D, not a panel behind the words. Text over a rendered
	# scene is unreadable wherever the scene happens to be bright, and the honest
	# fix is to darken the whole frame toward the side the text is on rather than
	# to put a box round the text — a box would hide the thing the background is
	# there to show.
	# A GRADIENT, NOT A FLAT WASH. A uniform veil has to be dark enough for the
	# worst case — text over the brightest thing in the scene — and at that
	# strength it also puts the whole firefight behind a grey sheet, which is the
	# one thing the background exists not to be. Ramping it across the frame lets
	# the left side be as dark as the words need while the right side, where the
	# fighting is, is barely touched.
	var grad := Gradient.new()
	grad.set_color(0, Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.93))
	grad.set_color(1, Color(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.62, 0.0)
	var wash := TextureRect.new()
	wash.texture = tex
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.stretch_mode = TextureRect.STRETCH_SCALE
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.offset_left = 0.0
	add_child(column)
	# Indented off the left edge rather than centred: see LIST_INDENT.
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", LIST_INDENT)
	column.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	pad.add_child(inner)

	inner.add_child(_label("QUADSQUAD", 68, ACCENT))
	inner.add_child(_rule())
	inner.add_child(_label("FOUR-PLAYER SPLIT SCREEN", 14, FAINT))
	inner.add_child(_spacer(18))

	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", 8)
	inner.add_child(_entries)

	# THE ORDER IS THE ARGUMENT. Local play is first and largest because it is
	# what this game IS — four pads on one sofa — and it was previously reachable
	# only by finding a dropdown called PLAYERS in the middle of a settings grid.
	var local := _entry("LOCAL PLAY", "Split screen for one to four on this machine")
	local.pressed.connect(_open_local)
	var online := _entry("ONLINE PLAY", "Host or join a match over the network")
	online.pressed.connect(func() -> void:
		get_tree().change_scene_to_file(LOBBY_SCENE))
	var options := _entry("SETTINGS", "Controls, quality and frame rate")
	options.pressed.connect(func() -> void:
		# ...and it comes back HERE. That screen used to return to the match-setup
		# menu whoever opened it, which from the front screen is a BACK that lands
		# somewhere you have never been.
		GameState.settings_return = FRONT_SCENE
		get_tree().change_scene_to_file(SETTINGS_SCENE))
	var quit := _entry("QUIT", "")
	quit.pressed.connect(func() -> void: get_tree().quit())

	_build_local_panel(inner)
	local.grab_focus()


## --- THE LOCAL PLAY STEP -------------------------------------------------------
##
## ONE QUESTION, THEN THE MATCH. How many of you — which is the only thing that
## cannot be defaulted, because it is a fact about the room rather than a
## preference — and then straight on to the setup screen, which already knows how
## to do everything else.
##
## It is built ONCE and shown, never rebuilt on the press: this screen has a live
## 3D viewport behind it and rebuilding Controls over that is a visible hitch for
## no gain.
func _build_local_panel(into: VBoxContainer) -> void:
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 8)
	_panel.visible = false
	into.add_child(_panel)

	_panel.add_child(_spacer(10))
	_panel.add_child(_label("HOW MANY OF YOU?", 22, Color(0.92, 0.94, 0.98)))
	_players_label = _label("", 15, DIM)
	_panel.add_child(_players_label)
	_panel.add_child(_spacer(4))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_panel.add_child(row)
	for n in range(GameState.MIN_HUMANS, GameState.MAX_HUMANS + 1):
		var b := _seat_button(n)
		row.add_child(b)
		b.pressed.connect(_pick_players.bind(n))

	_panel.add_child(_spacer(10))
	var go := _entry_into(_panel, "CONTINUE",
		"Sign in, then build your playlist")
	go.pressed.connect(func() -> void:
		# A fresh visit re-seats everybody: the seats are a fact about who is in
		# the room right now, and carrying last session's into a screen that is
		# about to ask again would show three people already signed in.
		GameState.clear_seats()
		get_tree().change_scene_to_file(SIGN_IN_SCENE))
	# ...and the OLD setup screen, kept and reachable. It is the only screen that
	# can build ONE odd match — an individual side row, a mixed setup, the map
	# rotation — without queuing anything, and a playlist of one round is a longer
	# way round for somebody who just wants a game of deathmatch. Second, smaller
	# and named for what it is: the flow above is the one being recommended.
	var single := _entry_into(_panel, "SINGLE MATCH",
		"The setup grid: one match, every setting on one screen")
	single.pressed.connect(func() -> void:
		GameState.playlist.clear()   # or a queue built earlier would still drive
		GameState.playlist_index = -1
		get_tree().change_scene_to_file(MENU_SCENE))
	var back := _entry_into(_panel, "BACK", "")
	back.pressed.connect(_close_local)
	_refresh_players()


func _open_local() -> void:
	_entries.visible = false
	_panel.visible = true
	_refresh_players()
	# Focus has to MOVE with the panel. A pad player whose focus is still on a
	# hidden button is a player whose controller has stopped working, and there
	# is nothing on screen to say why.
	for c in _panel.get_children():
		if c is Button:
			(c as Button).grab_focus()
			return


func _close_local() -> void:
	_panel.visible = false
	_entries.visible = true
	for c in _entries.get_children():
		if c is Button:
			(c as Button).grab_focus()
			return


func _pick_players(n: int) -> void:
	GameState.human_players = clampi(n, GameState.MIN_HUMANS, GameState.MAX_HUMANS)
	# FREE FOR ALL needs a second player, and picking one seat while it is on
	# would carry an illegal setup into the setup screen. `menu.gd` fixes this up
	# too, but a screen that hands on a state it knows is wrong is a screen
	# relying on the next one to notice.
	if GameState.human_players < 2:
		GameState.free_for_all = false
	_refresh_players()


func _refresh_players() -> void:
	if _players_label == null:
		return
	var n := GameState.human_players
	_players_label.text = "%d %s  ·  the screen splits %s" % [
		n, "player" if n == 1 else "players",
		"not at all" if n == 1 else ("in two" if n == 2 else "four ways")]
	var i := GameState.MIN_HUMANS
	for c in _panel.get_children():
		if c is HBoxContainer:
			for b in (c as HBoxContainer).get_children():
				_paint_seat(b as Button, i == n)
				i += 1


## --- the live background: A FIREFIGHT, NOT A PORTRAIT ------------------------
##
## THE BACKGROUND IS A BATTLE THE MENU IS SITTING IN FRONT OF. The first pass was
## one trooper standing on a plinth, which is a character viewer — it says what
## the units look like and nothing about what the game IS. What sells a shooter
## on its own front screen is the thing the player is buying: bodies in cover,
## bolts crossing the frame, something going off in the distance.
##
## EVERY PART OF IT IS THE SHIPPING PATH, which is the whole reason this is
## affordable to build. The bodies are real `CharacterModel`s playing real clips;
## the tracers are `blaster_bolt.tscn`, the same node a fired round spawns, taking
## its colour from `GameState.bolt_color` so the sides shoot the colours they
## actually shoot; the explosions are `Blast.pop`, which is every explosion in the
## game; the muzzle flashes are real lights, built once and toggled, exactly as
## `Weapon._muzzle_light` is. Nothing here is a mock-up of the game, so nothing
## here can drift away from it.
##
## A SUBVIEWPORT and not a camera on this Control, because the UI has to draw
## over it with its own wash and a 3D scene rendered into the root viewport
## cannot be composited that way.

## The firefight runs on a loop of shots. Fast enough that several tracers are
## always in the air — a bolt crosses the frame in a few frames at the shipping
## speed, so a slow rate would read as an empty field with the occasional streak.
const SHOT_EVERY := 0.07
## ...and something goes off every few seconds, alternating ends of the line so
## the eye is not repeatedly pulled to one corner.
const BLAST_EVERY := 2.3
const FLASH_TIME := 0.09
## FOUR, NOT SEVEN. At seven the flash did not light the shooter, it ERASED him
## — a body a few metres from a 9 m light at that energy comes back as a white
## silhouette through AgX, which is the same note the turret's sensor slit and
## the gun's lit trim both carry: past unity, emission and exposure stop
## carrying colour and start carrying nothing.
const FLASH_ENERGY := 2.1
## THE MENU'S BOLTS FLY SLOWER THAN THE GAME'S, and that is a decision rather
## than an oversight. A round at the shipping 400 m/s crosses this diorama in
## three frames — correct for something deciding a firefight, and functionally
## invisible for something whose entire job is to be looked at. Slowed to a rate
## that keeps half a dozen streaks in the air at once, which is what reads as
## sustained fire. Passed as an override to the SAME bolt the game fires, so the
## colour, the material and the impact flash cannot drift from the real thing.
const BOLT_SPEED := 38.0

## WHO IS IN THE SHOT. Positions are in the diorama's own space; the whole thing
## is pushed to the RIGHT of the frame because the entry list owns the left third
## (see LIST_INDENT). `aim` is the point a body shoots AT, so the tracers cross
## rather than run parallel — parallel fire reads as a firing range.
## WHO IS IN THE SHOT. Positions are in the diorama's own space; the whole thing
## is pushed to the RIGHT of the frame because the entry list owns the left third
## (see LIST_INDENT).
##
## A BODY FACES WHAT IT SHOOTS AT, AND THAT IS DERIVED RATHER THAN STATED. The
## first pass carried a hand-written `face` angle beside each `aim` point, and
## every one of them was a half-turn out — a Node3D's forward is -Z, the near
## rank was written facing +Z, and the result was two squads standing back to
## back firing over their own shoulders while the muzzle flash went off behind
## their heads. It looked like a bug in the animation. There is no angle column
## now: `look_at` takes it from the aim point, so a body CANNOT face the wrong
## way without also shooting the wrong way, and moving somebody is one edit.
const FIGHTERS: Array[Dictionary] = [
	# The near side, in the player's own colours, fighting away from camera.
	{"team": 0, "at": Vector3(4.1, 0.0, 0.6), "clip": "idle",
		"shoots": true, "aim": Vector3(2.0, 1.1, -12.0)},
	{"team": 0, "at": Vector3(6.1, 0.0, -1.2), "clip": "crouch_idle",
		"shoots": true, "aim": Vector3(4.5, 1.0, -14.5)},
	# ...and the far side, shooting back up the frame.
	{"team": 1, "at": Vector3(2.0, 0.0, -12.0), "clip": "idle",
		"shoots": true, "aim": Vector3(4.1, 1.2, 0.6)},
	# One of them is moving rather than shooting: a line where every body is
	# stood still firing is a firing range, and the run clip is the only thing in
	# the frame that says this is going somewhere.
	{"team": 1, "at": Vector3(4.5, 0.0, -14.5), "clip": "run",
		"shoots": false, "aim": Vector3(5.2, 1.0, -2.0)},
	{"team": 1, "at": Vector3(7.8, 0.0, -16.0), "clip": "idle",
		"shoots": true, "aim": Vector3(6.1, 1.0, -1.2)},
]

var _shooters: Array[Dictionary] = []      # {muzzle, aim, team, light, left}
var _shot_in := 0.0
var _blast_in := 1.0
var _next_shooter := 0
var _world: Node3D


func _build_stage() -> void:
	var holder := SubViewportContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.stretch = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	_stage = SubViewport.new()
	_stage.handle_input_locally = false
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	holder.add_child(_stage)

	_world = Node3D.new()
	_stage.add_child(_world)

	# The key light, through `Grade.light` so its shadow settings are the ones
	# every map ships with rather than a second opinion. FROM THE CAMERA'S SIDE,
	# not from behind the subjects: the first pass lit them over the far shoulder,
	# which is a lovely rim light and leaves every surface the screen exists to
	# show in shadow.
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-34.0), deg_to_rad(-24.0), 0.0)
	# A LITTLE STRONGER THAN THE MUZZLE FLASHES. The key has to be what lights the
	# bodies; when the flash out-reads it, every shot turns the shooter white and
	# the scene flickers between two different exposures.
	sun.light_energy = 2.3
	Grade.light(sun)
	_world.add_child(sun)
	# ...and a dim shadowless fill OPPOSITE it, which is the documented way to
	# lift a shadow side in this project rather than raising ambient.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-14.0), deg_to_rad(150.0), 0.0)
	fill.light_energy = 0.45
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	_world.add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BG_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.30, 0.36, 0.46)
	e.ambient_light_energy = 0.55
	env.environment = e
	_world.add_child(env)
	# The grade brings its own fog with it, which is what gives the far side of
	# the firefight any depth at all — without it the back rank is the same value
	# as the front one and the whole scene is flat.
	Grade.apply_to(env)
	# ...and then the FOG is pinned to the background colour, over the top of the
	# grade. The floor is a plane and a plane has an EDGE: at any size, a camera
	# looking near-horizontally sees where it stops, and that edge draws a hard
	# line across the frame which reads as a rendering fault rather than as a
	# horizon. Fading the ground into exactly the colour behind it is what makes
	# the edge cease to exist rather than merely move.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = BG_COLOR
	e.fog_density = 0.0
	e.fog_depth_begin = 24.0
	e.fog_depth_end = 78.0
	e.fog_depth_curve = 1.0

	_world.add_child(_stage_floor())
	_build_cover()
	_build_fires()
	_build_fighters()

	# THE CAMERA ORBITS THE FIGHT, so the rig is centred on the action rather
	# than on a body — the drift has to look like a camera moving around a scene,
	# not like the scene turning on a turntable.
	_rig = Node3D.new()
	_rig.position = Vector3(5.0, 0.0, -7.0)
	_world.add_child(_rig)
	var cam := Camera3D.new()
	cam.fov = 46.0
	# WELL BEHIND THE NEAR RANK, not among it. The first pass put the camera 1.5 m
	# from the nearest body, which filled the bottom third of the frame with one
	# enormous out-of-focus trooper lying across the menu — a diorama has to be
	# framed from outside itself.
	cam.position = Vector3(-0.6, 2.35, 16.4)
	cam.rotation.x = deg_to_rad(-6.0)
	_rig.add_child(cam)


## The bodies. Two sides, real models, real clips — a bare `CharacterModel` sits
## in its rest pose with both arms hanging, which is not a pose the game ever
## shows and is the documented failure of every look test in this project.
func _build_fighters() -> void:
	for row: Dictionary in FIGHTERS:
		var team := int(row["team"])
		var at: Vector3 = row["at"]
		var aim: Vector3 = row["aim"]
		var body := CharacterModel.new()
		body.set_style(_style_for(team))
		body.set_team_color(GameState.team_color(team))
		_world.add_child(body)
		body.position = at
		# LEVEL, and pointed at what it is shooting at. `look_at` also pitches and
		# rolls toward a target that is not at the same height, so the two are
		# zeroed after — the same two lines every look test in this project uses
		# to face a body at the camera without tipping it over.
		body.look_at(Vector3(aim.x, at.y, aim.z), Vector3.UP)
		body.rotation.x = 0.0
		body.rotation.z = 0.0
		if body.anim_player:
			body.anim_player.play(str(row["clip"]))
		if not bool(row["shoots"]):
			continue
		# A muzzle light per shooter, built ONCE and toggled — house rule 2, and
		# this fires fourteen times a second for as long as the menu is open.
		var light := OmniLight3D.new()
		light.omni_range = 4.2
		light.light_color = GameState.bolt_color(team)
		light.light_energy = 0.0
		light.shadow_enabled = false
		_world.add_child(light)
		# At the gun: forward of the chest and off to the trigger side, taken
		# from the body's OWN basis so it follows whatever `look_at` decided.
		var muzzle: Vector3 = at + Vector3(0.0, 1.2, 0.0) \
			+ (-body.global_transform.basis.z) * 0.55 \
			+ body.global_transform.basis.x * 0.18
		light.position = muzzle
		_shooters.append({
			"muzzle": muzzle, "aim": aim, "team": team,
			"light": light, "left": 0.0,
		})


## Cover to fight around. It is what gives the ground a scale and stops the
## bodies reading as figures standing on an empty plane — the same job the
## `cover_boxes` do on a real map, and deliberately the same shapes.
func _build_cover() -> void:
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.0            # house rule 12, and it applies to a menu too
	mat.roughness = 0.85
	# LIGHT ENOUGH TO BE A SHAPE. At 0.17 these were black slabs with no face on
	# them — the documented trap of a dark map, where cover and props wash into
	# the ground and the layout stops being readable.
	mat.albedo_color = Color(0.26, 0.27, 0.31)
	for spec: Array in [
		[Vector3(3.2, 0.9, 0.9), Vector3(2.4, 0.45, -1.6)],
		[Vector3(2.4, 1.1, 0.9), Vector3(6.4, 0.55, -3.4)],
		[Vector3(1.1, 2.4, 1.1), Vector3(9.4, 1.2, -7.0)],
		[Vector3(3.6, 1.0, 1.0), Vector3(0.4, 0.5, -13.6)],
		[Vector3(1.2, 2.8, 1.2), Vector3(10.2, 1.4, -15.0)],
		[Vector3(4.4, 1.4, 1.1), Vector3(4.0, 0.7, -21.0)],
	]:
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.chamfer_box(spec[0])
		mi.position = spec[1]
		mi.material_override = mat
		_world.add_child(mi)


## Something for the bodies to stand on and cast shadows onto. Without it they
## float in a void and the shadow — which is most of what says "this is lit" —
## lands on nothing. BIG ENOUGH THAT ITS EDGE IS NEVER IN FRAME: at 14 m the far
## corner cut across the background as a hard diagonal, which reads as a
## rendering seam rather than as a floor.
func _stage_floor() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900.0, 900.0)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.0
	mat.roughness = 0.92
	mat.albedo_color = Color(0.16, 0.17, 0.20)
	mi.material_override = mat
	mi.position = Vector3(4.0, 0.0, -8.0)
	return mi


## SOMETHING IS ALREADY BURNING WHEN YOU ARRIVE. The salvo of blasts is an
## EVENT and events are not on screen most of the time — a still of this menu
## taken between two of them has no fire in it at all. A couple of standing
## wrecks give the far end of the field a permanent warm glow to fight against,
## which is what makes the scene read as the middle of a battle rather than as
## the beginning of one.
const FIRE_ENERGY := 3.4


func _build_fires() -> void:
	for at: Vector3 in [Vector3(-1.6, 0.7, -19.0), Vector3(11.0, 0.9, -13.0)]:
		var glow := OmniLight3D.new()
		glow.omni_range = 16.0
		glow.light_color = Color(1.0, 0.55, 0.22)
		glow.light_energy = FIRE_ENERGY
		glow.shadow_enabled = false
		glow.position = at
		_world.add_child(glow)
		# ...and something for the light to be COMING FROM. A glow with no source
		# in the frame reads as a lighting bug.
		var mi := MeshInstance3D.new()
		mi.mesh = Meshes.chamfer_box(Vector3(1.6, 1.1, 1.6))
		mi.position = at - Vector3(0.0, 0.25, 0.0)
		var lit := StandardMaterial3D.new()
		lit.metallic = 0.0
		lit.roughness = 0.7
		lit.albedo_color = Color(0.14, 0.09, 0.07)
		lit.emission_enabled = true
		lit.emission = Color(1.0, 0.42, 0.14)
		# Kept under unity for the reason the turret's sensor slit is on record
		# for: AgX takes emission much past 1 to white, and white fire is no fire.
		lit.emission_energy_multiplier = 0.9
		mi.material_override = lit
		_world.add_child(mi)


## Fire the next round, flash the gun that fired it, and let the flashes decay.
## ROUND ROBIN rather than all at once: a volley where every gun fires on the
## same frame reads as a light switch, where a rolling exchange reads as a fight.
func _tick_battle(delta: float) -> void:
	for s in _shooters:
		if float(s["left"]) <= 0.0:
			continue
		s["left"] = maxf(0.0, float(s["left"]) - delta)
		# Decayed rather than switched off — a hard cut reads as a dropped frame,
		# which is the note the real muzzle flash carries.
		(s["light"] as OmniLight3D).light_energy = \
			FLASH_ENERGY * (float(s["left"]) / FLASH_TIME)

	_shot_in -= delta
	if _shot_in <= 0.0 and not _shooters.is_empty():
		_shot_in += SHOT_EVERY
		var s: Dictionary = _shooters[_next_shooter % _shooters.size()]
		_next_shooter += 1
		_fire(s)

	_blast_in -= delta
	if _blast_in <= 0.0:
		_blast_in += BLAST_EVERY
		# Behind the far rank, alternating across the frame.
		var side: float = 1.0 if (_next_shooter % 2) == 0 else -1.0
		Blast.pop(_world, Vector3(4.0 + side * 5.0, 0.8, -19.0 - side * 2.0),
			5.5, 0.8)


func _fire(s: Dictionary) -> void:
	s["left"] = FLASH_TIME
	(s["light"] as OmniLight3D).light_energy = FLASH_ENERGY
	var bolt: Node3D = BOLT.instantiate()
	_world.add_child(bolt)
	# A LITTLE SCATTER, or every round from one gun retraces the same line and the
	# tracers stack into a single bright rod.
	var spread := Vector3(randf_range(-0.5, 0.5), randf_range(-0.35, 0.35),
		randf_range(-0.5, 0.5))
	bolt.launch(s["muzzle"], (s["aim"] as Vector3) + spread,
		GameState.bolt_color(int(s["team"])), BOLT_SPEED)
	# FATTER AND LONGER THAN A FIRED ROUND. A bolt is sized to be read at the
	# range you shoot at it from, over your own sights; here it is scenery seen
	# across twenty-five metres at a fifth of the screen height, and at its own
	# scale it came out as a two-pixel dash. Scaled on the ROOT, because the
	# impact flash animates the mesh's own scale and would overwrite it.
	bolt.scale = Vector3(2.4, 2.4, 3.4)


## Which body a side fields, following the menu's own faction pick — so a player
## who set up a Warhammer match last time is met by Space Marines. Falls back to
## the first class of the first Star Wars roster.
func _style_for(team: int) -> int:
	var classes := GameState.classes_for(team)
	if classes.is_empty():
		return CharacterModel.Style.CLONE
	return Loadout.faction_build(int(classes[0])).character_style()


## --- furniture -----------------------------------------------------------------

## A FRONT-SCREEN ENTRY IS NOT A SETTING, so it does not look like one: a wide
## left-aligned slab with a title and a line of explanation under it. The blurb
## is the half that matters — "ONLINE PLAY" is a guess until something tells you
## whether it means hosting, joining or matchmaking.
func _entry(title: String, blurb: String) -> Button:
	return _entry_into(_entries, title, blurb)


func _entry_into(into: Control, title: String, blurb: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(430, 70 if blurb != "" else 48)
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ""
	_paint_entry(b, false)
	into.add_child(b)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	box.offset_left = 18
	box.offset_top = 8
	b.add_child(box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	box.add_child(t)
	if blurb != "":
		var s := Label.new()
		s.text = blurb
		s.add_theme_font_size_override("font_size", 12)
		s.add_theme_color_override("font_color", FAINT)
		box.add_child(s)
	# FOCUS IS THE ONLY POINTER FOUR PADS HAVE. It is carried by a filled bar and
	# a bright left edge rather than by a border, for the reason `menu.gd` records
	# about its own primary button: an accent border on a dark box is the same
	# treatment every unfocused control already has.
	b.focus_entered.connect(func() -> void:
		_paint_entry(b, true)
		Audio.play("ui_move"))
	b.focus_exited.connect(func() -> void: _paint_entry(b, false))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	return b


func _paint_entry(b: Button, on: bool) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22) if on else PANEL
	box.border_color = ACCENT if on else PANEL_EDGE
	box.set_border_width_all(0)
	box.border_width_left = 4 if on else 2
	box.content_margin_left = 18
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)


func _seat_button(n: int) -> Button:
	var b := Button.new()
	b.text = str(n)
	b.custom_minimum_size = Vector2(84, 60)
	b.add_theme_font_size_override("font_size", 26)
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	_paint_seat(b, false)
	return b


func _paint_seat(b: Button, on: bool) -> void:
	if b == null:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = ACCENT if on else PANEL
	box.border_color = ACCENT
	box.set_border_width_all(2)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color",
		Color(0.05, 0.07, 0.10) if on else Color(0.90, 0.93, 0.98))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55)
	r.custom_minimum_size = Vector2(420, 2)
	return r


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
