extends Node
## Autoload: match state — teams, team-deathmatch score, spawn points, and the
## map rotation. Levels register spawn markers per team; actors credit frags
## here on a kill, so the mode rules live in one place. Also bootstraps the
## control bindings (Controls, registered in code — no project.godot
## serialization) before anything can ask what a button does.

signal score_changed(team: int, score: int)
signal match_won(team: int)
## The match proper hasn't begun until everyone has picked a loadout and the
## start countdown has run. `match_countdown` ticks whole seconds (0 = FIGHT),
## and nobody can move or shoot until `match_live` is true.
signal match_countdown(seconds: int)
signal match_began()
signal zone_moved(point: Vector3)     # the capture area relocated
signal zone_state(holder: int, contested: bool, seconds_left: int)

enum Team { REPUBLIC, CIS }
## DEATHMATCH scores on kills; ZONES scores a point per second for whichever
## team has the most bodies inside the roaming capture area.
## ROYALE is the odd one out: it is not scored at all. Nobody respawns, you
## start with a sidearm and scavenge the rest off the ground, a shrinking storm
## herds everyone together, and the last side still standing wins.
enum Mode { DEATHMATCH, ZONES, ROYALE }
const MODE_NAMES := {
	Mode.DEATHMATCH: "DEATHMATCH", Mode.ZONES: "ZONES", Mode.ROYALE: "BATTLE ROYALE",
}
const MODE_BLURBS := {
	Mode.DEATHMATCH: "First to %d kills",
	Mode.ZONES: "Hold the area. A point a second, new area every %ds, first to %d",
	Mode.ROYALE: "No respawns. Scavenge your gear, outlast the storm, last side wins",
}

# What each mode plays to: kills, seconds of control, or simply being the last
# side left, which is one "point" awarded once.
const SCORE_LIMITS := {Mode.DEATHMATCH: 25, Mode.ZONES: 60, Mode.ROYALE: 1}

# A respawn must never land on a living body: two overlapping capsules push each
# other apart every physics frame and ride that ejection out of the map, which
# drags the innocent player along with the one who died.
const SPAWN_CLEARANCE := 2.5  # a marker this close (m) to a live player is taken
## Metres above the computed ground to place anything, so it falls the last step
## rather than starting buried. See place_corner_spawns.
const SPAWN_LIFT := 1.2
const MIN_BODY_GAP := 1.0     # capsules are 0.7 wide, so this always separates them

# The map roster: the menu lists it, Main loads MAPS[map_index].scene, and the
# rotation walks it in order. Adding a map means adding one row here.
const MAPS: Array[Dictionary] = [
	{"name": "CROSSFIRE", "blurb": "Symmetric arena, bunker centre",
		"scene": preload("res://scenes/levels/crossfire.tscn")},
	{"name": "FOUNDRY", "blurb": "Tight lanes across a divider wall",
		"scene": preload("res://scenes/levels/foundry.tscn")},
	{"name": "OVERGROWTH", "blurb": "Wide outdoor jungle, temple ruins",
		"scene": preload("res://scenes/levels/overgrowth.tscn")},
	{"name": "HIGHRIDGE", "blurb": "Jungle mountain, tunnel and a flag on the peak",
		"scene": preload("res://scenes/levels/highridge.tscn")},
	{"name": "HANGAR", "blurb": "Imperial deck, close quarters",
		"scene": preload("res://scenes/levels/hangar.tscn")},
	{"name": "SPILLWAY", "blurb": "Long narrow channel, staggered blocks",
		"scene": preload("res://scenes/levels/spillway.tscn")},
	{"name": "CITADEL", "blurb": "Central keep and corner towers, fought in a rotation",
		"scene": preload("res://scenes/levels/citadel.tscn")},
	{"name": "RELAY", "blurb": "Wide open plain, low cover, long sight lines",
		"scene": preload("res://scenes/levels/relay.tscn")},
	{"name": "CATWALK", "blurb": "Cramped corridors, every fight is a corner",
		"scene": preload("res://scenes/levels/catwalk.tscn")},
	{"name": "GEONOSIS", "blurb": "Vast red basin: five mesas around an arena. 300m across",
		"scene": preload("res://scenes/levels/geonosis.tscn")},
]
## A team is just an index now, 0 .. active_teams()-1. Two is the classic
## Republic/Separatist match; three or four makes it a free-for-all between
## squads; FREE FOR ALL gives every player a team of one. Team.REPUBLIC and
## Team.CIS are still 0 and 1, so maps that name them keep working.
##
## Arrays, not dictionaries keyed by the enum: every `TEAM_COLORS[team]` lookup
## in the game indexes by int and carries on working unchanged.
const MAX_TEAMS := 4
const TEAM_NAMES: Array[String] = ["REPUBLIC", "SEPARATIST", "MANDALORE", "HUTT CARTEL"]
const TEAM_COLORS: Array[Color] = [
	Color(0.35, 0.55, 1.0),   # blue
	Color(1.0, 0.40, 0.32),   # red
	Color(0.45, 0.85, 0.45),  # green
	Color(0.95, 0.78, 0.30),  # gold
]

var scores := {}
var match_over := false
var map_index := 0  # index into MAPS; the menu sets it
## Menu choice: true = play the whole roster in order (rotating on each win),
## false = replay the chosen map, then back to the menu.
var rotate_maps := false

## Match setup, all chosen on the menu.
## `human_players` is how many split-screen humans are at the couch, and decides
## the viewport layout. `team_size` is the headcount PER TEAM: humans fill the
## slots first and AI makes up the difference, so 2 humans at a team size of 3
## is a 3v3 with four bots in it. `ai_skill` indexes Loadout.SQUAD_SKILLS.
## False from map load until the start countdown finishes. Everything that can
## act checks it, so the opening seconds are a real hold rather than a free hit
## for whoever loads fastest.
var match_live := false

var mode := Mode.DEATHMATCH
## Where the capture area currently is, and whether there is one at all. Bots
## read these to decide where to push in ZONES.
var zone_point := Vector3.ZERO
var zone_active := false

## What the map screen draws. `map_extents` is the playable half-size on XZ;
## `map_shapes` are top-down footprints of the solid geometry, scanned once at
## match start (see scan_map_geometry).
var map_center := Vector3.ZERO
var map_extents := Vector2(40.0, 40.0)
var map_shapes: Array = []  # [{pos: Vector2, size: Vector2, angle: float}, ...]
var map_bounds_known := false

# A box whose top is at or below this is the floor slab, not an obstacle.
const MAP_FLOOR_TOP := 0.05
const MAP_MAX_SHAPES := 500  # the map is a sketch, not a second render of the level

## Aim assist. PADS by default, because that is the fairness problem it exists
## to fix: a thumbstick is at a real disadvantage against the mouse player
## sitting on the same couch. It only ever slows your look down and nudges it —
## it never bends a shot, so where a round goes is still entirely yours.
enum AimAssist { OFF, PADS, EVERYONE }
const AIM_ASSIST_NAMES := {
	AimAssist.OFF: "OFF", AimAssist.PADS: "PADS", AimAssist.EVERYONE: "EVERYONE",
}
var aim_assist := AimAssist.PADS

var human_players := 4
var team_size := 2
var ai_skill := 1
## How many sides when it is not a free-for-all, and whether it is one.
var team_count := 2
var free_for_all := false

const MIN_HUMANS := 1
const MAX_HUMANS := 4
const MIN_TEAM_SIZE := 1
const MAX_TEAM_SIZE := 6


## How many sides are actually in this match. Free-for-all is one team per
## human, so it needs no separate branch anywhere else in the game.
func active_teams() -> int:
	return human_players if free_for_all else mini(team_count, MAX_TEAMS)


## Which team a given human player lands on. Dealt round-robin, so 4 humans
## across 2 teams is 2v2, across 3 is 2/1/1, and free-for-all is one each.
func team_for_player(index: int) -> int:
	return index % active_teams()


func humans_on_team(team: int) -> int:
	var count := 0
	for i in human_players:
		if team_for_player(i) == team:
			count += 1
	return count


## How many AI are needed to bring a team up to the chosen size. Free-for-all
## fills nothing: it is a fight between the people at the couch.
func ai_needed(team: int) -> int:
	if free_for_all:
		return 0
	return maxi(team_size - humans_on_team(team), 0)
## Every body that can be shot, shove or be shoved, and block a spawn marker:
## players and their bought AI squads alike. They register in _ready and drop
## out in _exit_tree; spawn picking and the anti-stacking push both walk this
## instead of a group query, which would allocate every frame.
##
## Duck-typed on purpose so bots don't need to inherit Player: a combatant must
## expose is_alive(), team, take_damage() and global_position.
var combatants: Array[Node3D] = []

var _spawns: Dictionary = {}  # Team -> Array[Node3D]


func _init() -> void:
	# Bindings (the kb_* InputMap actions and every pad profile) live in Controls
	# and are read back from user://controls.cfg here, before anything can ask.
	Controls.ensure_loaded()


func score_limit() -> int:
	return SCORE_LIMITS[mode]


## The current mode's blurb with its own numbers already in it.
##
## How many arguments a blurb takes is part of the blurb, and only this file
## knows it — ROYALE's line takes none where the others take one and two. A
## caller that guesses gets "not all arguments converted", which in GDScript
## aborts the whole function it happens in: the menu's one refresh closure
## updates every chip, so a mismatch here silently froze the entire screen the
## moment you selected the mode. Format the blurb HERE, never at the caller.
func mode_blurb() -> String:
	match mode:
		Mode.DEATHMATCH:
			return MODE_BLURBS[mode] % score_limit()
		Mode.ZONES:
			return MODE_BLURBS[mode] % [int(Zone.RELOCATE_EVERY), score_limit()]
		_:
			return MODE_BLURBS[mode]


func reset_match() -> void:
	scores = {}
	for t in active_teams():
		scores[t] = 0
	match_over = false
	match_live = false
	zone_active = false
	map_shapes.clear()
	map_bounds_known = false
	smokes.clear()
	_spawns.clear()
	combatants.clear()


## A map declares its playable area. Arena does this for every procedural map;
## anything hand-authored falls back to the scanned geometry's own extents.
func register_map_bounds(center: Vector3, extents: Vector2) -> void:
	map_center = center
	map_extents = extents
	map_bounds_known = true


## Build the map screen's picture of the level: every world-layer box collider,
## flattened to a top-down footprint. Scanned rather than declared per map, so a
## new map draws on the map screen without doing anything — including the
## hand-authored hangar, which has no layout table to read.
##
## Only layer-1 (world) bodies count, which is what keeps turrets, shields and
## players out of it; and only box shapes, so the terrain map's trimesh hill is
## skipped and Highridge shows its props rather than its contours.
func scan_map_geometry(level: Node) -> void:
	map_shapes.clear()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for body in level.find_children("*", "StaticBody3D", true, false):
		if (body.collision_layer & 1) == 0:
			continue
		for node in body.find_children("*", "CollisionShape3D", true, false):
			if map_shapes.size() >= MAP_MAX_SHAPES:
				break
			var box := node.shape as BoxShape3D
			if box == null:
				continue
			var xform: Transform3D = node.global_transform
			var scale: Vector3 = xform.basis.get_scale()
			if xform.origin.y + box.size.y * 0.5 * scale.y <= MAP_FLOOR_TOP:
				continue  # the floor slab; drawing it would black out the whole map
			var half := Vector2(box.size.x * scale.x, box.size.z * scale.z) * 0.5
			var at := Vector2(xform.origin.x, xform.origin.z)
			map_shapes.append({
				"pos": at,
				"size": half * 2.0,
				"angle": atan2(-xform.basis.z.x, -xform.basis.z.z),
			})
			var reach := half.length()  # rotation-proof outer bound
			lo = lo.min(at - Vector2(reach, reach))
			hi = hi.max(at + Vector2(reach, reach))
	if not map_bounds_known and lo.x < INF:
		map_center = Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
		map_extents = (hi - lo) * 0.5
		map_bounds_known = true


func register_combatant(body: Node3D) -> void:
	if not combatants.has(body):
		combatants.append(body)


func unregister_combatant(body: Node3D) -> void:
	combatants.erase(body)


## Smoke clouds currently on the field. They have no collider on purpose (that
## would stop bullets and bodies), so sight checks consult this list instead.
var smokes: Array[Node3D] = []


func register_smoke(cloud: Node3D) -> void:
	if not smokes.has(cloud):
		smokes.append(cloud)


func unregister_smoke(cloud: Node3D) -> void:
	smokes.erase(cloud)


## Does a sight line pass through smoke? Segment-vs-sphere, closest approach
## clamped to the segment, so a cloud behind the viewer or past the target does
## not count. Every AI vision check runs this, so it stays allocation-free and
## returns immediately in the normal case of no smoke on the field.
func sight_blocked(from: Vector3, to: Vector3) -> bool:
	if smokes.is_empty():
		return false
	var seg := to - from
	var len_sq := seg.length_squared()
	for cloud in smokes:
		if not is_instance_valid(cloud):
			continue
		var centre: Vector3 = cloud.global_position
		var t := 0.0 if len_sq < 0.0001 else clampf((centre - from).dot(seg) / len_sq, 0.0, 1.0)
		var nearest := from + seg * t
		var r: float = cloud.radius()
		if nearest.distance_squared_to(centre) <= r * r:
			return true
	return false


func register_spawn_point(team: int, marker: Node3D) -> void:
	_spawns.get_or_add(team, []).append(marker)


## Deterministic when index is given (initial spawns), otherwise random among
## the markers no living player is standing on (respawns), so players never
## stack on one marker.
func get_spawn_point(team: int, index: int = -1) -> Node3D:
	var list: Array = _spawn_list(team)
	if list.is_empty():
		return null
	if index >= 0:
		return list[index % list.size()]
	var free: Array = []
	var roomiest: Node3D = list[0]
	var roomiest_gap := -1.0
	for m in list:
		var gap := _nearest_body_gap(m.global_position)
		if gap >= SPAWN_CLEARANCE:
			free.append(m)
		elif gap > roomiest_gap:
			roomiest_gap = gap
			roomiest = m
	# Every marker crowded (small map, everyone bunched): take the roomiest one.
	return free.pick_random() if not free.is_empty() else roomiest


## Markers a team may start on.
func _spawn_list(team: int) -> Array:
	return _spawns.get(team, [])


## Put each side in its own corner of the map.
##
## Maps only ever author TWO sets of markers, at two ends. With three or four
## teams that leaves the extra sides sharing somebody else's start, which in a
## free-for-all means spawning on top of an enemy. So for a 3+ team match the
## authored layout is replaced wholesale: every side gets a corner of its own,
## as far from the others as the map allows.
##
## Two-team matches are left completely alone — those layouts are hand-placed
## and tuned, and a corner is not automatically better than the spot a map
## author chose.
##
## Ground height comes from the level's own `height_at` when it has one (the
## terrain maps), because colliders are not in the physics world yet when this
## runs and a downward raycast would find nothing.
##
## And it is lifted by SPAWN_LIFT. `height_at` is the ANALYTIC surface, but what
## you collide with is a heightfield MESH sampled on a coarse grid, and across a
## hollow the mesh's flat triangles sit ABOVE the curve they approximate — so a
## body placed at the analytic height starts inside the ground and is stuck
## there. Dropping the last metre costs nothing and is always safe.
func place_corner_spawns(level: Node) -> void:
	if active_teams() <= 2:
		return
	_spawns.clear()
	var inset: Vector2 = map_extents * 0.72
	var corners := [
		Vector2(-inset.x, -inset.y), Vector2(inset.x, inset.y),
		Vector2(inset.x, -inset.y), Vector2(-inset.x, inset.y),
	]
	for team in active_teams():
		var at: Vector2 = corners[team % corners.size()]
		# Three markers spread around the corner, so a side of several bodies
		# does not have to funnel through one point.
		for k in 3:
			var a := TAU * float(k) / 3.0
			var spot := at + Vector2(cos(a), sin(a)) * 5.0
			var y := 0.0
			if level.has_method("height_at"):
				y = level.height_at(spot.x, spot.y)
			var m := Marker3D.new()
			m.position = Vector3(map_center.x + spot.x, y + SPAWN_LIFT,
				map_center.z + spot.y)
			level.add_child(m)
			# Face the middle, so a side spawns looking into the map.
			if Vector2(spot.x, spot.y).length() > 0.1:
				m.look_at(Vector3(map_center.x, y, map_center.z), Vector3.UP)
			register_spawn_point(team, m)


## Last line of defence for the crowded case: shove a spawn transform sideways
## until it clears the body nearest to it, so a respawn never starts inside
## another capsule even when every marker was occupied.
func clear_of_bodies(xform: Transform3D) -> Transform3D:
	var body := _nearest_body(xform.origin)
	if body == null or xform.origin.distance_to(body.global_position) >= MIN_BODY_GAP:
		return xform
	var away := xform.origin - body.global_position
	away.y = 0.0
	if away.length() < 0.01:  # exactly on top of them: any direction will do
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	xform.origin += away.normalized() * MIN_BODY_GAP
	return xform


## Distance from a candidate spawn to the closest living player.
func _nearest_body_gap(pos: Vector3) -> float:
	var body := _nearest_body(pos)
	return INF if body == null else pos.distance_to(body.global_position)


## The living player closest to a point. Dead players have their collision
## disabled, so they don't block a marker.
func _nearest_body(pos: Vector3) -> Node3D:
	var best: Node3D = null
	var best_gap := INF
	for p in combatants:
		if not p.is_alive():
			continue
		var gap := pos.distance_to(p.global_position)
		if gap < best_gap:
			best_gap = gap
			best = p
	return best


## Credit a kill. Only DEATHMATCH scores for it — in ZONES a kill is a means to
## an end, and in ROYALE the only thing that counts is who is left.
func add_frag(team: int) -> void:
	if mode == Mode.DEATHMATCH:
		_award(team)


## Royale has no score, so the match ends the moment one side is the only one
## with anybody left alive. Called whenever a combatant dies.
##
## Deliberately counts COMBATANTS, not players: a squad of bought AI keeps their
## owner's side alive after they personally go down, which is what makes buying
## a squad matter in a mode with no respawns.
func check_last_standing() -> void:
	if mode != Mode.ROYALE or match_over or not match_live:
		return
	var alive := {}
	for c in combatants:
		if is_instance_valid(c) and c.is_alive():
			alive[c.team] = true
	if alive.size() == 1:
		_award(alive.keys()[0])
	elif alive.is_empty():
		match_over = true   # everyone went down together; nobody wins


## A second of holding the capture area.
func add_zone_tick(team: int) -> void:
	if mode == Mode.ZONES:
		_award(team)


func _award(team: int) -> void:
	if match_over:
		return
	# A team can score before reset_match has seen it (a bot spawned early, a
	# team added by the menu), so never assume the key is there.
	scores[team] = int(scores.get(team, 0)) + 1
	score_changed.emit(team, scores[team])
	if scores[team] >= score_limit():
		match_over = true
		match_won.emit(team)
