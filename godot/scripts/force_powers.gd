class_name ForcePowers
extends RefCounted
## The Force adept's gadgets, as static functions shared by Player and Bot.
##
## They live outside both because a bot uses PUSH for exactly the reason a
## player does — something got too close to a melee fighter — and duplicating
## the cone test in two files means two sets of numbers to keep in step.
##
## Everything here moves people rather than damaging them. That is the point of
## the class: the saber does the killing, and the powers decide who is standing
## where when it lands. The one exception is push's small damage, which exists
## so a shove that puts someone off a ledge is a real threat rather than a
## pillow.
##
## SHOVING SOMEBODY ELSE is the hard part. A Bot writes its own velocity every
## physics frame and a Player rewrites velocity.x/z from the stick, so anything
## simply added to `velocity` is gone before it renders — the same trap as a
## gun's kick_back and the cable's vault. Both therefore carry a decaying
## impulse of their own and expose it as `apply_impulse`, which is what these
## functions call. Anything that should be shoveable needs that method; a turret
## is bolted down and correctly has none.

# A combatant's origin is at its feet. Anything that traces a LINE between two
# of them has to lift both ends off the floor, or the ray grazes the ground and
# reports cover that is not there. Player's own head sits at 1.55; a bot has one
# too, and the fallback is for anything else that turns up in `combatants`.
const EYE_HEIGHT := 1.5
const TORSO_HEIGHT := 1.0

const PUSH_RANGE := 12.0
const PUSH_ARC := deg_to_rad(50.0)   # half-angle of the cone in front of you
const PUSH_FORCE := 16.0             # m/s of shove, straight away from you
const PUSH_LIFT := 5.5               # ...plus this much up, so they leave the floor
const PUSH_DAMAGE := 20.0

const PULL_RANGE := 34.0
const PULL_ARC := deg_to_rad(10.0)   # a narrow cone: you pull who you LOOK at
const PULL_FORCE := 21.0
const PULL_LIFT := 3.5

# LIGHTNING is the one power that kills. It is aimed like the pull — a narrow
# cone on whoever you are looking at — and then ARCS to the nearest bodies to
# THAT target rather than to the caster, so it punishes a group standing
# together exactly as the mortar does, and cannot be swept across a room.
#
# It is CHANNELLED: hold the button and it pours for up to CHANNEL_TIME, ticking
# damage every CHANNEL_TICK and re-acquiring on every tick, so a target that
# breaks the cone or ducks behind cover cuts the stream off. That re-acquire is
# what makes holding it a real aim rather than a fire-and-forget button — and it
# is why the per-tick damage is a fraction of what the old one-shot burst did:
# the whole channel is worth a bit more than the burst was, but only if you can
# keep it on somebody for two seconds while they shoot back.
const BOLT_RANGE := 18.0
const BOLT_ARC := deg_to_rad(14.0)
const CHANNEL_TIME := 2.2            # seconds of stream before it cuts out
const CHANNEL_TICK := 0.2            # ...and how often it bites
const BOLT_DAMAGE := 11.0            # per tick, so ~121 over a full channel
const BOLT_CHAINS := 3               # extra bodies past the first
# How far it jumps, target to target. Generous on purpose: this is the number
# that decides whether the arc reads as chain lightning at all. At 7 m the jump
# only happened when two enemies were practically touching, so most bolts looked
# like a single-target zap with a chain nobody ever saw.
const BOLT_CHAIN_RANGE := 9.0
const BOLT_CHAIN_FALLOFF := 0.6      # each jump is worth this much of the last
const BOLT_SHOVE := 4.0              # a stagger, not a throw: push is the throw

const LEAP_UP := 11.5
const LEAP_FORWARD := 13.0


## Shove everyone in a cone in front of `user` away from it, and hurt them a
## little. Returns how many were caught, which the caller uses to decide whether
## the power was worth its cooldown.
static func push(user: Node3D, team: int) -> int:
	var origin := user.global_position
	var facing := -user.global_transform.basis.z
	var caught := 0
	for c in GameState.combatants:
		if not _is_enemy(c, user, team):
			continue
		var to: Vector3 = c.global_position - origin
		var gap := to.length()
		if gap > PUSH_RANGE or gap < 0.01:
			continue
		var dir := to / gap
		# The cone is measured FLAT. Judging it in 3D would make a shove miss
		# someone standing on a crate directly in front of you.
		var flat_dir := Vector3(dir.x, 0.0, dir.z)
		var flat_face := Vector3(facing.x, 0.0, facing.z)
		if flat_dir.length() < 0.01 or flat_face.length() < 0.01:
			continue
		if flat_face.normalized().angle_to(flat_dir.normalized()) > PUSH_ARC:
			continue
		# Falls off with distance, so a shove at the edge of the cone nudges and
		# one in your face throws.
		var strength := 1.0 - 0.5 * (gap / PUSH_RANGE)
		_shove(c, flat_dir.normalized() * PUSH_FORCE * strength + Vector3.UP * PUSH_LIFT)
		if c.has_method("take_damage"):
			c.take_damage(PUSH_DAMAGE * strength, user, false)
		caught += 1
	return caught


## Yank the enemy you are looking at toward you. Narrow cone and nearest-first,
## so it takes the one target rather than the crowd — pull is a way to start a
## fight you can reach, not a second push.
static func pull(user: Node3D, team: int) -> Node3D:
	var mark := _nearest_in_cone(user, team, PULL_RANGE, PULL_ARC)
	if mark == null:
		return null
	var to: Vector3 = user.global_position - mark.global_position
	to.y = 0.0
	if to.length() < 0.01:
		return null
	_shove(mark, to.normalized() * PULL_FORCE + Vector3.UP * PULL_LIFT)
	return mark


## Throw lightning at whoever `user` is looking at, then let it arc on to the
## bodies standing near THEM. Returns the chain in the order it was struck, so
## the caller can draw one continuous bolt through it — an empty array means the
## power found nobody and (like the pull) should not cost its full cooldown.
##
## Each jump is measured from the LAST victim, with its own line-of-sight check,
## so lightning does not reach around a corner the caster cannot see past any
## more than it reaches through a wall.
static func lightning(user: Node3D, team: int) -> Array:
	var struck: Array = []
	var mark := _nearest_in_cone(user, team, BOLT_RANGE, BOLT_ARC)
	if mark == null:
		return struck
	var damage := BOLT_DAMAGE
	var from := mark
	while from != null:
		struck.append(from)
		_zap(from, user, damage)
		if struck.size() > BOLT_CHAINS:
			break
		damage *= BOLT_CHAIN_FALLOFF
		from = _nearest_chain(from, user, team, struck)
	return struck


## Resolve one bite AND draw it, for a caller channelling the power. Frees the
## PREVIOUS bolt first — a channel ticks five times a second and stacking a fresh
## arc per tick would pile five fading copies on top of each other — and returns
## the new one (null if the bite found nobody) for the caller to hold as its next
## `previous`. This is the ONE place Player and Bot's channels agree on the
## draw-and-replace invariant; they are duck-typed siblings with no shared base,
## so the shared FX rule lives here with the shared force logic. The scene is
## passed in rather than preloaded, to keep this file free of resource deps.
static func channel_bolt(user: Node3D, team: int, arc_scene: PackedScene,
		muzzle: Node3D, previous: Node3D) -> Node3D:
	var chain := lightning(user, team)
	if is_instance_valid(previous):
		previous.queue_free()
	if chain.is_empty():
		return null
	var arc: Node3D = arc_scene.instantiate()
	user.get_parent().add_child(arc)
	arc.strike(muzzle, chain)
	return arc


## Hurt one body and rock it back a little. The stagger is deliberately small:
## knocking people about is what push and pull are for, and a bolt that threw
## its victim would also throw them out of saber reach.
static func _zap(victim: Node, user: Node3D, damage: float) -> void:
	if victim is Node3D:
		var away: Vector3 = victim.global_position - user.global_position
		away.y = 0.0
		if away.length() > 0.01:
			_shove(victim, away.normalized() * BOLT_SHOVE)
	if victim.has_method("take_damage"):
		victim.take_damage(damage, user, false)


## The next body for the arc to jump to: nearest enemy to `from` that has not
## already been struck, within BOLT_CHAIN_RANGE and in sight of it.
static func _nearest_chain(from: Node3D, user: Node3D, team: int,
		struck: Array) -> Node3D:
	var best: Node3D = null
	var best_gap := BOLT_CHAIN_RANGE
	for c in GameState.combatants:
		if not _is_enemy(c, user, team) or c in struck:
			continue
		var gap: float = from.global_position.distance_to(c.global_position)
		if gap > best_gap:
			continue
		if not _can_reach(from, _torso(from), _torso(c)):
			continue
		best = c
		best_gap = gap
	return best


## The nearest living enemy inside a cone in front of `user`, or null.
static func _nearest_in_cone(user: Node3D, team: int, reach: float,
		arc: float) -> Node3D:
	var origin := _eye(user)
	var facing := -user.global_transform.basis.z
	var best: Node3D = null
	var best_gap := reach
	for c in GameState.combatants:
		if not _is_enemy(c, user, team):
			continue
		var to: Vector3 = _torso(c) - origin
		var gap := to.length()
		if gap > best_gap or gap < 0.01:
			continue
		if facing.angle_to(to / gap) > arc:
			continue
		# Line of sight, including smoke: a power that reaches through a wall or
		# a cloud would be the one thing on the map that ignores cover.
		if not _can_reach(user, origin, _torso(c)):
			continue
		best = c
		best_gap = gap
	return best


## Where a body LOOKS FROM and where it is AIMED AT. Both matter because a
## combatant's origin is at its FEET: a sight ray traced origin-to-origin runs
## exactly along the ground, and a floor collider stops it — measured, on a flat
## test floor, at every range. The pull has been tracing that ray since it was
## written; lightning inherited it and is what found it.
static func _eye(body: Node3D) -> Vector3:
	var head: Node3D = body.get_node_or_null("Head")
	return head.global_position if head != null else body.global_position + Vector3.UP * EYE_HEIGHT


static func _torso(body: Node3D) -> Vector3:
	return body.global_position + Vector3.UP * TORSO_HEIGHT


static func _can_reach(user: Node3D, from: Vector3, to: Vector3) -> bool:
	if GameState.sight_blocked(from, to):
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # world only; bodies are what we are reaching for
	if user is CollisionObject3D:
		query.exclude = [user.get_rid()]
	return user.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


static func _is_enemy(c: Node, user: Node3D, team: int) -> bool:
	return is_instance_valid(c) and c != user and c is Node3D \
		and c.has_method("is_alive") and c.is_alive() \
		and "team" in c and c.team != team


## Push somebody, if they are the sort of thing that can be pushed.
static func _shove(target: Node, impulse: Vector3) -> void:
	if target.has_method("apply_impulse"):
		target.apply_impulse(impulse)


## The self-only power: a Force-assisted jump. Returned rather than applied so
## the caller can put the horizontal part wherever its own movement code keeps a
## surviving impulse.
static func leap_velocity(user: Node3D) -> Vector3:
	var facing := -user.global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = Vector3.FORWARD
	return facing.normalized() * LEAP_FORWARD + Vector3.UP * LEAP_UP
