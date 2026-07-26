class_name Bot
extends CharacterBody3D
## An AI squadmate, bought on the buy screen and fighting for its owner's team.
##
## Deliberately duck-typed against Player rather than sharing a base class: the
## rest of the game only ever asks a combatant for take_damage / is_headshot /
## is_alive / team, and hitscan already resolves targets by has_method. That
## keeps Player free of AI plumbing and this file readable on its own.
##
## Behaviour is a three-state loop run on the physics tick:
##   HOLD    - no target: fall in behind the owner, or hold ground if they're
##             dead, so a squad doesn't wander off alone.
##   ADVANCE - target seen but too far: close to engagement range.
##   ENGAGE  - target in range and in sight: face it and fire.
## Skill (bought per head) sets how fast it reacts, how far it sees, how well it
## shoots and what it carries — see SKILLS, indexed by Loadout.SQUAD_SKILLS.

const CORPSE_SCENE := preload("res://scenes/fx/corpse.tscn")
const GRENADE_SCENE := preload("res://scenes/fx/grenade.tscn")
const TURRET_SCENE := preload("res://scenes/actors/turret.tscn")
const MORTAR_SCENE := preload("res://scenes/actors/mortar.tscn")
const SHIELD_SCENE := preload("res://scenes/fx/front_shield.tscn")
const CABLE_WIRE_SCENE := preload("res://scenes/fx/cable_wire.tscn")
const LIGHTNING_SCENE := preload("res://scenes/fx/lightning_arc.tscn")
const ROCKET_SCENE := preload("res://scenes/fx/rocket.tscn")

# One row per Loadout.SQUAD_SKILLS tier, same order.
# aim_error = degrees of aim wobble (the bot's "spread" on top of the weapon's);
# reaction = seconds staring at a new target before it opens fire;
# sight = metres it can acquire from; hold = the CLOSEST it will settle to fight
#   at — a floor, not the answer, since _hold_range works the real stand-off out
#   of the gun in its hands (see _hit_reach).
# ads = whether it aims down sights, trading nothing (a bot has no camera to
#   zoom) for the weapon's tight ads_spread instead of its hip cone — the same
#   accuracy a human buys by aiming. Only the top tiers know to do it.
# lead = whether it compensates for its own aim lag against a moving target.
#   Fire is hitscan, so this is not projectile lead: the head LERPS toward where
#   the target is, so against anything strafing it is always shooting a fraction
#   of a second behind. Harmless at ten metres, a clean miss at fifty, which is
#   why it belongs to the tiers that fight at fifty.
#
# Skill is intelligence, NOT gear: two bots on the same preset differ only in
# how well they fight it. The gun, armour and gadget come from a Loadout preset
# (Loadout.BOT_BUILDS), so a firefight has marksmen and engineers in it instead
# of a dozen identical riflemen. `health` and `speed` below are multipliers on
# whatever the preset's armour gives.
const SKILLS: Array[Dictionary] = [
	{"aim_error": 7.0, "reaction": 0.7, "sight": 45.0, "hold": 14.0,
		"health": 0.85, "speed": 0.92, "turn": 2.8, "ads": false, "lead": false},
	{"aim_error": 3.6, "reaction": 0.45, "sight": 62.0, "hold": 16.0,
		"health": 1.0, "speed": 1.0, "turn": 3.8, "ads": false, "lead": false},
	{"aim_error": 1.8, "reaction": 0.26, "sight": 80.0, "hold": 20.0,
		"health": 1.1, "speed": 1.08, "turn": 5.0, "ads": true, "lead": true},
	{"aim_error": 0.7, "reaction": 0.12, "sight": 105.0, "hold": 24.0,
		"health": 1.25, "speed": 1.15, "turn": 6.4, "ads": true, "lead": true},
]
# --- shooting at distance ------------------------------------------------------
#
# How wide a target is worth aiming at: half a body, so a shot inside this many
# metres of centre at the target's range is a hit. It is the one number the
# engagement-range arithmetic needs (see _hit_reach).
const TARGET_HALF_WIDTH := 0.45
# A cap on the derived stand-off. Past this the sight lines on these maps are
# the limit anyway, and a bot that parks at 120 m stops taking part in the match.
const HOLD_RANGE_MAX := 70.0
# How far past its reliable reach a bot will still take the shot. Fire out there
# is not free damage, it is pressure — and a marksman who refuses every shot it
# is not certain of never fires at all.
const LONG_SHOT_SLACK := 1.5
# Optics spot further, and only the tiers that know to raise them get it.
const SCOPE_SIGHT_MULT := 1.35
# Roughly the lag in _aim_head's lerp, which is what `lead` compensates for.
const AIM_LAG := 0.14
# Raising the sights steadies the bot's own wobble, not just the gun's cone.
# Without it "aiming" bought an AI nothing but a narrower spread around an
# aim that was still 1.8 degrees off, which at forty metres is over a metre
# wide on its own — the tighter cone had nothing to be tight about.
const ADS_STEADY := 0.7
# Beyond this, a bot fighting at range stops circling and takes the shot from a
# stop. Strafing is what stops it being a free headshot at ten metres; at fifty
# it only costs accuracy, and there is nothing to dodge that far out.
const LONG_RANGE_STILL := 28.0
const LONG_RANGE_STRAFE := 0.25   # share of the usual circling kept out there
const BASE_SPEED := 4.0        # walking pace before armour and skill scale it
# Gadget habits. Kept deliberately simple: a bot uses what it bought when the
# obvious moment arrives, rather than planning.
const GRENADE_RANGE := Vector2(9.0, 26.0)   # too close and it kills itself
const GRENADE_COOLDOWN := 6.0
const TURRET_PLACE_GAP := 12.0  # drop it once we're near where we're heading
# Mortar habits. A bot cannot read a map, so its knowledge gate is its own
# target: it only ever shells somewhere it has actually seen an enemy. The
# minimum range is what keeps it INDIRECT fire — anything closer is the gun's
# job, and lobbing shells onto your own position is not a tactic.
const MORTAR_PLACE_GAP := 12.0
const MORTAR_MIN_RANGE := 15.0
const MORTAR_CLUSTER := 9.0   # enemies this close to the mark get aimed between
# How often a bot moves its barrage. The tube shells a mark indefinitely, so
# without this the bot would re-aim every physics frame and the barrage would
# track a running target perfectly — which removes the whole counterplay of
# walking out from under it.
#
# Derived from the tube's FULL cycle, not just its burst: re-aiming restarts the
# burst, so a bot re-aiming every BURST_TIME landed in the middle of every rest
# phase and cancelled it — the AI mortar fired continuously and never rested at
# all. Measured 1499 damage on a stationary target in 16s before this, against
# ~1000 the cycle can actually produce.
const MORTAR_REAIM := Mortar.BURST_TIME + Mortar.REST_TIME
const CABLE_COOLDOWN := 6.0
const CABLE_MIN_GOAL := 22.0   # only worth grappling toward something far off
const CABLE_SPEED := 17.0
const CABLE_PULL_TIME := 0.9

const RETARGET_INTERVAL := 0.35  # seconds between target searches (staggered)
# With nothing to shoot, a bot pushes for the middle of the map rather than
# standing on its spawn. Team AI have no owner to follow, so without this they
# never move at all and a match with few humans looks broken.
const ROAM_SPREAD := 16.0    # how far around the middle they'll pick a spot
const ROAM_REPICK := 7.0     # seconds before choosing somewhere new
const ROAM_ARRIVE := 3.5
const FOLLOW_DISTANCE := 5.0 # how close a squadmate tucks in behind its owner
# How far a BOUGHT squadmate will stray from the player who paid for it. Without
# a leash a squad fights its way across the map the moment anything walks into
# view and never comes back, which is the opposite of what you bought: they are
# meant to go where you go. Team AI (no owner) are unaffected and still push the
# map on their own.
const LEASH := 14.0
# Sight lines flicker constantly in a firefight — a teammate crosses, the bot
# strafes behind a trunk. Without memory the bot would drop its target, spin
# back toward its owner, then re-acquire and restart its reaction timer, and so
# never actually shoot. It keeps chasing a target it briefly cannot see.
const TARGET_MEMORY := 1.5
const FIRE_CONE_DEG := 12.0      # must be facing this close to shoot
# Trigger discipline. Holding the trigger down forever just overheats the gun
# and locks it out for longer than the pause would have cost — without this a
# recruit's low-heat pistol out-damages a veteran's rifle, which is backwards.
const FIRE_HEAT_CEILING := 0.7
const STRAFE_SPEED := 0.45       # share of speed used to circle at hold range
const UNSTICK_RADIUS := 0.8      # matches Player: never let capsules stack
const UNSTICK_SPEED := 5.0
const EYE_HEIGHT := 1.5
const TARGET_AIM_HEIGHT := 1.0  # aim at the chest, not the feet
const AIM_REROLL := 0.25  # seconds a given aim error is held for
# Recoil applies to bots too, or raising it across the board would just be a
# one-sided nerf to the humans. It's added straight onto the head, and _aim_head
# lerping back toward the target IS the recovery — so a bot holding the trigger
# climbs off its mark exactly like a player does. Scaled down a little because
# that lerp is slower than the player's RECOIL_RECOVER and a bot can't pull
# down against the climb the way a player can.
const RECOIL_TAKE := 0.75
const RECOIL_YAW_SHARE := 0.5  # sideways lean per shot, as a share of the pitch

enum State { HOLD, ADVANCE, ENGAGE }

var team: int = GameState.Team.REPUBLIC
var owner_player: Node3D          # who paid for it; the bot falls in behind them
var health := 90.0
var loadout: Loadout              # the preset it deployed with
## Bots act on the FIRST gadget slot only. The Mandalorian preset carries a
## second one it never uses, which costs it nothing it would otherwise have.
var _force_cd := 0.0
## The lightning channel: seconds of stream left, time to the next bite, and the
## bolt currently drawn. `_tick_delta` is this frame's delta, stashed because the
## channel is advanced from inside the engage branch.
var _channel_left := 0.0
var _channel_tick := 0.0
var _channel_arc: Node3D
var _tick_delta := 0.0
var _shove := Vector3.ZERO        # decaying push from someone else's Force power
var _path := PackedVector2Array()
var _path_i := 0
var _path_goal := Vector3.ZERO
var _repath_cd := 0.0
var _stuck_for := 0.0
var _sidestep_left := 0.0
var _sidestep := Vector3.ZERO

var _skill: Dictionary = SKILLS[1]
var _state: int = State.HOLD
var _target: Node3D
var _retarget_in := 0.0
var _reaction_left := 0.0
var _memory_left := 0.0  # grace left on a target we've lost sight of
var _aim_offset := Vector2.ZERO  # held aim error (yaw, pitch) in radians
var _aim_reroll_in := 0.0
var _roam_target := Vector3.ZERO
var _roam_left := 0.0
var _speed := 4.0
var _since_damage := 0.0  # for passive regen, like the player
var _grenade_cd := 0.0
var _cable_cd := 0.0
var _cable_left := 0.0
var _cable_anchor := Vector3.ZERO
var _cable_wire: Node3D      # the visible line, while one is out
var _turret: Node3D
var _mortar: Node3D
var _mortar_reaim := 0.0   # seconds until it may move its barrage again
var _shield: Node3D
var _strafe_dir := 1.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _dead := false

@onready var head: Node3D = $Head
@onready var weapon: Weapon = $Head/Weapon
@onready var model: CharacterModel = $Model
@onready var _collision: CollisionShape3D = $CollisionShape3D


const SHOVE_DECAY := 22.0   # m/s of shove bled off per second, as Player's kick

# --- routing (see _route) ---------------------------------------------------
const REPATH_INTERVAL := 0.7   # seconds between plans while the goal holds still
const GOAL_DRIFT := 3.5        # ...or sooner, if the goal has moved this far
const WAYPOINT_REACH := 1.6    # close enough; move on to the next one
const SMOOTH_LOOKAHEAD := 4    # waypoints to try to skip straight to
# A bot that is trying to walk and is not moving has snagged on something the
# grid does not know about (another body, a prop, a lip in the terrain). Give it
# a moment, then send it sideways rather than letting it grind.
const STUCK_SPEED := 0.6       # m/s below which "trying to move" counts as stuck
const STUCK_TIME := 0.5
const SIDESTEP_TIME := 0.6


func _ready() -> void:
	GameState.register_combatant(self)
	# Own capsule instance, so one bot's shape isn't shared with every other.
	_collision.shape = _collision.shape.duplicate()
	weapon.shooter = self
	weapon.fired.connect(_on_weapon_fired)
	# Stagger the search so a squad of four doesn't retarget on the same frame.
	_retarget_in = randf() * RETARGET_INTERVAL
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0


func _exit_tree() -> void:
	GameState.unregister_combatant(self)


## Called by the owner right after spawning it. `build` picks which preset it
## deploys with; -1 rolls one at random, which is what a team fill wants.
func setup(owner: Node3D, bot_team: int, skill_index: int, build := -1) -> void:
	owner_player = owner
	team = bot_team
	_skill = SKILLS[clampi(skill_index, 0, SKILLS.size() - 1)]
	# On FACTION classes a bot fields its SIDE's roster rather than the generic
	# trooper presets: Republic bots are clones, Separatist bots are droids.
	# `build` is the class slot (team_build wraps it into the team's four), so
	# Main dealing the counter out in order still fields a mix of the faction's
	# classes. Keyed to the class SETTING, not to Conquest, so faction bots turn
	# up wherever faction humans do.
	if GameState.faction_classes():
		loadout = Loadout.team_build(bot_team, build if build >= 0 else randi())
	else:
		loadout = Loadout.bot_build(build if build >= 0 else randi())
	var armor := loadout.armor_stats()
	health = loadout.max_health() * float(_skill["health"])
	# The class multiplies the frame here exactly as it does on a Player, so an
	# AI Force adept closes ground as fast as a human one.
	_speed = BASE_SPEED * float(armor["speed"]) * float(_skill["speed"]) \
		* loadout.kit_speed()
	_since_damage = 0.0
	model.set_style(loadout.character_style())   # clone, droid, Wookiee... per build
	model.set_team_color(GameState.TEAM_COLORS[team])
	weapon.set_class(loadout.deploy_class(), loadout.primary_mods())
	# Show the blade on the body, not just in the hitscan: a saber bot that walks
	# in holding a blaster gives no warning at all that it intends to reach you.
	model.set_melee(weapon.is_melee(), weapon.is_staff())
	if loadout.gadget == Loadout.Gadget.SHIELD:
		_raise_shield()
	# The bot's gun is a world object, not a viewmodel: everyone should see it.
	for mi in weapon.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1


func is_alive() -> bool:
	return not _dead


## Same contract as Player: hitscan and splash both find this by method name.
func is_headshot(world_pos: Vector3) -> bool:
	return world_pos.y - global_position.y >= 1.42


func take_damage(amount: float, attacker: Node = null, headshot := false) -> void:
	if _dead:
		return
	if attacker != null and "team" in attacker and attacker.team == team:
		return  # friendly fire is off for bots too
	health -= amount
	_since_damage = 0.0  # a hit restarts the regen delay
	# Same contract as Player: confirm the hit back to whoever landed it, only
	# once the damage is real.
	if attacker != null and attacker.has_method("on_hit_confirmed"):
		attacker.on_hit_confirmed(headshot, health <= 0.0)
	if health <= 0.0:
		_die(attacker)


func _die(attacker: Node) -> void:
	_dead = true
	if attacker != null and "team" in attacker and attacker.team != team:
		GameState.add_frag(attacker.team)
		if attacker.has_method("credit_kill"):
			attacker.credit_kill()
	GameState.report_death(team)  # CONQUEST: an AI death spends a reinforcement too
	var corpse := CORPSE_SCENE.instantiate()
	get_tree().current_scene.add_child(corpse)
	var push := Vector3.ZERO
	if attacker is Node3D:
		push = global_position - (attacker as Node3D).global_position
	corpse.launch(Transform3D(Basis(Vector3.UP, rotation.y), global_position),
		GameState.TEAM_COLORS[team], push,
		loadout.character_style() if loadout != null else -1)
	if is_instance_valid(_turret):
		_turret.queue_free()  # the engineer's turret dies with the engineer
	if is_instance_valid(_mortar):
		_mortar.queue_free()  # ...and so does the tube
	GameState.check_last_standing()
	queue_free()  # bots don't respawn; the owner re-buys them on their next deploy


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not GameState.match_live:
		weapon.update_fire(false, false)  # hold until the match is called on
		return
	_grenade_cd = maxf(_grenade_cd - delta, 0.0)
	_regen_if_calm(delta)
	_cable_cd = maxf(_cable_cd - delta, 0.0)
	_force_cd = maxf(_force_cd - delta, 0.0)
	# The channel is ticked from _throw_lightning_if_in_reach, which runs inside
	# the engage branch and so has no delta of its own to hand it.
	_tick_delta = delta
	_retarget_in -= delta
	_memory_left = maxf(_memory_left - delta, 0.0)
	if _retarget_in <= 0.0:
		_retarget_in = RETARGET_INTERVAL
		_acquire_target()

	if is_instance_valid(_target) and _target.is_alive():
		_fight(delta)
	else:
		_target = null
		_state = State.HOLD
		weapon.aiming = false  # lower the sights when there's nothing to shoot
		_patrol(delta)

	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _cable_left > 0.0:
		# Being reeled in by our own grapple: that overrides normal steering.
		_cable_left -= delta
		var to_anchor := _cable_anchor - global_position
		# Reel the wire back in the moment the pull ends — on arrival OR when the
		# timer runs out — or the cosmetic line hangs in the world forever. Player
		# does the same in _apply_gadget_motion; a Bot never released it, so a bot
		# that ever grappled left a permanent wire stuck across the map.
		if to_anchor.length() <= 2.5 or _cable_left <= 0.0:
			_cable_left = 0.0
			if is_instance_valid(_cable_wire):
				_cable_wire.release()
			_cable_wire = null
		else:
			velocity = to_anchor.normalized() * CABLE_SPEED
	# An outside shove (a Force push or pull) rides its own decaying velocity and
	# is added LAST, after everything above has written velocity for the frame.
	# A bot rewrites velocity.x/z every physics tick, so anything added earlier
	# is gone before it moves — the same trap as a gun's kick_back on a Player.
	if _shove.length_squared() > 0.0001:
		velocity.x += _shove.x
		velocity.z += _shove.z
		if _shove.y > 0.0:
			velocity.y = maxf(velocity.y, _shove.y)
			_shove.y = 0.0
		_shove = _shove.move_toward(Vector3.ZERO, SHOVE_DECAY * delta)
	move_and_slide()
	_animate()


## Nearest living enemy that's within sight and actually visible. Bots ignore
## anything behind cover, so they don't shoot through the map.
func _acquire_target() -> void:
	var best: Node3D = null
	var best_gap := _sight_range()
	for c in GameState.combatants:
		if c == self or not c.is_alive() or c.team == team:
			continue
		# A squadmate only takes on what is threatening its owner. Picking
		# targets by ITS own sight range is what sent squads wandering off.
		if _leashed() and owner_player.global_position.distance_to(c.global_position) > LEASH:
			continue
		var gap := global_position.distance_to(c.global_position)
		if gap < best_gap and _can_see(c):
			best_gap = gap
			best = c
	if best == null:
		# Nothing visible: hang onto the last one for a moment before giving up.
		if _memory_left > 0.0 and is_instance_valid(_target) and _target.is_alive():
			return
		_target = null
		return
	_memory_left = TARGET_MEMORY
	if best == _target:
		return
	_target = best
	# Only a genuinely NEW target costs reaction time; re-spotting the one we
	# were already fighting does not.
	_reaction_left = _skill["reaction"]


## How far this bot picks targets up from. A scope is magnification, so a bot
## that knows to raise one spots further through it — which is what stops a
## sniper bot standing at the stand-off its own rifle earned it (see
## _hold_range) with nothing acquired to shoot at.
func _sight_range() -> float:
	var see := float(_skill["sight"])
	if _skill["ads"] and weapon.has_scope():
		see *= SCOPE_SIGHT_MULT
	return see


## How far away this bot can shoot and still expect to land it.
##
## Derived, not tabled, because it is the same arithmetic for every gun and
## every tier: a shot connects while the total angular error keeps it inside a
## body's width at that range. The error is the tier's own wobble — a HELD
## offset drawn uniformly across +/- aim_error, so half of it on average — plus
## whatever cone the gun leaves with in the stance this bot will actually shoot
## from.
##
## The point of computing it is that RANGE then falls out of SKILL instead of
## being a flat number per tier: an elite behind a scoped rifle works out a
## stand-off around seventy metres, the same elite holding a scattergun works out
## eleven, and a recruit spraying a repeater works out ten and has to walk in.
func _hit_reach() -> float:
	var wobble := _aim_error_deg(_skill["ads"]) * 0.5
	var cone: float = weapon.aimed_spread_deg() if _skill["ads"] else weapon.hip_spread_deg()
	return TARGET_HALF_WIDTH / tan(deg_to_rad(maxf(wobble + cone, 0.02)))


## The tier's aim wobble, steadied while the sights are up. Both _hit_reach and
## _aim_head go through this, so the range a bot works out for itself and the
## aim it actually shoots with can never drift apart.
func _aim_error_deg(aimed: bool) -> float:
	return float(_skill["aim_error"]) * (ADS_STEADY if aimed else 1.0)


## The distance this bot tries to fight at.
##
## The tier's own `hold` is a FLOOR: nothing closes further than it used to, but
## a bot carrying a weapon it can hit with from further out now backs that and
## stays there rather than walking into everyone else's effective range. Still
## capped by what the weapon can physically reach, which is what keeps a saber
## bot closing to arm's length.
func _hold_range() -> float:
	return minf(maxf(float(_skill["hold"]), _hit_reach()),
		minf(weapon.max_range() * 0.8, HOLD_RANGE_MAX))


func _can_see(other: Node3D) -> bool:
	# A cloaked target is invisible to AI outright — the same idea as smoke, one
	# body instead of an area. This is what the Trandoshan's cloak buys.
	if GameState.is_cloaked(other):
		return false
	var from := global_position + Vector3.UP * EYE_HEIGHT
	var to := other.global_position + Vector3.UP * EYE_HEIGHT * 0.6
	# Smoke has no collider (it would stop bullets too), so it is checked
	# separately — this is what makes a smoke grenade break an AI's lock.
	if GameState.sight_blocked(from, to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 0b11  # world + bodies
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == other


func _fight(delta: float) -> void:
	var to_target := _target.global_position - global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var gap := flat.length()
	_face(flat, delta)
	_aim_head(delta)

	# Where this bot wants to stand: what its own aim and its own gun can hit
	# from, floored by the tier's stand-off and capped by the weapon's reach —
	# without that cap a lightsaber bot would stop at twenty metres and swing at
	# the air for the rest of the match.
	var hold := _hold_range()
	_state = State.ENGAGE if gap <= hold else State.ADVANCE
	var speed := _speed
	if _state == State.ADVANCE:
		# Close on the target, but never off the leash: past it, the pull back to
		# the owner wins and the bot gives ground rather than chasing. It keeps
		# facing and shooting the whole time — this limits where it WALKS, not
		# what it fights.
		var want := _route(_target.global_position, delta)
		if _leashed():
			var home: Vector3 = owner_player.global_position - global_position
			home.y = 0.0
			if home.length() > LEASH:
				# Past the leash the pull home wins, and it is routed too — the
				# way back is as full of walls as the way out.
				want = _route(owner_player.global_position, delta)
		var step := want * speed
		velocity.x = step.x
		velocity.z = step.z
		_watch_for_snag(want, delta)
	else:
		# In range: circle rather than stand still, so it isn't a free headshot.
		# A shot taken from fifty metres is steadier from a stop, and there is
		# nothing to dodge that far out, so the circling fades with distance.
		var side := flat.normalized().cross(Vector3.UP) * _strafe_dir
		var circle := STRAFE_SPEED
		if gap > LONG_RANGE_STILL:
			circle *= LONG_RANGE_STRAFE
		velocity.x = side.x * speed * circle
		velocity.z = side.z * speed * circle
	_apply_unstick()

	_place_turret_if_ready(false)  # in contact: dig in where we stand
	_place_mortar_if_ready(false)
	_force_push_if_crowded(gap)
	_throw_lightning_if_in_reach(gap)
	_fire_wrist_rocket_if_useful(gap)
	_call_mortar_strike(delta)
	_reaction_left = maxf(_reaction_left - delta, 0.0)
	var facing := Vector3.FORWARD.rotated(Vector3.UP, rotation.y)
	var on_aim := rad_to_deg(facing.angle_to(flat.normalized())) <= FIRE_CONE_DEG
	# A bot fires when it is settled at its stand-off, OR when the target is
	# still inside the range its own aim can reach — the long shot on the way in.
	# That second branch is what stopped a marksman walking thirty metres with a
	# target in its sights and its finger off the trigger: it used to require
	# ENGAGE, which by definition is "already close enough to stop".
	var shot := minf(_hit_reach() * LONG_SHOT_SLACK, weapon.max_range() * 0.9)
	var in_range := _state == State.ENGAGE or gap <= shot
	# Aiming down sights follows the same rule. It used to be gated on ENGAGE to
	# mirror the human "no ADS while running" — but a bot has no sprint, so what
	# that actually did was deny the sights to exactly the shot they are for.
	weapon.aiming = _skill["ads"] and in_range and on_aim
	var may_fire := in_range and on_aim and _reaction_left <= 0.0 \
		and weapon.heat() < FIRE_HEAT_CEILING
	weapon.update_fire(may_fire, may_fire)
	_throw_grenade_if_useful(gap)


## Nothing to shoot. A bought squadmate falls in behind the player who paid for
## it; anyone else (team AI, or a squadmate whose owner is down) pushes for the
## middle of the map, which is where the fighting is on every layout.
func _patrol(delta: float) -> void:
	# Ease the gun back to level while nothing is being aimed at.
	head.rotation.x = lerpf(head.rotation.x, 0.0, clampf(delta * 3.0, 0.0, 1.0))
	head.rotation.y = lerpf(head.rotation.y, 0.0, clampf(delta * 3.0, 0.0, 1.0))

	var goal := _patrol_goal(delta)
	_try_cable(goal)
	var flat := goal - global_position
	flat.y = 0.0
	var gap := flat.length()
	var arrive := FOLLOW_DISTANCE if _has_owner() else ROAM_ARRIVE
	_place_turret_if_ready(gap <= TURRET_PLACE_GAP)
	_place_mortar_if_ready(gap <= MORTAR_PLACE_GAP)
	if gap <= arrive:
		velocity.x = 0.0
		velocity.z = 0.0
		if not _has_owner():
			_roam_left = 0.0  # arrived: pick somewhere new on the next tick
		_apply_unstick()
		return
	_state = State.ADVANCE
	_face(flat, delta)
	var want := _route(goal, delta)
	var step := want * _speed
	velocity.x = step.x
	velocity.z = step.z
	_apply_unstick()
	_watch_for_snag(want, delta)


## The direction to WALK in to reach `goal` — around the level's geometry rather
## than straight through it. Returns a flat unit vector, or zero if there is
## nowhere to go.
##
## This only chooses where the feet go. Which way the bot FACES and what it
## shoots at are decided by the caller and are unaffected: a bot rounding a
## crate keeps its gun on the target the whole way.
##
## A failed plan falls back to the straight line rather than standing still. An
## AI that stops when pathing fails is worse than one that occasionally scrapes
## a wall, and on a map with no scanned geometry at all (nothing but terrain)
## the straight line is the correct answer anyway.
func _route(goal: Vector3, delta: float) -> Vector3:
	var straight := goal - global_position
	straight.y = 0.0
	if straight.length() < 0.01:
		return Vector3.ZERO
	straight = straight.normalized()

	# Shoved off a corner and going nowhere: commit to a sidestep for a moment.
	# Committing matters — re-deciding every frame just jitters in place.
	if _sidestep_left > 0.0:
		_sidestep_left -= delta
		return _sidestep

	var nav: NavGrid = GameState.nav
	if not nav.ready:
		return straight

	_repath_cd -= delta
	if _path.is_empty() or _repath_cd <= 0.0 \
			or goal.distance_to(_path_goal) > GOAL_DRIFT:
		_path_goal = goal
		# The search itself is RATE LIMITED across the whole AI (see
		# NavGrid.PLANS_PER_FRAME): a plan costs 2 ms on the big maps, bots
		# re-plan on their own timers, and several landing on one frame is what
		# produced stutter with no visible cause. Refused means keep following
		# the route we already have and ask again next frame, so the cooldown is
		# only reset when a plan actually ran.
		if nav.may_plan():
			_repath_cd = REPATH_INTERVAL
			_path = nav.path(global_position, goal)
			_path_i = 0

	# Drop waypoints already reached.
	var here := Vector2(global_position.x, global_position.z)
	while _path_i < _path.size() and here.distance_to(_path[_path_i]) <= WAYPOINT_REACH:
		_path_i += 1
	if _path_i >= _path.size():
		return straight   # arrived, or nothing was found: close the last gap direct

	# String-pulling: aim at the furthest waypoint we can actually see, so the
	# bot cuts across open ground instead of walking the grid's staircase.
	var target_i := _path_i
	for i in range(_path_i + 1, mini(_path_i + SMOOTH_LOOKAHEAD, _path.size())):
		var p: Vector2 = _path[i]
		if nav.line_clear(global_position, Vector3(p.x, global_position.y, p.y)):
			target_i = i
	var wp: Vector2 = _path[target_i]
	var dir := Vector3(wp.x - global_position.x, 0.0, wp.y - global_position.z)
	return dir.normalized() if dir.length() > 0.01 else straight


## Notice when the feet are not keeping up with the intent, and break out of it.
## The grid cannot see other bodies or anything that is not a box collider, so
## this is the backstop that covers everything it misses.
func _watch_for_snag(want: Vector3, delta: float) -> void:
	if _sidestep_left > 0.0:
		return
	var moving := Vector2(velocity.x, velocity.z).length()
	if want.length() < 0.01 or moving > STUCK_SPEED:
		_stuck_for = 0.0
		return
	_stuck_for += delta
	if _stuck_for < STUCK_TIME:
		return
	_stuck_for = 0.0
	# Peel off along the wall rather than reversing: a bot that backs up walks
	# into the same corner again a second later.
	_sidestep = want.cross(Vector3.UP).normalized() * _strafe_dir
	_sidestep_left = SIDESTEP_TIME
	_path.clear()   # whatever we were following did not work; plan again after
	_repath_cd = 0.0


## Gadget habits, all deliberately simple: use what you bought at the obvious
## moment. Together these are what make an AI firefight look like a firefight
## rather than two lines of riflemen.
## Passive regen, the same rule the player has: heal back to full once enough
## time has passed since the last hit. Replaces the medkit.
func _regen_if_calm(delta: float) -> void:
	_since_damage += delta
	if _since_damage < Player.REGEN_DELAY:
		return
	var full := loadout.max_health() * float(_skill["health"])
	if health < full:
		health = minf(health + Player.REGEN_RATE * delta, full)


## Lob one at a target that's far enough away not to catch us in the blast.
func _throw_grenade_if_useful(gap: float) -> void:
	if _grenade_cd > 0.0 or not is_instance_valid(_target):
		return
	# Grenades are gadgets now, so a bot throws only if it BOUGHT one; the type
	# comes from whichever slot holds it.
	var g := loadout.gadget if loadout.gadget in Loadout.GRENADE_GADGETS \
		else loadout.gadget2
	if not (g in Loadout.GRENADE_GADGETS):
		return
	if gap < GRENADE_RANGE.x or gap > GRENADE_RANGE.y:
		return
	_grenade_cd = GRENADE_COOLDOWN
	var nade := GRENADE_SCENE.instantiate()
	get_tree().current_scene.add_child(nade)
	var aim := (_target.global_position + Vector3.UP * 0.8) - head.global_position
	# Lob it: the further away, the more arc, so it lands rather than skids.
	var toss := (aim.normalized() + Vector3.UP * (0.25 + gap * 0.012)).normalized() \
		* (9.0 + gap * 0.45)
	nade.launch(head.global_position + aim.normalized() * 0.6, toss, self,
		Loadout.GRENADE_GADGETS[g])


## Engineers drop their turret once they've reached the ground they're holding,
## or the moment they make contact, and only ever run one at a time.
##
## `near_goal` is measured against the bot's OWN patrol goal rather than the
## capture area, so this works the same in deathmatch: keying it to the zone
## meant an engineer in deathmatch had to wander within a few metres of the map
## origin before it would ever deploy.
func _place_turret_if_ready(near_goal: bool) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.TURRET:
		return
	if is_instance_valid(_turret):
		return
	if not near_goal and not is_instance_valid(_target):
		return
	_turret = TURRET_SCENE.instantiate()
	get_parent().add_child(_turret)
	_turret.global_position = global_position - global_transform.basis.z * 2.0
	_turret.setup(self, team)


## The other placeable, gated exactly like the turret: set the tube down once
## we're near where we were heading, or the moment we make contact.
func _place_mortar_if_ready(near_goal: bool) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.MORTAR:
		return
	if is_instance_valid(_mortar):
		return
	if not near_goal and not is_instance_valid(_target):
		return
	_mortar = MORTAR_SCENE.instantiate()
	get_parent().add_child(_mortar)
	_mortar.global_position = global_position - global_transform.basis.z * 2.0
	_mortar.setup(self, team)


## Call a salvo. A player picks the spot off the map screen; a bot has no map,
## so it shells its OWN target's position — it never drops rounds somewhere it
## has not actually seen an enemy, which is what keeps AI artillery honest
## rather than omniscient.
##
## It aims at the middle of whatever group the target is standing in, so a
## mortar punishes a bunched-up push instead of chasing one runner. The shells
## take over a second to arrive and are visible on the way in, so walking out of
## them is the counterplay.
##
## Keyed to the bot's own target, not to the capture area, so it behaves the
## same in deathmatch as in zones — the same rule the turret follows.
func _call_mortar_strike(delta: float) -> void:
	_mortar_reaim = maxf(_mortar_reaim - delta, 0.0)
	if not is_instance_valid(_mortar) or not _mortar.ready_to_fire():
		return
	# Same gate the gun uses: it has to have held the target long enough to
	# react, so a mortar never fires on a target it has only just glimpsed.
	if not is_instance_valid(_target) or _reaction_left > 0.0:
		return
	# Already shelling somewhere, and not yet allowed to move the barrage.
	if _mortar.is_aimed() and _mortar_reaim > 0.0:
		return
	var mark: Vector3 = _target.global_position
	if _mortar.global_position.distance_to(mark) < MORTAR_MIN_RANGE:
		return  # close enough to shoot at; a lob would land on our own line
	_mortar.fire_at(_enemy_cluster(mark))
	_mortar_reaim = MORTAR_REAIM


## Centroid of the enemies bunched around a mark, so a salvo lands BETWEEN a
## group rather than on the one of them we happen to be looking at.
func _enemy_cluster(mark: Vector3) -> Vector3:
	var sum := mark
	var count := 1.0
	for c in GameState.combatants:
		if c == _target or c.team == team or not c.is_alive():
			continue
		if c.global_position.distance_to(mark) <= MORTAR_CLUSTER:
			sum += c.global_position
			count += 1.0
	return sum / count


## Scouts grapple ahead when they have a long way to go, which is both faster
## and the only way you'll see the wire fly in a match with no humans in it.
func _try_cable(goal: Vector3) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.CABLE:
		return
	if _cable_cd > 0.0 or _cable_left > 0.0:
		return
	if global_position.distance_to(goal) < CABLE_MIN_GOAL:
		return
	var from := head.global_position
	var toward := (goal - from)
	toward.y = 0.0
	var to := from + toward.normalized() * 30.0 + Vector3.UP * 2.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1  # world geometry only
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_cable_cd = CABLE_COOLDOWN
	_cable_anchor = hit["position"]
	_cable_left = CABLE_PULL_TIME
	_cable_wire = CABLE_WIRE_SCENE.instantiate()
	get_parent().add_child(_cable_wire)
	_cable_wire.launch(self, weapon, _cable_anchor, 0.12)


## A Force adept shoves whatever has closed on it. The gate is the same idea as
## the bot's grenade: a power it only spends when the situation it is for has
## actually arrived, so it is not simply on cooldown forever.
func _force_push_if_crowded(gap: float) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.FORCE_PUSH:
		return
	if _force_cd > 0.0 or gap > ForcePowers.PUSH_RANGE * 0.7:
		return
	if ForcePowers.push(self, team) > 0:
		_force_cd = float(Loadout.GADGET_COOLDOWNS[Loadout.Gadget.FORCE_PUSH])


## The other half of a Force adept's answer to distance: when the target is too
## far to cut but inside the arc's reach, throw lightning at it. The gate is a
## RANGE band rather than a crowd, because unlike push this is what the bot uses
## while it is still closing — and it is spent only on a target it can actually
## see, which _nearest_in_cone re-checks for itself.
func _throw_lightning_if_in_reach(gap: float) -> void:
	if loadout == null or loadout.gadget != Loadout.Gadget.FORCE_LIGHTNING:
		return
	# Already pouring: keep it going while the target is still in reach. A bot
	# has to CHANNEL for the same reason a player does — the power is worth 11 a
	# tick now, so one bite is a scratch and the whole threat is in holding it.
	if _channel_left > 0.0:
		_channel_left -= _tick_delta
		if gap > ForcePowers.BOLT_RANGE or _channel_left <= 0.0:
			_channel_left = 0.0
			_force_cd = float(Loadout.GADGET_COOLDOWNS[Loadout.Gadget.FORCE_LIGHTNING])
			return
		_channel_tick -= _tick_delta
		if _channel_tick <= 0.0:
			_channel_tick = ForcePowers.CHANNEL_TICK
			_channel_arc = ForcePowers.channel_bolt(
				self, team, LIGHTNING_SCENE, weapon, _channel_arc)
		return
	if _force_cd > 0.0 or gap > ForcePowers.BOLT_RANGE * 0.9:
		return
	# Open on the FIRST bite: channel_bolt returns null if the cone was empty, so
	# the channel is committed only when it actually hit — and the cone is
	# resolved (and damage dealt) exactly once, not once to probe and once to fire.
	var arc := ForcePowers.channel_bolt(self, team, LIGHTNING_SCENE, weapon, _channel_arc)
	if arc == null:
		return
	_channel_arc = arc
	_channel_left = ForcePowers.CHANNEL_TIME
	_channel_tick = ForcePowers.CHANNEL_TICK


## A wrist rocket, on the same "use it when the moment it is for arrives" rule
## as the grenade: far enough away that the splash cannot reach us, close enough
## to hit. It is deliberately NOT fired at point-blank — a bot blowing itself up
## is the one thing an AI rocket must never do.
func _fire_wrist_rocket_if_useful(gap: float) -> void:
	if loadout == null or _force_cd > 0.0:
		return
	if loadout.gadget != Loadout.Gadget.WRIST_ROCKET \
			and loadout.gadget2 != Loadout.Gadget.WRIST_ROCKET:
		return
	if gap < Player.WRIST_ROCKET_SPLASH * 2.5 or gap > 60.0:
		return
	if _target == null or not _can_see(_target):
		return
	var rocket := ROCKET_SCENE.instantiate()
	get_parent().add_child(rocket)
	var from := head.global_position
	var dir := (_target.global_position + Vector3.UP * TARGET_AIM_HEIGHT - from).normalized()
	rocket.launch(from + dir * 0.6, dir, self, Player.WRIST_ROCKET_SPLASH,
		Player.WRIST_ROCKET_DAMAGE, Player.WRIST_ROCKET_RANGE)
	_force_cd = float(Loadout.GADGET_COOLDOWNS[Loadout.Gadget.WRIST_ROCKET])


## Take a shove from someone else's Force power. See _physics_process for why it
## cannot simply be added to velocity here.
func apply_impulse(impulse: Vector3) -> void:
	_shove += impulse


func _raise_shield() -> void:
	if is_instance_valid(_shield):
		return
	_shield = SHIELD_SCENE.instantiate()
	add_child(_shield)
	_shield.setup(GameState.TEAM_COLORS[team])


## Bodies our own fire ignores — the same contract Player exposes, so a bot with
## a front shield can shoot through its own cover.
func hitscan_exclusions() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	if is_instance_valid(_shield):
		out.append(_shield.get_rid())
	return out


func _has_owner() -> bool:
	return owner_player != null and is_instance_valid(owner_player) \
		and owner_player.is_alive()


## True for a bought squadmate whose owner is alive and on the field. An orphan
## (owner dead, or a team-fill bot with no owner at all) is not leashed — it has
## nobody to follow, so it falls back to pushing the map.
func _leashed() -> bool:
	return _has_owner()


func _patrol_goal(delta: float) -> Vector3:
	if _has_owner():
		return owner_player.global_position
	_roam_left -= delta
	if _roam_left <= 0.0:
		_roam_left = ROAM_REPICK
		# Head for the capture area when the mode has one, otherwise the middle
		# of the map. Spread around it, so a squad holds ground instead of all
		# standing on the same spot.
		var focus := GameState.zone_point if GameState.zone_active else Vector3.ZERO
		var spread := ROAM_SPREAD * (0.35 if GameState.zone_active else 1.0)
		var angle := randf() * TAU
		var reach := sqrt(randf()) * spread
		_roam_target = focus + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
	# A zone that moved mid-wander should pull the squad straight away.
	if GameState.zone_active and Vector2(_roam_target.x - GameState.zone_point.x,
			_roam_target.z - GameState.zone_point.z).length() > ROAM_SPREAD:
		_roam_left = 0.0
	return _roam_target


func _face(flat_dir: Vector3, delta: float) -> void:
	if flat_dir.length() < 0.01:
		return
	var want := atan2(-flat_dir.x, -flat_dir.z)  # -Z is forward
	rotation.y = rotate_toward(rotation.y, want, float(_skill["turn"]) * delta)


## Point the gun at the target, off by the skill's aim error: a recruit sprays
## around its mark, an elite is nearly on it.
##
## The error is a HELD offset re-rolled a few times a second, not fresh noise
## every frame. Per-frame noise fed through the aim lerp just averages back out
## to a perfect shot, which made all four tiers shoot identically. It's applied
## to the head in both axes, so the gun is off without the body turning — the
## same trick the player's recoil yaw uses.
##
## Pitch is measured from the HEAD, not the body origin: the gun sits about
## 1.4 m up, so solving the angle from the feet sends every shot roughly a body
## height over the target at normal range.
func _aim_head(delta: float) -> void:
	_aim_reroll_in -= delta
	if _aim_reroll_in <= 0.0:
		_aim_reroll_in = AIM_REROLL
		var wobble := deg_to_rad(_aim_error_deg(weapon.aiming))
		_aim_offset = Vector2(randf_range(-wobble, wobble), randf_range(-wobble, wobble))
	var muzzle := head.global_position
	var aim_at: Vector3 = _target.global_position + Vector3.UP * TARGET_AIM_HEIGHT
	# Fire is hitscan, so this is NOT projectile lead — it is the bot's own lag.
	# The head lerps toward where the target is, so against anything strafing it
	# permanently shoots a fraction of a second behind: nothing at ten metres, a
	# clean miss at fifty, which is why only the tiers that fight at fifty do it.
	if _skill["lead"] and _target is CharacterBody3D:
		var drift: Vector3 = (_target as CharacterBody3D).velocity * AIM_LAG
		drift.y = 0.0   # only the sideways lag matters; vertical is gravity noise
		aim_at += drift
	var to_aim := aim_at - muzzle
	var flat := Vector3(to_aim.x, 0.0, to_aim.z).length()
	var pitch := atan2(to_aim.y, maxf(flat, 0.01))
	var blend := clampf(delta * 8.0, 0.0, 1.0)
	head.rotation.x = lerpf(head.rotation.x, pitch + _aim_offset.y, blend)
	head.rotation.y = lerpf(head.rotation.y, _aim_offset.x, blend)


## The gun kicks the bot's aim up the same way it kicks a player's camera. The
## shove big guns give (kick_back) is ignored: a bot walks by writing its own
## velocity every frame and would simply erase it.
func _on_weapon_fired(cam_recoil: float, _kick_back: float) -> void:
	head.rotation.x += cam_recoil * RECOIL_TAKE
	head.rotation.y += randf_range(-RECOIL_YAW_SHARE, RECOIL_YAW_SHARE) \
		* cam_recoil * RECOIL_TAKE


## Same horizontal separation the players use: two capsules inside each other
## get ejected upwards by the solver and never come back down.
func _apply_unstick() -> void:
	for c in GameState.combatants:
		if c == self or not c.is_alive():
			continue
		var away := global_position - c.global_position
		away.y = 0.0
		var gap := away.length()
		if gap >= UNSTICK_RADIUS or gap < 0.001:
			continue
		var push := away.normalized() * (1.0 - gap / UNSTICK_RADIUS) * UNSTICK_SPEED
		velocity.x += push.x
		velocity.z += push.z


## Same idle/walk/run rule the player uses, minus the jump (bots don't jump).
func _animate() -> void:
	var anim := model.anim_player
	if anim == null:
		return
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var clip := "idle"
	if ground_speed > 3.9:
		clip = "run"
	elif ground_speed > 0.15:
		clip = "walk"
	if anim.assigned_animation != clip and anim.has_animation(clip):
		anim.play(clip, 0.12)
