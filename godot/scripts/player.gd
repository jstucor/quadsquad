class_name Player
extends CharacterBody3D
## First-person player: movement, per-player device input, health, the bought
## loadout, and the buy-screen/deploy flow.
## input_device -1 = keyboard + mouse (player 1); >= 0 = that joypad device.
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
signal gear_changed(grenades: int, medkits: int)
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
const BLOCK_COST := 0.009
const BLOCK_IDLE_DRAIN := 0.14   # pool per second just holding it up
const BLOCK_REGEN := 0.28        # pool per second once lowered
const BLOCK_RECOVER_AT := 0.35   # a broken guard cannot be raised until here
const BLOCK_ARC := deg_to_rad(105.0)  # half-angle in front that the blade covers
# The Force adept's double jump. Slightly weaker than the standing jump, so the
# second one reads as a Force-assisted correction rather than a free ladder, and
# it still scales with the armour frame like every other jump.
const AIR_JUMP_MULT := 0.9
# You deploy on a button press, not a timer. These are only the floor before the
# button goes live: long enough at match start for everyone to spec a build, and
# short enough after a death that you're never sat waiting on a decision made.
const DEPLOY_FLOOR := 5.0
const RESPAWN_FLOOR := 2.0
const GRENADE_THROW_SPEED := 13.0
const GRENADE_LOB := 0.28  # upward share of the throw, so it arcs
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
var buy_row := 0
## Kills on the CURRENT life. Reset on every deploy, so it reads as a streak
## rather than a running total.
var kills_this_life := 0
var grenades_left := 0
var medkits_left := 0
var squad: Array[Bot] = []  # the AI squadmates currently alive under this player
var gadget := Loadout.Gadget.NONE
## The Mandalorian's second gadget, driven by the GRENADE control. See
## Loadout.gadget2 for why that button rather than a new binding.
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
## Set once per physics frame from the interact control, and cleared by the
## Pickup that acts on it, so one press collects exactly one crate.
var pickup_pressed := false
## Whatever crate is currently in reach, for the HUD prompt. Pickups claim and
## release this as the player walks in and out of them.
var pickup_in_reach: Node3D
var _rotary_out := false
var _force_cd := [0.0, 0.0]   # seconds left on each gadget slot's cooldown
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
var _jet_thrusting := false
var _jet_pct := 20  # last fuel level pushed to the HUD, in 5% steps
var _look_pitch := 0.0     # head pitch from look input (recoil is added on top)
var _recoil_pitch := 0.0   # transient camera kick, settles back to 0
var _recoil_yaw := 0.0
var _kick_vel := Vector3.ZERO  # horizontal shove from the last shot, decaying
var _crouch_t := 0.0       # 0 standing .. 1 crouched
var _dead := false
var _speed_mult := 1.0     # from the armour frame: scales walk + sprint
var _jump_mult := 1.0      # from the armour frame: scales jump velocity
var _buy_latch := Vector2.ZERO  # stick/key held: one step per push, not per frame
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
@onready var model: Node3D = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	GameState.register_combatant(self)  # spawn picking skips the markers we occupy
	_anim = model.find_child("AnimationPlayer", true, false)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (1 + player_index)
	# Put this player's viewmodel on its private layer (owner-only).
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (VIEWMODEL_BIT + player_index)
	for mi in weapon_off.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << (VIEWMODEL_BIT + player_index)
	# Own copy of the capsule so crouch-resizing one player doesn't resize all.
	_collision.shape = _collision.shape.duplicate()
	weapon.shooter = self
	weapon.fired.connect(_on_weapon_fired)
	weapon_off.shooter = self
	weapon_off.fired.connect(_on_weapon_fired)
	weapon_off.visible = false
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
	# The saber guard stops what it can pay for, and tires doing it. Anything
	# left over goes through as normal — a broken guard is not a shield that
	# merely stops working, it is one that stops covering you mid-burst.
	amount = _absorb_with_guard(amount, attacker)
	if amount <= 0.0:
		return
	health -= amount
	health_changed.emit(health)
	damaged.emit(amount)
	# Tell whoever shot us that it landed. This is deliberately AFTER the
	# friendly-fire check and the health subtraction, so the hit marker only
	# ever confirms damage that was actually dealt.
	if attacker != null and attacker != self and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	if health <= 0.0:
		_die(attacker)


## How many mid-air jumps this build gets. A property of the CLASS rather than
## of the saber, so a Force adept keeps it while holding a sidearm.
func air_jump_allowance() -> int:
	return 1 if loadout.kit == Loadout.Kit.FORCE else 0


## True while the lightsaber guard is actually up: blade in hand, aim held, and
## the exhaustion pool not spent. Nothing else can block — a raised guard is the
## Force adept's answer to having no gun, not a general-purpose defence.
func guard_up() -> bool:
	return not _dead and not map_open and weapon.is_melee() \
		and _ads_held() and not _block_broken and _block > 0.0


## The exhaustion pool, 0..1, for the HUD.
func guard_level() -> float:
	return _block


func guard_broken() -> bool:
	return _block_broken


## Drain the guard while it is up, refill it while it is down, and un-break it
## once there is enough back to be worth raising.
func _update_guard(delta: float) -> void:
	if not weapon.is_melee():
		return
	var before := _block
	var was_broken := _block_broken
	if guard_up():
		_block = maxf(_block - BLOCK_IDLE_DRAIN * delta, 0.0)
		if _block <= 0.0:
			_block_broken = true
	else:
		_block = minf(_block + BLOCK_REGEN * delta, 1.0)
		if _block_broken and _block >= BLOCK_RECOVER_AT:
			_block_broken = false
	# The HUD only needs telling on a visible change; this runs every frame.
	if absf(_block - before) > 0.02 or was_broken != _block_broken:
		block_changed.emit(_block, _block_broken)


## How much of a hit the guard stops. It only covers the ARC you are facing, so
## being flanked beats it, and it pays BLOCK_COST of the pool per point stopped
## — when the pool runs dry mid-hit the remainder lands.
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
	var affordable := _block / BLOCK_COST
	var stopped := minf(amount, affordable)
	_block = maxf(_block - stopped * BLOCK_COST, 0.0)
	if _block <= 0.0:
		_block_broken = true
	block_changed.emit(_block, _block_broken)
	return amount - stopped


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
## found on the ground behaves exactly like one that was bought. Health kits and
## grenades are counted rather than swapped, and re-applying would reset them,
## so those two are added after the fact.
func collect(item: Pickup) -> void:
	var grenades := grenades_left
	var medkits := medkits_left
	var health_before := health
	pending = loadout.duplicate_loadout()
	_apply_loadout()
	# _apply_loadout refills to the build's counts; put back what we were
	# carrying and add what was on the ground.
	grenades_left = grenades
	medkits_left = medkits
	match item.kind:
		Pickup.Kind.GRENADES:
			grenades_left = mini(grenades + item.amount, Loadout.GRENADE_MAX)
		Pickup.Kind.MEDKIT:
			medkits_left = mini(medkits + item.amount, Loadout.MEDKIT_MAX)
	# A pickup is not a heal: you keep the damage you were carrying.
	health = minf(health_before, max_health)
	health_changed.emit(health)
	gear_changed.emit(grenades_left, medkits_left)
	weapon_changed.emit(_hand_name())


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


## Take on the bought build: armour stats, the gun with its upgrades fitted, and
## a fresh set of consumables. Called on every deploy, never mid-life.
func _apply_loadout() -> void:
	loadout = pending.duplicate_loadout()
	var armor := loadout.armor_stats()
	max_health = armor["health"]
	_speed_mult = armor["speed"]
	_jump_mult = armor["jump"]
	health = max_health
	grenades_left = loadout.grenades
	medkits_left = loadout.medkits
	kills_this_life = 0
	_on_secondary = not loadout.has_primary()
	_rotary_out = false
	weapon.set_class(loadout.deploy_class(), loadout.mods_for(_on_secondary))
	_refresh_offhand()
	gadget = loadout.gadget_id()
	gadget2 = loadout.gadget2_id()
	_force_cd = [0.0, 0.0]
	_air_jumps = air_jump_allowance()
	_block = 1.0
	_block_broken = false
	block_changed.emit(_block, _block_broken)
	jet_fuel = 1.0
	_cable_left = 0.0
	_hook_left = 0.0
	_cable_cd = 0.0  # a fresh life gets a fresh cable
	_vault_left = 0.0
	_clear_gadget_props()
	_muster_squad()
	gear_changed.emit(grenades_left, medkits_left)
	weapon_changed.emit(_hand_name())


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


## Buy-screen input while dead: up/down picks a row, left/right changes it, and
## the jump button deploys once the floor has elapsed. All of it rides inputs
## the player already has, so there is nothing extra to bind.
func _update_buy_input() -> void:
	var move := _buy_axis()
	if move.y != 0:
		buy_row = pending.next_row(
			wrapi(buy_row + move.y, 0, Loadout.Row.size()), move.y)
		buy_changed.emit(buy_row)
	if move.x != 0 and pending.step(buy_row, move.x):
		# Changing class rewrites the whole build, which can take the row the
		# cursor is sitting on out of existence (the grenade rows, most often).
		# Walk it forward to the next real one rather than leaving it parked on a
		# line that is no longer drawn.
		buy_row = pending.next_row(buy_row, 1)
		buy_changed.emit(buy_row)
	# The button has to be pressed, not merely held down from before you died.
	var deploy := _deploy_held()
	if deploy and not _deploy_latch and _deploy_armed:
		_respawn()
		return
	_deploy_latch = deploy


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
	buy_row = 0
	# Forget any held trigger/button: the new life starts on a fresh press.
	_buy_latch = Vector2.ZERO
	_deploy_latch = true  # released-then-pressed, so a held jump can't deploy
	_downs.clear()
	_deploy_wait = floor_secs
	_deploy_armed = false
	died.emit(eliminated)
	buy_changed.emit(buy_row)


func _spawn_corpse(attacker: Node) -> void:
	_corpse = CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(_corpse)
	var push := Vector3.ZERO  # shove away from the shooter
	if attacker is Node3D and attacker != self:
		push = global_position - (attacker as Node3D).global_position
	var xform := Transform3D(Basis(Vector3.UP, rotation.y), global_position)
	_corpse.launch(xform, GameState.TEAM_COLORS[team], push)


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
	_update_buy_input()


func _respawn() -> void:
	# Place the body BEFORE clearing _dead: while we still read as dead, the
	# spawn picker skips us, so we don't treat the body we just left as an
	# obstacle and shove ourselves off our own marker.
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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(Vector2(-event.relative.x, -event.relative.y) * MOUSE_SENS)
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
	if _map_pressed():
		_toggle_map()
	if map_open:
		_process_map(delta)
		return
	pickup_pressed = _interact_pressed()
	_update_gear()
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
		_apply_look(-look * STICK_LOOK_SPEED * _assist_slowdown(mark) * delta)
		_assist_pull(mark, look, delta)

	var move := _move_input()
	var crouching := _crouch_held()
	var sprinting := _sprint_held() and not crouching
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
	return lerpf(1.0, ASSIST_SLOW, _assist_closeness(target))


## Nudge the view toward the target, in proportion to how centred it already is
## and only while the stick is actually being moved. Applied straight to the
## body yaw and head pitch rather than through _apply_look, so zooming does not
## quietly scale the assist down at exactly the moment you want it most.
func _assist_pull(target: Node3D, stick: Vector2, delta: float) -> void:
	if target == null or stick.length() < ASSIST_STICK_DEADZONE:
		return
	var eye := head.global_position
	var to: Vector3 = target.global_position + Vector3.UP * ASSIST_AIM_HEIGHT - eye
	var step := ASSIST_PULL * _assist_closeness(target) * delta
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
	var aiming := _ads_held() and not dual_active() and not shield_up() \
		and not weapon.is_melee()
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
	weapon_changed.emit(_hand_name())


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


## The gadget button. Toggles (shield, rotary) and one-shots (cable, turret) act
## on the press; the jetpack burns while held, in _apply_gadget_motion.
func _use_gadget(slot: int) -> void:
	var id := gadget_in(slot)
	# The force powers are the only gadgets on a cooldown of their own; the rest
	# are toggles, placements, or (the cable) time themselves.
	var cd: float = Loadout.GADGET_COOLDOWNS.get(id, 0.0)
	if cd > 0.0 and _force_cd[slot] > 0.0:
		return
	match id:
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
func has_gadget(id: int) -> bool:
	return gadget == id or gadget2 == id


## Which slot holds it, or -1. Used to pick which BUTTON drives it.
func slot_of(id: int) -> int:
	if gadget == id:
		return 0
	return 1 if gadget2 == id else -1


## Is the button for this slot down right now?
func _slot_held(slot: int) -> bool:
	return _gadget_held() if slot == 0 else Controls.held(input_device, "grenade")


func _start_gadget_cd(slot: int, seconds: float) -> void:
	_force_cd[slot] = seconds
	gear_changed.emit(grenades_left, medkits_left)


## Seconds until the gadget on `slot` can be used again, 0 when it is ready.
func gadget_cooldown(slot: int) -> float:
	return _force_cd[slot]


## Velocity the gadget imposes, applied after normal movement so it wins: the
## jetpack overrides gravity while thrusting, the cable overrides steering while
## reeling you in.
func _apply_gadget_motion(delta: float) -> void:
	# Tick the force powers' cooldowns, whichever slot they sit in.
	for slot in 2:
		if _force_cd[slot] <= 0.0:
			continue
		_force_cd[slot] = maxf(_force_cd[slot] - delta, 0.0)
		var left := ceili(_force_cd[slot])
		if left != _force_shown[slot]:
			_force_shown[slot] = left
			gear_changed.emit(grenades_left, medkits_left)
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
			gear_changed.emit(grenades_left, medkits_left)
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
		gear_changed.emit(grenades_left, medkits_left)


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
	gear_changed.emit(grenades_left, medkits_left)


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
	_shield.setup(GameState.TEAM_COLORS[team])


## Swap to the spin-up rotary cannon (and back). Carrying it slows you down.
func _toggle_rotary() -> void:
	_rotary_out = not _rotary_out
	if _rotary_out:
		weapon.set_class(Weapon.Class.ROTARY, loadout.primary_mods())
	else:
		weapon.set_class(loadout.secondary_class() if _on_secondary
			else loadout.weapon_class() as Weapon.Class, loadout.mods_for(_on_secondary))
	_refresh_offhand()
	weapon_changed.emit(_hand_name())


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
	# The grenade control drives the second gadget for whoever carries one. No
	# kit has both, so the two never contend: the class with two gadget slots is
	# exactly the class with no grenades.
	if _grenade_pressed():
		if gadget2 != Loadout.Gadget.NONE:
			_use_gadget(1)
		elif grenades_left > 0:
			grenades_left -= 1
			_throw_grenade()
			gear_changed.emit(grenades_left, medkits_left)
	if _medkit_pressed() and medkits_left > 0 and health < max_health:
		medkits_left -= 1
		health = minf(health + Loadout.MEDKIT_HEAL, max_health)
		health_changed.emit(health)
		gear_changed.emit(grenades_left, medkits_left)


func _throw_grenade() -> void:
	var grenade := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(grenade)
	# Thrown from the camera, along the look direction with an upward share so it
	# arcs instead of firing flat.
	var aim := -head.global_transform.basis.z
	var toss := (aim + Vector3.UP * GRENADE_LOB).normalized() * GRENADE_THROW_SPEED
	grenade.launch(head.global_position + aim * 0.6, toss + velocity, self,
		loadout.grenade_type)


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


func _gadget_held() -> bool:
	return Controls.held(input_device, "gadget")


func _fire_pressed() -> bool:
	return _edge("fire")


func _grenade_pressed() -> bool:
	return _edge("grenade")


func _medkit_pressed() -> bool:
	return _edge("medkit")


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
	var target: String
	if not is_on_floor():
		target = "jump"
	elif _crouch_t > 0.5:
		target = "crouch_walk" if move.length() > 0.1 else "crouch_idle"
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
		_:
			_anim.speed_scale = 1.0
