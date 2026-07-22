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

const PUSH_RANGE := 12.0
const PUSH_ARC := deg_to_rad(50.0)   # half-angle of the cone in front of you
const PUSH_FORCE := 16.0             # m/s of shove, straight away from you
const PUSH_LIFT := 5.5               # ...plus this much up, so they leave the floor
const PUSH_DAMAGE := 20.0

const PULL_RANGE := 34.0
const PULL_ARC := deg_to_rad(10.0)   # a narrow cone: you pull who you LOOK at
const PULL_FORCE := 21.0
const PULL_LIFT := 3.5

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


## The nearest living enemy inside a cone in front of `user`, or null.
static func _nearest_in_cone(user: Node3D, team: int, reach: float,
		arc: float) -> Node3D:
	var origin := user.global_position
	var facing := -user.global_transform.basis.z
	var best: Node3D = null
	var best_gap := reach
	for c in GameState.combatants:
		if not _is_enemy(c, user, team):
			continue
		var to: Vector3 = c.global_position - origin
		var gap := to.length()
		if gap > best_gap or gap < 0.01:
			continue
		if facing.angle_to(to / gap) > arc:
			continue
		# Line of sight, including smoke: a power that reaches through a wall or
		# a cloud would be the one thing on the map that ignores cover.
		if not _can_reach(user, origin, c.global_position):
			continue
		best = c
		best_gap = gap
	return best


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
