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
## This body became a signature (or stopped being one). The HUD names it.
signal signature_changed()
## SOMETHING HURT YOU, AND IT CAME FROM THERE. Carries the world position of
## whatever did it, so the HUD can keep the bearing correct as you turn and move
## rather than freezing it at the angle it arrived on.
##
## SEPARATE FROM `damaged` DELIBERATELY, and raised EARLIER. `damaged` fires only
## once a hit has cost you health — the saber guard and a full overshield both
## return before it — and "where is that coming from" is the question you most
## need answered in exactly those cases: a shield eating a burst still means
## somebody has line of sight on you and you still have to decide which way to
## move. Being told where a hit came from is not the same information as being
## told it hurt, so it is not the same signal.
signal hit_from(source: Vector3)
## This body is being driven by a different controller now. Anything that CACHED
## `input_device` has to hear about it — see `adopt_device`.
signal device_changed(device: int)

const CORPSE_SCENE := preload("res://scenes/fx/corpse.tscn")
const GRENADE_SCENE := preload("res://scenes/fx/grenade.tscn")
const BOT_SCENE := preload("res://scenes/actors/bot.tscn")
const SHIELD_SCENE := preload("res://scenes/fx/front_shield.tscn")
const TURRET_SCENE := preload("res://scenes/actors/turret.tscn")
const MORTAR_SCENE := preload("res://scenes/actors/mortar.tscn")
const CABLE_WIRE_SCENE := preload("res://scenes/fx/cable_wire.tscn")
const LIGHTNING_SCENE := preload("res://scenes/fx/lightning_arc.tscn")
const VEHICLE_SCENE := preload("res://scenes/actors/vehicle.tscn")
const RECON_SWEEP := preload("res://scripts/recon_sweep.gd")
const ORBITAL_STRIKE := preload("res://scripts/orbital_strike.gd")
const GUNSHIP := preload("res://scripts/gunship.gd")
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
# Kinesis adept's double jump. Slightly weaker than the standing jump, so the
# second one reads as a Force-assisted correction rather than a free ladder, and
# it still scales with the armour frame like every other jump.
const AIR_JUMP_MULT := 0.9
# Kinesis dash: a burst of speed on the ground or in the air. Delivered as an
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
## HOW HARD A GRENADE IS THROWN. It was 13 m/s, which is a lob — about fourteen
## metres of flat ground before it lands, so on any of the big maps you could not
## reach the cover you were shooting at. A real throw is an ARMED one: 22 m/s
## carries roughly twenty-four metres, which is the distance a firefight in this
## game is actually held at.
##
## The LOB is a share of the throw rather than a fixed rise, so the arc keeps its
## shape as the speed changes — raising the speed alone would flatten it into a
## line drive that skids past the target.
const GRENADE_THROW_SPEED := 22.0
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
## HOW LONG THE SIGHTS TAKE TO COME UP, and it is the gun's number rather than
## one number for everything. `ADS_TIME_BASE` is the DC-15's; every other weapon
## multiplies it by its own `handling` (see `Weapon.handling`). A holdout is at
## the eye in 0.14 s and a Gauss Cannon takes 0.35.
##
## **The camera's zoom and the viewmodel's slide are eased over the SAME
## duration.** They used to be a rate (14/s) and a duration (0.12 s) authored
## separately, so the world finished magnifying at one moment and the sight
## arrived at another — which is felt as mush rather than seen as a fault, and is
## the reason a fast ADS can still feel slow.
const ADS_TIME_BASE := 0.20
## Aiming costs you ground. Without it ADS is strictly better than hip fire in
## every situation, which removes a decision rather than adding an option.
const ADS_SPEED_MULT := 0.58


func ads_time() -> float:
	return ADS_TIME_BASE * weapon.handling()


## THE SPRINT-OUT, which is the dial that makes carrying a heavy gun mean
## something outside a firefight as well as inside one.
##
## The weapon is stowed across the chest while you run — everyone else could
## already see that — and coming back out of it TAKES TIME proportional to the
## weapon (`SPRINT_RAISE_TIME * handling`). The trigger does nothing until it is
## up (`weapon_ready`), which is the whole point: sprinting somewhere is now a
## commitment you can be caught inside, and the SAW's 0.42 s is a real reason to
## carry the carbine's 0.24.
##
## Stowing is NOT scaled by the gun — dropping a weapon is the same shrug
## whatever it weighs, and only the recovery is work.
const SPRINT_STOW_TIME := 0.16
const SPRINT_RAISE_TIME := 0.26
## How far back down the stow has to come before the gun will fire. Not zero:
## the round should leave as the sights settle, not a beat after them.
const FIRE_READY_AT := 0.30
var _stow := 0.0


## Step the stow and push it to both hands. Player owns this rather than the
## viewmodel because it decides whether the TRIGGER works, and that is a physics
## answer — a visual timer running on render frames would let the two disagree
## about whether the gun is up, which is exactly the lie this is here to stop.
func _update_stow(delta: float) -> void:
	# Reaching for the trigger or the sights is itself the decision to stop
	# sprinting, so both start the weapon coming up.
	var want := 1.0 if (_is_running() and not _fire_held() and not _ads_held()) \
		else 0.0
	var dur := SPRINT_STOW_TIME if want > 0.0 \
		else SPRINT_RAISE_TIME * weapon.handling()
	_stow = move_toward(_stow, want, delta / maxf(0.01, dur))
	weapon.set_sprint_amount(_stow)
	weapon_off.set_sprint_amount(_stow)


## Is the gun far enough out of the sprint carry to shoot?
func weapon_ready() -> bool:
	return _stow <= FIRE_READY_AT


## 0 at the hip, 1 fully aimed, stepped over the weapon's own `ads_time()`. It
## drives the camera zoom; the viewmodel eases its own slide over the same
## duration, which is what keeps the two arriving together.
var _ads_t := 0.0
# Recoil. The camera kick always settles all the way back to where you were
# looking, so a burst climbs and then hands your aim back rather than stealing
# it — the cost of firing is the climb, not a permanent drift. Recovery is slow
# enough that a fast gun is still climbing when its next round leaves.
const RECOIL_RECOVER := 6.0   # per-second rate the camera recoil settles back
const RECOIL_YAW_SHARE := 0.55  # sideways lean, as a share of the pitch kick
# THE PATTERN (see `_on_weapon_fired`). A burst climbs hardest at the start and
# settles; the sideways component weaves on a smooth curve you can learn instead
# of jittering at random. The jitter that remains is small on purpose — enough
# that two bursts are not pixel-identical, not enough to make the curve a lie.
const RECOIL_FIRST_SHOT := 1.45   # first-round climb, as a multiple of the rest
const RECOIL_SETTLE_SHOTS := 5.0  # rounds it takes to fall to the steady climb
const RECOIL_WEAVE := 0.7         # radians of pattern phase per round fired
const RECOIL_YAW_JITTER := 0.10   # the only random part left
# How long off the trigger before the pattern starts again from the first round.
# Shorter than a reload and longer than the gap between rounds of the slowest
# automatic, so tapping resets the climb and holding does not.
const RECOIL_PATTERN_RESET := 0.35
var _recoil_step := 0
var _recoil_idle := 0.0
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
@export var team: int = GameState.Team.CONCORD
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
## --- The death cam ----------------------------------------------------------
##
## WHO KILLED YOU IS THE ONE THING A DEATH SCREEN CAN TEACH. The camera already
## stayed where you fell, which shows you the floor you died on and nothing about
## why. These three carry the answer across the death: the reference so the view
## can TURN onto them while they are still alive, the name so the HUD can still
## say it after they are freed, and the flag so it can say how.
var _killer: Node = null
var _killer_name := ""
var _last_hit_headshot := false
var squad: Array[Bot] = []  # the AI squadmates currently alive under this player
var gadget := Loadout.Gadget.NONE
## The second gadget slot, driven by the GADGET 2 (`grenade`) control.
var gadget2 := Loadout.Gadget.NONE
var gadget3 := Loadout.Gadget.NONE
var jet_fuel := 1.0

var _anim: AnimationPlayer
## THE ANIMATION MODULE for this body — one object, made with the rig and ticked
## once a frame. See `Locomotion` for what it owns and why it is not static.
var _loco: Locomotion
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
var _force_cd := [0.0, 0.0, 0.0]   # seconds left on each gadget slot's cooldown
## The lightning channel: seconds of stream left, which slot opened it, and the
## time until the next bite. A channel rather than a shot because the power is
## HELD — see Kinesis.CHANNEL_TIME.
var _channel_left := 0.0
var _channel_slot := -1
var _channel_tick := 0.0
var _channel_arc: Node3D       # the bolt currently on screen, re-aimed per tick
## The Saurian's cloak: seconds of invisibility left. While it is up the
## model is faded and `GameState.cloaked` holds this player, which every AI
## vision check skips. Firing or the timer ending drops it.
var _cloak_left := 0.0
# THREE entries, one per gadget slot. This was two, and `_force_cd` beside it
# was widened to three when the sustained slot landed — so the moment a slot-3
# ability went on cooldown the HUD push read off the end of this array, and a
# GDScript error ABORTS THE ENCLOSING FUNCTION: the rest of `_apply_gadget_motion`
# stopped running for that frame, which is the jetpack, the cable and the dash.
# Your jetpack died while your overshield recharged.
var _force_shown := [0, 0, 0]   # last whole second pushed to the HUD, per slot
## Saber guard. `_block` is the exhaustion pool, 0..1; it drains while raised
## and, much faster, per point of damage it stops. At zero the guard BREAKS and
## cannot be raised again until it has recovered past BLOCK_RECOVER_AT — without
## that, a pool that empties and refills to a sliver would flicker the block on
## and off every frame under sustained fire.
var _block := 1.0
var _block_broken := false
## Mid-air jumps left this flight. Only Kinesis adept gets any, and the count
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
var _speed_mult := 1.0     # armour frame x the unit's own: scales walk + sprint
var _jump_mult := 1.0      # armour frame x the unit's own: scales jump velocity
var _stature := 1.0        # how tall this unit is against a standard trooper
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
	_loco = Locomotion.new()
	_loco.setup(_anim, model)
	# FOOT PLANTING IS BUILT BUT NOT ON — see `Locomotion.plant_feet` and
	# `CharacterModel._solve_feet` for what it does and what is still wrong with
	# it. Flip this to true to try it.
	_loco.plant_feet = false
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
	# See only our own viewmodel: drop the whole viewmodel block, add ours back.
	for j in VIEWMODEL_SLOTS:
		cam.cull_mask &= ~(1 << (VIEWMODEL_BIT + j))
	remote_cam.remote_path = remote_cam.get_path_to(cam)
	_camera = cam
	_base_fov = cam.fov
	_apply_view_mode()


## --- THIRD PERSON ---------------------------------------------------------------
##
## A SABER DUELLIST IS WATCHED, NOT LOOKED THROUGH. A Force Master's whole
## repertoire is things that happen to the BODY — a two-metre blade swung on an
## arc, a guard raised across the chest, a leap, a shove — and a first-person
## camera 30 cm from the hilt is pointed at the one part of all that which cannot
## be seen. It is also the reward the player has climbed fourteen kills for, and
## the transformation is invisible to the only person who earned it.
##
## THE PARALLAX QUESTION IS WHY THIS IS PER-REWARD AND NOT A SETTING. Moving the
## camera off the head puts the crosshair and the gun on two different lines —
## the same fault that made the HAMMERHEAD's ball turret unusable, and there it was
## fatal. Here it is not, and that is a property of THIS BODY rather than of
## third person: the shot origin is the weapon (`Weapon._fire_hitscan` traces
## from `global_position`, which is on the head), and a Force Master's weapons
## are a melee ARC, a Force CONE and a sidearm. None of them is a precision ray
## at range, so a camera half a metre off the aim line costs nothing measurable.
## A trooper on a scoped rifle in this camera would be a different question, and
## the answer would be no.
var third_person := false

## Behind and above, and only a LITTLE to the side. A hard over-the-shoulder
## offset is the iconic look and it is also the one that costs the most parallax,
## so this leans toward keeping the aim line and the sight line in nearly the same
## vertical plane.
const CHASE_BACK := 3.4
const CHASE_UP := 0.45
const CHASE_SIDE := 0.55
## How fast the camera falls back on the transformation and returns on death. Not
## instant: the pull-back IS most of the entry animation, and a cut would throw
## the whole moment away.
const CHASE_EASE := 3.2
## The camera must not go through walls, so it is pulled in to whatever the sweep
## hits. Kept a little off the surface, or a camera resting exactly on a wall
## renders the inside of it.
const CHASE_CLEARANCE := 0.30

var _chase_t := 0.0        # 0 first person .. 1 fully out

## --- SCREEN SHAKE ---------------------------------------------------------------
##
## THE WORLD HAD NO PHYSICAL EFFECT ON THE VIEW. A rocket could detonate at your
## feet, a mortar could land beside you, an MARAUDER could put a shell into the wall
## you are behind, and the camera did not acknowledge any of it — the only things
## that ever moved it were your own gun and your own legs. That is the difference
## between explosions being events and being decals with a damage number on them.
##
## IT RIDES `remote_cam`, NOT THE HEAD, and that is the whole design constraint.
## The weapon is a child of the head, so shake applied there would move the
## SHOTS — a screen shake that spoils your aim is not a feel improvement, it is
## an input bug. The RemoteTransform3D copies its OWN transform onto the camera,
## so offsetting it moves what you SEE and nothing else. Same mechanism the chase
## camera uses, for the same reason.
##
## MOSTLY ROLL, AND ONLY A LITTLE TRANSLATION. Roll is the one axis that is
## completely boresight-neutral: rotating about the view axis cannot move where
## the centre of the screen points, so the crosshair still covers exactly what
## the gun will hit. Yaw and pitch shake would put the reticle and the barrel on
## different lines, which is the fault that made the HAMMERHEAD's ball turret unusable
## and is not worth reintroducing for an effect. Translation is kept small for
## the same reason (it is parallax, not angle, so it is far more forgiving).
##
## TRAUMA, NOT DISPLACEMENT. The stored value is squared when it is applied, so
## a big hit reads as violently different from a small one rather than merely
## larger — and it decays linearly, so it always ENDS rather than asymptotically
## trailing off into a camera that never quite settles.
const SHAKE_MAX := 1.0
const SHAKE_DECAY := 1.9          # trauma per second
const SHAKE_ROLL := 0.085         # radians at full trauma
const SHAKE_SHIFT := 0.075        # metres at full trauma
const SHAKE_FREQ := 24.0          # how fast it rattles

var _shake := 0.0
var _shake_t := 0.0


## Add to this body's shake. `amount` is trauma, not displacement: 0.2 is a
## grenade somewhere near, 1.0 is being stood on the thing that went off.
##
## ASKED OF THE PLAYER RATHER THAN PUSHED BY THE EXPLOSION, so a body that
## cannot be shaken (a Bot, which has no camera) simply does not have the method
## and the caller's duck-typed check skips it — the same shape as `apply_impulse`
## and `on_hit_confirmed`.
func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, SHAKE_MAX)


## Where the shake has pushed the camera this frame. Two offset sine chains at
## unrelated frequencies rather than `randf`: noise re-rolled per frame at 60 Hz
## reads as a broken cable, where a wobble at a fixed rate reads as a shock going
## through a body. It is the same argument the recoil PATTERN makes about not
## being random.
func _shake_offset() -> Vector3:
	if _shake <= 0.0:
		return Vector3.ZERO
	var k: float = _shake * _shake        # trauma is squared on the way out
	return Vector3(
		sin(_shake_t * SHAKE_FREQ) * SHAKE_SHIFT * k,
		sin(_shake_t * SHAKE_FREQ * 1.37 + 1.1) * SHAKE_SHIFT * k,
		0.0)


## WHICH MESHES THIS PLAYER'S OWN CAMERA MAY SEE. One function for both modes, so
## the body and the viewmodel can never both be on or both be off — which is what
## "my gun is floating in front of my own face" and "I am invisible to myself"
## each look like.
func _apply_view_mode() -> void:
	if _camera == null:
		return
	var body_bit := 1 << (1 + player_index)
	var gun_bit := 1 << (VIEWMODEL_BIT + player_index)
	if third_person:
		_camera.cull_mask |= body_bit    # ...and now you can see yourself
		_camera.cull_mask &= ~gun_bit    # the first-person gun would be inside you
	else:
		_camera.cull_mask &= ~body_bit
		_camera.cull_mask |= gun_bit


## Ease the camera out to the chase position and keep it out of the scenery.
##
## It rides `remote_cam.position` rather than a second camera or a new node: the
## RemoteTransform3D already copies ITS OWN transform onto the camera, so moving
## the transform back along the head's +Z IS a chase camera, and everything that
## already drives the view — the look, the recoil, the landing dip, a vehicle
## writing angles — keeps working untouched.
func _update_chase(delta: float) -> void:
	var want := 1.0 if third_person else 0.0
	# NOT AN EARLY-OUT ANY MORE when the shake is live: this function is also
	# what decays it and writes it, so returning here would freeze a shaking
	# camera at whatever offset it happened to be at.
	if is_equal_approx(_chase_t, want) and _chase_t <= 0.0 and _shake <= 0.0:
		if remote_cam.position != Vector3.ZERO:
			remote_cam.position = Vector3.ZERO
			remote_cam.rotation.z = 0.0
		return
	_chase_t = move_toward(_chase_t, want, delta * CHASE_EASE)
	var back := CHASE_BACK * _chase_t
	if back > 0.01:
		# Sweep from the head to where the camera wants to be. WORLD layer only:
		# pulling the camera in because a teammate walked behind you would be a
		# camera that lurches every time somebody runs past.
		var from := head.global_position
		var to := head.global_transform * Vector3(
			CHASE_SIDE * _chase_t, CHASE_UP * _chase_t, back)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var room: float = from.distance_to(hit["position"]) - CHASE_CLEARANCE
			back = clampf(room, 0.0, back)
	# THE SHAKE COMPOSES WITH THE CHASE, rather than either overwriting the
	# other — they are two different reasons for the camera to be somewhere other
	# than on the head, and both can be true at once.
	_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
	_shake_t += delta
	var jitter := _shake_offset()
	remote_cam.position = Vector3(
		CHASE_SIDE * _chase_t, CHASE_UP * _chase_t, back) + jitter
	# ROLL ONLY. See the note on `SHAKE_ROLL` for why the other two axes are not
	# touched: roll cannot move where the centre of the screen points.
	remote_cam.rotation.z = sin(_shake_t * SHAKE_FREQ * 0.83) \
		* SHAKE_ROLL * _shake * _shake


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
	# THE TRANSFORMATION CANNOT BE INTERRUPTED. A BECOME reward lands in the
	# middle of a firefight by definition — that is what a ten-kill streak is —
	# so without this the rounds already in the air arrive during the entry and
	# the prize can be taken away in the second it is handed over. Just over a
	# second, which is too short to walk anywhere behind.
	if _entry_left > 0.0:
		return
	# WHERE IT CAME FROM, ANNOUNCED BEFORE ANYTHING CAN ABSORB IT. See `hit_from`:
	# a blocked or shielded hit is still somebody shooting at you from somewhere,
	# and the paths below return early for both.
	if attacker != null and attacker != self and attacker is Node3D \
			and is_instance_valid(attacker):
		hit_from.emit((attacker as Node3D).global_position)
	# The saber guard stops the whole hit while it has anything left to pay with,
	# and spends itself doing it. Once it BREAKS, everything lands as normal —
	# what the pool buys is a window, not a permanent shield.
	amount = _absorb_with_guard(amount, attacker)
	if amount <= 0.0:
		return
	_flinch(amount)
	# BATTLE FURY takes the edge off everything while it lasts, and the
	# OVERSHIELD eats what is left before your health does — spent rather than
	# worn down, so what it buys is a fixed number of rounds. Neither suppresses
	# the hit marker or the damage flash: the shooter is still landing shots and
	# both of you should be told so.
	if _fury_left > 0.0:
		amount *= FURY_RESIST
	# BULWARK is the same shape of discount for a body that has given up its
	# legs, and RALLY is somebody ELSE'S — asked per bullet rather than pushed
	# per frame, which is the whole reason a team aura is affordable here.
	if _bulwark_left > 0.0:
		amount *= BULWARK_RESIST
	amount *= GameState.rally_resist(self)
	if _over_pool > 0.0:
		var eaten: float = minf(_over_pool, amount)
		_over_pool -= eaten
		amount -= eaten
		if _over_pool <= 0.0:
			_over_left = 0.0
		gear_changed.emit()
		if amount <= 0.0:
			Audio.play("hurt", -8.0)
			return
	health -= amount
	_since_damage = 0.0  # taking a hit restarts the regen delay
	# DELIBERATELY NOT THE HIT MARKER. This is information about YOU, and if the
	# two sounds were confusable a player under fire would read incoming rounds
	# as their own shots landing — hence a dull thud with no brightness in it at
	# all (`Sfx._hurt`). Played flat rather than positioned: it happened here.
	Audio.play("hurt")
	health_changed.emit(health)
	damaged.emit(amount)
	# Tell whoever shot us that it landed. This is deliberately AFTER the
	# friendly-fire check and the health subtraction, so the hit marker only
	# ever confirms damage that was actually dealt.
	if attacker != null and attacker != self and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	if health <= 0.0:
		# The killing blow's own flag, so the feed can say HEADSHOT. Read by `_die`
		# on the next line rather than passed through it: `_die` is also reached
		# from the storm and from a fall, which have no shot to describe.
		_last_hit_headshot = headshot
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
## of the saber, so a Kinesis adept keeps it while holding a sidearm.
func air_jump_allowance() -> int:
	return 1 if loadout.kit == Loadout.Kit.ADEPT else 0


## True while the arc blade guard is actually up: blade in hand, aim held, and
## the exhaustion pool not spent. Nothing else can block — a raised guard is the
## Kinesis adept's answer to having no gun, not a general-purpose defence.
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
## weapon froze the pool the moment you swapped: a Kinesis adept who broke their
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


## Take an outside shove — a kinetic shove or pull. It rides _kick_vel rather than
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
	var before := kills_this_life
	kills_this_life += 1
	killed_someone.emit(kills_this_life)
	_check_streak(before, kills_this_life)


## --- kill streak rewards ------------------------------------------------------
##
## The table and the design are in `scripts/streaks.gd`. What lives here is the
## three lines that notice one was earned and the switch that grants it.

## Raised when one is OFFERED, and again (with an empty name) when the offer is
## resolved either way, so the HUD prompt can take itself down.
signal streak_offered(name: String, blurb: String)

## What this life can earn, resolved ONCE at deploy. Class and side cannot change
## under a life, so asking the table on every one of thirteen rounds a second
## would be the question house rule 5 exists about.
var _streak_rewards: Array[Dictionary] = []
## What has already been handed over this life, so a reward fires once even if
## the streak is re-crossed (a BECOME reward re-applies the loadout, and a body
## that could re-earn its own transformation would heal itself on every kill).
var _streak_taken := {}


func _refresh_streaks() -> void:
	var f: Dictionary = Loadout.faction(GameState.team_faction[
		clampi(team, 0, GameState.team_faction.size() - 1)])
	_streak_rewards = Streaks.available(int(f["side"]), int(f["universe"]))
	_streak_taken.clear()


## A REWARD IS OFFERED, NOT APPLIED. It waits on the pad's D-UP or D-DOWN, and
## until one of those is pressed nothing has happened.
##
## THE REASON IS THAT SOME OF THESE COST YOU SOMETHING. A BECOME reward replaces
## the build you chose and are in the middle of using — an ambusher on a scoped
## rifle does not necessarily want to be an Ork Warboss, and the gunship takes you
## off the ground for twenty seconds while your side is holding a post. Forcing
## those on somebody at the moment they are doing best is the opposite of a
## reward. So DECLINE is a real answer and not a politeness: it costs the reward
## and keeps the life.
##
## It also solves what the first version had no answer for — a reward landing
## mid-firefight with no say in the timing.
var _offer: Dictionary = {}


func _check_streak(before: int, after: int) -> void:
	if not GameState.match_live or _streak_rewards.is_empty():
		return
	var row := Streaks.earned(_streak_rewards, before, after)
	if row.is_empty() or _streak_taken.has(row["name"]):
		return
	# Taken the moment it is OFFERED, not when it is accepted: declining spends
	# the offer. Otherwise every further kill re-offers the thing you just said
	# no to, which is the most annoying possible prompt.
	_streak_taken[row["name"]] = true
	_offer = row
	# `offer_blurb` and not the raw blurb: a BECOME states its COST on the prompt,
	# because declining is only a real answer if you were told what you are
	# agreeing to, and "this body never heals" is not visible from looking at it.
	streak_offered.emit(str(row["name"]), Streaks.offer_blurb(row))
	Audio.play("streak")


## Poll the two answers. Read from the ordinary per-frame input path rather than
## from `_input`, like every other control this game has — four players are on
## four pads and an InputMap action is device-wide.
func _update_reward_offer() -> void:
	if _offer.is_empty():
		return
	if _edge("reward_accept"):
		accept_reward()
	elif _edge("reward_decline"):
		decline_reward()


## Take what is on offer. PUBLIC and separate from the control read, so the
## button and a test exercise the same path — an accept simulated by calling
## `_grant_streak` directly would not prove the offer is cleared.
func accept_reward() -> void:
	if _offer.is_empty():
		return
	var row := _offer
	_offer = {}
	streak_offered.emit("", "")
	_grant_streak(row)


## Turn it down. The offer is spent either way (see `_check_streak`), so this
## costs the reward and keeps the life — which is the whole reason it exists.
func decline_reward() -> void:
	if _offer.is_empty():
		return
	_offer = {}
	streak_offered.emit("", "")
	Audio.play("ui_back")


## What is on the table, for the HUD. Empty when there is nothing to answer.
func pending_reward() -> Dictionary:
	return _offer


func _grant_streak(row: Dictionary) -> void:
	match int(row["kind"]):
		Streaks.Kind.RECON:
			var sweep: Node3D = RECON_SWEEP.new()
			get_tree().current_scene.add_child(sweep)
			sweep.begin(team, float(row.get("duration", 12.0)))
		Streaks.Kind.BOMBARDMENT:
			var strike: Node3D = ORBITAL_STRIKE.new()
			get_tree().current_scene.add_child(strike)
			# Placed at the caller, because the strike measures its search radius
			# from itself — an orbital battery still only shells this battle.
			strike.global_position = global_position
			strike.begin(self, team, float(row.get("duration", 6.0)))
		Streaks.Kind.VEHICLE:
			_deliver_vehicle(str(row.get("vehicle", "")))
		Streaks.Kind.GUNSHIP:
			var ship: Node3D = GUNSHIP.new()
			get_tree().current_scene.add_child(ship)
			ship.begin(self, team, float(row.get("duration", 20.0)))
		Streaks.Kind.BECOME:
			_become(row)


## Set the earned machine down beside its owner. BESIDE, and behind: dropping it
## on top of the player puts two bodies inside one another, which is the
## documented ejection bug, and dropping it in front puts a wall between them and
## whatever they were shooting at.
const STREAK_VEHICLE_OFFSET := 6.0


func _deliver_vehicle(row_id: String) -> void:
	if row_id == "":
		return
	var v: Vehicle = VEHICLE_SCENE.instantiate()
	# Stated before it enters the tree so the walker is built ONCE. It used to be
	# added first, which built a Concord speeder, then re-setup twice — three
	# full model builds on the single frame a player earns the thing.
	v.team = team
	v.spawn_row_id = row_id
	get_tree().current_scene.add_child(v)
	var back := Vector3.FORWARD.rotated(Vector3.UP, rotation.y) * -STREAK_VEHICLE_OFFSET
	var at := global_position + back
	# The ground under that spot rather than the player's own feet — they may be
	# stood on a crate or halfway up a slope.
	v.global_position = Vector3(at.x, global_position.y + 1.0, at.z)
	# A DELIVERY IS A TELEPORT (house rule 10): without this the hull is drawn
	# smeared from the origin to where it landed for one frame.
	v.reset_physics_interpolation()


## Stop being a trooper. The preset goes through the SAME `_build_from` every AI
## build and authored class uses, so a reward's body is described exactly the way
## every other body in the game is.
func _become(row: Dictionary) -> void:
	var preset := Streaks.become_preset(row, team)
	if preset.is_empty():
		return
	# THE STREAK MUST SURVIVE THE TRANSFORMATION, and so must the record of what
	# has already been handed over. `_apply_loadout` resets both, because it is
	# also what a fresh DEPLOY calls — and here it is not one. Without the first,
	# a transformed body's counter goes back to nothing and it can never reach
	# the reward above it; without the second it re-earns ITSELF on its next kill,
	# healing to full and re-issuing its own shield every time.
	var keep_kills := kills_this_life
	var keep_taken := _streak_taken.duplicate()
	pending = Loadout.preset_build(preset)
	_apply_loadout()
	kills_this_life = keep_kills
	_streak_taken = keep_taken
	# AND THE POOL DOES NOT COME BACK. See `_no_regen` for why this is the
	# counterweight rather than a smaller number would be.
	_no_regen = true
	# The reward LIST is deliberately left as `_apply_loadout` just rebuilt it: a
	# body that changed kit has changed which rewards are its own, which is what
	# stops a transformed body being offered the reward it just became.
	if row.has("overshield"):
		_over_pool = float(row["overshield"])
		# A LONG FINITE LIFETIME, NOT `INF`. The intent is "it lasts until it is
		# spent", and `_over_left` is a countdown the HUD gauge reads straight out
		# as its fill fraction — INF makes that fraction meaningless and the gauge
		# draws nothing sensible. A minute and a half outlives any firefight the
		# shield could survive, so it expires by being SHOT OFF, which is what the
		# pool is for.
		_over_left = float(row.get("overshield_time", 90.0))
		gear_changed.emit()
	# WATCHED RATHER THAN LOOKED THROUGH, when the row asks for it. A TABLE KEY
	# and not a test on the reward's name: Kinesis Master is the body this was
	# written for, but nothing about the mechanism is Force-specific and a future
	# saber signature should get it by stating one word.
	third_person = bool(row.get("third_person", false))
	_apply_view_mode()
	# THE BANNER NAMES THE BODY, NOT THE ROW. They are deliberately different for
	# Kinesis Master: one row, two units — `preset_by_team` resolves it to WARDEN
	# MASTER or REAVER MASTER — so a HUD reading `row["name"]` would announce
	# "KINESIS MASTER" to a player who is visibly a Reaver. `build_name` is what
	# `_build_from` already resolved, so it is the answer that cannot disagree
	# with the model standing on screen.
	signature_name = loadout.build_name if loadout.build_name != "" \
		else str(row.get("name", ""))
	_signature_entry()
	health_changed.emit(health)


## --- THE TRANSFORMATION -----------------------------------------------------
##
## A BECOME REWARD HAS TO BE AN EVENT, and until now it was a statistic. The
## body swapped between one frame and the next: same position, same footing, a
## different silhouette and a much bigger number behind the health bar. Ten kills
## bought you a quiet substitution that the player mostly noticed by reading the
## HUD, and everyone around them noticed by dying.
##
## So it is announced, in the three places an event has to land:
##
##   ON THE SPOT   a shockwave at the feet, through `Blast.pop` — the same call
##                 every explosion in the game already makes, so this costs no
##                 new effect and cannot drift from how the rest of them look.
##   OUT LOUD      the streak sting, at the body rather than on the HUD, so the
##                 people about to have a problem hear where it came from.
##   IN THE FRAME  the chase camera easing out (`_update_chase`) if this body is
##                 watched, which is a second of the transformation being SHOWN
##                 to the one person who earned it.
##
## AND IT BUYS A MOMENT OF COVER. `_entry_left` is brief invulnerability, and it
## is not generosity: the reward lands mid-firefight by definition — that is what
## a ten-kill streak IS — and a transformation whose animation can be interrupted
## by the shot that was already in the air is one that gets taken away at the
## exact moment it is given. It is short enough to be no use as a push.
const ENTRY_TIME := 1.1
const ENTRY_BLAST := 3.2

var _entry_left := 0.0
## What this body is, while it is a signature — "" for an ordinary trooper. The
## HUD reads it to name the thing on screen.
var signature_name := ""


func _signature_entry() -> void:
	_entry_left = ENTRY_TIME
	Blast.pop(get_tree().current_scene,
		global_position + Vector3.UP * 0.35, ENTRY_BLAST, 0.85)
	Audio.play_at("streak", global_position, 0.0)
	signature_changed.emit()


## The combatant contract's two answers about IDENTITY (house rule 15): what to
## call this body in the feed, and which stat row is its own. A Bot answers the
## first and refuses the second — it is freed on death, so it has nothing to
## accumulate into.
## A human is always "PLAYER N" and never the class they happen to be wearing.
## At a couch the question the feed answers is WHO, and the class is the one
## thing about a human that changes every life.
func combatant_name() -> String:
	return "PLAYER %d" % (player_index + 1)


func stat_index() -> int:
	return player_index


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
	# The class multiplies the frame, rather than replacing it: a Kinesis adept in
	# a light frame is quick and tough for both reasons, which is the point of
	# letting them wear one. All four go through Loadout so the buy screen's HP
	# line and what you deploy with are the same arithmetic — and so an authored
	# faction class can state a physique of its own (see Loadout.unit_speed).
	max_health = loadout.max_health()
	_speed_mult = loadout.move_speed()
	_jump_mult = loadout.jump_power()
	_apply_stature(loadout.stature())
	health = max_health
	_since_damage = 0.0
	# An ordinary body regenerates. `_become` turns this back off AFTER calling
	# here, exactly as it restores the streak and the taken-set — this function is
	# what a fresh DEPLOY calls, and there the answer is always yes.
	_no_regen = false
	# AND AN ORDINARY BODY IS LOOKED THROUGH, not watched. Same argument as
	# `_no_regen` directly above: `_become` turns it back on AFTER calling here,
	# because this is also what a fresh DEPLOY runs and there the answer is always
	# first person. Without the reset, dying as a Force Master and respawning as a
	# trooper would leave you playing the rest of the match over your own shoulder.
	third_person = false
	_apply_view_mode()
	# ...and it stops being a signature, which the HUD has to be told about.
	if signature_name != "":
		signature_name = ""
		signature_changed.emit()
	_entry_left = 0.0
	vehicle_owns_view = false
	# AND EVERY SUSTAINED WINDOW IS SHUT. Same argument as `_no_regen` and
	# `third_person` above — this is what a fresh DEPLOY calls, so a body must
	# never stand up still carrying the last life's ability. Two of these outlive
	# a death in a way nothing on screen would show: a RALLY left registered goes
	# on protecting a squad from a corpse, and an UNSCANNABLE flag left set makes
	# a body permanently unmarkable, both for the rest of the match.
	_clear_sustained()
	# A FRESH BODY IS AT REST. Momentum is carried in `_move_vel` now, and without
	# this a respawn inherits whatever the last life was doing when it died.
	_move_vel = Vector3.ZERO
	# ...and stands level, with the stride's phase reset. A body that deployed
	# mid-bob would arrive with its head off centre and leaning.
	_bob = Vector3.ZERO
	_bob_t = 0.0
	_bob_amp = 0.0
	_view_roll = 0.0
	_sprint_fov_t = 0.0
	# ...and it is not mid-slide, nor still paying for the last one. Without the
	# cooldown reset a body that died sliding could not slide for a second after
	# it respawned, which is a rule nobody could ever work out.
	_slide_left = 0.0
	_slide_speed = 0.0
	_slide_cd = 0.0
	_shake = 0.0
	# A FRESH BODY STANDS UP. Crouch is a toggle, so without this you deploy in
	# whatever stance the last life ended in — and the last thing most lives do
	# is get shot while crouched behind something.
	_crouched = false
	kills_this_life = 0
	# WHAT THIS LIFE CAN EARN, resolved here because this is the one function that
	# knows the build is settled — it runs on every deploy and on every BECOME.
	_refresh_streaks()
	_on_secondary = not loadout.has_primary()
	_rotary_out = false
	weapon.set_class(loadout.deploy_class(), loadout.mods_for(_on_secondary))
	_refresh_offhand()
	gadget = loadout.gadget_id()
	gadget2 = loadout.gadget2_id()
	gadget3 = loadout.gadget3_id()
	_force_cd = [0.0, 0.0, 0.0]
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
	# THE ONE PLACE THE BODY BECOMES A DIFFERENT UNIT — a redeploy, a class
	# change, a crate picked up — so it is the one place the network has to be
	# told what everyone else should now be drawing. Style, stature and weapon go
	# out; motion is already going out every tick and says nothing about which
	# unit this is.
	if Net.online() and NetSync.current != null:
		NetSync.current.send_info(NetSync.current.id_of(self))


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
		bot.reset_physics_interpolation()
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
				pending = faction_class_build()
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
		var classes := GameState.classes_for(team)
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
	var classes := GameState.classes_for(team)
	return classes[clampi(spawn_class, 0, classes.size() - 1)]


## THE BUILD THAT DEPLOYS IS THE ROW THE SCREEN SAID WAS SELECTED, and this
## function is what makes that true BY CONSTRUCTION rather than by two paths
## agreeing.
##
## They did not agree. Deploy called `Loadout.team_build(team, spawn_class)`,
## which takes a SIDE SLOT and a UNIVERSE and was being handed a TEAM NUMBER and
## no universe at all — so it read the roster out of `active_universe` at the
## team's own index. The character select next to it lists
## `GameState.classes_for(team)`, which resolves the side's real faction. The two
## only coincide while every side is the menu's default deal-out; pick a
## different faction for a side (the whole point of the row) and the screen
## offers one roster while the deploy builds from another, with no error
## anywhere. That is "I chose a roster and it loaded a different faction's".
##
## `faction_class_index()` is already the one function that resolves a selection
## into a row, and `faction_class_name()` already reads it — so the fix is for
## the BUILD to read it too. Now the name on the screen, the blurb under it and
## the body that stands up are three reads of one answer, and no future edit can
## move one without moving all three.
func faction_class_build() -> Loadout:
	return Loadout.faction_build(faction_class_index())


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
	Audio.play("ui_accept")
	buy_changed.emit(buy_row)


## Inside an open box: rows above/below, values left/right, B to come back out.
func _update_buy_open(move: Vector2i, back_edge: bool) -> void:
	if back_edge:
		buy_inside = false
		Audio.play("ui_back")
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
		Audio.play("ui_move")
		buy_changed.emit(buy_row)
	if move.x != 0 and pending.step(buy_row, move.x):
		Audio.play("ui_move")
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
	var head_min := lerpf(STAND_HEAD_MIN, CROUCH_HEAD_MIN, _crouch_t) * _stature
	return world_pos.y - global_position.y >= head_min


func _die(attacker: Node = null) -> void:
	if _dead:
		return
	# WHO KILLED ME is remembered before anything else runs, because the death cam
	# is about to need it and `_enter_buy_screen` is where the body stops being
	# able to answer. Kept as a reference AND a name: the reference drives the
	# camera while the killer is alive, the name outlives them.
	# The offer dies with the life that earned it — same rule as the streak, and
	# without it a player deploys with a prompt still on screen for a reward the
	# next life did not earn.
	if not _offer.is_empty():
		_offer = {}
		streak_offered.emit("", "")
	_killer = attacker if attacker != self else null
	_killer_name = GameState.combatant_name(attacker) if _killer != null else ""
	# NETWORKED: THE SCORE IS THE HOST'S AND ONLY THE HOST'S. A client running
	# these three lines as well would count its own death on its own machine and
	# again on the host, so the scoreboard everybody actually reads would move by
	# two. `NetSync.report_kill` carries it to the host, which runs the identical
	# GameState calls — the rules live in one place either way.
	#
	# The corpse and the announcement are separate from the score for the reason
	# stated on `announce_death`: a host-side bot needs one and not the other.
	if Net.online():
		_report_net_death(attacker)
	else:
		# Credit the frag to an enemy killer (not suicide/self or a teammate).
		if attacker is Player and attacker != self and attacker.team != team:
			GameState.add_frag(attacker.team)
			attacker.credit_kill()
		GameState.report_death(team)  # CONQUEST: a death is a reinforcement spent
		# The RECORD, not the score: this runs in every mode and for a teamkill and
		# a suicide too, which the three lines above all decline to count.
		GameState.record_kill(attacker, self, _last_hit_headshot)
		GameState.check_last_standing()
	Audio.play_at("death", global_position)
	_spawn_corpse(attacker)
	_enter_buy_screen(RESPAWN_FLOOR, true)


## Tell the session this body went down. The kill streak is credited locally when
## the killer is on this machine and over the wire when it is not — `NetPlayer`
## forwards `credit_kill` the same way it forwards `on_hit_confirmed`, so a
## player's own streak counts a remote kill exactly like a local one.
func _report_net_death(attacker: Node) -> void:
	var sync := NetSync.current
	if sync == null:
		return
	if attacker != null and attacker != self and "team" in attacker \
			and attacker.team != team and attacker.has_method("credit_kill"):
		attacker.credit_kill()
	var push := Vector3.ZERO
	if attacker is Node3D and attacker != self:
		push = global_position - (attacker as Node3D).global_position
	var id := sync.id_of(self)
	sync.announce_death(id, push)
	sync.report_kill(sync.id_of(attacker), id, team)


## Go to the buy screen. It stays up until the player presses deploy — `floor`
## is only how long the button is greyed out first. Shared by the match-start
## deploy and every death, so a build is always bought the same way.
func _enter_buy_screen(floor_secs: float, eliminated: bool) -> void:
	_dead = true
	velocity = Vector3.ZERO
	weapon.aiming = false
	# Dying at the controls: drop the mount here rather than waiting for the
	# vehicle to notice, so nothing downstream can see a dead player who is still
	# flying. The vehicle clears its own `driver` on the same frame.
	_vehicle = null
	# Dying while cloaked must not leave a ghost in GameState.cloaked that no AI
	# can ever see — the body is about to be hidden anyway.
	if _cloak_left > 0.0:
		_end_cloak()
	# ...and the same for every sustained window, for the same reason one notch
	# further out: a RALLY registered on a dead body keeps protecting its squad
	# from the grave, and it is `_apply_loadout` that would otherwise be the only
	# thing to clear it — which does not run until the player chooses to deploy.
	_clear_sustained()
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
	# The corpse wears the body you deployed as, not a generic trooper — and it
	# is FORCED past the view-range and headcount rules in corpse.gd: those exist
	# to stop a big roster carpeting the map with bodies nobody is looking at,
	# and the one body a human is certain to look at is their own.
	_corpse.launch(xform, GameState.team_colors[team], push,
		loadout.character_style(), true, _stature)


func _process_dead(delta: float) -> void:
	# The view turns onto whoever killed you WHATEVER the mode, before the Royale
	# early-out below: in the one mode with no respawn, the death cam is the only
	# screen you get.
	_track_killer(delta)
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


## Swing the dead view onto the killer. The camera hangs off Head through the
## RemoteTransform3D, so turning the body and pitching the head is all it takes —
## the same two dials a live player steers with, which is why this needs no
## second camera and no scene changes.
##
## IT TURNS RATHER THAN CUTS, and slowly (DEATH_CAM_TURN). A hard cut onto a body
## somewhere behind you tells you nothing about WHERE it is; watching the view
## sweep round is what places them on the map you just died on.
##
## It stops tracking once the killer dies or is freed, and holds the last heading
## instead of snapping back — a view that whips away the moment your killer is
## shot loses exactly the thing you were looking at.
const DEATH_CAM_TURN := 2.6      # radians/s the dead view swings at
const DEATH_CAM_HEIGHT := 1.1    # aim at the chest, not the feet


func _track_killer(delta: float) -> void:
	if _killer == null or not is_instance_valid(_killer):
		return
	if _killer.has_method("is_alive") and not _killer.is_alive():
		return
	if not _killer is Node3D:
		return
	var to: Vector3 = (_killer as Node3D).global_position \
		+ Vector3.UP * DEATH_CAM_HEIGHT - head.global_position
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05:
		return
	var step := DEATH_CAM_TURN * delta
	var want_yaw := atan2(-to.x, -to.z)
	rotation.y += clampf(wrapf(want_yaw - rotation.y, -PI, PI), -step, step)
	var want_pitch := atan2(to.y, flat)
	_look_pitch = clampf(_look_pitch + clampf(want_pitch - _look_pitch, -step, step),
		-PI / 2 + 0.05, PI / 2 - 0.05)
	_refresh_head()


## What the HUD prints on the death screen: who did it and how. Empty while
## alive, and a plain string once dead — the killer may already be freed.
func killer_line() -> String:
	if not _dead or _killer_name == "":
		return ""
	return "KILLED BY %s%s" % [_killer_name, "  •  HEADSHOT" if _last_hit_headshot else ""]


## 0..1 of the killer's health, or -1 when there is nothing to show (no killer,
## or they have since died themselves). BF2 shows you what you left them on,
## which is the difference between "outplayed" and "one more shot".
func killer_health() -> float:
	if _killer == null or not is_instance_valid(_killer):
		return -1.0
	if _killer.has_method("is_alive") and not _killer.is_alive():
		return -1.0
	var maxh: float = float(_killer.get("max_health"))
	if maxh <= 0.0:
		return -1.0
	return clampf(float(_killer.get("health")) / maxh, 0.0, 1.0)


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
	# A RESPAWN IS A TELEPORT, and with physics interpolation on (see
	# project.godot) the renderer would otherwise draw this body smeared from
	# where it died to where it just appeared, for one frame, every death.
	# Anything that MOVES a body rather than letting it walk has to say so.
	reset_physics_interpolation()
	_dead = false
	# The last life's killer goes with the last life. Held until here rather than
	# cleared on the deploy press, because the death screen is up until this line.
	_killer = null
	_killer_name = ""
	_last_hit_headshot = false
	# Your own deployment, so it is played flat rather than positioned: the point
	# of it is "you are back in", not "something happened over there".
	Audio.play("deploy")
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


## A MOUNT THAT AIMS SOMETHING OTHER THAN YOUR OWN HEAD TAKES THE LOOK DELTA,
## NOT THE ANGLES IT PRODUCED. `vehicle_look` reports the world yaw and pitch the
## body is already holding, which is right for a speeder — its gun follows the
## driver's eyes inside a cone — and exactly wrong for a turret bolted to a hull
## that turns underneath it. Differencing a free-running world yaw against a
## rotating hull means a CENTRED stick still sweeps the gun: measured on the HAMMERHEAD,
## the aim point walked 30.2 m across the ground every second while nobody
## touched anything, and the turret sat pinned against its own yaw stop.
##
## So the vehicle banks the delta here and steers whatever it is really aiming,
## then writes the camera back through `set_view_angles`. Intercepting at
## `_apply_look` catches the STICK and the MOUSE in one place, which is the only
## reason this is one flag and not two input paths.
var vehicle_owns_view := false
var _view_delta := Vector2.ZERO


## A TURRET SEAT IS AN EYE POSITION; A SADDLE IS A FOOT POSITION. Which one a
## mount is has to be stated, because the body is anchored by its FEET and the
## camera rides `head.position.y` above them.
##
## On a speeder that is right: the seat is where the driver's backside goes, the
## body stands on it and the camera ends up at head height over the cowl, looking
## out of the machine the way somebody sitting on it would.
##
## In the HAMMERHEAD's ball turret it was wrong, and it is most of why that reward was
## unusable. The seat is INSIDE a 0.92 m sphere, so anchoring the feet there put
## the camera 1.6 m above the seat — outside the ball, above the glass, floating
## in the open air beside the gunship. And because the shell is hidden from the
## gunner, there was nothing on screen to say so; it simply did not look like
## sitting in a turret, because it was not. It also broke the AIM: the gun's
## boresight runs from the muzzle, and a camera a metre and a half above that
## line does not point where the barrels point. Over the 124 m this gun shoots
## at, that offset is about three body widths of parallax — a crosshair that is
## honestly drawn and honestly wrong.
##
## With the eye on the seat instead, the camera sits 2.25 m directly behind the
## muzzle along the barrel axis and 1 cm off it: boresighted, by construction.
var seat_is_eye := false


## Where the body must be put so the anchor lands on the seat. `Vector3.ZERO`
## for an ordinary mount, so a speeder is untouched.
func seat_anchor_offset() -> Vector3:
	return Vector3.UP * head.position.y if seat_is_eye else Vector3.ZERO


## Take the look input banked since the last call, and clear it.
func take_view_delta() -> Vector2:
	var d := _view_delta
	_view_delta = Vector2.ZERO
	return d


## Point the camera where the vehicle says. Yaw and pitch only and never roll —
## the ball turret hangs off a body banked 24 degrees into its turn, and
## inheriting that would cant the gunner's horizon for the whole ride.
func set_view_angles(yaw: float, pitch: float) -> void:
	rotation.y = yaw
	_look_pitch = clampf(pitch, -PI / 2 + 0.05, PI / 2 - 0.05)
	_refresh_head()


func _apply_look(delta_look: Vector2) -> void:
	if vehicle_owns_view:
		_view_delta += delta_look
		return
	rotate_y(delta_look.x * _look_scale)
	_look_pitch = clampf(_look_pitch + delta_look.y * _look_scale,
		-PI / 2 + 0.05, PI / 2 - 0.05)
	_refresh_head()


## --- flying a vehicle ---------------------------------------------------------
##
## A mounted player keeps its own LOOK and gives up everything else. The three
## `vehicle_*` accessors below are the whole interface the Vehicle reads, which
## is what stops it reaching into this script's input helpers — it never learns
## what a binding is, and this never learns what a repulsor is.
##
## The body is hidden and its collision switched off, then slaved to the seat
## each physics frame. That reuses the death-cam's precedent (hide the body, keep
## the camera live) and it means the existing RemoteTransform3D on Head is
## untouched: the camera still follows the head, the head still follows this
## body, and this body now follows the seat.

var _vehicle: Node3D


func in_vehicle() -> bool:
	return _vehicle != null


## AM I OFF THE FIELD? True while riding a CALL-IN — the orbital station or the
## gunship's ball turret — as opposed to sitting in a speeder, which is on the
## field and can be driven anywhere.
##
## It exists for the storm, which burns a body for WHERE IT IS: a gunner the game
## has put 210 m up on a timer has not failed to move, and cannot. Duck-typed
## like every other question this project asks of a mount (house rule 15), so a
## future call-in answers it by stating one method and nothing here changes.
func off_the_field() -> bool:
	return _vehicle != null and _vehicle.has_method("is_call_in") \
		and bool(_vehicle.is_call_in())


## DRIVE THIS BODY WITH A DIFFERENT CONTROLLER.
##
## The couch case this exists for is not "the pad reconnected" — Godot usually
## hands a reconnected pad its old index back and that path needs nothing. It is
## the far more common one: the batteries died, and somebody picked up A
## DIFFERENT CONTROLLER. Without this, the new pad is an input nothing is
## listening to and the player is locked out of a match they are sitting in front
## of, holding a working controller.
##
## `input_device` is read live everywhere through `Controls.held(input_device, …)`
## so almost nothing needs telling — but the settings overlay CACHES it at build
## time (it has to; it is per-device by design), which is exactly the kind of copy
## that goes stale in silence. Hence the signal rather than a bare assignment.
##
## The new pad brings its own settings with it, and that is correct rather than a
## compromise: `Controls.bindings_for` already falls back device-own → PLAYER 1 →
## ALL_PADS, so an unconfigured spare controller inherits the house layout.
func adopt_device(new_device: int) -> void:
	if new_device == input_device:
		return
	input_device = new_device
	refresh_settings()
	device_changed.emit(new_device)


## WHAT THIS BODY IS RIDING, or null. Public so a HUD can ask what KIND of mount
## it is — a speeder and a gunship want completely different things on screen —
## without reaching into the private field to find out.
func mount() -> Node3D:
	return _vehicle


func enter_vehicle(v: Node3D) -> void:
	if _vehicle != null or _dead:
		return
	_vehicle = v
	velocity = Vector3.ZERO
	_collision.disabled = true
	model.visible = false
	# The first-person gun goes away too. The vehicle has its own, and a rifle
	# floating over the cowl is the first thing anybody would notice.
	weapon.visible = false
	weapon_off.visible = false
	weapon.update_fire(false, false)
	weapon.aiming = false
	map_open = false
	# A mount is a TELEPORT, not a walk. Without this the renderer smears the body
	# from wherever it was standing to the seat across one frame — the same rule
	# every respawn and every corpse landing follows.
	# ASKED FOR, NOT PATHED TO. A speeder's seat is a direct child; a gunship's is
	# buried inside a ball turret that yaws and pitches, and `get_node("Seat")`
	# finds neither reliably. The vehicle knows where its own seat is.
	# A MOUNT STANDS YOU UP, which is the same decision jumping, sprinting and
	# deploying already make. It matters here because the eye offset below is read
	# off the head, and `_update_crouch` — the only thing that moves the head — does
	# not run while mounted: climb into a turret from a crouch and the camera would
	# be frozen half a metre low inside a 0.92 m ball for the whole ride.
	_crouched = false
	_crouch_t = 0.0
	# Level and still: a mount owns the horizon, and the eye offset below is read
	# straight off the head, so a body carrying bob into the seat would put the
	# camera a centimetre out and rocking.
	_bob = Vector3.ZERO
	_bob_amp = 0.0
	_view_roll = 0.0
	_land_dip = 0.0
	_refresh_head()
	var seat: Node3D = v.seat() if v.has_method("seat") else v.get_node_or_null("Seat")
	if seat != null:
		global_position = seat.global_position - seat_anchor_offset()
	reset_physics_interpolation()


## Back on your feet. `forced` is a wreck or a death — the caller has already
## decided, this only places the body.
func exit_vehicle(spot: Vector3, _hull_yaw: float, forced: bool) -> void:
	if _vehicle == null:
		return
	_vehicle = null
	# The view comes back to the body whatever else happens — a dead gunner still
	# has a death cam to steer.
	vehicle_owns_view = false
	_view_delta = Vector2.ZERO
	seat_is_eye = false
	# ONLY RESTORE THE BODY IF IT IS STILL ALIVE. Dying at the controls reaches
	# here through the vehicle's own `_eject`, and `_enter_buy_screen` has already
	# hidden the model and killed the collision for the death cam — putting them
	# back would stand a live body up next to its own corpse. `_respawn` is what
	# restores those, and it always was.
	if _dead:
		return
	_collision.disabled = false
	model.visible = true
	weapon.visible = true
	weapon_off.visible = dual_active()
	global_position = spot
	velocity = Vector3.ZERO
	reset_physics_interpolation()   # a dismount is a teleport too
	if forced:
		# Thrown clear of a wreck: a little air, so you land rather than appearing.
		velocity.y = 4.0


## What the vehicle reads instead of touching this script's input helpers.
func vehicle_move() -> Vector2:
	return _move_input()


## Where the driver is looking, in WORLD yaw and local pitch. The vehicle turns
## this into a gun angle inside its own traverse cone.
func vehicle_look() -> Vector2:
	return Vector2(rotation.y, _look_pitch)


func vehicle_firing() -> bool:
	return _fire_held()


## Mounted: take the look input and nothing else. Movement, gravity and collision
## all belong to the vehicle now, and `_update_anim` is fed a standing pose so the
## model is in a sane state the frame it becomes visible again.
func _process_mounted(delta: float) -> void:
	if not GameState.match_live:
		return
	if settings_open:
		return
	pickup_pressed = _interact_pressed()   # this is how you get back off
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_tick_recoil_pattern(delta)
	_refresh_head()
	if input_device >= 0:
		var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		_apply_look(-look * STICK_LOOK_SPEED * _sens_mult * delta)
	_update_regen(delta)
	_update_reward_offer()
	_update_anim(Vector2.ZERO, false)


## The camera pitch is look input plus the transient recoil kick; recoil yaw
## rides on the head so it throws off aim without turning the whole body.
## --- THE HEAD IS ONE TRANSFORM WITH ONE OWNER ------------------------------
##
## Five different things move the camera — the crouch, the landing dip, the
## walk bob, the look and the recoil — and until this function existed three of
## them wrote `head.position.y` directly from wherever they happened to run.
## That works exactly as long as nobody adds a fourth: each writer has to know to
## SUBTRACT everything the others contribute, and the one that runs last silently
## wins. `_update_crouch` and `_apply_stature` both carried their own copy of the
## crouch-height-minus-land-dip expression for that reason, and neither knew
## about the bob.
##
## So every contributor now writes its own variable and this composes them. It is
## the same rule the model's twist joint follows (`Locomotion`): two rules on one
## transform in two places is a fight nobody wins.
func _head_base_y() -> float:
	return lerpf(STAND_HEAD_Y, CROUCH_HEAD_Y, _crouch_t) * _stature


func _refresh_head() -> void:
	head.position = Vector3(_bob.x, _head_base_y() - _land_dip + _bob.y, 0.0)
	head.rotation = Vector3(_look_pitch + _recoil_pitch, _recoil_yaw, _view_roll)


## --- WALK BOB AND THE STRAFE LEAN -------------------------------------------
##
## A BODY THAT MOVES AT A CONSTANT HEIGHT IN A DEAD-LEVEL FRAME IS A CAMERA ON
## RAILS, and that was the whole of first-person movement here. The WEAPON bobbed
## (`Viewmodel._bob_t`), so the gun rose and fell against a horizon that never
## did — which reads as the gun being loose rather than as the body walking. The
## landing dip was the only thing in the game that moved the camera off its rail,
## and it fires once per jump.
##
## THE PHASE ADVANCES WITH DISTANCE TRAVELLED, NOT WITH TIME, and that is the
## whole difference between a bob and a wobble. Stride length is roughly fixed,
## so footfalls happen every so many METRES; drive the phase off a clock and the
## bob keeps its rate while your speed changes, which is precisely the motion of
## a camera being shaken rather than a person walking. Off distance, breaking
## into a sprint speeds the footfalls up because you are covering ground faster,
## and that is free.
##
## Vertical runs at TWICE the phase and lateral at once: two footfalls per stride
## cycle, one weight transfer. That relationship is what makes it read as legs.
const BOB_PER_METRE := 1.5          # radians of phase per metre travelled
const BOB_VERT := 0.024
const BOB_SIDE := 0.020
const BOB_ROLL := 0.006             # radians, rocking with the weight transfer
## Damped hard while aiming — a braced sight picture is the one time a real body
## is deliberately holding its head still — and taken to nothing in third person,
## where the camera is a chase rig and the BODY does the walking on screen.
const BOB_AIM_DAMP := 0.22
## How fast the amplitude follows the speed. Eased rather than read straight off
## velocity, or a body clipping a wall gets a one-frame lurch.
const BOB_EASE := 6.0

## LEANING INTO A SIDESTEP. The body already turns its hips to travel sideways
## (`Locomotion.swivel_for`) and the camera did not acknowledge lateral movement
## at all. Small on purpose: past about a degree and a half this stops reading as
## weight and starts reading as a broken horizon.
const LEAN_MAX := 0.026             # radians at full lateral speed
const LEAN_EASE := 5.5

## AND THE SPEED YOU CAN SEE. A sprint that changes nothing but the number in
## `velocity` is a sprint nobody can feel; widening the frame is the oldest and
## still the clearest way to say "faster". Composed with the ADS zoom rather than
## fighting it — the two barely overlap, since you cannot aim while running.
const SPRINT_FOV_GAIN := 1.075
const SPRINT_FOV_EASE := 3.5

var _bob := Vector3.ZERO
var _bob_t := 0.0
var _bob_amp := 0.0
var _view_roll := 0.0
var _sprint_fov_t := 0.0


func _update_view_bob(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z).length()
	# THE CHASE CAMERA DOES NOT BOB. In third person the model on screen is
	# already striding, and bobbing the rig watching it is the classic way to make
	# a third-person camera unpleasant to look at.
	var want: float = clampf(flat / maxf(SPRINT_SPEED, 0.1), 0.0, 1.0) 		* (1.0 - BOB_AIM_DAMP * 0.0)
	if not is_on_floor():
		want = 0.0        # feet off the ground is the one time there is no stride
	want *= lerpf(1.0, BOB_AIM_DAMP, _ads_t)
	want *= 1.0 - _chase_t
	# NOTHING BOBS DURING A SLIDE. There are no footfalls — that is the entire
	# point of it — so a stride bob here would be the camera describing a motion
	# the body is not making, which is the fault this whole section exists about.
	if sliding():
		want = 0.0
	_bob_amp = lerpf(_bob_amp, want, clampf(delta * BOB_EASE, 0.0, 1.0))
	_bob_t += flat * delta * BOB_PER_METRE
	_bob = Vector3(
		cos(_bob_t) * BOB_SIDE * _bob_amp,
		-absf(sin(_bob_t * 2.0)) * BOB_VERT * _bob_amp,
		0.0)

	# The lean: how much of the travel is sideways, in the body's own frame.
	var side: float = global_transform.basis.x.dot(
		Vector3(velocity.x, 0.0, velocity.z))
	var want_roll: float = -clampf(side / maxf(SPRINT_SPEED, 0.1), -1.0, 1.0) 		* LEAN_MAX * (1.0 - _chase_t)
	# ...plus the stride's own rock, which is the bob expressed as roll.
	want_roll += cos(_bob_t) * BOB_ROLL * _bob_amp
	# ...and the slide leans HARD into its own direction and drops the camera,
	# on top of the crouch's own drop. It is the most violent thing the camera
	# does and it is deliberately brief.
	if sliding():
		var side_slide: float = global_transform.basis.x.dot(_slide_dir)
		want_roll = -side_slide * SLIDE_ROLL - SLIDE_ROLL * 0.35
		_bob.y -= SLIDE_DIP
	# A MOUNT OWNS THE HORIZON. The ball turret's whole point is that the gunner
	# stays level under a hull banked 24 degrees into its turn, so nothing here
	# may add roll to a view a vehicle is writing.
	if vehicle_owns_view or _vehicle != null:
		want_roll = 0.0
	_view_roll = lerpf(_view_roll, want_roll, clampf(delta * LEAN_EASE, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	# BEFORE EVERY BRANCH BELOW, because the camera has to come back in on death
	# and while mounted just as much as it has to go out on the transformation —
	# and each of those paths returns early. The entry window is ticked here for
	# the same reason: it grants invulnerability, so a path that forgot to age it
	# would grant it forever.
	_update_chase(delta)
	if _entry_left > 0.0:
		_entry_left = maxf(0.0, _entry_left - delta)
	if _dead:
		_process_dead(delta)
		return
	# FLYING. Checked before everything else, because a mounted player is not a
	# body being simulated any more: the vehicle owns the movement, the collision
	# and the gun, and this body is only carrying the head the camera hangs off.
	if _vehicle != null:
		_process_mounted(delta)
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
	_update_reward_offer()
	_update_aim(delta)
	_update_guard(delta)
	_update_crouch(delta)

	# Settle the camera recoil back toward zero, and bleed off the shot's shove.
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(delta * RECOIL_RECOVER, 0.0, 1.0))
	_tick_recoil_pattern(delta)
	_kick_vel = _kick_vel.move_toward(Vector3.ZERO, KICK_DECAY * delta)
	_refresh_head()

	if input_device >= 0:
		var look := _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		var mark := _assist_target()
		# Slowdown first, so the stick eases off as the crosshair crosses a body.
		_apply_look(-look * STICK_LOOK_SPEED * _sens_mult * _assist_slowdown(mark) * delta)
		_assist_pull(mark, look, delta)

	# Ticked BEFORE the stance is read, so a slide that ended this frame has
	# already put `_crouched` where it belongs and everything below sees one
	# answer rather than last frame's.
	_update_slide(delta)
	var move := _move_input()
	var crouching := _crouch_held()
	var sprinting := _sprint_held() and not crouching and _bulwark_left <= 0.0
	_update_stance_spread(move, crouching)
	# The SPRINT CARRY, in first person. Cancelled by the trigger: the weapon has
	# to come back up the instant you decide to shoot, or the first round of every
	# engagement leaves a gun that is visibly stowed. Sprinting already denies the
	# sights, so this only ever changes what the pose LOOKS like, never what the
	# shot does.
	_update_stow(delta)
	var speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * _speed_mult
	if _fury_left > 0.0:
		speed *= FURY_SPEED
	if _stim_left > 0.0:
		speed *= STIM_SPEED
	if _rotary_out:
		speed *= ROTARY_SPEED_MULT  # the cannon is heavy; you walk with it out
	if crouching:
		speed *= CROUCH_SPEED_MULT
	# AIMING COSTS YOU GROUND. Standing behind the sights is a decision to stop
	# being mobile, and without a price on it there is no reason ever to hip fire
	# — ADS was strictly better in every situation, which is one fewer decision
	# per engagement rather than a stronger option.
	if weapon.aiming:
		speed *= ADS_SPEED_MULT
	var dir := global_transform.basis * Vector3(move.x, 0, move.y)

	if not is_on_floor():
		velocity.y -= _gravity * delta
		# Kinesis adept can push off nothing. Setting velocity outright rather
		# than adding to it means a double jump saves you just as well on the way
		# down as at the top of the arc, which is the whole point of having one.
		if _air_jumps > 0 and _jump_pressed():
			_air_jumps -= 1
			velocity.y = JUMP_VELOCITY * _jump_mult * AIR_JUMP_MULT
	elif _jump_pressed():
		velocity.y = JUMP_VELOCITY * _jump_mult
		# A JUMP CANCELS A SLIDE, and it is the move players will look for. Ended
		# through `_end_slide` rather than by zeroing the timer, so it still pays
		# the cooldown — cancelling early must not be a way to slide more often.
		if sliding():
			_end_slide()
		# A jump stands you up. With crouch on a toggle, leaving the stance on
		# through a jump means landing in a crouch you never asked to keep, and
		# the air spread penalty is already the worst in the game.
		_crouched = false
	if is_on_floor():
		_air_jumps = air_jump_allowance()
	var unstick := _unstick_push()
	# THE SLIDE OWNS THE HORIZONTAL VELOCITY WHILE IT LASTS. `_accelerate` eases
	# `_move_vel` toward what the stick asked for; for this second the stick is
	# only allowed to curve the heading, so the two are alternatives rather than
	# both writing the same accumulator.
	if sliding():
		_drive_slide(dir, delta)
	else:
		_accelerate(dir * speed, delta)
	velocity.x = _move_vel.x + unstick.x + _kick_vel.x
	velocity.z = _move_vel.z + unstick.z + _kick_vel.z
	_apply_gadget_motion(delta)
	move_and_slide()
	# A WALL TAKES YOUR MOMENTUM. `move_and_slide` resolves the collision into
	# `velocity`, but `_move_vel` is this script's own accumulator and knows
	# nothing about it — so without folding the result back, a body held against a
	# wall keeps building speed into a surface it is not moving along and then
	# slides off it the moment you turn away.
	_move_vel.x = velocity.x - unstick.x - _kick_vel.x
	_move_vel.z = velocity.z - unstick.z - _kick_vel.z
	_update_landing(delta)
	# AFTER `move_and_slide`, deliberately: the bob is driven by how far the body
	# ACTUALLY travelled, and `velocity` before the move is what the stick asked
	# for. Walking into a wall should stop the footfalls, and read off the request
	# it would keep striding on the spot.
	_update_view_bob(delta)
	_refresh_head()
	if global_position.y > BOUNDS_MAX_Y or global_position.y < BOUNDS_MIN_Y:
		_die()  # launched or fell out of the map: respawn through the normal flow
		return

	# THE DEFLECTOR LOCKS THE TRIGGER. It is what separates the bubble from the
	# overshield: one buys you rounds, the other buys you a reposition.
	# ...AND SO DOES A STOWED WEAPON. Coming out of a sprint takes time and that
	# time is the gun's own (`_update_stow`), so the trigger does nothing until it
	# is actually up.
	if deflector_up() or not weapon_ready():
		weapon.update_fire(false, false)
	else:
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
## CROUCH IS A TOGGLE, NOT A HOLD, and on a pad that is not a preference.
##
## It lives on R3 — you press the stick you are steering with. Holding it means
## holding a thumb down on the stick for the whole of a firefight, which fights
## every other thing that thumb is doing; and crouch is not a momentary action
## like aiming, it is a STANCE you take and then fight from for a while. The
## project's own AI already treats it that way: `Bot._update_post` plants,
## crouches and holds it for `POST_TIME`.
##
## Three things stand you back up, all of them because they are the opposite
## decision: jumping, breaking into a sprint, and deploying a fresh body.
## ONE READER FOR THE CROUCH BUTTON. `_edge` is CONSUMED by whoever asks first
## (it updates `_downs` on the way out), so a second place testing the same press
## would silently get `false` — and which of the two won would depend on the order
## two unrelated functions happen to be called in. The slide and the stance toggle
## are the same press, so they are decided together, here.
func _toggle_crouch_input() -> void:
	if _edge("crouch"):
		# AT A RUN THE BUTTON MEANS SLIDE; STANDING IT MEANS CROUCH. The press
		# does not do both — a slide that also toggled the stance would leave you
		# crouched or standing at the end depending on what you were before it,
		# which is the one thing about a slide that has to be predictable.
		if _may_slide():
			_begin_slide()
		else:
			_crouched = not _crouched
	# Sprint is a declaration that you are moving, so it cancels the stance
	# rather than being silently refused by it — otherwise a player who toggled
	# crouch an hour ago holds sprint and simply does not run, with nothing on
	# screen saying why. NOT DURING A SLIDE: a slide IS sprint and crouch at once,
	# and this rule would cancel it on the frame it started.
	if _crouched and not sliding() and _sprint_held() \
			and _move_input().length() > 0.1:
		_crouched = false


## --- THE SLIDE ----------------------------------------------------------------
##
## HOLD THE CROUCH BUTTON AT A RUN AND YOU GO TO GROUND, carrying the speed you
## had into a low, fast, committed slide. It is the one piece of modern shooter
## movement this game did not have, and it is worth having for a reason beyond
## familiarity: every other way of changing what you are doing here is free and
## instant — crouch is a toggle, sprint is a modifier, the stance flips on a
## frame. A slide is the first movement decision that COMMITS you. You give up
## steering and the ability to stop, for a second, in exchange for closing ground
## fast and low. That is a trade, and it is the only one in the movement set.
##
## WHAT IT IS BUILT OUT OF, and why none of it is new machinery:
##
##   THE STANCE   `_crouch_held()` answers TRUE while sliding, so the capsule,
##                the spread multiplier, the recoil multiplier, the animation and
##                the ADS rules all follow with no second code path. That one
##                line is most of the integration, and it is why a slide is
##                automatically a small target that shoots straight.
##   THE VELOCITY `_move_vel` is written DIRECTLY rather than eased through
##                `_accelerate`, because for this second the slide owns your
##                momentum and the stick does not. The wall fold-back after
##                `move_and_slide` still applies, so sliding into cover stops you
##                exactly as walking into it does.
##   THE CAMERA   the same `_bob` / `_view_roll` the walk uses, pushed further.
##
## IT CANNOT BE CHAINED INTO A FASTER WAY TO TRAVEL, and that is the whole
## balance question — it is the thing players find within a minute of being given
## a slide. The boost is modest, it DECAYS, and `SLIDE_COOLDOWN` is long enough
## that slide-hopping across a map is measurably slower than simply sprinting it.
## `tests/movement_feel.gd` asserts that directly rather than trusting the
## arithmetic, because it is one number away from being the only way anybody
## moves.

## How much faster than a sprint the slide starts. Modest: the value of a slide
## is the LOW profile and the commitment, not the metres.
const SLIDE_BOOST := 1.5
## ...and how fast that bleeds off. Tuned with SLIDE_TIME so the slide ends by
## running out of speed at about the moment it runs out of clock, rather than
## being cut off while still moving — a slide that stops dead reads as a bug.
const SLIDE_DRAG := 7.0
const SLIDE_TIME := 0.85
## Below this it is not a slide any more, it is a crouched shuffle.
const SLIDE_MIN_SPEED := 2.2
## You cannot start one from a standstill; you have to actually be running.
const SLIDE_ENTRY_SPEED := 4.2
## How much you may curve it. Not zero — a slide you cannot aim at all is a
## slide nobody uses in a corridor — and nowhere near enough to turn.
const SLIDE_STEER := 2.6
## THE COOLDOWN IS NOT WHAT STOPS SLIDE-HOPPING — the DRAG is, and it is worth
## being clear about which, because the obvious assumption sends any future
## tuning pass at the wrong number.
##
## Measured: a slide opens at 1.48x sprint, decays, and covers 4.92 m in 0.83 s —
## an average of 5.93 m/s against a 6.0 m/s sprint. It is SPEED-NEUTRAL by
## construction, so chaining it can never out-run simply running however short
## the cooldown is; lengthening the cooldown does not move that number at all
## (checked: 1.1 and 1.4 both measure 35.1 m against 35.6 m over six seconds).
## That neutrality is the design. A slide is chosen for what it DOES — arriving
## low, under fire, and finishing in cover already crouched — and never because
## it is the faster way to cross a map. Nothing here is compulsory.
##
## What the cooldown is actually for is keeping it a DECISION rather than a
## texture: without one you are on the floor more often than on your feet.
const SLIDE_COOLDOWN := 1.1
## The camera goes lower than a crouch and leans into it. Small numbers: this is
## already the most violent thing the camera does, and the crouch's own drop is
## underneath it.
const SLIDE_DIP := 0.13
const SLIDE_ROLL := 0.055

var _slide_left := 0.0
var _slide_cd := 0.0
var _slide_speed := 0.0
var _slide_dir := Vector3.ZERO


## Is this body sliding right now? Asked by everything rather than tested against
## the timer, for the same reason `_crouch_held()` exists.
func sliding() -> bool:
	return _slide_left > 0.0


## Can this press start one? Deliberately strict: on the ground, off cooldown,
## sprint down, stick pushed, and ALREADY MOVING at a run. The speed floor is the
## one that matters — without it, tapping crouch while stationary and holding
## sprint launches you, which is a dash rather than a slide.
func _may_slide() -> bool:
	return not sliding() and _slide_cd <= 0.0 and is_on_floor() \
		and not _dead and _vehicle == null and _sprint_held() \
		and _bulwark_left <= 0.0 \
		and _move_input().length() > 0.1 \
		and Vector2(_move_vel.x, _move_vel.z).length() >= SLIDE_ENTRY_SPEED


func _begin_slide() -> void:
	var flat := Vector3(_move_vel.x, 0.0, _move_vel.z)
	if flat.length() < 0.01:
		return
	_slide_dir = flat.normalized()
	# FROM THE SPEED YOU ACTUALLY HAD, not from a constant. A slide out of a
	# heavy unit's slower sprint should be slower — the boost is a multiplier on
	# what you brought into it, so every physique keeps its own relationship to
	# everybody else's.
	_slide_speed = flat.length() * SLIDE_BOOST
	_slide_left = SLIDE_TIME
	# THE GUN COMES UP ON ITS OWN, and that is worth stating because it looks like
	# something is missing here. `_update_stow` asks `_is_running()`, which asks
	# `_crouch_held()`, which answers TRUE while sliding — so the sprint carry
	# starts lowering the moment the slide begins, through the same path a player
	# reaching for the trigger uses. Writing the stow here as well would be a
	# second rule on one value.
	Audio.play_at("slide", global_position, 0.0)


## Tick the slide, and end it for any of the four reasons it can end. Called
## before the movement drive, so `_drive_slide` below is writing into the same
## `_move_vel` the stick would otherwise have written.
func _update_slide(delta: float) -> void:
	_slide_cd = maxf(0.0, _slide_cd - delta)
	if not sliding():
		return
	_slide_left -= delta
	_slide_speed = move_toward(_slide_speed, 0.0, SLIDE_DRAG * delta)
	# A JUMP CANCELS IT, which is not a concession to the exploit — it is the
	# move players expect to exist and it costs them the rest of the slide.
	# Leaving the ground ends it for the same reason: there is nothing to slide on.
	if _slide_left <= 0.0 or _slide_speed <= SLIDE_MIN_SPEED \
			or not is_on_floor():
		_end_slide()


## WHETHER YOU STAND UP AT THE END IS WHETHER YOU ARE STILL HOLDING THE BUTTON.
## That is what makes it "hold to slide" rather than "tap to slide": ride it out
## with the button down and you finish in cover, crouched and already aiming;
## let go on the way and you come up running.
func _end_slide() -> void:
	_slide_left = 0.0
	_slide_speed = 0.0
	_slide_cd = SLIDE_COOLDOWN
	_crouched = Controls.held(input_device, "crouch")


## The slide owns the horizontal velocity while it lasts. `want` is the stick, and
## it is allowed to curve the heading rather than replace it.
func _drive_slide(want: Vector3, delta: float) -> void:
	if want.length() > 0.01:
		_slide_dir = _slide_dir.move_toward(
			want.normalized(), SLIDE_STEER * delta).normalized()
	_move_vel.x = _slide_dir.x * _slide_speed
	_move_vel.z = _slide_dir.z * _slide_speed


func _update_crouch(delta: float) -> void:
	_toggle_crouch_input()
	var target := 1.0 if _crouch_held() else 0.0
	_crouch_t = move_toward(_crouch_t, target, delta / CROUCH_TIME)
	# The head itself is composed in ONE place now (`_refresh_head`), which runs
	# after this — writing it here as well is how the crouch height, the landing
	# dip and the walk bob would start overwriting each other.
	var cap := _collision.shape as CapsuleShape3D
	cap.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t) * _stature
	_collision.position.y = cap.height * 0.5


## Become a unit of this size: the model, the capsule, the camera and the
## headshot line all scale off the ONE number, because the moment they are
## allowed to disagree you get a head you can see but cannot hit.
##
## The capsule's RADIUS is deliberately left alone. Height is what the eye
## reads and what cover has to clear; width is what the nav grid, the unstick
## loop and every doorway on every map were tuned against, and a Ursan that
## cannot fit through a gap the map says is passable is a worse bug than a
## Ursan who is slightly narrower than he looks.
func _apply_stature(scale_to: float) -> void:
	_stature = maxf(scale_to, 0.2)
	model.scale = Vector3.ONE * _stature
	var cap := _collision.shape as CapsuleShape3D
	cap.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t) * _stature
	_collision.position.y = cap.height * 0.5
	_refresh_head()


## How tall this body actually stands, in metres. Duck-typed like is_alive() —
## Bot has one too, and a shooter aiming at "the middle of that body" has to ask
## rather than assume 1.8 m.
func body_height() -> float:
	return lerpf(STAND_HEIGHT, CROUCH_HEIGHT, _crouch_t) * _stature


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
	# A RECOIL PATTERN IS SOMETHING YOU LEARN; RANDOM SPRAY IS SOMETHING YOU
	# ENDURE. This used to be `randf_range` on every shot, which means no two
	# bursts from the same gun ever climb the same way and no amount of practice
	# makes the tenth round land where you meant it to. What a shooter is
	# actually good at is memorising ONE curve per weapon and cancelling it, so
	# the pattern is deterministic in `_recoil_step` and only lightly dithered.
	#
	# Shape, in order of what the hand feels: the first rounds climb HARDEST and
	# the climb tapers as the burst settles (RECOIL_FIRST_SHOT over
	# RECOIL_SETTLE_SHOTS), and the sideways component swings on a slow, smooth
	# curve rather than jittering — so a burst walks up and leans one way, which
	# is a thing you can pull against.
	var burst := clampf(float(_recoil_step) / RECOIL_SETTLE_SHOTS, 0.0, 1.0)
	var climb := lerpf(RECOIL_FIRST_SHOT, 1.0, burst)
	_recoil_pitch += cam_recoil * steady * climb
	var swing := sin(float(_recoil_step) * RECOIL_WEAVE) * RECOIL_YAW_SHARE
	swing += randf_range(-RECOIL_YAW_JITTER, RECOIL_YAW_JITTER)
	_recoil_yaw += swing * cam_recoil * steady
	_recoil_step += 1
	_recoil_idle = 0.0
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
		# ONE DURATION FOR THE ZOOM AND THE SIGHT. Both are eased over the
		# weapon's own `ads_time()`, so the world finishes magnifying on the frame
		# the sight arrives instead of a beat either side of it.
		_ads_t = move_toward(_ads_t, 1.0 if aiming else 0.0,
			delta / maxf(0.01, ads_time()))
		# Smoothstepped rather than linear: a linear zoom reads as a machine
		# moving the camera, where a settle reads as a body bringing a weapon up.
		var eased: float = _ads_t * _ads_t * (3.0 - 2.0 * _ads_t)
		# THE SPRINT WIDENS THE FRAME. Composed into the SAME assignment as the
		# zoom rather than added afterwards, so the two can never both be writing
		# `fov` and disagree about what it should be. They barely overlap in
		# practice — you cannot aim while running — but "barely" is how a fight
		# between two writers hides until somebody changes one of them.
		_sprint_fov_t = move_toward(_sprint_fov_t, 1.0 if _is_running() else 0.0,
			delta * SPRINT_FOV_EASE)
		var hip: float = _base_fov * lerpf(1.0, SPRINT_FOV_GAIN, _sprint_fov_t)
		_camera.fov = lerpf(hip, weapon.zoom_fov(), eased)
		# Sensitivity still scales off the RESTING frame, not the sprint-widened
		# one: a sprint must not quietly change how far the stick turns you.
		_look_scale = lerpf(_base_fov, weapon.zoom_fov(), eased) / _base_fov


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
		Loadout.Gadget.BIOFOAM:
			# THE ONLY INSTANT HEAL IN THE GAME. Health regenerates on its own
			# once you break contact, so what this buys is the one moment where
			# breaking contact is not an option — and it is priced as a long
			# cooldown rather than a big number so it can never out-sustain
			# somebody who is actually shooting you.
			if health >= max_health:
				Audio.play("ui_deny")
				return
			health = minf(max_health, health + BIOFOAM_HEAL)
			_since_damage = 0.0
			health_changed.emit(health)
			_start_gadget_cd(slot, cd)
			Audio.play("pickup")
			return
		Loadout.Gadget.DEFLECTOR:
			# THE AEGIS DRONE'S BUBBLE, and the Skiri's gauntlet. It is an
			# overshield with a catch that makes it a different decision: while it
			# is up you cannot fire, so it buys you a REPOSITION or a wait, never
			# a duel you were losing.
			# Tops up rather than assigns, same reason as OVERSHIELD below — the
			# trigger lock is the trade, and it applies to whatever pool is under it.
			_over_pool = maxf(_over_pool, DEFLECTOR_POOL)
			_over_left = maxf(_over_left, DEFLECTOR_TIME)
			_deflector_left = DEFLECTOR_TIME
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -3.0)
			gear_changed.emit()
			return
		Loadout.Gadget.OVERSHIELD:
			# NEVER DOWNGRADE A POOL THAT IS ALREADY BIGGER. A streak signature
			# issues four hundred-odd points through `Streaks`, and a plain
			# assignment here would let pressing your own sustain button drop that
			# to 110 — making the strongest body in the game one button press away
			# from gutting itself, with no error and no way to tell. It TOPS UP,
			# which is also what makes slot 3 the one thing that gives ground back
			# to a body that no longer regenerates.
			_over_pool = maxf(_over_pool, OVERSHIELD_POOL)
			_over_left = maxf(_over_left, OVERSHIELD_TIME)
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -4.0)
			gear_changed.emit()
			return
		Loadout.Gadget.FURY:
			_fury_left = FURY_TIME
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -2.0)
			gear_changed.emit()
			return
		Loadout.Gadget.COOLANT:
			# The VENT is the half of this you feel: it is the only thing in the
			# game that answers a LOCKOUT, and a lockout is the moment a heavy
			# gun stops being a gun. Both hands — see `_push_heat_mult`.
			if weapon:
				weapon.vent()
			if weapon_off:
				weapon_off.vent()
			_coolant_left = COOLANT_TIME
			_push_heat_mult(COOLANT_HEAT_MULT)
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -3.0)
			gear_changed.emit()
			return
		Loadout.Gadget.BULWARK:
			_bulwark_left = BULWARK_TIME
			# Ending a slide in progress is not cosmetic: the legs ARE the
			# price, so a body that braced mid-slide would take the discount and
			# keep the thing it was supposed to cost. The SPRINT needs no such
			# line — it is derived from the button every frame, and the two
			# places that derive it both refuse while this is up.
			if sliding():
				_end_slide()
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -2.0)
			gear_changed.emit()
			return
		Loadout.Gadget.STIM:
			_stim_left = STIM_TIME
			_start_gadget_cd(slot, cd)
			Audio.play("pickup", -2.0)
			gear_changed.emit()
			return
		Loadout.Gadget.SCRAMBLER:
			# CLEARS an existing mark as well as refusing new ones. Half the
			# value of this button is being pressed BECAUSE you have just been
			# darted, and a version that only stopped the NEXT mark would do
			# nothing at exactly the moment it is reached for.
			_scrambler_left = SCRAMBLER_TIME
			GameState.set_unscannable(self, true)
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -5.0)
			gear_changed.emit()
			return
		Loadout.Gadget.RALLY:
			_rally_left = RALLY_TIME
			GameState.set_rally(self, team, RALLY_RADIUS, RALLY_RESIST)
			_start_gadget_cd(slot, cd)
			Audio.play("deploy", -1.0)
			gear_changed.emit()
			return
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
		Loadout.Gadget.KINETIC_PUSH:
			Kinesis.push(self, team)
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.KINETIC_PULL:
			# A pull that caught nobody costs a fraction of the cooldown, not the
			# whole thing: the power needs a target and missing should not take
			# the class out of the fight for seven seconds.
			var caught := Kinesis.pull(self, team)
			_start_gadget_cd(slot, cd if caught != null else cd * 0.3)
		Loadout.Gadget.ARC_STORM:
			# Opens the CHANNEL; the stream itself is poured in
			# _update_lightning_channel while the button stays down. The cooldown
			# is not charged here — it starts when the channel ENDS, so a tap that
			# found nobody costs almost nothing and a full two seconds of holding
			# costs the lot.
			_channel_left = Kinesis.CHANNEL_TIME
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
			# The same lunge Kinesis adept has, offered here as a gadget. It runs
			# on its OWN cooldown timer (_dash_cd) already, so the gadget cooldown
			# is set to match rather than double-gating it.
			_dash()
			_start_gadget_cd(slot, cd)
		Loadout.Gadget.KINETIC_LEAP:
			var launch := Kinesis.leap_velocity(self)
			velocity.y = launch.y
			# Horizontal carry rides _kick_vel for the same reason a gun's shove
			# does: movement rewrites velocity.x/z from the stick every frame.
			_kick_vel += Vector3(launch.x, 0.0, launch.z)
			_start_gadget_cd(slot, cd)


## Which gadget is on a slot. Slot 0 is the gadget control, slot 1 the grenade
## control.
func gadget_in(slot: int) -> int:
	if slot == 0:
		return gadget
	return gadget2 if slot == 1 else gadget3


## True if either slot carries this gadget — the jetpack and the cable have to
## work from whichever hand the Hunter bought them into.
##
## Compared on the ACTION, so a caller asks "do I have a jetpack" and gets the
## right answer whether the slot holds a jetpack, a jump pack or a rokkit pack.
func has_gadget(id: int) -> bool:
	return Loadout.gadget_action(gadget) == id \
		or Loadout.gadget_action(gadget2) == id \
		or Loadout.gadget_action(gadget3) == id


## Which slot holds it, or -1. Used to pick which BUTTON drives it.
func slot_of(id: int) -> int:
	if Loadout.gadget_action(gadget) == id:
		return 0
	if Loadout.gadget_action(gadget2) == id:
		return 1
	return 2 if Loadout.gadget_action(gadget3) == id else -1


## Is the button for this slot down right now? Slot 0 is the GADGET 1 control,
## slot 1 the GADGET 2 control — both ordinary rebindable bindings now.
func _slot_held(slot: int) -> bool:
	match slot:
		0: return _gadget_held()
		1: return _slot1_held()
	return Controls.held(input_device, "sustain")


## The second gadget slot's control (the `grenade` binding: G on the keyboard,
## LB on a pad by default). An ordinary rebindable control like slot 0 now — the
## old fixed LB+RB chord is gone, so each slot has its own independent binding.
func _slot1_held() -> bool:
	return Controls.held(input_device, "grenade")


## The rising edge of the slot-1 control. Uses the same per-device _edge helper
## as the other pad controls now that it is a normal binding.
func _slot1_pressed() -> bool:
	return _edge("grenade")


## SLOT 3: the sustained abilities, on the `sustain` binding — R on the keyboard,
## and on a pad the face button weapon swap used to have (swap moved to circle).
## A thing you put UP and keep is worth a face button; a chord is for things you
## use once.
func _slot2_pressed() -> bool:
	return _edge("sustain")


## THE SUSTAINED PAIR (slot 3). Both are a WINDOW rather than an effect: you put
## them up before you need them and they run on their own clock whether or not
## they did you any good, which is the whole difference between this slot and the
## two that throw things.
##
## OVERSHIELD is a second health pool that takes damage FIRST and does not
## regenerate — it is spent, not worn down, so what it buys is a fixed number of
## rounds rather than a percentage. It deliberately does not stop the damage
## flash or the hit marker: the shooter should still be told they are landing.
##
## FURY is speed, toughness and a heavier swing at once. One buff rather than
## three gadgets, because at this scale a player has to be able to say what a
## button does in four words.
const BIOFOAM_HEAL := 65.0
## The deflector: a bigger pool than the overshield and a shorter window, and it
## LOCKS THE TRIGGER — that is the whole difference between them.
const DEFLECTOR_POOL := 200.0
const DEFLECTOR_TIME := 6.0
const OVERSHIELD_POOL := 110.0
const OVERSHIELD_TIME := 8.0
const FURY_TIME := 8.0
const FURY_SPEED := 1.22
const FURY_RESIST := 0.75    # damage taken while it lasts
const FURY_MELEE := 1.35     # ...and what a swing does

## THE FOUR NEW WINDOWS, and what makes each a different DECISION rather than a
## different number. Every one of these is deliberately NOT about your own hit
## points, because four of the five that existed already were.
##
## COOLANT is the one that acts on the GUN. Heat is this game's ammunition —
## there is no reload anywhere in it — so "keep firing" had no representation in
## the catalogue at all, and the heaviest guns are exactly the ones whose pool
## runs out mid-fight. Venting on the press is most of the value; the halved
## gain is what makes it a window rather than a button.
##
## BULWARK takes your LEGS, which is the same shape of trade as the deflector
## taking your trigger, and the reason it is worth having both is that they are
## opposite: one buys a reposition you cannot shoot during, the other buys a
## stand you cannot leave. It is the objective-mode ability.
##
## STIM heals you WHILE you are being shot, which is the one thing this game's
## regeneration deliberately refuses to do (see `_update_regen`: breaking
## contact is how you recover). It is not a bigger heal than BIOFOAM, it is a
## heal on a clock that does not care about `REGEN_DELAY` — so it wins the
## fights that BIOFOAM's cooldown is too slow for and loses the ones a burst
## decides.
##
## SCRAMBLER answers a whole CATEGORY rather than a weapon: scan darts, pulse
## scans, the AUGUR, the four-kill recon streak. Being un-markable is worth
## nothing at all in a quiet minute and is worth the round in a bad one, which
## is exactly the shape a sustained ability should have. It does NOT touch line
## of sight — a scrambler is not a cloak, and anybody looking at you still sees
## you.
const COOLANT_TIME := 7.0
const COOLANT_HEAT_MULT := 0.5
const BULWARK_TIME := 9.0
const BULWARK_RESIST := 0.6
const STIM_TIME := 8.0
const STIM_SPEED := 1.15
const STIM_REGEN := 14.0     # hp/s, and it ignores REGEN_DELAY entirely
const SCRAMBLER_TIME := 10.0
## RALLY is the only one that reaches anybody else, so it is the only one with a
## RADIUS. Applied to the ally taking the hit rather than broadcast on a timer:
## a field that is asked about once per bullet costs nothing, where one that
## pushes a buff onto everybody nearby every frame is house rule 1 all over.
const RALLY_TIME := 10.0
const RALLY_RADIUS := 12.0
const RALLY_RESIST := 0.8

var _over_pool := 0.0
var _over_left := 0.0
var _fury_left := 0.0
var _deflector_left := 0.0
var _coolant_left := 0.0
var _bulwark_left := 0.0
var _stim_left := 0.0
var _scrambler_left := 0.0
var _rally_left := 0.0


func _update_sustained(delta: float) -> void:
	if _deflector_left > 0.0:
		_deflector_left = maxf(0.0, _deflector_left - delta)
		if _deflector_left <= 0.0:
			gear_changed.emit()
	if _over_left > 0.0:
		_over_left = maxf(0.0, _over_left - delta)
		if _over_left <= 0.0:
			_over_pool = 0.0
			gear_changed.emit()
	if _fury_left > 0.0:
		_fury_left = maxf(0.0, _fury_left - delta)
		if _fury_left <= 0.0:
			gear_changed.emit()
	if _coolant_left > 0.0:
		_coolant_left = maxf(0.0, _coolant_left - delta)
		# RE-PUSHED EVERY TICK rather than set once, and it is two float writes.
		# `Weapon.set_class` clears the multiplier on every rebuild — a swap, a
		# rotary toggle, a pickup — so a window set once would keep counting down
		# on the HUD while having silently stopped doing anything.
		_push_heat_mult(COOLANT_HEAT_MULT)
		if _coolant_left <= 0.0:
			_push_heat_mult(1.0)
			gear_changed.emit()
	if _bulwark_left > 0.0:
		_bulwark_left = maxf(0.0, _bulwark_left - delta)
		if _bulwark_left <= 0.0:
			gear_changed.emit()
	if _stim_left > 0.0:
		_stim_left = maxf(0.0, _stim_left - delta)
		# The heal is the ability, so it runs HERE and not in `_update_regen` —
		# that function's whole job is to refuse while `REGEN_DELAY` is unspent,
		# and teaching it an exception would put the exception in the path every
		# ordinary body walks sixty times a second.
		if health < max_health and not _no_regen:
			health = minf(health + STIM_REGEN * delta, max_health)
			health_changed.emit(health)
		if _stim_left <= 0.0:
			gear_changed.emit()
	if _scrambler_left > 0.0:
		_scrambler_left = maxf(0.0, _scrambler_left - delta)
		# Held rather than set once: a mark that lands DURING the window has to
		# be refused too, and `mark_scanned` is called from four places.
		GameState.set_unscannable(self, true)
		if _scrambler_left <= 0.0:
			GameState.set_unscannable(self, false)
			gear_changed.emit()
	if _rally_left > 0.0:
		_rally_left = maxf(0.0, _rally_left - delta)
		if _rally_left <= 0.0:
			GameState.clear_rally(self)
			gear_changed.emit()


## Shut every sustained window and give back everything registered with an
## autoload. Called by `_apply_loadout` (which is both a deploy and a respawn)
## and on death — the two that leak are the ones registered ELSEWHERE, because a
## countdown on this node dies with the body and an entry in a GameState
## dictionary does not.
func _clear_sustained() -> void:
	_over_pool = 0.0
	_over_left = 0.0
	_fury_left = 0.0
	_deflector_left = 0.0
	_coolant_left = 0.0
	_bulwark_left = 0.0
	_stim_left = 0.0
	_scrambler_left = 0.0
	_rally_left = 0.0
	_push_heat_mult(1.0)
	GameState.set_unscannable(self, false)
	GameState.clear_rally(self)


## COOLANT reaches BOTH hands. `_refresh_offhand` can put a second gun in play at
## any time, so the multiplier is pushed rather than read — a dual-wielding body
## whose off-hand never got the memo would vent one gun and cook the other.
func _push_heat_mult(mult: float) -> void:
	if weapon:
		weapon.heat_mult = mult
	if weapon_off:
		weapon_off.heat_mult = mult


## What the HUD gauge reads while one is UP, 0..1. The gauge shows a sustained
## ability draining while it runs and refilling while it recharges, which is the
## same widget doing both jobs (see AbilityGauge).
func overshield_left() -> float:
	return _over_left


func fury_left() -> float:
	return _fury_left


## WHAT A SUSTAINED ABILITY HAS LEFT, AND HOW LONG ITS WINDOW IS, asked by
## ACTION. One pair of functions rather than a `left()` per ability and a
## ternary chain in the gauge that grows with the catalogue — that chain is
## exactly how a seventh sustained ability ships with no gauge at all, reading
## as an ability that does not work.
func sustained_left(action: int) -> float:
	match action:
		Loadout.Gadget.OVERSHIELD: return _over_left
		Loadout.Gadget.FURY: return _fury_left
		Loadout.Gadget.DEFLECTOR: return _deflector_left
		Loadout.Gadget.COOLANT: return _coolant_left
		Loadout.Gadget.BULWARK: return _bulwark_left
		Loadout.Gadget.STIM: return _stim_left
		Loadout.Gadget.SCRAMBLER: return _scrambler_left
		Loadout.Gadget.RALLY: return _rally_left
	return 0.0


func sustained_time(action: int) -> float:
	match action:
		Loadout.Gadget.OVERSHIELD: return OVERSHIELD_TIME
		Loadout.Gadget.FURY: return FURY_TIME
		Loadout.Gadget.DEFLECTOR: return DEFLECTOR_TIME
		Loadout.Gadget.COOLANT: return COOLANT_TIME
		Loadout.Gadget.BULWARK: return BULWARK_TIME
		Loadout.Gadget.STIM: return STIM_TIME
		Loadout.Gadget.SCRAMBLER: return SCRAMBLER_TIME
		Loadout.Gadget.RALLY: return RALLY_TIME
	return 1.0


## True while a window that CHANGES WHAT YOU MAY DO is open. Read by the HUD so
## a player can see why the sprint they are asking for is not happening — an
## ability that silently refuses an input reads as the controller being broken.
func bulwark_up() -> bool:
	return _bulwark_left > 0.0


func fury_up() -> bool:
	return _fury_left > 0.0


## While the deflector is up the trigger is dead. Asked by the fire path rather
## than enforced by taking the weapon away, so the gun stays in hand and the
## player can see exactly what they have given up for the bubble.
func deflector_up() -> bool:
	return _deflector_left > 0.0


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
	_update_sustained(delta)
	# Tick the force powers' cooldowns, whichever slot they sit in.
	for slot in 3:
		if _force_cd[slot] <= 0.0:
			continue
		_force_cd[slot] = maxf(_force_cd[slot] - delta, 0.0)
		var left := ceili(_force_cd[slot])
		if left != _force_shown[slot]:
			_force_shown[slot] = left
			gear_changed.emit()
	# Asked of BOTH slots, not of `gadget`: a Hunter can buy the jetpack
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


## The Legion ARC's scan dart: fires from the head like the wrist rocket, so it
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
			_channel_tick = Kinesis.CHANNEL_TICK
			# One bite: resolves damage, replaces the drawn bolt, and returns
			# null on an empty cone — which drops the bolt but keeps the channel
			# open, so sweeping off a target and back on stays one press.
			_channel_arc = Kinesis.channel_bolt(
				self, team, LIGHTNING_SCENE, weapon, _channel_arc)
		return
	# Ended: released, out of time, dead, or on the map screen.
	var spent := 1.0 - clampf(_channel_left / Kinesis.CHANNEL_TIME, 0.0, 1.0)
	var cd: float = Loadout.GADGET_COOLDOWNS.get(Loadout.Gadget.ARC_STORM, 0.0)
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
	# Kinesis adept's dash costs no new binding, exactly as before.
	if _slot1_pressed():
		if gadget2 != Loadout.Gadget.NONE:
			_use_gadget(1)
		elif loadout.can_dash():
			_dash()
	# ...and slot 3, the sustained ability. No dash fallback here: an empty
	# sustained slot is a class that has nothing to put up, not a spare button.
	if _slot2_pressed() and gadget3 != Loadout.Gadget.NONE:
		_use_gadget(2)


## A BECOME REWARD DOES NOT REGENERATE, and that is the price of the pool it
## came with. Set by `_become` and cleared by every ordinary deploy.
##
## THE POOL IS A BUDGET FOR THE REST OF THE LIFE rather than a bigger version of
## the same body. A signature carries seven to eleven times a trooper's health,
## and with regeneration on top the only way to end one is to burst it down
## faster than 18 hp/s heals it — so the correct play against a Warboss becomes
## hiding until it leaves, and the correct play AS one is to break contact and
## come back whole every time. Taking regeneration off makes every point spent a
## point gone: you can win five fights on one shield and you cannot win fifty,
## and it is the only counterweight that scales with how big the pool gets.
##
## The SUSTAIN slot is deliberately left as the exception — an OVERSHIELD or an
## IRON HALO re-issues the second pool, so slot 3 is the one thing that still
## gives ground back, which is why every signature carries one.
var _no_regen := false


## Passive regeneration: once REGEN_DELAY has passed since the last hit, heal
## back to full. Replaces the health kit — you recover by breaking contact, not
## by spending a consumable.
func _update_regen(delta: float) -> void:
	_since_damage += delta
	if _no_regen or _since_damage < REGEN_DELAY or health >= max_health:
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


## The crouch STATE, which is a toggle rather than the button's own down-state —
## see `_toggle_crouch_input`. Everything that asks "is this body crouched" asks
## here, so the stance, the spread multiplier, the recoil multiplier, the capsule
## and the animation can never disagree about it.
var _crouched := false


## THE STANCE, and a SLIDE IS ONE. Answering true here is what makes the capsule
## shrink, the spread and recoil multipliers apply, the animation pick a crouched
## clip, the sprint carry drop and the sights become available — all of it,
## through the paths that already existed, from one line. Anything that asks "is
## this body crouched" goes through here, which is precisely why the slide only
## has to answer it once rather than being wired into six places.
func _crouch_held() -> bool:
	return _crouched or sliding()


func _ads_held() -> bool:
	return Controls.held(input_device, "ads")


## Actually running: the sprint control down, not crouched, and the movement
## stick pushed — so holding sprint while standing still is NOT running and does
## not deny the sights. Used to disallow ADS mid-run.
## BULWARK IS REFUSED HERE AND NOT AT THE STICK, which is the one place that
## makes the whole ability honest: `_is_running` is what the speed, the sights,
## the sprint carry, the stow timer and the slide all ask, so braced plating
## takes your legs everywhere at once rather than in whichever of those five a
## later edit remembered.
func _is_running() -> bool:
	if _bulwark_left > 0.0:
		return false
	return _sprint_held() and not _crouch_held() and _move_input().length() > 0.1


## Feed the weapons this frame's stance penalty on the spread cone: wider in the
## air, wide while moving, tight while crouched (they multiply). Both hands get
## it so a dual-wielding Hunter sprays wider on the move too.
## --- upper/lower body separation ----------------------------------------------
##
## A CharacterBody3D yawing under a look input turns the WHOLE body, feet
## included, so panning your aim while standing still pirouettes the model on the
## spot. Real bodies turn the torso first and move their feet only once they run
## out of neck, and that lag is one of the strongest cues that a thing on screen
## is a person rather than an object being rotated.
##
## So the legs get a heading of their own that the body's aim yaw is allowed to
## lead. The MODEL is counter-rotated back onto the feet and the model's own
## Twist joint puts the upper body back on the aim, which nets to: legs where the
## feet are, chest where the crosshair is. Nothing about aiming, shooting or
## collision changes — `rotation.y` is still the body's true facing and the
## weapon still fires down it.
##
## ALL OF IT LIVES IN `Locomotion` NOW, because the hip SWIVEL that replaced the
## sidestep clips writes the same joint: two rules on one transform in two files
## is a fight nobody wins. It is also how a BOT got the behaviour, which it never
## had — one used to turn its whole body, chest and all, to circle a target.


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


## Which locomotion clip a move input calls for. `move` is body-relative: x is
## strafe (+ right), y is forward/back (- forward, matching the input convention
## used throughout movement).
##
## FORWARD WINS TIES, and the band is deliberately wide (a 2:1 ratio rather than
## a 45-degree split). Walking forward at a slight angle is by far the commonest
func _update_anim(move: Vector2, sprinting: bool) -> void:
	# THE STATE MACHINE, THE STRIDE TABLE AND THE BLEND ALL LIVE IN `Locomotion`
	# NOW. They used to live here AND in Bot, in two copies that had already
	# drifted (this one paced `crouch_walk` and `guard_walk` off their own
	# strides; the bot's had neither case). `move` is not passed on: the module
	# takes the real VELOCITY and brings it into the body's frame itself, which
	# is the one step the two copies did differently.
	if _loco == null:
		return
	_loco.tick(get_physics_process_delta_time(), velocity, rotation.y,
		not is_on_floor(), _crouch_t > 0.5, guard_up(), sprinting,
		WALK_SPEED * CROUCH_SPEED_MULT, sliding())


## THE PATTERN STARTS OVER WHEN YOU COME OFF THE TRIGGER. That is what makes
## TAPPING a real technique rather than a slower way to spray: a burst of three
## fired in taps costs three first-shot climbs and no weave at all, where holding
## thirty walks the whole curve. Ticked from the same place the camera settles,
## so a mounted gunner and a walking trooper follow the same rule.
func _tick_recoil_pattern(delta: float) -> void:
	if _recoil_step == 0:
		return
	_recoil_idle += delta
	if _recoil_idle >= RECOIL_PATTERN_RESET:
		_recoil_step = 0
		_recoil_idle = 0.0


## FLINCH: being shot moves your aim.
##
## The last thing in the game with no physical answer was taking a round. A hit
## flashed the screen and moved a number, and the body holding the rifle did not
## react at all — so a duel was decided purely by who started shooting first,
## with no cost at all to being second. Flinch is what makes the first shot of an
## engagement worth something beyond its damage: it does not decide the fight,
## it makes the man being shot at work harder to win it.
##
## It rides the SAME `_recoil_pitch` / `_recoil_yaw` the gun's own kick uses, so
## it settles at `RECOIL_RECOVER` like everything else, is scaled down by
## crouching exactly as recoil is, and needs no second recovery rule. Up and to
## a random side, because a round arriving is not a pattern you can learn — this
## is the one place randomness is right, and it is why the GUN's pattern is not.
const FLINCH_PER_100 := 0.030   # radians of pitch for a hundred damage
const FLINCH_MAX := 0.055       # ...and a ceiling, so a rocket is not a blackout
const FLINCH_YAW_SHARE := 0.6


func _flinch(amount: float) -> void:
	var kick := minf(FLINCH_PER_100 * amount * 0.01, FLINCH_MAX)
	# Crouched, you are braced — the same argument CROUCH_RECOIL_MULT already
	# makes about your own gun.
	kick *= lerpf(1.0, CROUCH_RECOIL_MULT, _crouch_t)
	_recoil_pitch += kick
	_recoil_yaw += randf_range(-FLINCH_YAW_SHARE, FLINCH_YAW_SHARE) * kick


## THE LANDING DIP. A body that drops four metres and carries on at eye level is
## the single most weightless thing a first-person camera can do. The knees take
## it: the camera dips by how fast you were falling and springs back.
##
## On `head.position.y`, NOT on the pitch — a landing bends your legs, it does
## not tip your head back — and applied on top of the crouch's own head height so
## the two compose instead of fighting.
const LAND_DIP_PER_SPEED := 0.011   # metres of dip per m/s of impact
const LAND_DIP_MAX := 0.16
const LAND_DIP_RECOVER := 7.0
var _land_dip := 0.0
var _was_airborne := false


func _update_landing(delta: float) -> void:
	var airborne := not is_on_floor()
	if _was_airborne and not airborne:
		# `velocity.y` has already been zeroed by `move_and_slide` on the landing
		# frame, so the fall speed has to be the one carried IN — which is what
		# `_fall_speed` is tracking.
		_land_dip = minf(_land_dip + _fall_speed * LAND_DIP_PER_SPEED, LAND_DIP_MAX)
	_was_airborne = airborne
	_fall_speed = maxf(0.0, -velocity.y) if airborne else 0.0
	_land_dip = lerpf(_land_dip, 0.0, clampf(delta * LAND_DIP_RECOVER, 0.0, 1.0))


var _fall_speed := 0.0


## A BODY HAS MASS, AND THIS IS WHERE THE GAME MOST OBVIOUSLY DID NOT.
##
## Movement used to be `velocity.x = dir.x * speed` — the stick's direction times
## the top speed, written straight into the velocity every frame. That is an
## INSTANT change of momentum in both directions: full sprint from standing in
## one frame, and a dead stop in one frame, with a right-angle turn at full speed
## costing nothing at all. Nothing above this line in the animation code can
## rescue that; a lean, a stride and a swivel are all describing a motion that is
## not happening.
##
## So the input picks a TARGET velocity and the body moves toward it. Reaching a
## walk takes about a tenth of a second and stopping a little longer, which is
## quick enough that the controls stay sharp and slow enough that the body reads
## as something being carried rather than slid.
##
## It is also what makes `Locomotion`'s lean mean anything: acceleration used to
## be a one-frame spike of infinity followed by nothing, so a lean driven off it
## was a twitch. Now there is a real ramp under it.
const GROUND_ACCEL := 34.0     # m/s², ~0.12 s to a walk
const GROUND_STOP := 26.0      # ...and stopping takes longer than starting
## AIR CONTROL IS NOT GROUND CONTROL. The same line used to run while airborne,
## so a jump could be steered as freely as a walk and momentum meant nothing —
## you could leap forward and arrive sideways. What you keep in the air is what
## you left the ground with, plus a nudge.
const AIR_ACCEL := 7.0
var _move_vel := Vector3.ZERO


func _accelerate(want: Vector3, delta: float) -> void:
	var rate := GROUND_ACCEL
	if not is_on_floor():
		rate = AIR_ACCEL
	elif want.length_squared() < 0.01:
		rate = GROUND_STOP
	_move_vel = _move_vel.move_toward(want, rate * delta)
