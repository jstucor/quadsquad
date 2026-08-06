extends Control
## THE BALL TURRET'S OWN SIGHT, drawn over one viewport while that player is
## riding the HAMMERHEAD.
##
## It exists because the ordinary HUD answers none of the questions a gunner has.
## The bloom crosshair reads `Weapon.current_spread_deg()` off the rifle the
## player is CARRYING, and while mounted that rifle is hidden and irrelevant — so
## the reticle on screen was describing the cone of a gun that was not firing,
## while the gun that WAS firing had no reticle at all. The gauges beside it read
## a body that cannot be hurt and abilities that cannot be used.
##
## What a gunner actually has to know is three things, and they are the only
## three here: WHERE the rounds go, HOW LONG the ride lasts, and WHETHER the gun
## is ready to fire again. Everything else is deliberately absent — this is a
## sight, not a dashboard, and the whole point of the reward is looking at the
## ground.
##
## Its own script rather than a lambda on the tree, for the reason every other
## HUD piece here has one: a closure on `process_frame` outlives the scene it was
## built for (house rule 11).

## In the SIDE's colour, like the rest of the gameplay HUD.
var color := Color.WHITE

var _player: Player
## The last picture drawn, so a sight that has not changed is not re-recorded
## sixty times a second for four viewports. Quantised, exactly as the ability
## gauge quantises its fill: the eye cannot read a hundredth of a second and the
## canvas item does not need to hear about it.
var _seen_left := -1
var _seen_ready := false
var _seen_on := false
## Where the sight was last drawn. A vehicle's sight sits on the point its GUN is
## about to hit, so it moves independently of everything else on this widget.
var _seen_aim := Vector2.ZERO


func setup(p: Player, c: Color) -> void:
	_player = p
	color = c
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Asked once per frame by `Main._tick_overlays`, which is where every other
## overlay's per-frame question lives so the HUD's cost is visible in one place.
func tick() -> void:
	var ride := _ride()
	var on := not ride.is_empty()
	# The clearing frame matters: coming out of the ball has to take the sight
	# off the screen, and a redraw that only happens while the sight is UP can
	# never do that.
	if on != _seen_on:
		_seen_on = on
		visible = on
		queue_redraw()
	if not on:
		return
	# A RIDE COUNTS SECONDS; A MACHINE YOU DRIVE COUNTS HULL. Whichever it is, the
	# widget redraws when the number it prints changes — and a vehicle also has
	# to redraw as the sight MOVES, which a clock never does (see `_seen_aim`).
	var left := int(ceil(_bar_value(ride)))
	var ready: bool = bool(ride["ready"])
	var aim := _aim_screen(ride)
	if aim.distance_squared_to(_seen_aim) > 4.0:
		_seen_aim = aim
		queue_redraw()
	if left != _seen_left or ready != _seen_ready:
		_seen_left = left
		_seen_ready = ready
		queue_redraw()


## The ride, or an empty dictionary when this player is not in one. Asked of the
## MOUNT rather than tested against a class: a gunship has no `class_name` and
## the question here is "does this thing have a gunner's sight to draw", which is
## what the method's presence says.
func _ride() -> Dictionary:
	if _player == null or not is_instance_valid(_player):
		return {}
	var m: Node3D = _player.mount()
	if m == null or not m.has_method("gunner_readout"):
		return {}
	return m.gunner_readout()


## The bracket sight. Deliberately NOT a crosshair with a dot in the middle: the
## rounds land at the centre and the centre is the one part of the screen the
## gunner needs to be able to SEE THROUGH, because the target is a man half a
## metre wide seen from 46 m up. Four corner brackets frame that point and leave
## it clear, which is the same reason a camera's focus box is a box.
const REACH := 26.0        # how far out the brackets sit from centre
const ARM := 9.0           # how long each bracket arm is
const THICK := 2.0


## The number under the sight: seconds left of a ride, or hull left of a machine.
func _bar_value(ride: Dictionary) -> float:
	return float(ride["left"]) if ride.has("left") else float(ride.get("hull", 0.0))


func _bar_total(ride: Dictionary) -> float:
	return float(ride["total"]) if ride.has("total") else float(ride.get("hull_max", 1.0))


## WHERE THE SIGHT GOES, and it is not always the middle of the screen.
##
## A ride's seat is boresighted by construction — the HAMMERHEAD's camera sits 2.25 m
## straight behind its own muzzle — so the centre IS where the rounds go. A
## vehicle's is not: the MARAUDER's cannon is under the cockpit, a speeder's is out
## on the nose, and the gun is clamped to a cone the camera is not, so past the
## stop the barrel stays put while the view keeps turning. So the mount hands
## over the world point its next round LANDS on and the sight is drawn there.
##
## Behind the camera it falls back to the centre rather than drawing a sight
## somewhere impossible — `unproject_position` happily returns a point for
## something behind you, mirrored, which is worse than no sight at all.
func _aim_screen(ride: Dictionary) -> Vector2:
	var mid := size * 0.5
	if not ride.has("aim") or _player == null or not is_instance_valid(_player):
		return mid
	var cam: Camera3D = _player.camera()
	var at: Vector3 = ride["aim"]
	if cam == null or at == Vector3.ZERO or cam.is_position_behind(at):
		return mid
	return cam.unproject_position(at)


func _draw() -> void:
	var ride := _ride()
	if ride.is_empty():
		return
	var mid := _aim_screen(ride)
	# READY is the side's colour at full strength; RELOADING drops it back, so
	# the sight itself reports the gun's state and no second widget has to.
	var ready: bool = bool(ride["ready"])
	var col := Color(color.r, color.g, color.b, 1.0 if ready else 0.45)

	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := mid + Vector2(sx * REACH, sy * REACH)
			draw_line(corner, corner - Vector2(sx * ARM, 0.0), col, THICK)
			draw_line(corner, corner - Vector2(0.0, sy * ARM), col, THICK)
	# A single pip at the exact impact point. One pixel of information, and it is
	# the one the whole widget is for.
	draw_circle(mid, 1.6, col)

	# THE CLOCK. A ride you cannot see the end of is one you cannot spend — the
	# last four seconds are when a gunner picks their final target rather than
	# being cut off mid-burst.
	var total: float = maxf(_bar_total(ride), 0.001)
	var frac: float = clampf(_bar_value(ride) / total, 0.0, 1.0)
	var bar := Vector2(minf(size.x * 0.34, 260.0), 4.0)
	# PINNED TO THE SCREEN, not to the sight. The sight moves with the gun; a
	# readout that followed it around would be a label chasing the crosshair.
	var at := Vector2(size.x * 0.5 - bar.x * 0.5, size.y * 0.82)
	draw_rect(Rect2(at, bar), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(at, Vector2(bar.x * frac, bar.y)), color)

	var font := ThemeDB.fallback_font
	var label := "%s   %ds" % [str(ride["name"]), int(ceil(float(ride["left"])))] \
		if ride.has("left") else "%s   HULL %d%%" % [str(ride["name"]),
			int(round(frac * 100.0))]
	var fs := 13
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(size.x * 0.5 - w * 0.5, at.y - 8.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
