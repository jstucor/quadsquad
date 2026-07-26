class_name BoxScreen
## The shared look and feel of the two DEPLOY screens — the buy screen (custom
## classes) and the character select (faction classes).
##
## Both are the same mechanic: a grid of category BOXES with a free cursor over
## them, driven by that player's own stick. The box under the cursor takes the
## player's colour on its border; opening it with accept fills it too and gives
## you a row caret inside; back closes it. Nothing about the build can change
## while no box is open, which is the safety property the whole layout exists
## for (see Player._enter_buy_screen).
##
## It lives here, static, rather than in Main because the character-select
## screen is its own node and must be able to render and resolve boxes without
## going through the HUD that happens to host it. "Looks just like the other
## screen" is then true by construction rather than by two files agreeing.
##
## Everything here takes the boxes as an argument, because only the node holding
## the real PanelContainers knows where they landed: hidden boxes reflow the
## grid, so nothing analytic can work it out.

const EDGE := Color(0.26, 0.30, 0.36)
const BG := Color(0.07, 0.08, 0.11, 0.92)
const DEATH_DIM := Color(0.16, 0.0, 0.0, 0.5)
const DEPLOY_DIM := Color(0.0, 0.0, 0.0, 0.55)
const ELIMINATED := Color(1.0, 0.4, 0.35)
const HEAD := Color(0.55, 0.60, 0.68)
const BLURB := Color(0.7, 0.74, 0.8)
const PROMPT := Color(0.62, 0.66, 0.72)
const SPAWN_READY := Color(0.85, 0.95, 0.8)
const SPAWN_WAIT := Color(0.55, 0.58, 0.62)

## The boxes have to fit whatever slice of the screen this player owns. At four
## players a viewport is a quarter of the window and the full-size layout runs
## off both edges of it, so the metrics are picked off the player count.
const WIDE := {"name": 150, "value": 150, "text": 14, "head": 12, "title": 22}
const TIGHT := {"name": 104, "value": 96, "text": 11, "head": 9, "title": 16}


static func metrics() -> Dictionary:
	return WIDE if GameState.human_players == 1 else TIGHT


## One box's frame. `fill` tints the panel when the box is OPEN — the border
## alone says "the selector is here", and open needs to read differently from
## merely highlighted or the two states are the same picture.
static func panel(edge: Color, fill := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG if fill.a <= 0.0 else BG.blend(Color(fill, 0.22))
	sb.border_color = edge
	sb.set_border_width_all(2 if fill.a > 0.0 else 1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	return sb


## Restyle every box for where the selector is: `here` takes the player's
## colour, `open` fills as well.
static func paint(boxes: Array, at: int, open: bool, color: Color) -> void:
	for i in boxes.size():
		var frame: PanelContainer = boxes[i]
		if frame == null:
			continue
		var here := i == at
		frame.add_theme_stylebox_override("panel", panel(
			color if here else EDGE,
			color if (here and open) else Color(0, 0, 0, 0)))


## The cursor's arena: the union of every VISIBLE box rect. The normalised
## cursor maps across this, so it can reach every box and nothing off the panel.
static func arena(boxes: Array) -> Rect2:
	var out := Rect2()
	var first := true
	for b in boxes:
		if b == null or not (b as Control).visible:
			continue
		var r: Rect2 = (b as Control).get_global_rect()
		if first:
			out = r
			first = false
		else:
			out = out.merge(r)
	return out


static func cursor_pixel(boxes: Array, cursor: Vector2) -> Vector2:
	var a := arena(boxes)
	return a.position + Vector2(cursor.x * a.size.x, cursor.y * a.size.y)


## Set player.buy_box to whichever visible box the cursor is over — the one that
## contains it, else the nearest by centre so there is always a live target.
## Returns true when the box changed, so the caller can redraw its text. Frozen
## while a box is open: the cursor does not roam while you are editing.
static func resolve(player: Player, boxes: Array) -> bool:
	if player.buy_inside:
		return false
	var px := cursor_pixel(boxes, player.buy_cursor)
	var best := player.buy_box
	var best_d := INF
	for i in boxes.size():
		var b: Control = boxes[i]
		if b == null or not b.visible:
			continue
		var r := b.get_global_rect()
		if r.has_point(px):
			best = i
			break
		var d := r.get_center().distance_squared_to(px)
		if d < best_d:
			best_d = d
			best = i
	if best == player.buy_box:
		return false
	player.buy_box = best
	return true


## The reticle: a ring with a centre dot in the player's colour, at the cursor.
## Hidden while a box is open — there is no cursor to steer then.
static func draw_cursor(c: Control, player: Player, boxes: Array, color: Color) -> void:
	if player.buy_inside or c.size.y <= 0.0:
		return
	var local := cursor_pixel(boxes, player.buy_cursor) - c.global_position
	c.draw_arc(local, 9.0, 0.0, TAU, 24, Color(color, 0.95), 2.5, true)
	c.draw_circle(local, 2.5, Color(color, 1.0))


## A row inside a box or column.
static func label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
