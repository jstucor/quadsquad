extends Control
## WHERE THAT CAME FROM — a wedge around the crosshair pointing at whatever just
## hurt you, one per viewport.
##
## The game already told you that you had been hit, three ways: a red flash, a
## dull thud, and the number on the health bar going down. It never told you the
## one thing that decides what you do next. On a quarter-screen viewport with
## eight bodies on the field, "I am taking fire" without "from behind me and to
## the left" is not actionable — you turn the wrong way about half the time, and
## dying to something you never saw reads as the game being unfair rather than as
## having been outplayed.
##
## THE BEARING IS RECOMPUTED EVERY FRAME FROM THE WORLD POSITION, never frozen at
## the angle the hit arrived on. That is the entire mechanic: the marker has to
## swing toward twelve o'clock as you turn toward the shooter, because what a
## player does with it is turn until it is at the top. A marker that held the
## angle it was created with would point somewhere meaningless the instant you
## moved, and would actively mislead — worse than not drawing it.
##
## Its own script rather than a lambda on the tree, for the reason every other
## HUD piece here has one: a closure on `process_frame` outlives the scene it was
## built for (house rule 11).

## How long a marker lives. Long enough to read and turn on, short enough that
## the screen is not ringed with history — this is a warning, not a log.
const LIFE := 1.15
## Where the wedges sit, as a share of the viewport's SHORT axis. Outside the
## reticle so it never touches the crosshair, well inside the edges so it is not
## competing with the minimap or the health bar.
## Photographed over a real match, 0.17 with a 26-degree spread came back as a
## small red tick rather than an arc — legible only because I knew where to look,
## which is the opposite of what a warning has to be. A wedge has to read as a
## DIRECTION at a glance from the edge of vision, and at a quarter-screen
## viewport it has half these pixels to do it in.
const RADIUS := 0.20
## The wedge itself.
const SPREAD := deg_to_rad(36.0)   # how wide the arc is
const THICK := 8.0
const SEGMENTS := 11

## Two hits from nearly the same place are ONE marker refreshed, not two stacked.
## A burst is six rounds; six overlapping wedges is a solid blob that says
## nothing more than one does, and it would drown the second shooter who is the
## thing you actually need to know about.
const MERGE_ANGLE := deg_to_rad(30.0)
## ...and a cap, so a crossfire cannot ring the whole screen.
const MAX_MARKS := 4

## RED, AND DELIBERATELY NOT THE SIDE'S COLOUR, which is the one place this HUD
## departs from the team-colour rule.
##
## Everything else on screen was moved onto the faction's colour because it is
## all answering "whose is that". This answers something else entirely — "you are
## being hurt" — and it is the only element on the HUD that is about harm rather
## than about allegiance. Drawing it in the side's colour would make the warning
## look like a friendly marker, and on a side whose colour IS red it would be
## indistinguishable from the rest of the frame at exactly the moment it has to
## cut through. Same argument the health gauge's white low-health edge makes.
const CORE := Color(1.0, 0.93, 0.90)
const EDGE := Color(1.0, 0.22, 0.14)

var player: Player

## {bearing_from: Vector3 (world), left: float}
var _marks: Array[Dictionary] = []
var _was_live := false


func setup(p: Player) -> void:
	player = p
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.hit_from.connect(_on_hit_from)
	# A fresh body is not under fire. Without this you deploy wearing the last
	# life's last wedge.
	p.respawned.connect(func() -> void:
		_marks.clear()
		queue_redraw())


func _on_hit_from(source: Vector3) -> void:
	if player == null or not is_instance_valid(player):
		return
	var bearing := _bearing_to(source)
	# REFRESH THE NEAREST EXISTING MARKER rather than adding one, if it is close
	# enough to be the same threat. Compared as ANGLES rather than as positions,
	# because two men standing ten metres apart at eighty metres out are one
	# direction as far as the player turning toward them is concerned.
	for m in _marks:
		if absf(wrapf(_bearing_to(m["from"]) - bearing, -PI, PI)) <= MERGE_ANGLE:
			m["from"] = source
			m["left"] = LIFE
			return
	if _marks.size() >= MAX_MARKS:
		# Drop the faintest, which is the oldest — a crossfire should show the
		# threats you have most recently taken fire from.
		var worst := 0
		for i in _marks.size():
			if float(_marks[i]["left"]) < float(_marks[worst]["left"]):
				worst = i
		_marks.remove_at(worst)
	_marks.append({"from": source, "left": LIFE})


## Asked once a frame by `Main._tick_overlays`, where every other overlay's
## per-frame question lives so the HUD's cost is visible in one place.
##
## IT REDRAWS EVERY FRAME WHILE ANYTHING IS LIVE, which is the opposite of the
## discipline most of this HUD follows — and it has to. The picture depends on
## where the player is LOOKING, so it changes on every frame they turn, which is
## most frames while somebody is shooting at them. It costs nothing the rest of
## the time: markers are the exception, not the state.
func tick(delta: float) -> void:
	if _marks.is_empty():
		# THE CLEARING FRAME. Without it the last wedge stays burned on screen
		# after its marker has gone — the same rule the scan overlay follows.
		if _was_live:
			_was_live = false
			queue_redraw()
		return
	var i := _marks.size() - 1
	while i >= 0:
		_marks[i]["left"] = float(_marks[i]["left"]) - delta
		if float(_marks[i]["left"]) <= 0.0:
			_marks.remove_at(i)
		i -= 1
	_was_live = true
	queue_redraw()


## Screen bearing to a world point: 0 is dead ahead, positive is to the right.
##
## Taken from the BODY's yaw rather than from the camera. They are the same
## number for a body on foot, and where they are not — a gunner in a mount, whose
## view a vehicle is writing — the body's yaw is still what the player's own
## stick is steering, so it is the one that stays meaningful.
func _bearing_to(source: Vector3) -> float:
	var to := source - player.global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return 0.0
	var local := to.rotated(Vector3.UP, -player.rotation.y)
	return atan2(local.x, -local.z)


func _draw() -> void:
	if _marks.is_empty() or size.y <= 0.0:
		return
	var mid := size * 0.5
	var radius: float = minf(size.x, size.y) * RADIUS
	for m in _marks:
		var fade: float = clampf(float(m["left"]) / LIFE, 0.0, 1.0)
		# Eased rather than linear: a marker that fades evenly spends half its
		# life being too faint to read, where one that holds and then goes is
		# legible for the whole of the time it exists.
		var alpha: float = fade * fade * 0.5 + fade * 0.5
		var bearing := _bearing_to(m["from"])
		_wedge(mid, radius, bearing, alpha)


## One arc, drawn as a short polyline around the crosshair. A LINE and not a
## filled triangle: a solid wedge at this radius covers the ground the player is
## about to have to look at, and the thing being communicated is an ANGLE, which
## an arc states and a blob only implies.
func _wedge(mid: Vector2, radius: float, bearing: float, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in SEGMENTS:
		var t: float = float(i) / float(SEGMENTS - 1) - 0.5
		var a: float = bearing + t * SPREAD
		# Screen space: bearing 0 is UP, and y grows downward.
		pts.append(mid + Vector2(sin(a), -cos(a)) * radius)
	# Drawn twice: a wide dark edge under a narrow bright core, which is what
	# keeps it readable over a bright skybox and over dark ground alike. The same
	# reason the countdown and the pad banner carry outlines.
	draw_polyline(pts, Color(EDGE.r, EDGE.g, EDGE.b, alpha), THICK, true)
	draw_polyline(pts, Color(CORE.r, CORE.g, CORE.b, alpha * 0.9),
		THICK * 0.45, true)
