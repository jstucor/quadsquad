class_name Player
extends CharacterBody3D
## First-person player: movement, per-player device input, health, the bought
## loadout, and the buy-screen/deploy flow.
## input_device -1 = keyboard + mouse; >= 0 = that joypad device. Main puts
## every player on a pad (P1..P4 = joypads 0..3), but the keyboard path is kept
## working for testing and because Controls still binds it.
## Each player's model renders on layer (2 + player_index); bind_camera()
## clears that bit from the viewport camera so you never see your own body
## while the other three players (and your shadow) still do.

signal health_changed(health: float)
signal weapon_changed(display_name: String)
signal aim_changed(aiming: bool)
## Entered the buy screen. `eliminated` is false for the very first deploy of
## the match (nobody died, so the HUD says DEPLOY, not ELIMINATED).
signal died(eliminated: bool)
signal respawned()
signal buy_changed(row: int)     # cursor moved or the build changed; redraw
signal deploy_ready()            # the minimum wait elapsed; the button is live
signal gear_changed()  # a HUD redraw ping (gadget cooldowns, etc.)
signal killed_someone(streak: int)  # a kill this life; streak resets on death
signal damaged(amount: float)       # took a hit: drives the red screen flash
## One of OUR shots landed on an enemy: drives the hit marker and its click.
signal hit_confirmed(headshot: bool, killed: bool)
signal map_toggled(open: bool)   # the map screen opened or closed
signal squad_changed(alive: int)  # squadmates mustered or lost
signal block_changed(level: float, broken: bool)  # saber guard, for the HUD

const CORPSE_SCENE := preload("res://scenes/fx/corpse.tscn")
const GRENADE_SCENE := preload("res://scenes/fx/grenade.tscn")
const BOT_SCENE := preload("res://scenes/actors/bot.tscn")
const SHIELD_SCENE := preload("res://scenes/fx/front_shield.tscn")
const TURRET_SCENE := preload("res://scenes/actors/turret.tscn")
const MORTAR_SCENE := preload("res://scenes/actors/mortar.tscn")
const CABLE_WIRE_SCENE := preload("res://scenes/fx/cable_wire.tscn")
const LIGHTNING_SCENE := preload("res://scenes/fx/lightning_arc.tscn")
const ROCKET_SCENE := preload("res://scenes/fx/rocket.tscn")
const SCAN_DART_SCENE := preload("res://scripts/scan_dart.gd")

# Gadgets. The jetpack burns a 0..1 fuel pool and refills on the ground; the
# cable yanks you toward whatever you grappled for a fixed pull; the rotary
# cannon trades your walking speed for its output.
const JET_THRUST := 24.0   # acceleration while thrusting; must beat gravity
const JET_KICK := 4.2      # instant lift when taking off, so you clear the floor
const JET_BURN := 0.5      # fuel per second of thrust
# Refill is per second and only on the floor. At 0.45 against JET_BURN a full
# tank is ~2.2s of standing for ~2s of flight, so landing to top up is a real
# choice in a firefight rather than a walk to the shops.
const JET_REFILL := 0.45
const JET_MAX_RISE := 7.0
const CABLE_COOLDOWN := 5.0     # seconds between uses, hit or miss
const CABLE_RANGE := 34.0       # a miss flies the full length, so you see the limit
const CABLE_HOOK_SPEED := 115.0 # claw travel; the reel starts when it bites
const CABLE_SPEED := 17.0
const CABLE_PULL_TIME := 1.1
const CABLE_ARRIVE := 2.2      # let go once this close to the anchor
# Arriving at the anchor throws you into a ballistic vault that peaks above it,
# so grappling the face of a crate puts you on top of the crate instead of
# leaving you standing against it.
const CABLE_VAULT_CLEAR := 1.6  # metres to peak above the anchor
const CABLE_VAULT_MIN_UP := 4.0 # a grapple at your own height still pops you up
const CABLE_VAULT_MAX_UP := 13.0
const CABLE_VAULT_PUSH := 6.0   # horizontal carry, to land past the edge
const CABLE_VAULT_TIME := 0.55  # how long the vault owns your steering
const ROTARY_SPEED_MULT := 0.55
# Saber guard. BLOCK_COST is per point of damage stopped, so the pool is worth
# roughly 1/BLOCK_COST damage: at 0.009 a full guard eats ~110, or about five
# rifle rounds, and then you are open. That is the exhaustion the class trades
# its range for — blocking buys you the walk in, it does not win the fight.
#
# The guard is CONTINUOUS: while the button is down and the pool is not spent,
# every round arriving in front is stopped OUTRIGHT. It is spent by damage and
# by nothing else — no drain for merely holding it, and no partial hits. Both of
# those made it feel intermittent, which is the opposite of what a block is for:
# a guard you cannot trust to be up is one you may as well not raise.
## The buy screen's grid. SPAWN_BOX is one past the last category — the deploy
## target, drawn as a wide box under the grid — and the column count has to
## match what Main lays the panels out in, or the selector moves one way on the
## stick and another way on the screen.
const BUY_GRID_COLUMNS := 2
## How fast the buy cursor crosses the panel, in normalised units per second at
## full stick — the panel is 1.0 wide, so ~1.9 sweeps corner to corner in about
## half a second. Fast enough to feel like a pointer, slow enough to land on a
## box.
const BUY_CURSOR_SPEED := 1.9
## A `static var` rather than a const: `Array.size()` is a method call, which
## GDScript will not accept in a constant expression. Derived rather than
## written out so it cannot drift when a box is added to the table.
static var SPAWN_BOX := Loadout.BUY_BOXES.size()
## ...and the DEPLOY POST box after it, shown only in Conquest. Picking where you
## come back in is a Conquest rule, not a buy-screen one, so it has to exist on
## BOTH deploy screens — the buy screen when you are shopping and the character
## select when you are on faction classes.
static var POST_BOX := Loadout.BUY_BOXES.size() + 1
## The CHARACTER SELECT screen's own boxes (faction classes). It is a different
## screen with a different box list, so these index the same `buy_box` field
## from a different table — the two screens are never up at the same time, and
## each input handler only ever uses its own set.
const PICK_CLASS_BOX := 0
const PICK_POST_BOX := 1
const PICK_SPAWN_BOX := 2
const PICK_BOXES := 3

const BLOCK_COST := 0.009
const BLOCK_REGEN := 0.28        # pool per second once lowered
const BLOCK_RECOVER_AT := 0.35   # a broken guard cannot be raised until here
const BLOCK_ARC := deg_to_rad(105.0)  # half-angle in front that the blade covers
# The Force adept's double jump. Slightly weaker than the standing jump, so the
# second one reads as a Force-assisted correction rather than a free ladder, and
# it still scales with the armour frame like every other jump.
const AIR_JUMP_MULT := 0.9
# The Force dash: a burst of speed on the ground or in the air. Delivered as an
# impulse rather than a held speed, so it is a committed lunge you cannot steer
# out of. It rides _kick_vel, which bleeds off at KICK_DECAY — 19 m/s therefore
# carries about 19^2 / (2 * KICK_DECAY), a little over 8 m.
const DASH_SPEED := 19.0
const DASH_COOLDOWN := 2.5
const DASH_LIFT := 1.4     # just enough to unstick you from a slope, not a hop
# You deploy on a button press, not a timer. These are only the floor before the
# button goes live: long enough at match start for everyone to spec a build, and
# short enough after a death that you're never sat waiting on a decision made.
const DEPLOY_FLOOR := 5.0
const RESPAWN_FLOOR := 2.0
const GRENADE_THROW_SPEED := 13.0
const GRENADE_LOB := 0.28  # upward share of the throw, so it arcs
# Passive regen, in place of health kits: after REGEN_DELAY seconds without
# taking a hit, heal REGEN_RATE per second back to full. The delay is what keeps
# it from healing mid-firefight — you have to break contact to recover.
const REGEN_DELAY := 5.0
const REGEN_RATE := 18.0
# Map screen. The cursor crosses the level in about this many seconds at full
# stick, so it feels the same on a small arena and on the big terrain map.
const MAP_CURSOR_CROSS_TIME := 2.2

const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.0
const CROUCH_SPEED_MULT := 0.45
const JUMP_VELOCITY := 4.5
const MOUSE_SENS := 0.0022
const STICK_LOOK_SPEED := 2.6
const STICK_DEADZONE := 0.15
# Aim assist. The cone is deliberately narrow — this helps you finish a motion
# onto someone you are already nearly pointing at, it does not hunt across the
# screen for targets. See the block above _assist_enabled.
const ASSIST_CONE := deg_to_rad(9.0)   # half-angle it will help inside
const ASSIST_RANGE := 70.0
const ASSIST_AIM_HEIGHT := 1.0         # aim at the chest, as the AI does
const ASSIST_SLOW := 0.55              # look speed dead on target
const ASSIST_PULL := 1.5               # radians/sec of nudge, dead on target
const ASSIST_ADS_MULT := 1.4           # firmer once the sights are up
const ASSIST_STICK_DEADZONE := 0.12    # below this you are not aiming, so no pull
const BUY_DEADZONE := 0.6  # stick push that counts as one buy-screen step
const AIM_FOV_LERP := 14.0  # per-second rate the camera eases toward zoom FOV
# Recoil. The camera kick always settles all the way back to where you were
# looking, so a burst climbs and then hands your aim back rather than stealing
# it — the cost of firing is the climb, not a permanent drift. Recovery is slow
# enough that a fast gun is still climbing when its next round leaves.
const RECOIL_RECOVER := 6.0   # per-second rate the camera recoil settles back
const RECOIL_YAW_SHARE := 0.55  # sideways lean, as a share of the pitch kick
# Two ways to steady a gun, both things the player chooses in the moment.
const ADS_RECOIL_MULT := 0.8
const CROUCH_RECOIL_MULT := 0.6
# Stance penalties on the SPREAD cone (Weapon.stance_spread_mult). Moving opens
# it up, a jump opens it further, and a crouch closes it — they multiply, so
# crouch-walking is tighter than standing-walking but looser than a crouched
# still shot. Crouch also drops the kick (CROUCH_RECOIL_MULT), so the crouched
# still shot is the steadiest one you can take.
const MOVE_SPREAD_MULT := 1.5
const AIR_SPREAD_MULT := 2.1
const CROUCH_SPREAD_MULT := 0.6
# The backwards shove big guns give you. It can't just be added to velocity:
# movement rewrites velocity.x/z from the stick every frame (same reason the
# cable vault has to hold its heading), so it rides alongside as its own
# decaying push, like _unstick_push.
const KICK_DECAY := 22.0  # m/s of shove bled off per second
# Crouch: lower stance = smaller hitbox, steadier, slower. Values are lerped by
# _crouch_t between standing and crouched.
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const STAND_HEAD_Y := 1.55
const CROUCH_HEAD_Y := 1.05
# Seconds to fold into (or out of) the crouch. Matches the animation blend in
# _update_anim, so the capsule, the camera and the pose all arrive together.
const CROUCH_TIME := 0.12
# Head-hit band (metres above the body origin) — anything above counts as a
# headshot; drops with the crouch so it tracks the lowered head.
const STAND_HEAD_MIN := 1.42
const CROUCH_HEAD_MIN := 0.85
# First-person viewmodels live on their own render-layer block (one bit per
# player) so each gun is seen ONLY by its owner's camera — the inverse of the
# body layers, which every camera sees except the owner's.
const VIEWMODEL_BIT := 10
const VIEWMODEL_SLOTS := 4
# Two capsules that end up inside each other are depenetrated by the solver
# straight upwards, and the pair rides that ladder out of the map forever (it
# never falls back: move_and_slide zeroes the gravity it just accumulated). So
# nudge overlapping players apart horizontally before the solver can, and treat
# anything that still leaves the map as a death.
const UNSTICK_RADIUS := 0.8   # < two capsule radii (0.35 each) + margin
const UNSTICK_SPEED := 5.0
const BOUNDS_MIN_Y := -30.0
const BOUNDS_MAX_Y := 60.0

@export var player_index := 0
@export var input_device := -1
@export var team: int = GameState.Team.REPUBLIC
var health := 100.0
var max_health := 100.0
## The build bought on the buy screen. `loadout` is what you deployed with and
## persists across deaths; `pending` is what the buy screen is editing.
var loadout := Loadout.starter()
var pending := Loadout.starter()
## The buy screen's selector. It is a free-moving CURSOR now, not a box-to-box
## step: `buy_cursor` is its position, normalised 0..1 across the panel, driven
## by the movement stick every frame. `buy_box` is whichever panel the cursor is
## OVER — resolved from the real box rects by Main, because hidden boxes reflow
## the layout and only Main knows where they actually landed. `buy_inside` is
## whether that box has been OPENED with accept; nothing about the build can
## change while it is false, which is the point (see _enter_buy_screen). SPAWN
## is the box past the last category, and the cursor starts on it.
var buy_cursor := Vector2(0.5, 1.0)
var buy_box := 0
var buy_inside := false
var buy_row := 0
## CONQUEST spawn screen: which owned command post you deploy on (index into
## GameState.owned_posts(team)) and which of your side's four fixed classes you
## deploy as. The class persists across deaths (you tend to keep playing one),
## the post is re-clamped each frame because posts change hands while you're dead.
var spawn_post := 0
var spawn_class := 0
## Kills on the CURRENT life. Reset on every deploy, so it reads as a streak
## rather than a running total.
var kills_this_life := 0
var squad: Array[Bot] = []  # the AI squadmates currently alive under this player
var gadget := Loadout.Gadget.NONE
## The second gadget slot, driven by the GADGET 2 (`grenade`) control.
var gadget2 := Loadout.Gadget.NONE
var jet_fuel := 1.0

var _anim: AnimationPlayer
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D
var _base_fov := 75.0
# Look sensitivity scales with zoom so aiming down a scope isn't twitchy.
var _look_scale := 1.0
var _prev_aim := false
var _downs := {}             # control id -> was it down last frame (joypad edges)
## Seconds since the last damage taken. Passive regen (there are no health kits)
## kicks in once this passes REGEN_DELAY, healing REGEN_RATE per second to full.
var _since_damage := 0.0
var _on_secondary := false   # which weapon slot is in hand
var _cable_left := 0.0       # seconds of grapple pull remaining
var _cable_anchor := Vector3.ZERO
var _cable_cd := 0.0         # seconds until the cable can be fired again
var _cable_cd_shown := 0     # last whole second pushed to the HUD
var _hook_left := 0.0        # claw still in flight
var _hook_hit := false       # ...and whether it will find anything
var _wire: Node3D            # the visible line, while one is out
var _vault_left := 0.0       # seconds the cable vault still owns steering
var _vault_dir := Vector3.ZERO
var _shield: Node3D          # deployed front shield, if any
var _turret: Node3D          # placed turret, if any (one at a time)
var _mortar: Mortar          # placed mortar tube, if any
## The map screen. While it is up you stand still and your movement input
## steers the strike cursor instead — reading the map is a real commitment,
## not something you do mid-firefight.
var map_open := false
var map_cursor := Vector2.ZERO  # world XZ the cursor is over
## The in-game START overlay: while it is up you stand still (like the map),
## because reading and rebinding your controls is a commitment, not a glance.
## Per player — one player opening it does not stop the other three.
var settings_open := false
## Set once per physics frame from the interact control, and cleared by the
## Pickup that acts on it, so one press collects exactly one crate.
var pickup_pressed := false
## Whatever crate is currently in reach, for the HUD prompt. Pickups claim and
## release this as the player walks in and out of them.
var pickup_in_reach: Node3D
var _rotary_out := false
var _force_cd := [0.0, 0.0]   # seconds left on each gadget slot's cooldown
## The lightning channel: seconds of stream left, which slot opened it, and the
## time until the next bite. A channel rather than a shot because the power is
## HELD — see ForcePowers.CHANNEL_TIME.
var _channel_left := 0.0
var _channel_slot := -1
var _channel_tick := 0.0
var _channel_arc: Node3D       # the bolt currently on screen, re-aimed per tick
## The Trandoshan's cloak: seconds of invisibility left. While it is up the
## model is faded and `GameState.cloaked` holds this player, which every AI
## vision check skips. Firing or the timer ending drops it.
var _cloak_left := 0.0
var _force_shown := [0, 0]    # last whole second pushed to the HUD, per slot
## Saber guard. `_block` is the exhaustion pool, 0..1; it drains while raised
## and, much faster, per point of damage it stops. At zero the guard BREAKS and
## cannot be raised again until it has recovered past BLOCK_RECOVER_AT — without
## that, a pool that empties and refills to a sliver would flicker the block on
## and off every frame under sustained fire.
var _block := 1.0
var _block_broken := false
## Mid-air jumps left this flight. Only the Force adept gets any, and the count
## is refilled on the floor rather than decremented toward a total, so a jump
## spent falling off a ledge cannot be carried into the next hop.
var _air_jumps := 0
var _dash_cd := 0.0
var _dash_shown := 0   # last whole second pushed to the HUD
var _jet_thrusting := false
var _jet_pct := 20  # last fuel level pushed to the HUD, in 5% steps
## Per-player feel, from Controls (the START overlay edits them). Cached rather
## than looked up every frame, and refreshed by refresh_settings() when the
## overlay changes them. _sens_mult scales look speed; _assist_mult scales the
## aim assist's pull and slowdown (0 turns assist off for this player alone).
var _sens_mult := 1.0
var _assist_mult := 1.0
var _look_pitch := 0.0     # head pitch from look input (recoil is added on top)
var _recoil_pitch := 0.0   # transient camera kick, settles back to 0
var _recoil_yaw := 0.0
var _kick_vel := Vector3.ZERO  # horizontal shove from the last shot, decaying
var _crouch_t := 0.0       # 0 standing .. 1 crouched
var _dead := false
var _speed_mult := 1.0     # from the armour frame: scales walk + sprint
var _jump_mult := 1.0      # from the armour frame: scales jump velocity
var _buy_latch := Vector2.ZERO  # stick/key held: one step per push, not per frame
var _accept_latch := false # A: one action per press, never per frame
var _back_latch := false   # ...and the same for B
var _deploy_wait := 0.0    # seconds until the deploy button goes live
var _deploy_armed := false # ...and whether it already has
var _deploy_latch := false # deploy must be a fresh press, not one held from before
var _corpse: Node3D        # the flop spawned on death, freed on respawn

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon
## The dual-wield gun. Always present, hidden unless DUAL WIELD is bought and
## the sidearm is in hand — a second Weapon node is far simpler than building
## one at runtime, and it keeps the viewmodel layer wiring in one place.
@onready var weapon_off: Weapon = $Head/WeaponOff
@onready var remote_cam: RemoteTransform3D = $Head/RemoteTransform3D
@onready var model: CharacterModel = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	GameState.register_combatant(self)  # spawn picking skips the markers we occupy
	_anim = model.find_child("AnimationPlayer", true, false)
	_stamp_model_layers()
	# Put this player's viewmodel on its private layer (owner-only). Told to the
	# WEAPON rather than stamped on the meshes here: there are none yet, and the
	# gun is rebuilt by _apply_loadout below and again on every swap. Stamping
	# them here left every rebuild on the shared layer, where the other three
	# players saw this one's first-person weapon hanging in front of its face.
	weapon.set_view_layer(1 << (VIEWMODEL_BIT + player_index))
	weapon_off.set_view_layer(1 << (VIEWMODEL_BIT + player_index))
	# Own copy of the capsule so crouch-resizing one player doesn't resize all.
	_collision.shape = _collision.shape.duplicate()
	weapon.shooter = self
	weapon.fired.connect(_on_weapon_fired)
	weapon_off.shooter = self
	weapon_off.fired.connect(_on_weapon_fired)
	weapon_off.visible = false
	refresh_settings()
	_apply_loadout()


## Match start: everyone picks a class before they can shoot. Main calls this
## once the viewport HUD is wired — _ready() would emit `died` into nothing.
func _exit_tree() -> void:
	GameState.unregister_combatant(self)


func begin_deploy() -> void:
	# Royale has no shop: you drop in with a sidearm and scavenge the rest, so
	# there is nothing to put on a buy screen. Deploy straight away.
	if GameState.mode == GameState.Mode.ROYALE:
		pending = Loadout.royale_start()
		loadout = pending.duplicate_loadout()
		_respawn()
		return
	_enter_buy_screen(DEPLOY_FLOOR, false)


## Re-read this player's feel settings from Controls. Called on spawn and by the
## START overlay whenever it changes the sliders, so a change takes effect the
## moment you close the overlay (or live, while it is open).
func refresh_settings() -> void:
	_sens_mult = Controls.sensitivity(input_device)
	_assist_mult = Controls.aim_assist_strength(input_device)


## Put every mesh of the (re)built body on this player's own render layer, so
## the owner's camera culls it (first person) while everyone else sees it.
func _stamp_model_layers() -> void:
	# Told to the MODEL rather than stamped on the meshes here, for the same
	# reason the viewmodel is told its layer: the body rebuilds itself on a style
	# change and on a melee swap, and fresh meshes default to the shared layer —
	# where this player's own third-person blade hangs in front of its camera.
	model.set_render_layers(1 << (1 + player_index))


func bind_camera(cam: Camera3D) -> void:
	cam.cull_mask &= ~(1 << (1 + player_index))
	# See only our own viewmodel: drop the whole viewmodel block, add ours back.
	for j in VIEWMODEL_SLOTS:
		cam.cull_mask &= ~(1 << (VIEWMODEL_BIT + j))
	cam.cull_mask |= 1 << (VIEWMODEL_BIT + player_index)
	remote_cam.remote_path = remote_cam.get_path_to(cam)
	_camera = cam
	_base_fov = cam.fov


func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if _dead:
		return  # already eliminated, waiting to respawn
	# Friendly fire is off: teammates deal no damage (self-damage still counts).
	# Tested on `team`, not on `attacker is Player`, so it also blocks a friendly
	# BOT — which used to get through. Harmless while the only AI weapon was a
	# rifle aimed at enemies, but AI artillery drops splash on an area, and that
	# area has your own side standing in it.
	if attacker != null and attacker != self and "team" in attacker \
			and attacker.team == team:
		return
	# The saber guard stops the whole hit while it has anything left to pay with,
	# and spends itself doing it. Once it BREAKS, everything lands as normal —
	# what the pool buys is a window, not a permanent shield.
	amount = _absorb_with_guard(amount, attacker)
	if amount <= 0.0:
		return
	health -= amount
	_since_damage = 0.0  # taking a hit restarts the regen delay
	health_changed.emit(health)
	damaged.emit(amount)
	# Tell whoever shot us that it landed. This is deliberately AFTER the
	# friendly-fire check and the health subtraction, so the hit marker only
	# ever confirms damage that was actually dealt.
	if attacker != null and attacker != self and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	if health <= 0.0:
		_die(attacker)


## A committed lunge along the way you are MOVING, or the way you are facing if
## you are standing still — dashing on the spot should carry you forward, not
## refuse. Works in the air too: half the value of a dash to a melee class is
## crossing the last few metres of a gap.
func _dash() -> void:
	if _dash_cd > 0.0:
		return
	var move := _move_input()
	var dir := global_transform.basis * Vector3(move.x, 0.0, move.y)
	if dir.length() < 0.05:
		dir = -global_transform.basis.z
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	# Rides the decaying shove for the same reason every other impulse does:
	# movement rewrites velocity.x/z from the stick every frame.
	_kick_vel += dir.normalized() * DASH_SPEED
	if is_on_floor():
		velocity.y = maxf(velocity.y, DASH_LIFT)
	_dash_cd = DASH_COOLDOWN
	gear_changed.emit()


## Seconds until the dash is available again, 0 when it is ready.
func dash_cooldown() -> float:
	return _dash_cd


## How many mid-air jumps this build gets. A property of the CLASS rather than
## of the saber, so a Force adept keeps it while holding a sidearm.
func air_jump_allowance() -> int:
	return 1 if loadout.kit == Loadout.Kit.FORCE else 0


## True while the lightsaber guard is actually up: blade in hand, aim held, and
## the exhaustion pool not spent. Nothing else can block — a raised guard is the
## Force adept's answer to having no gun, not a general-purpose defence.
func guard_up() -> bool:
	return not _dead and not map_open and not settings_open and weapon.is_melee() \
		and _ads_held() and not _block_broken and _block > 0.0


## The exhaustion pool, 0..1, for the HUD.
func guard_level() -> float:
	return _block


func guard_broken() -> bool:
	return _block_broken


## Refill the guard while it is down, and un-break it once there is enough back
## to be worth raising. Holding it up costs NOTHING by itself — the pool is a
## damage budget, not a stamina bar, so what ends a block is being shot at, not
## the clock. Standing with the blade up used to spend the whole pool in seven
## seconds, which meant a guard raised early was already gone when the shooting
## started.
##
## This runs whatever is in hand, deliberately. Skipping it for a non-melee
## weapon froze the pool the moment you swapped: a Force adept who broke their
## guard and drew the sidearm to cover the gap came back to a blade that was
## still spent, and stayed spent until they held it out long enough to refill.
func _update_guard(delta: float) -> void:
	var before := _block
	var was_broken := _block_broken
	if not guard_up():
		_block = minf(_block + BLOCK_REGEN * delta, 1.0)
		if _block_broken and _block >= BLOCK_RECOVER_AT:
			_block_broken = false
	# The HUD only needs telling on a visible change; this runs every frame.
	if absf(_block - before) > 0.02 or was_broken != _block_broken:
		block_changed.emit(_block, _block_broken)


## How much of a hit the guard stops: ALL of it, or none.
##
## It still only covers the ARC you are facing, so being flanked beats it, and it
## still pays BLOCK_COST of the pool per point stopped. What it no longer does is
## let the remainder through when the pool runs dry mid-hit: the shot that empties
## the guard is stopped in full and BREAKS it, and the next one is the one that
## hurts. Splitting a round between the blade and your chest is invisible from
## behind the blade — all the player sees is a block that sometimes does not
## work.
func _absorb_with_guard(amount: float, attacker: Node) -> float:
	if not guard_up() or attacker == null or not attacker is Node3D:
		return amount
	var to: Vector3 = attacker.global_position - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return amount
	var facing := -global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.01 or facing.normalized().angle_to(to.normalized()) > BLOCK_ARC:
		return amount   # came in from behind the blade
	_block = maxf(_block - amount * BLOCK_COST, 0.0)
	if _block <= 0.0:
		_block_broken = true
	# Show it on the blade. Raised HERE rather than at the weapon that fired, for
	# the same reason the hit marker is raised in take_damage: this is the one
	# place that knows the block actually happened and what it cost.
	weapon.parry()
	block_changed.emit(_block, _block_broken)
	return 0.0


## Take an outside shove — a Force push or pull. It rides _kick_vel rather than
## being added to velocity, because movement rewrites velocity.x/z from the
## stick every frame and would erase it before it rendered.
func apply_impulse(impulse: Vector3) -> void:
	_kick_vel += Vector3(impulse.x, 0.0, impulse.z)
	if impulse.y > 0.0:
		velocity.y = maxf(velocity.y, impulse.y)


## Called BY whatever we just damaged, on the same duck-typed contract as
## credit_kill: anything that takes damage reports it back to its attacker if
## the attacker cares. Bots don't implement it — they need no feedback.
func on_hit_confirmed(headshot: bool, killed: bool) -> void:
	hit_confirmed.emit(headshot, killed)


## Take a pickup's contents into the current build and re-apply it, so a gun
## found on the ground behaves exactly like one that was bought. Everything a
## pickup grants is now a LOADOUT change (a weapon, a sidearm, a gadget), so it
## is folded in and re-applied with no counted extras to carry across.
func collect(item: Pickup) -> void:
	var health_before := health
	pending = loadout.duplicate_loadout()
	_apply_loadout()
	# A pickup is not a heal: you keep the damage you were carrying.
	health = minf(health_before, max_health)
	health_changed.emit(health)
	gear_changed.emit()
	_announce_hand()


## Credited by whatever we just killed. Duck-typed like the rest of the combat
## contract: Player, Bot and Turret all call it on their killer if it exists.
func credit_kill() -> void:
	kills_this_life += 1
	killed_someone.emit(kills_this_life)


## False while eliminated (collision off, waiting to respawn). GameState uses it
## to skip corpses-in-waiting when it looks for a clear spawn marker.
func is_alive() -> bool:
	return not _dead


## True once the buy screen's minimum wait has elapsed and the deploy button
## will actually do something.
## Seconds left on the buy screen's deploy lock, 0 once the button is live.
func deploy_wait() -> float:
	return maxf(_deploy_wait, 0.0)


## Seconds until the wrist cable is usable again, 0 when it's ready.
func cable_cooldown() -> float:
	return _cable_cd


func deploy_armed() -> bool:
	return _deploy_armed


## What to call the deploy button in this player's prompt — whatever they have
## jump bound to, so the prompt follows a rebind.
func deploy_button_name() -> String:
	return Controls.label(input_device, "jump")


## The buy screen's two buttons, named for THIS player's bindings. Nothing in
## the UI may say "A" or "B": those are this pad's defaults, not a fact, and the
## moment somebody rebinds either one the prompt would be a lie.
func buy_accept_name() -> String:
	return Controls.label(input_device, "jump")


## BACK is the pad's B button, FIXED — not the `crouch` binding, and the one
## thing on this screen that cannot be rebound. Same reasoning as the controls
## screen's START/BACK: a mode you can get stuck inside needs an exit that no
## rebind can take away. It is not hypothetical — this project's own saved
## config has crouch on R3, so keying "close the box" to it would have put the
## exit somewhere nobody would ever press.
func buy_back_name() -> String:
	return "ESC" if input_device < 0 else "B"


func _buy_back_held() -> bool:
	if input_device < 0:
		return Input.is_key_pressed(KEY_ESCAPE) or Input.is_key_pressed(KEY_BACKSPACE)
	return Input.is_joy_button_pressed(input_device, JOY_BUTTON_B)


## Take on the bought build: armour stats, the gun with its upgrades fitted, and
## a fresh set of consumables. Called on every deploy, never mid-life.
func _apply_loadout() -> void:
	loadout = pending.duplicate_loadout()
	# Build the body this class wears. set_style rebuilds the model meshes, so the
	# per-player render layer has to go back on afterwards (same reason the
	# viewmodel re-stamps itself) or the owner's camera would see its own body.
	model.set_style(loadout.character_style())
	_stamp_model_layers()
	var armor := loadout.armor_stats()
	# The class multiplies the frame, rather than replacing it: a Force adept in
	# a light frame is quick and tough for both reasons, which is the point of
	# letting them wear one. Health goes through Loadout.max_health() so the buy
	# screen's HP line and what you deploy with are the same arithmetic.
	max_health = loadout.max_health()
	_speed_mult = float(armor["speed"]) * loadout.kit_speed()
	_jump_mult = armor["jump"]
	health = max_health
	_since_damage = 0.0
	kills_this_life = 0
	_on_secondary = not loadout.has_primary()
	_rotary_out = false
	weapon.set_class(loadout.deploy_class(), loadout.mods_for(_on_secondary))
	_refresh_offhand()
	gadget = loadout.gadget_id()
	gadget2 = loadout.gadget2_id()
	_force_cd = [0.0, 0.0]
	_dash_cd = 0.0
	_air_jumps = air_jump_allowance()
	_block = 1.0
	_block_broken = false
	block_changed.emit(_block, _block_broken)
	jet_fuel = 1.0
	_cable_left = 0.0
	_hook_left = 0.0
	_cable_cd = 0.0  # a fresh life gets a fresh cable
	_vault_left = 0.0
	# A fresh life is never cloaked, and the model is solid again — set_cloak(1.0)
	# also puts back the transparency the last life's cloak left on the materials.
	_cloak_left = 0.0
	GameState.set_cloaked(self, false)
	model.set_cloak(1.0)
	_clear_gadget_props()
	_muster_squad()
	gear_changed.emit()
	_announce_hand()


## Bring the squad up to the headcount you paid for. Survivors are kept and only
## the losses are replaced, so redeploying never wipes a squad that's still
## fighting, and never stacks up more than you bought.
func _muster_squad() -> void:
	squad = squad.filter(func(b: Bot) -> bool: return is_instance_valid(b) and b.is_alive())
	var want := loadout.squad
	# Bought fewer than you have (re-spec): stand the extras down.
	while squad.size() > want:
		squad.pop_back().queue_free()
	for i in want - squad.size():
		squad.append(_spawn_bot())
	squad_changed.emit(squad.size())


func _on_squadmate_lost() -> void:
	squad = squad.filter(func(b: Bot) -> bool: return is_instance_valid(b) and b.is_alive())
	squad_changed.emit(squad.size())


func _spawn_bot() -> Bot:
	var bot: Bot = BOT_SCENE.instantiate()
	get_parent().add_child(bot)  # a sibling in the level, not a child of the player
	bot.setup(self, team, loadout.squad_skill)
	# tree_exited fires when a bot is freed on death, so the HUD count follows
	# losses without the bot needing to know anything about its owner's UI.
	bot.tree_exited.connect(_on_squadmate_lost)
	# Drop them on a clear team marker, same as a respawn, so they never spawn
	# inside a body.
	var spawn := GameState.get_spawn_point(team)
	if spawn:
		bot.global_transform = GameState.clear_of_bodies(spawn.global_transform)
	else:
		bot.global_position = global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	return bot


## --- character select (faction classes) --------------------------------------
##
## Pick one of your side's four fixed classes and — in Conquest — the command
## post you come back in on, then deploy. It is the SAME mechanic as the buy
## screen and deliberately so: a free cursor over boxes, accept to open a box,
## up/down inside it, back to close, accept on SPAWN to deploy. Only the boxes
## differ, so a player who has learned one screen has learned both.
##
## That also keeps the safety property the buy screen was rebuilt for: the
## cursor opens on SPAWN, closed, so a stick still held on the frame you died
## drifts a pointer and never re-rolls the class you are about to deploy as.
func _update_pick_input(delta: float) -> void:
	var accept := _deploy_held()          # A, the same button as JUMP/DEPLOY
	var back := _buy_back_held()          # B, fixed — see buy_back_name()
	var accept_edge := accept and not _accept_latch
	var back_edge := back and not _back_latch
	_accept_latch = accept
	_back_latch = back
	_deploy_latch = accept  # kept in step: a held A must never deploy on respawn

	if buy_inside:
		apply_pick_input(_buy_axis(), accept_edge, back_edge)
		return
	var raw := _move_input()
	if raw != Vector2.ZERO:
		buy_cursor.x = clampf(buy_cursor.x + raw.x * BUY_CURSOR_SPEED * delta, 0.0, 1.0)
		buy_cursor.y = clampf(buy_cursor.y + raw.y * BUY_CURSOR_SPEED * delta, 0.0, 1.0)
	apply_pick_input(Vector2i.ZERO, accept_edge, back_edge)


## The character select's decisions, split from reading the device the same way
## apply_buy_input is: the input path polls and this decides, so a test can
## drive the screen without a pad.
func apply_pick_input(move: Vector2i, accept_edge: bool, back_edge: bool) -> void:
	if buy_inside:
		_update_pick_open(move, back_edge)
		return
	if not accept_edge:
		return
	match buy_box:
		PICK_SPAWN_BOX:
			if _deploy_armed:
				pending = Loadout.team_build(team, spawn_class)
				_respawn()
		PICK_POST_BOX:
			if _post_choice_live():
				buy_inside = true
				buy_changed.emit(buy_row)
		_:
			buy_inside = true
			buy_changed.emit(buy_row)


## Inside an open box on the character select: up/down walks it, B comes out.
func _update_pick_open(move: Vector2i, back_edge: bool) -> void:
	if back_edge:
		buy_inside = false
		buy_changed.emit(buy_row)
		return
	if move.y == 0:
		return
	if buy_box == PICK_POST_BOX:
		_step_spawn_post(move.y)
	else:
		var classes := Loadout.faction_classes(team)
		spawn_class = wrapi(spawn_class + move.y, 0, classes.size())
	buy_changed.emit(buy_row)


## Walk the owned command posts. Shared by both deploy screens, because the post
## box is on both — in Conquest you choose where you come back in whether or not
## you are also choosing what to come back as.
func _step_spawn_post(step: int) -> void:
	var posts := GameState.owned_posts(team)
	if posts.size() > 1:
		spawn_post = wrapi(spawn_post + step, 0, posts.size())


## Is there a post choice to make at all? Conquest only, and only while your
## side actually holds something — pushed off every post, you deploy at base and
## the box is dead.
func _post_choice_live() -> bool:
	return GameState.mode == GameState.Mode.CONQUEST \
		and not GameState.owned_posts(team).is_empty()


## Where a Conquest deploy actually lands: the chosen owned post, or a home
## marker as a last resort if the side has just been pushed off every post.
func _conquest_spawn_transform() -> Transform3D:
	var posts := GameState.owned_posts(team)
	if not posts.is_empty():
		var post: CommandPost = posts[clampi(spawn_post, 0, posts.size() - 1)]
		return GameState.clear_of_bodies(post.spawn_transform())
	var m := GameState.get_spawn_point(team)
	return GameState.clear_of_bodies(m.global_transform) if m else global_transform


## The name of the class currently selected on the character select, for the HUD.
func faction_class_name() -> String:
	return str(Loadout.FACTION_BUILDS[faction_class_index()]["name"])


## Which FACTION_BUILDS row this player is about to deploy as.
func faction_class_index() -> int:
	var classes := Loadout.faction_classes(team)
	return classes[clampi(spawn_class, 0, classes.size() - 1)]


## Buy-screen input while dead. TWO MODES, and which one you are in is the
## whole design:
##
##   CURSOR  the stick drives a free pointer over the boxes. Nothing changes. A
##           on a category opens it; A on SPAWN deploys, once the floor elapsed.
##   OPEN    up/down walks the rows inside that box, left/right changes them,
##           B closes it and hands control back to the cursor.
##
## Deploying is accept on the SPAWN box rather than the jump button working from
## anywhere, and modifying is accept on the box UNDER THE CURSOR — the same idea
## both times: while you are shopping, every button that does something has to be
## aimed at a target you can see. All of it rides inputs the player already has.
func _update_buy_input(delta: float) -> void:
	var accept := _deploy_held()          # A, the same button as JUMP/DEPLOY
	var back := _buy_back_held()          # B, fixed — see buy_back_name()
	var accept_edge := accept and not _accept_latch
	var back_edge := back and not _back_latch
	_accept_latch = accept
	_back_latch = back
	_deploy_latch = accept  # kept in step: a held A must never deploy on respawn

	if buy_inside:
		apply_buy_input(_buy_axis(), accept_edge, back_edge)
		return
	# Cursor state: the stick moves the pointer (analog, every frame), and the
	# box it lands on is resolved by Main. Forward on the stick is up on screen,
	# which _move_input already gives as a negative Y.
	var raw := _move_input()
	if raw != Vector2.ZERO:
		buy_cursor.x = clampf(buy_cursor.x + raw.x * BUY_CURSOR_SPEED * delta, 0.0, 1.0)
		buy_cursor.y = clampf(buy_cursor.y + raw.y * BUY_CURSOR_SPEED * delta, 0.0, 1.0)
	apply_buy_input(Vector2i.ZERO, accept_edge, back_edge)


## The screen's LOGIC, with the pad already read. Split out so a test can drive
## it directly — a test sets buy_box (the box the cursor is notionally over) and
## presses accept, which is what proves what a press DOES without needing a HUD
## to resolve a cursor position into a box.
func apply_buy_input(move: Vector2i, accept_edge: bool, back_edge: bool) -> void:
	if buy_inside:
		_update_buy_open(move, back_edge)
		return
	if not accept_edge:
		return
	if buy_box == SPAWN_BOX:
		if _deploy_armed:
			_respawn()
		return
	if buy_box == POST_BOX:
		# Conquest while shopping: you still choose which post you come back in
		# on, so the box opens and walks like any other.
		if _post_choice_live():
			buy_inside = true
			buy_changed.emit(buy_row)
		return
	# Opening a box parks the row cursor on its first real line, so the caret
	# never starts on something this kit does not have.
	var first := pending.first_row_in(buy_box)
	if first < 0:
		return
	buy_inside = true
	buy_row = first
	buy_changed.emit(buy_row)


## Inside an open box: rows above/below, values left/right, B to come back out.
func _update_buy_open(move: Vector2i, back_edge: bool) -> void:
	if back_edge:
		buy_inside = false
		buy_changed.emit(buy_row)
		return
	if buy_box == POST_BOX:
		# The post box holds no Loadout rows — it walks the command posts, and
		# nothing about the build can change from inside it.
		if move.y != 0:
			_step_spawn_post(move.y)
			buy_changed.emit(buy_row)
		return
	if move.y != 0:
		buy_row = pending.step_row_in(buy_box, buy_row, move.y)
		buy_changed.emit(buy_row)
	if move.x != 0 and pending.step(buy_row, move.x):
		# Changing class rewrites the whole build, which can take the row the
		# cursor is sitting on out of existence (a melee kit hides SIGHT/GRIP) —
		# or the whole box, if you were in one the new kit does not have.
		if not pending.box_available(buy_box):
			buy_inside = false
			buy_box = SPAWN_BOX
		else:
			buy_row = pending.step_row_in(buy_box, buy_row, 0)
			if not pending.row_available(buy_row):
				buy_row = pending.first_row_in(buy_box)
		buy_changed.emit(buy_row)


## One step per push on each axis, from the movement stick/keys plus the d-pad.
func _buy_axis() -> Vector2i:
	var raw := _move_input()
	if input_device >= 0:
		if Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_LEFT):
			raw.x = -1.0
		elif Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_RIGHT):
			raw.x = 1.0
		if Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_UP):
			raw.y = -1.0
		elif Input.is_joy_button_pressed(input_device, JOY_BUTTON_DPAD_DOWN):
			raw.y = 1.0
	# Forward is -Z, which reads as "up" on the menu.
	return Vector2i(_axis_step(raw.x, "x"), _axis_step(raw.y, "y"))


func _axis_step(value: float, axis: String) -> int:
	var latched: float = _buy_latch.x if axis == "x" else _buy_latch.y
	var step := 0
	if absf(value) >= BUY_DEADZONE:
		if latched == 0.0:
			step = signi(value)
		latched = signf(value)
	else:
		latched = 0.0
	if axis == "x":
		_buy_latch.x = latched
	else:
		_buy_latch.y = latched
	return step


func view_fov() -> float:
	return _camera.fov if _camera else _base_fov


## This player's camera, for the HUD to project world points onto its own
## viewport (the thermal read). Null until bind_camera has run.
func camera() -> Camera3D:
	return _camera


## Is the heat sight raised right now? The thermal overlay only draws while it
## is, so it reads as a scope you look through rather than a permanent tracker.
func thermal_active() -> bool:
	return not _dead and weapon.aiming and weapon.has_thermal()


## True if a world-space hit point lands in this body's head band (tracks the
## crouch so a crouched head still counts). Weapons use it for bonus damage.
func is_headshot(world_pos: Vector3) -> bool:
	var head_min := lerpf(STAND_HEAD_MIN, CROUCH_HEAD_MIN, _crouch_t)
	return world_pos.y - global_position.y >= head_min


func _die(attacker: Node = null) -> void:
	if _dead:
		return
	# Credit the frag to an enemy killer (not suicide/self or a teammate).
	if attacker is Player and attacker != self and attacker.team != team:
		GameState.add_frag(attacker.team)
		attacker.credit_kill()
	GameState.report_death(team)  # CONQUEST: a death is a reinforcement spent
	_spawn_corpse(attacker)
	_enter_buy_screen(RESPAWN_FLOOR, true)
	GameState.check_last_standing()


## Go to the buy screen. It stays up until the player presses deploy — `floor`
## is only how long the button is greyed out first. Shared by the match-start
## deploy and every death, so a build is always bought the same way.
func _enter_buy_screen(floor_secs: float, eliminated: bool) -> void:
	_dead = true
	velocity = Vector3.ZERO
	weapon.aiming = false
	# Dying while cloaked must not leave a ghost in GameState.cloaked that no AI
	# can ever see — the body is about to be hidden anyway.
	if _cloak_left > 0.0:
		_end_cloak()
	if map_open:
		map_open = false  # the buy screen owns the view now
		map_toggled.emit(false)
	if _camera:
		_camera.fov = _base_fov
	# Hide the live body + turn off its collision; the camera stays put as a
	# death cam while the flop tumbles and you spend.
	model.visible = false
	weapon.visible = false  # no gun in hand while you're still buying one
	_clear_gadget_props()
	_collision.disabled = true
	# The screen opens on the build you were using, so an unchanged respawn is
	# one button press.
	pending = loadout.duplicate_loadout()
	# The selector opens ON THE SPAWN BOX, closed, every time. That is the whole
	# safety property of this screen: the frame you die you are usually still
	# holding a direction, and the old flat cursor started on the CLASS row where
	# a nudge re-rolled the entire build. From here a stray shove moves a
	# highlight and nothing else, and the common case — respawn with what you
	# had — is still one press of the same button it always was.
	# Both deploy screens open on their own SPAWN box (they are separate box
	# lists indexing the same field — see PICK_SPAWN_BOX), so whichever one this
	# match uses, the ordinary respawn is one press of accept.
	buy_box = PICK_SPAWN_BOX if GameState.faction_classes() else SPAWN_BOX
	buy_inside = false
	# The cursor opens ON the spawn box, so a straight respawn is still: wait out
	# the floor, press accept. Moving the cursor never touches the build, so a
	# stick still held on the death frame just drifts a pointer — the accident
	# the box rework was for cannot happen at all now.
	buy_cursor = Vector2(0.5, 1.0)
	buy_row = pending.first_row_in(0)
	# Forget any held trigger/button: the new life starts on a fresh press.
	_buy_latch = Vector2.ZERO
	_accept_latch = true   # A must be released and pressed again
	_back_latch = true
	_deploy_latch = true  # released-then-pressed, so a held jump can't deploy
	_downs.clear()
	_deploy_wait = floor_secs
	_deploy_armed = false
	# CONQUEST offers a post to come back in on, on whichever screen is up. Open
	# on the first one your side holds; the class carries over from the last life.
	spawn_post = 0
	died.emit(eliminated)
	buy_changed.emit(buy_row)


func _spawn_corpse(attacker: Node) -> void:
	_corpse = CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(_corpse)
	var push := Vector3.ZERO  # shove away from the shooter
	if attacker is Node3D and attacker != self:
		push = global_position - (attacker as Node3D).global_position
	var xform := Transform3D(Basis(Vector3.UP, rotation.y), global_position)
	# The corpse wears the body you deployed as, not a generic trooper.
	_corpse.launch(xform, GameState.team_colors[team], push,
		loadout.character_style())


func _process_dead(delta: float) -> void:
	# Royale has no respawns: once you are down you stay down, and the buy
	# screen never arms. Main's last-side-standing check ends the match.
	if GameState.mode == GameState.Mode.ROYALE and GameState.match_live:
		return
	if not _deploy_armed:
		var whole_before := ceili(_deploy_wait)
		_deploy_wait -= delta
		if _deploy_wait <= 0.0:
			_deploy_armed = true
			deploy_ready.emit()
		elif ceili(_deploy_wait) != whole_before:
			buy_changed.emit(buy_row)  # so the "ready in N" line actually counts
	# Which deploy screen is up follows the CLASS SETTING, not the mode: faction
	# classes are pickable in deathmatch and the buy screen works in Conquest.
	if GameState.faction_classes():
		_update_pick_input(delta)
	else:
		_update_buy_input(delta)


func _respawn() -> void:
	# Place the body BEFORE clearing _dead: while we still read as dead, the
	# spawn picker skips us, so we don't treat the body we just left as an
	# obstacle and shove ourselves off our own marker.
	if GameState.mode == GameState.Mode.CONQUEST:
		global_transform = _conquest_spawn_transform()
	else:
		var spawn := GameState.get_spawn_point(team)
		if spawn:
			global_transform = GameState.clear_of_bodies(spawn.global_transform)
	_dead = false
	model.visible = true
	weapon.visible = true
	_collision.disabled = false
	# Whatever we were doing when we died (falling, jumping) must not carry over
	# into the new body at the spawn point.
	velocity = Vector3.ZERO
	_recoil_pitch = 0.0
	_recoil_yaw = 0.0
	# The legs start under the body they respawned in. Left at whatever heading
	# the last life ended on, the first frame would be a full-lead twist and the
	# body would deploy visibly wrung out.
	_feet_yaw = rotation.y
	model.rotation.y = 0.0
	model.set_twist(0.0)
	_kick_vel = Vector3.ZERO
	_apply_loadout()
	health_changed.emit(health)
	if is_instance_valid(_corpse):
		_corpse.queue_free()
	_corpse = null
	respawned.emit()


func _unhandled_input(event: InputEvent) -> void:
	if input_device >= 0:
		return
	if settings_open:
		return  # the START overlay owns the keyboard and mouse while it is up
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(Vector2(-event.relative.x, -event.relative.y) * MOUSE_SENS * _sens_mult)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _apply_look(delta_look: Vector2) -> void:
	rotate_y(delta_look.x * _look_scale)
	_look_pitch = clampf(_look_pitch + delta_look.y * _look_scale,
		-PI / 2 + 0.05, PI / 2 - 0.05)
	_refresh_head()


## The camera pitch is look input plus the transient recoil kick; recoil yaw
## rides on the head so it throws off aim without turning the whole body.
func _refresh_head() -> void:
	head.rotation.x = _look_pitch + _recoil_pitch
	head.rotation.y = _recoil_yaw


func _physics_process(delta: float) -> void:
	if _dead:
		_process_dead(delta)
		return
	# Deployed, but the match hasn't been called on yet: stand still and hold
	# fire until the start countdown finishes.
	if not GameState.match_live:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		_update_anim(Vector2.ZERO, false)
		return
	# The START overlay holds you still while it is open, like the map. It owns its
	# own input (the overlay Control polls this player's device); here we only stop
	# moving and firing. Gravity still applies so opening it midair doesn't hang you.
	if settings_open:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= _gravity * delta
		move_and_slide()
		_update_anim(Vector2.ZERO, false)
		return
	if _map_pressed():
		_toggle_map()
	if map_open:
		_process_map(delta)
		return
	pickup_pressed = _interact_pressed()
	_update_gear()
	_update_regen(delta)
	_update_aim(delta)
	_update_guard(delta)
	_update_crouch(delta)

	# Settle the camera recoil back toward zero, and bleed off the shot's shove.
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_kick_vel = _kick_vel.move_toward(Vector3.ZERO, KICK_DECAY * delta)
	_refresh_head()

	if input_device >= 0:
		var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		var mark := _assist_target()
		# Slowdown first, so the stick eases off as the crosshair crosses a body.
		_apply_look(-look * STICK_LOOK_SPEED * _sens_mult * _assist_slowdown(mark) * delta)
		_assist_pull(mark, look, delta)

	var move := _move_input()
	var crouching := _crouch_held()
	var sprinting := _sprint_held() and not crouching
	_update_stance_spread(move, crouching)
	# The SPRINT CARRY, in first person. Cancelled by the trigger: the weapon has
	# to come back up the instant you decide to shoot, or the first round of every
	# engagement leaves a gun that is visibly stowed. Sprinting already denies the
	# sights, so this only ever changes what the pose LOOKS like, never what the
	# shot does.
	var stow := _is_running() and not _fire_held()
	weapon.set_sprinting(stow)
	weapon_off.set_sprinting(stow)
	_update_torso_twist(move, delta)
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * _speed_mult
	if _rotary_out:
		speed *= ROTARY_SPEED_MULT  # the cannon is heavy; you walk with it out
	if crouching:
		speed *= CROUCH_SPEED_MULT
	var dir := global_transform.basis * Vector3(move.x, 0, move.y)

	if not is_on_floor():
		velocity.y -= _gravity * delta
		# The Force adept can push off nothing. Setting velocity outright rather
		# than adding to it means a double jump saves you just as well on the way
		# down as at the top of the arc, which is the whole point of having one.
		if _air_jumps > 0 and _jump_pressed():
			_air_jumps -= 1
			velocity.y = JUMP_VELOCITY * _jump_mult * AIR_JUMP_MULT
	elif _jump_pressed():
		velocity.y = JUMP_VELOCITY * _jump_mult
	if is_on_floor():
		_air_jumps = air_jump_allowance()
	var unstick := _unstick_push()
	velocity.x = dir.x * speed + unstick.x + _kick_vel.x
	velocity.z = dir.z * speed + unstick.z + _kick_vel.z
	_apply_gadget_motion(delta)
	move_and_slide()
	if global_position.y > BOUNDS_MAX_Y or global_position.y < BOUNDS_MIN_Y:
		_die()  # launched or fell out of the map: respawn through the normal flow
		return

	weapon.update_fire(_fire_held(), _fire_pressed())
	# Dual wield spends the aim control on the left gun, which is the whole
	# trade: two guns, no sights. Holding both triggers fires both.
	if dual_active():
		weapon_off.update_fire(_ads_held(), _edge("ads"))
	_update_anim(move, sprinting)


## --- map screen -------------------------------------------------------------

## Open or close the map. It opens on your own position, so the first thing the
## cursor tells you is where you are.
func _toggle_map() -> void:
	map_open = not map_open
	if map_open:
		map_cursor = Vector2(global_position.x, global_position.z)
		weapon.aiming = false
		if _camera:
			_camera.fov = _base_fov
	map_toggled.emit(map_open)


## While the map is up: stand still, steer the cursor, and let the fire button
## call a strike instead of shooting. Gravity still applies, so opening the map
## in mid-air does not leave you hanging there.
func _process_map(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()
	_update_anim(Vector2.ZERO, false)

	var move := _move_input()
	var extents := GameState.map_extents
	# Cursor speed is derived from the map's own size, so crossing a small
	# arena and crossing the terrain map take about the same time.
	var speed := extents.length() * 2.0 / MAP_CURSOR_CROSS_TIME
	map_cursor += move * speed * delta
	var c := GameState.map_center
	map_cursor.x = clampf(map_cursor.x, c.x - extents.x, c.x + extents.x)
	map_cursor.y = clampf(map_cursor.y, c.z - extents.y, c.z + extents.y)

	if _fire_pressed():
		_call_mortar_strike()


## The placed mortar, or null. The map screen draws it.
func mortar() -> Mortar:
	return _mortar if is_instance_valid(_mortar) else null


func mortar_ready() -> bool:
	var m := mortar()
	return m != null and m.ready_to_fire()


## The line along the top of the map screen: what the fire button will do, and
## what the tube is doing right now.
func map_status() -> String:
	var m := mortar()
	if m == null:
		if has_gadget(Loadout.Gadget.MORTAR):
			return "MORTAR NOT PLACED  —  %s to set the tube down" % \
				Controls.label(input_device, "gadget")
		return "MAP"
	var press: String = Controls.label(input_device, "fire")
	if not m.is_aimed():
		return "MORTAR READY  —  %s to mark the barrage" % press
	if m.is_firing():
		return "MORTAR FIRING  %ds  —  %s to re-aim" % [ceili(m.phase_left()), press]
	return "MORTAR RELOADING  %ds  —  %s to re-aim" % [ceili(m.phase_left()), press]


func _call_mortar_strike() -> void:
	var m := mortar()
	if m == null or not m.ready_to_fire():
		return
	m.fire_at(Vector3(map_cursor.x, 0.0, map_cursor.y))


## --- aim assist --------------------------------------------------------------
##
## Two effects, both of which only ever change where your VIEW is pointing:
## the stick slows down as the crosshair crosses a body, and the view is nudged
## toward that body while you are actively moving the stick. Nothing here bends
## a bullet or widens a hitbox — a shot still goes exactly where the barrel is
## pointing, so a miss is always a real miss.
##
## The pull is gated on stick input on purpose. Assist that keeps working while
## you hold still is an aimbot; assist that only helps while YOU are moving the
## stick is helping you finish a motion you started, which is what a thumbstick
## actually needs against a mouse.

## Is this player assisted at all? Keyboard players are excluded under the PADS
## setting because the mouse is the thing pads are being brought level with.
func _assist_enabled() -> bool:
	match GameState.aim_assist:
		GameState.AimAssist.EVERYONE:
			return true
		GameState.AimAssist.PADS:
			return input_device >= 0
	return false


## The enemy the assist should help you onto: whichever living enemy sits
## closest to the crosshair inside ASSIST_CONE, in range, and actually visible.
## Line of sight matters — being dragged toward someone through a wall would be
## worse than no assist at all.
func _assist_target() -> Node3D:
	if not _assist_enabled():
		return null
	var eye := head.global_position
	var forward := -head.global_transform.basis.z
	var best: Node3D = null
	var best_angle := ASSIST_CONE
	for c in GameState.combatants:
		if c == self or c.team == team or not c.is_alive():
			continue
		var to: Vector3 = c.global_position + Vector3.UP * ASSIST_AIM_HEIGHT - eye
		var gap := to.length()
		if gap > ASSIST_RANGE or gap < 0.01:
			continue
		var angle := forward.angle_to(to / gap)
		if angle >= best_angle:
			continue
		if not _assist_can_see(eye, c):
			continue
		best_angle = angle
		best = c
	return best


func _assist_can_see(eye: Vector3, other: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		eye, other.global_position + Vector3.UP * ASSIST_AIM_HEIGHT)
	query.exclude = hitscan_exclusions()
	query.collision_mask = 0b11  # world + bodies
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == other


## 0..1, how centred a target is: 1 right on the crosshair, 0 at the cone edge.
func _assist_closeness(target: Node3D) -> float:
	if target == null:
		return 0.0
	var to: Vector3 = target.global_position + Vector3.UP * ASSIST_AIM_HEIGHT \
		- head.global_position
	var angle := (-head.global_transform.basis.z).angle_to(to.normalized())
	return 1.0 - clampf(angle / ASSIST_CONE, 0.0, 1.0)


## Look-speed multiplier. Sweeping across someone drags, which is what stops the
## crosshair skating past a body at full stick speed.
func _assist_slowdown(target: Node3D) -> float:
	# Per-player strength scales the drag; at strength 0 there is none (mult
	# clamps the interpolation weight back to 0, i.e. full stick speed).
	return lerpf(1.0, ASSIST_SLOW, clampf(_assist_closeness(target) * _assist_mult, 0.0, 1.0))


## Nudge the view toward the target, in proportion to how centred it already is
## and only while the stick is actually being moved. Applied straight to the
## body yaw and head pitch rather than through _apply_look, so zooming does not
## quietly scale the assist down at exactly the moment you want it most.
func _assist_pull(target: Node3D, stick: Vector2, delta: float) -> void:
	if target == null or stick.length() < ASSIST_STICK_DEADZONE:
		return
	var eye := head.global_position
	var to: Vector3 = target.global_position + Vector3.UP * ASSIST_AIM_HEIGHT - eye
	var step := ASSIST_PULL * _assist_closeness(target) * delta * _assist_mult
	if weapon.aiming:
		step *= ASSIST_ADS_MULT
	var want_yaw := atan2(-to.x, -to.z)
	rotation.y += clampf(wrapf(want_yaw - rotation.y, -PI, PI), -step, step)
	var flat := Vector2(to.x, to.z).length()
	var want_pitch := atan2(to.y, maxf(flat, 0.01))
	_look_pitch = clampf(_look_pitch + clampf(want_pitch - _look_pitch, -step, step),
		-PI / 2 + 0.05, PI / 2 - 0.05)
	_refresh_head()


## Horizontal shove away from any living player we're standing inside, so the
## overlap resolves sideways instead of ejecting both of us upwards. Scales with
## how deep the overlap is; zero in the normal case of nobody nearby.
func _unstick_push() -> Vector3:
	var push := Vector3.ZERO
	for p in GameState.combatants:
		if p == self or not p.is_alive():
			continue
		var away := global_position - p.global_position
		away.y = 0.0
		var gap := away.length()
		if gap >= UNSTICK_RADIUS:
			continue
		if gap < 0.01:  # exactly stacked: any direction beats staying put
			away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
			gap = 0.01
		push += away.normalized() * (1.0 - gap / UNSTICK_RADIUS) * UNSTICK_SPEED
	return push


## Ease the stance toward standing/crouched: lowers the camera and shrinks the
## capsule. The MODEL's crouch is a posed animation (CharacterModel's
## crouch_idle / crouch_walk, picked in _update_anim), not a scale — squashing
## the body just made a shorter person, not someone hunkering down.
func _update_crouch(delta: float) -> void:
	var target := 1.0 if _crouch_held() else 0.0
	_crouch_t = move_toward(_crouch_t, target, delta / CROUCH_TIME)
	head.position.y = lerpf(STAND_HEAD_Y, CROUCH_HEAD_Y, _crouch_t)
	var cap := _collision.shape as CapsuleShape3D
	cap.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t)
	_collision.position.y = cap.height * 0.5


## A shot went off: throw the camera up and lean it sideways, and shove the body
## backwards if the gun is heavy enough to have a kick_back. The stance you were
## in when you pulled the trigger decides how much of that you actually eat.
func _on_weapon_fired(cam_recoil: float, kick_back: float) -> void:
	# A shot drops the cloak: a hunter that stays invisible while firing is not
	# a stealth tool, it is a wallhack. The wrist rocket routes through here too,
	# which is correct — anything that reveals your position ends the cloak.
	if _cloak_left > 0.0:
		_end_cloak()
	var steady := 1.0
	if weapon.aiming:
		steady *= ADS_RECOIL_MULT
	steady *= lerpf(1.0, CROUCH_RECOIL_MULT, _crouch_t)
	_recoil_pitch += cam_recoil * steady
	_recoil_yaw += randf_range(-RECOIL_YAW_SHARE, RECOIL_YAW_SHARE) * cam_recoil * steady
	if kick_back > 0.0:
		# Straight back from where the gun is pointed, flattened: a shot fired at
		# the floor should stagger you, not launch you.
		var back := head.global_transform.basis.z
		back.y = 0.0
		if back.length() > 0.01:
			_kick_vel += back.normalized() * kick_back * steady


## Hold-to-aim: eases the camera FOV toward the weapon's zoom, tells the weapon
## to tighten its spread cone, and scales look sensitivity down with the zoom.
func _update_aim(delta: float) -> void:
	# Two builds give up the sights entirely. Dual wield spends the aim control
	# on the off-hand trigger, and a raised shield fills the hand you would brace
	# with — that's the cost of carrying cover with you. Both are checked every
	# frame, so throwing the shield up mid-aim drops you straight back to the hip
	# rather than leaving the sights stuck on the glass.
	# A blade has no sights either, and its aim control is spent on the guard.
	# You also cannot aim while RUNNING: a braced sight picture and a sprint are
	# mutually exclusive, so the sights drop the moment you break into a run and
	# come back up when you slow. Stand still (even holding sprint) and you may
	# aim — it is MOVING at sprint that denies it.
	var aiming := _ads_held() and not dual_active() and not shield_up() \
		and not weapon.is_melee() and not _is_running()
	weapon.aiming = aiming
	if aiming != _prev_aim:
		_prev_aim = aiming
		aim_changed.emit(aiming)
	if _camera:
		var want := weapon.zoom_fov() if aiming else _base_fov
		_camera.fov = lerpf(_camera.fov, want, clampf(delta * AIM_FOV_LERP, 0.0, 1.0))
		_look_scale = _camera.fov / _base_fov


## Consumables bought on the buy screen: a thrown grenade and a self-heal. Both
## are edge-triggered and simply do nothing when you have none left.
## The swap control moves between the primary you bought and your sidearm. With
## no primary there is nothing to swap to, and the rotary cannon overrides both
## while out.
func _swap_weapon() -> void:
	if not loadout.has_primary() or _rotary_out:
		return
	_on_secondary = not _on_secondary
	weapon.set_class(loadout.secondary_class() if _on_secondary
		else loadout.weapon_class() as Weapon.Class, loadout.mods_for(_on_secondary))
	_refresh_offhand()
	_announce_hand()


## True while a second sidearm is actually in the off hand: you bought DUAL
## WIELD, you have the sidearm out, and the rotary isn't overriding everything.
func dual_active() -> bool:
	return loadout.dual_wield() and _on_secondary and not _rotary_out


## Raise or stow the off-hand gun to match the current state. Called anywhere
## the hands can change: deploy, swap, and the rotary toggle.
func _refresh_offhand() -> void:
	var on := dual_active()
	weapon_off.visible = on
	if on:
		weapon_off.set_class(loadout.secondary_class(), loadout.secondary_mods())
	else:
		# A stowed gun must not keep firing, and its heat should not carry over
		# into the next time you draw it.
		weapon_off.update_fire(false, false)
		weapon_off.aiming = false


func _hand_name() -> String:
	return "DUAL %s" % weapon.display_name() if dual_active() else weapon.display_name()


## Everything that changes what is IN OUR HANDS goes through here: the HUD name
## and the third-person model both have to follow a swap, and they were drifting
## apart because only the HUD was being told. The model is what other players
## read, so a blade stowed on the wrong body is a lie about who can block.
func _announce_hand() -> void:
	weapon_changed.emit(_hand_name())
	model.set_melee(weapon.is_melee(), weapon.is_staff(), weapon.melee_look())


## The gadget button. Toggles (shield, rotary) and one-shots (cable, turret) act
## on the press; the jetpack burns while held, in _apply_gadget_motion.
func _use_gadget(slot: int) -> void:
	# The ACTION, not the id: a bubble shield, an iron halo and a kustom force
	# field are three catalogue rows and one mechanism, so this switch stays the
	# list of things a gadget can DO rather than a list of every gadget's name.
	var id := Loadout.gadget_action(gadget_in(slot))
	# The force powers are the only gadgets on a cooldown of their own; the rest
	# are toggles, placements, or (the cable) time themselves.
	var cd: float = Loadout.cooldown_of(gadget_in(slot))
	if cd > 0.0 and _force_cd[slot] > 0.0:
		return
	match id:
		Loadout.Gadget.GRENADE_FRAG, Loadout.Gadget.GRENADE_STICKY, \
		Loadout.Gadget.GRENADE_SMOKE:
			# Grenades are gadgets now: throw the type this one maps to, then a
			# cooldown before the next — the recharge IS the ammo.
			_throw_grenade(Loadout.GRENADE_GADGETS[id])
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.CABLE:
			_fire_cable()
		Loadout.Gadget.SHIELD:
			_toggle_shield()
		Loadout.Gadget.ROTARY:
			_toggle_rotary()
		Loadout.Gadget.TURRET:
			_place_turret()
		Loadout.Gadget.MORTAR:
			_place_mortar()
		Loadout.Gadget.FORCE_PUSH:
			ForcePowers.push(self, team)
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.FORCE_PULL:
			# A pull that caught nobody costs a fraction of the cooldown, not the
			# whole thing: the power needs a target and missing should not take
			# the class out of the fight for seven seconds.
			var caught := ForcePowers.pull(self, team)
			_start_gadget_cd(slot, cd if caught != null else cd * 0.3)
		Loadout.Gadget.FORCE_LIGHTNING:
			# Opens the CHANNEL; the stream itself is poured in
			# _update_lightning_channel while the button stays down. The cooldown
			# is not charged here — it starts when the channel ENDS, so a tap that
			# found nobody costs almost nothing and a full two seconds of holding
			# costs the lot.
			_channel_left = ForcePowers.CHANNEL_TIME
			_channel_slot = slot
			_channel_tick = 0.0
		Loadout.Gadget.WRIST_ROCKET:
			_fire_wrist_rocket()
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.CLOAK:
			_begin_cloak()
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.SCAN_DART:
			_fire_scan_dart()
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.DASH:
			# The same lunge the Force adept has, offered here as a gadget. It runs
			# on its OWN cooldown timer (_dash_cd) already, so the gadget cooldown
			# is set to match rather than double-gating it.
			_dash()
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.FORCE_LEAP:
			var launch := ForcePowers.leap_velocity(self)
			velocity.y = launch.y
			# Horizontal carry rides _kick_vel for the same reason a gun's shove
			# does: movement rewrites velocity.x/z from the stick every frame.
			_kick_vel += Vector3(launch.x, 0.0, launch.z)
			_start_gadget_cd(slot, cd)


## Which gadget is on a slot. Slot 0 is the gadget control, slot 1 the grenade
## control.
func gadget_in(slot: int) -> int:
	return gadget if slot == 0 else gadget2


## True if either slot carries this gadget — the jetpack and the cable have to
## work from whichever hand the Mandalorian bought them into.
##
## Compared on the ACTION, so a caller asks "do I have a jetpack" and gets the
## right answer whether the slot holds a jetpack, a jump pack or a rokkit pack.
func has_gadget(id: int) -> bool:
	return Loadout.gadget_action(gadget) == id or Loadout.gadget_action(gadget2) == id


## Which slot holds it, or -1. Used to pick which BUTTON drives it.
func slot_of(id: int) -> int:
	if Loadout.gadget_action(gadget) == id:
		return 0
	return 1 if Loadout.gadget_action(gadget2) == id else -1


## Is the button for this slot down right now? Slot 0 is the GADGET 1 control,
## slot 1 the GADGET 2 control — both ordinary rebindable bindings now.
func _slot_held(slot: int) -> bool:
	return _gadget_held() if slot == 0 else _slot1_held()


## The second gadget slot's control (the `grenade` binding: G on the keyboard,
## LB on a pad by default). An ordinary rebindable control like slot 0 now — the
## old fixed LB+RB chord is gone, so each slot has its own independent binding.
func _slot1_held() -> bool:
	return Controls.held(input_device, "grenade")


## The rising edge of the slot-1 control. Uses the same per-device _edge helper
## as the other pad controls now that it is a normal binding.
func _slot1_pressed() -> bool:
	return _edge("grenade")


func _start_gadget_cd(slot: int, seconds: float) -> void:
	_force_cd[slot] = seconds
	gear_changed.emit()


## Seconds until the gadget on `slot` can be used again, 0 when it is ready.
func gadget_cooldown(slot: int) -> float:
	return _force_cd[slot]


## Velocity the gadget imposes, applied after normal movement so it wins: the
## jetpack overrides gravity while thrusting, the cable overrides steering while
## reeling you in.
func _apply_gadget_motion(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd = maxf(_dash_cd - delta, 0.0)
		var dleft := ceili(_dash_cd)
		if dleft != _dash_shown:
			_dash_shown = dleft
			gear_changed.emit()
	_update_lightning_channel(delta)
	_update_cloak(delta)
	# Tick the force powers' cooldowns, whichever slot they sit in.
	for slot in 2:
		if _force_cd[slot] <= 0.0:
			continue
		_force_cd[slot] = maxf(_force_cd[slot] - delta, 0.0)
		var left := ceili(_force_cd[slot])
		if left != _force_shown[slot]:
			_force_shown[slot] = left
			gear_changed.emit()
	# Asked of BOTH slots, not of `gadget`: a Mandalorian can buy the jetpack
	# into either hand, and keying this off slot 0 alone left the pack dead for
	# anyone who bought it second.
	var jet_slot := slot_of(Loadout.Gadget.JETPACK)
	if jet_slot >= 0:
		var thrusting := _slot_held(jet_slot) and jet_fuel > 0.0
		if thrusting:
			jet_fuel = maxf(jet_fuel - JET_BURN * delta, 0.0)
			# Taking off needs a kick: on the floor move_and_slide keeps zeroing
			# the vertical velocity, so pure acceleration never gets you airborne.
			if not _jet_thrusting and is_on_floor():
				velocity.y = JET_KICK
			velocity.y = minf(velocity.y + JET_THRUST * delta, JET_MAX_RISE)
		elif is_on_floor():
			jet_fuel = minf(jet_fuel + JET_REFILL * delta, 1.0)
		# Push the level to the HUD on BOTH paths. Refilling used to be silent,
		# so the gauge sat wherever it was when you landed and only jumped back
		# up on the next thrust — the pack recharged, but nothing on screen said
		# so, which reads exactly like a pack that does not recharge at all.
		_show_jet_fuel()
		_jet_thrusting = thrusting
	if _cable_cd > 0.0:
		_cable_cd = maxf(_cable_cd - delta, 0.0)
		# Refresh the readout on whole seconds only, not every frame.
		var secs := ceili(_cable_cd)
		if secs != _cable_cd_shown:
			_cable_cd_shown = secs
			gear_changed.emit()
	# The claw is still in flight: the reel only starts when it bites.
	if _hook_left > 0.0:
		_hook_left -= delta
		if _hook_left <= 0.0:
			if _hook_hit:
				_cable_left = CABLE_PULL_TIME
			elif is_instance_valid(_wire):
				_wire.release()  # grabbed nothing: reel the empty line back in
	if _cable_left > 0.0:
		_cable_left -= delta
		var to_anchor := _cable_anchor - global_position
		if to_anchor.length() <= CABLE_ARRIVE or _cable_left <= 0.0:
			_cable_left = 0.0
			if is_instance_valid(_wire):
				_wire.release()
			_begin_vault()
		else:
			velocity = to_anchor.normalized() * CABLE_SPEED
	elif _vault_left > 0.0:
		# Hold the launch heading for a moment: normal movement rewrites x/z from
		# the stick every frame, which would kill the arc instantly. Gravity is
		# left alone, so this stays a real ballistic hop.
		_vault_left -= delta
		velocity.x = _vault_dir.x
		velocity.z = _vault_dir.z
		if velocity.y <= 0.0 and is_on_floor():
			_vault_left = 0.0


## Tell the HUD the fuel level, on a visible change only: this runs every frame
## you are flying OR standing on the ground with a pack, and gear_changed
## redraws the whole readout.
func _show_jet_fuel() -> void:
	var step_pct := roundi(jet_fuel * 20.0)
	if step_pct != _jet_pct:
		_jet_pct = step_pct
		gear_changed.emit()


## Launch up and over whatever we just reeled ourselves to. The rise is solved
## from the anchor height, so a low crate gives a small hop and a tall ledge a
## big one, and the horizontal push carries you past the edge onto the top.
func _begin_vault() -> void:
	var rise := _cable_anchor.y + CABLE_VAULT_CLEAR - global_position.y
	var up := sqrt(2.0 * _gravity * maxf(rise, 0.0)) if rise > 0.0 else 0.0
	velocity.y = clampf(maxf(up, CABLE_VAULT_MIN_UP), 0.0, CABLE_VAULT_MAX_UP)
	var flat := _cable_anchor - global_position
	flat.y = 0.0
	# Straight down the line we were pulled along; if we're already on top of the
	# anchor, carry on the way we're facing instead.
	var heading := flat.normalized() if flat.length() > 0.05 \
		else -global_transform.basis.z
	_vault_dir = heading * CABLE_VAULT_PUSH
	_vault_left = CABLE_VAULT_TIME


## Shoot the claw. A miss still fires the wire out to full range and reels it
## back with nothing on the end, so the cable's reach is something you can see
## rather than a number in the shop.
func _fire_cable() -> void:
	if _cable_cd > 0.0:
		return  # still winding in
	if _hook_left > 0.0 or _cable_left > 0.0 or is_instance_valid(_wire):
		return  # one line out at a time
	var from := head.global_position
	var to := from - head.global_transform.basis.z * CABLE_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = hitscan_exclusions()
	query.collision_mask = 1  # world geometry only: you can't grapple a person
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	_hook_hit = not hit.is_empty()
	var landed: Vector3 = hit["position"] if _hook_hit else to
	_cable_anchor = landed
	_hook_left = maxf(weapon.global_position.distance_to(landed) / CABLE_HOOK_SPEED, 0.02)

	_wire = CABLE_WIRE_SCENE.instantiate()
	get_parent().add_child(_wire)
	_wire.launch(self, weapon, landed, _hook_left)
	# The cooldown runs from the shot, hit or miss, so a whiff costs you just as
	# much as a grapple.
	_cable_cd = CABLE_COOLDOWN
	_cable_cd_shown = ceili(_cable_cd)
	gear_changed.emit()


## A rocket straight off the wrist. It reuses the RPG's projectile whole —
## `rocket.gd` already flies, arms, splashes and credits its shooter — so the
## gadget is a launch site and a set of numbers, not a second weapon.
##
## Two things it does NOT share with the RPG. It is weaker (a gadget on a 7 s
## cooldown must not out-damage a 110-token primary), and it launches from the
## HEAD rather than the weapon anchor, so the shot goes exactly where the
## crosshair is even while a gun is in hand — you fire this without lowering
## whatever you are already holding, which is the whole point of it being on
## your wrist.
const WRIST_ROCKET_SPLASH := 3.6
const WRIST_ROCKET_DAMAGE := 62.0
const WRIST_ROCKET_RANGE := 180.0


func _fire_wrist_rocket() -> void:
	var rocket := ROCKET_SCENE.instantiate()
	get_tree().current_scene.add_child(rocket)
	# Started a little ahead of the head so it clears our own capsule: the
	# projectile has a collider, and spawning it inside the shooter is how the
	# grenade's sticky learned to glue itself to its thrower's chest.
	var dir := -head.global_transform.basis.z
	rocket.launch(head.global_position + dir * 0.6, dir, self,
		WRIST_ROCKET_SPLASH, WRIST_ROCKET_DAMAGE, WRIST_ROCKET_RANGE)
	# The same shove a heavy gun gives, so firing it reads as launching something.
	_on_weapon_fired(0.09, 1.6)


## The Clone ARC's scan dart: fires from the head like the wrist rocket, so it
## goes exactly where the crosshair points. It reveals for the whole team, so it
## carries the team rather than the body.
func _fire_scan_dart() -> void:
	var dart := SCAN_DART_SCENE.new()
	get_tree().current_scene.add_child(dart)
	var dir := -head.global_transform.basis.z
	dart.launch(head.global_position + dir * 0.6, dir, self, team)


## How long a cloak lasts, and how faint you go. Not fully invisible to a HUMAN
## opponent — a faint shimmer is still there to spot if they are looking — but
## AI cannot see you at all (GameState.cloaked). That split is deliberate: an
## invisibility that beats a watching human as well is oppressive on a couch.
const CLOAK_TIME := 5.0
const CLOAK_ALPHA := 0.12   # how much of the model still shows


func _begin_cloak() -> void:
	_cloak_left = CLOAK_TIME
	GameState.set_cloaked(self, true)
	model.set_cloak(CLOAK_ALPHA)
	gear_changed.emit()


func _end_cloak() -> void:
	# Idempotent on the CLOAKED STATE, not on the timer: _update_cloak decrements
	# _cloak_left to zero and THEN calls this, so guarding on the timer made the
	# natural time-out skip its own cleanup and leave a permanent ghost in
	# GameState.cloaked.
	if not GameState.is_cloaked(self):
		return
	_cloak_left = 0.0
	GameState.set_cloaked(self, false)
	model.set_cloak(1.0)
	gear_changed.emit()


## Seconds of cloak left, 0 when visible — for the HUD.
func cloak_left() -> float:
	return _cloak_left


func _update_cloak(delta: float) -> void:
	if _cloak_left <= 0.0:
		return
	_cloak_left -= delta
	if _cloak_left <= 0.0:
		_end_cloak()


## Pour the lightning while the button is held. Each tick RE-ACQUIRES: the cone
## is tested again from wherever you are now looking, so a target that walks
## behind a wall or out of the arc cuts the stream instantly, and following them
## with the crosshair is the skill the power asks for.
##
## The cooldown is charged when the channel ENDS, in proportion to how much of it
## was actually spent — a tap that hit nobody costs almost nothing, while holding
## it dry costs the full four seconds. That is the same "a miss should not take
## the class out of the fight" rule the pull already follows, made continuous.
func _update_lightning_channel(delta: float) -> void:
	if _channel_left <= 0.0:
		return
	var holding := _slot_held(_channel_slot) and not _dead and not map_open
	_channel_left -= delta
	if holding and _channel_left > 0.0:
		_channel_tick -= delta
		if _channel_tick <= 0.0:
			_channel_tick = ForcePowers.CHANNEL_TICK
			# One bite: resolves damage, replaces the drawn bolt, and returns
			# null on an empty cone — which drops the bolt but keeps the channel
			# open, so sweeping off a target and back on stays one press.
			_channel_arc = ForcePowers.channel_bolt(
				self, team, LIGHTNING_SCENE, weapon, _channel_arc)
		return
	# Ended: released, out of time, dead, or on the map screen.
	var spent := 1.0 - clampf(_channel_left / ForcePowers.CHANNEL_TIME, 0.0, 1.0)
	var cd: float = Loadout.GADGET_COOLDOWNS.get(Loadout.Gadget.FORCE_LIGHTNING, 0.0)
	_start_gadget_cd(_channel_slot, maxf(cd * spent, cd * 0.25))
	_channel_left = 0.0
	_channel_slot = -1
	if is_instance_valid(_channel_arc):
		_channel_arc.queue_free()


## Is the front shield currently up? Anything that should be denied while you
## are carrying a barrier asks this — right now that is aiming down sights.
func shield_up() -> bool:
	return is_instance_valid(_shield)


## A barrier that hangs in front of you. It stops incoming fire but not yours —
## your own shots exclude it (see hitscan_exclusions), so you shoot through it.
## Raising it costs you your sights: see _update_aim.
func _toggle_shield() -> void:
	if is_instance_valid(_shield):
		_shield.queue_free()
		_shield = null
		return
	_shield = SHIELD_SCENE.instantiate()
	add_child(_shield)  # rides with the body, so it always faces where you do
	_shield.setup(GameState.team_colors[team])


## Swap to the spin-up rotary cannon (and back). Carrying it slows you down.
func _toggle_rotary() -> void:
	_rotary_out = not _rotary_out
	if _rotary_out:
		weapon.set_class(Weapon.Class.ROTARY, loadout.primary_mods())
	else:
		weapon.set_class(loadout.secondary_class() if _on_secondary
			else loadout.weapon_class() as Weapon.Class, loadout.mods_for(_on_secondary))
	_refresh_offhand()
	_announce_hand()


## Drop an auto-turret a couple of metres ahead. One at a time: placing again
## picks the old one back up.
func _place_turret() -> void:
	if is_instance_valid(_turret):
		_turret.queue_free()
		_turret = null
		return
	var ahead := global_position - global_transform.basis.z * 2.2
	_turret = TURRET_SCENE.instantiate()
	get_parent().add_child(_turret)
	_turret.global_position = ahead
	_turret.setup(self, team)


## Set the mortar tube down a couple of metres ahead, or pick it back up. Same
## one-at-a-time toggle as the turret.
##
## Placing it opens the map immediately: a tube you have not given a target is
## doing nothing, and the map is the only place you can give it one, so the two
## are one action. Picking the tube back up does NOT open the map — there would
## be nothing to aim.
func _place_mortar() -> void:
	if is_instance_valid(_mortar):
		_mortar.queue_free()
		_mortar = null
		return
	_mortar = MORTAR_SCENE.instantiate()
	get_parent().add_child(_mortar)
	_mortar.global_position = global_position - global_transform.basis.z * 2.2
	_mortar.setup(self, team)
	if not map_open:
		_toggle_map()


## Gadget leftovers that must not survive a death.
func _clear_gadget_props() -> void:
	if is_instance_valid(_wire):
		_wire.queue_free()
	_wire = null
	if is_instance_valid(_shield):
		_shield.queue_free()
	_shield = null
	if is_instance_valid(_turret):
		_turret.queue_free()
	_turret = null
	if is_instance_valid(_mortar):
		_mortar.queue_free()
	_mortar = null


## Bodies our own hitscan must ignore: ourselves, and our own front shield.
func hitscan_exclusions() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	if is_instance_valid(_shield):
		out.append(_shield.get_rid())
	return out


func _update_gear() -> void:
	if _switch_pressed():
		_swap_weapon()
	if _gadget_pressed():
		_use_gadget(0)
	# The GADGET 2 control (keyboard G, pad LB by default) fires the second gadget.
	# If the slot is empty and the class can dash, that button is the dash — the
	# Force adept's dash costs no new binding, exactly as before.
	if _slot1_pressed():
		if gadget2 != Loadout.Gadget.NONE:
			_use_gadget(1)
		elif loadout.can_dash():
			_dash()


## Passive regeneration: once REGEN_DELAY has passed since the last hit, heal
## back to full. Replaces the health kit — you recover by breaking contact, not
## by spending a consumable.
func _update_regen(delta: float) -> void:
	_since_damage += delta
	if _since_damage < REGEN_DELAY or health >= max_health:
		return
	health = minf(health + REGEN_RATE * delta, max_health)
	health_changed.emit(health)


## Lob a grenade of `type`, from the camera along the look direction with an
## upward share so it arcs instead of firing flat. Called by _use_gadget for a
## grenade gadget.
func _throw_grenade(type: int) -> void:
	var grenade := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(grenade)
	var aim := -head.global_transform.basis.z
	var toss := (aim + Vector3.UP * GRENADE_LOB).normalized() * GRENADE_THROW_SPEED
	grenade.launch(head.global_position + aim * 0.6, toss + velocity, self, type)


func _move_input() -> Vector2:
	if input_device < 0:
		return Input.get_vector("kb_left", "kb_right", "kb_forward", "kb_back")
	return _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)


func _stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var v := Vector2(Input.get_joy_axis(input_device, ax), Input.get_joy_axis(input_device, ay))
	return Vector2.ZERO if v.length() < STICK_DEADZONE else v


## Every control below goes through Controls, so all of it is rebindable and
## none of it names a key or a pad button. Held states are a straight lookup;
## edges need the split below.
func _jump_pressed() -> bool:
	return _edge("jump")


func _sprint_held() -> bool:
	return Controls.held(input_device, "sprint")


func _fire_held() -> bool:
	return Controls.held(input_device, "fire")


func _crouch_held() -> bool:
	return Controls.held(input_device, "crouch")


func _ads_held() -> bool:
	return Controls.held(input_device, "ads")


## Actually running: the sprint control down, not crouched, and the movement
## stick pushed — so holding sprint while standing still is NOT running and does
## not deny the sights. Used to disallow ADS mid-run.
func _is_running() -> bool:
	return _sprint_held() and not _crouch_held() and _move_input().length() > 0.1


## Feed the weapons this frame's stance penalty on the spread cone: wider in the
## air, wide while moving, tight while crouched (they multiply). Both hands get
## it so a dual-wielding Mandalorian sprays wider on the move too.
## --- upper/lower body separation ----------------------------------------------
##
## A CharacterBody3D yawing under a look input turns the WHOLE body, feet
## included, so panning your aim while standing still pirouettes the model on the
## spot. Real bodies turn the torso first and move their feet only once they run
## out of neck, and that lag is one of the strongest cues that a thing on screen
## is a person rather than an object being rotated.
##
## So the legs get a heading of their own (`_feet_yaw`) that the body's aim yaw
## is allowed to lead by up to TWIST_MAX. The MODEL is counter-rotated back onto
## the feet and the model's own Twist joint puts the upper body back on the aim,
## which nets to: legs where the feet are, chest where the crosshair is. Nothing
## about aiming, shooting or collision changes — `rotation.y` is still the body's
## true facing and the weapon still fires down it.
const TWIST_MAX := deg_to_rad(55.0)    # how far the chest may lead the feet
const TWIST_STEP_RATE := 7.0           # rad/s the feet catch up once they must
const TWIST_WALK_RATE := 14.0          # ...and much faster once you are moving

var _feet_yaw := 0.0


func _update_torso_twist(move: Vector2, delta: float) -> void:
	var aim := rotation.y
	var lead := wrapf(aim - _feet_yaw, -PI, PI)
	# Moving, airborne or crouched, the feet go where the body goes: a twist held
	# through a walk cycle reads as a broken hip, and the legs have to point
	# where they are actually carrying you.
	if move.length() > 0.1 or not is_on_floor() or _crouch_t > 0.5:
		_feet_yaw += lead * minf(TWIST_WALK_RATE * delta, 1.0)
	elif absf(lead) > TWIST_MAX:
		# Out of neck: step the feet round, but only far enough to get back
		# inside the limit — that is what makes it read as a shuffle rather than
		# as the legs snapping to the camera.
		var over := lead - signf(lead) * TWIST_MAX
		_feet_yaw += over * minf(TWIST_STEP_RATE * delta, 1.0)
	lead = wrapf(aim - _feet_yaw, -PI, PI)
	model.rotation.y = -lead     # the legs stay where the feet are...
	model.set_twist(lead)        # ...and the chest comes back onto the aim


func _update_stance_spread(move: Vector2, crouching: bool) -> void:
	var mult := 1.0
	if not is_on_floor():
		mult = AIR_SPREAD_MULT
	elif move.length() > 0.1:
		mult = MOVE_SPREAD_MULT
	if crouching:
		mult *= CROUCH_SPREAD_MULT
	weapon.stance_spread_mult = mult
	weapon_off.stance_spread_mult = mult


func _gadget_held() -> bool:
	return Controls.held(input_device, "gadget")


func _fire_pressed() -> bool:
	return _edge("fire")


func _gadget_pressed() -> bool:
	return _edge("gadget")


func _switch_pressed() -> bool:
	return _edge("switch")


func _map_pressed() -> bool:
	return _edge("map")


## True on the frame the pick-up control went down. Published rather than polled
## by Pickup calling _edge itself, because an edge is consumed by whoever reads
## it — with several crates overlapping, the first to look would eat the press
## and the rest would silently see nothing.
func _interact_pressed() -> bool:
	return _edge("interact")


## Press edge for a control. The keyboard gets it from the InputMap action for
## free; a pad cannot, because an InputMap action is device-wide and four
## players are on four pads — so for those we poll and remember the previous
## state per control, in this player's own _downs.
func _edge(id: String) -> bool:
	if input_device < 0:
		return Controls.kb_pressed(id)
	var down := Controls.pad_held(input_device, id)
	var edge: bool = down and not _downs.get(id, false)
	_downs[id] = down
	return edge


## Deploy off the buy screen: the same control as jump, held-state (the edge is
## tracked by the buy screen itself, which needs a fresh press).
func _deploy_held() -> bool:
	return Controls.held(input_device, "jump")


func _update_anim(move: Vector2, sprinting: bool) -> void:
	if _anim == null:
		return
	# Basic Minecraft/Krunker-style state machine: airborne -> jump (held),
	# moving -> walk/run, else idle. No landing clip on purpose. Crouching swaps
	# in the folded-leg variants; there is no crouched sprint because sprint is
	# already suppressed while crouched.
	#
	# The guard sits BELOW the crouch on purpose, even though it is the more
	# valuable tell: there is no crouched guard clip, so putting it above would
	# stand the model up out of a capsule that is still crouched — and the head
	# the model draws is the head other players are shooting at.
	var target: String
	if not is_on_floor():
		target = "jump"
	elif _crouch_t > 0.5:
		target = "crouch_walk" if move.length() > 0.1 else "crouch_idle"
	elif guard_up():
		target = "guard_walk" if move.length() > 0.1 else "guard_idle"
	elif move.length() > 0.1:
		target = "run" if sprinting else "walk"
	else:
		target = "idle"
	# assigned_animation (not current_animation) so the one-shot jump keeps
	# holding its last frame instead of retriggering every tick.
	if _anim.assigned_animation != target and _anim.has_animation(target):
		_anim.play(target, 0.12)
	# Scale locomotion cycles to ground speed so feet don't skate.
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	match target:
		"walk":
			_anim.speed_scale = clampf(ground_speed / 2.6, 0.6, 2.2)
		"run":
			_anim.speed_scale = clampf(ground_speed / 5.0, 0.6, 2.2)
		"crouch_walk":
			# Crouched movement is WALK_SPEED * CROUCH_SPEED_MULT, so the shuffle
			# is paced off that or the feet skate at a third of the stride.
			_anim.speed_scale = clampf(
				ground_speed / (WALK_SPEED * CROUCH_SPEED_MULT), 0.6, 2.2)
		"guard_walk":
			# The guard's stance takes a shorter step than the plain walk (a
			# smaller hip swing over a slightly shorter cycle), so it is paced off
			# its own stride, not the walk's, or the feet skate.
			_anim.speed_scale = clampf(ground_speed / 1.8, 0.6, 2.2)
		_:
			_anim.speed_scale = 1.0
