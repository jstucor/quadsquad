extends Control
## The hit confirmation marker: four diagonal ticks that snap in around the
## crosshair when your shot lands on someone, then fade.
##
## One of these sits in each player's HUD, so it only ever confirms ITS OWN
## player's hits — which is the whole point on a shared screen, where four
## people are shooting at once and the tracers all look alike.
##
## It draws nothing at rest, so it costs a fade timer and no pixels until you
## actually hit something.

const FADE := 0.32     # seconds from full to gone
const GAP := 6.0       # pixels from centre to the inner end of each tick
const LENGTH := 9.0
const WIDTH := 2.0
# A hit reads white, a headshot gold, a kill red and a size bigger — so you can
# tell what happened from the corner of your eye without reading anything.
const HIT_COLOR := Color(1.0, 1.0, 1.0)
const HEADSHOT_COLOR := Color(1.0, 0.82, 0.35)
const KILL_COLOR := Color(1.0, 0.42, 0.36)
const KILL_SCALE := 1.5

var _left := 0.0
var _color := HIT_COLOR
var _scale := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


## Confirm a hit. Retriggering restarts the fade, so a burst holds the marker up
## for as long as rounds keep landing.
func flash(headshot: bool, killed: bool) -> void:
	_left = FADE
	if killed:
		_color = KILL_COLOR
		_scale = KILL_SCALE
	elif headshot:
		_color = HEADSHOT_COLOR
		_scale = 1.2
	else:
		_color = HIT_COLOR
		_scale = 1.0
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)
	if _left <= 0.0:
		set_process(false)  # back to costing nothing until the next hit
	queue_redraw()


func _draw() -> void:
	if _left <= 0.0 or size.y <= 0.0:
		return
	# Hold full strength briefly, then fade: an instant fade makes a single hit
	# on a fast gun too faint to register.
	var alpha := clampf(_left / (FADE * 0.7), 0.0, 1.0)
	var color := Color(_color.r, _color.g, _color.b, alpha)
	var centre := size * 0.5
	var inner := GAP * _scale
	var outer := (GAP + LENGTH) * _scale
	var corners: Array[Vector2] = [
		Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
	for corner in corners:
		var dir := corner.normalized()
		draw_line(centre + dir * inner, centre + dir * outer, color, WIDTH * _scale)
