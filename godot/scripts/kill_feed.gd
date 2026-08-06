extends Control
## THE KILLFEED: what just happened to somebody who is not you.
##
## Every other piece of the HUD reports on the player it belongs to — their
## health, their heat, their cooldowns. This is the only one that reports on the
## MATCH, and until it existed a four-way split screen had no way of telling you
## that anything had happened anywhere except in your own quadrant. You could win
## a Conquest round without ever learning who was good at the game.
##
## IT IS PER VIEWPORT AND IT SHOWS EVERYTHING, both teams. A feed filtered to
## your own side is a feed that goes quiet exactly when you are losing, which is
## when a player most needs to be told what is killing them. There is no secret
## in it either: a name and a colour say a fight happened somewhere, not where.
##
## It reads `GameState.kill_feed` but keeps its OWN arrival times, because the
## entries are shared by four viewports and the ageing is a display decision.

## How long a line stays up, and the tail it fades over. A feed is read out of
## the corner of the eye between fights, so it has to outlast a respawn — but a
## column of eight names is a wall, hence a short life and a hard cap.
const HOLD_TIME := 5.0
const FADE_TIME := 0.6
const MAX_LINES := 5

## The fade is QUANTISED, so a dying line costs a handful of redraws instead of
## one per frame per viewport. Nobody can see the difference between a smooth
## fade and an eight-step one at this size; the frame can.
const FADE_STEPS := 8

## Sized off the split like every other HUD piece — the full-size text runs off
## the edge of a quarter-screen viewport.
const FONT_SIZES := {1: 16, 2: 14, 3: 13, 4: 13}
const MARGIN := Vector2(10.0, 8.0)
const LINE_GAP := 3.0
const ARROW := "  ▸  "

var _lines: Array[Dictionary] = []   # {entry, born, alpha_step}
var _font: Font
var _font_size := 13


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	_font_size = int(FONT_SIZES.get(GameState.human_players, 13))
	# A METHOD of this node, never a lambda: GameState outlives every scene, so a
	# lambda connection here would still be firing into a freed HUD on the next
	# map (house rule 11).
	GameState.kill_logged.connect(_on_kill_logged)
	set_process(false)


func _on_kill_logged(entry: Dictionary) -> void:
	_lines.append({"entry": entry, "born": _now(), "step": FADE_STEPS})
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	set_process(true)     # something is live again; age it until it is not
	queue_redraw()


func _now() -> float:
	return float(Time.get_ticks_msec()) * 0.001


## Ageing only. REDRAWS ONLY WHEN THE PICTURE CHANGES: a line sitting at full
## opacity costs nothing, a line in its last half second costs at most
## FADE_STEPS, and once the feed empties the widget stops processing entirely.
func _process(_delta: float) -> void:
	var now := _now()
	var dirty := false
	for i in range(_lines.size() - 1, -1, -1):
		var age: float = now - float(_lines[i]["born"])
		if age >= HOLD_TIME + FADE_TIME:
			_lines.remove_at(i)
			dirty = true
			continue
		var left := HOLD_TIME + FADE_TIME - age
		var step := FADE_STEPS if left >= FADE_TIME \
			else int(ceil(left / FADE_TIME * FADE_STEPS))
		if step != int(_lines[i]["step"]):
			_lines[i]["step"] = step
			dirty = true
	if dirty:
		queue_redraw()
	if _lines.is_empty():
		set_process(false)


## A line is THREE COLOURED RUNS, and the colours are the whole read: at a glance
## you are not reading names, you are seeing which side lost somebody. The team
## colour is the same one that player's quadrant, minimap dot and tag already
## use, so nothing new has to be learned.
func _draw() -> void:
	if _lines.is_empty():
		return
	var x_right := size.x - MARGIN.x
	var y := MARGIN.y + float(_font_size)
	for line in _lines:
		var entry: Dictionary = line["entry"]
		var alpha := float(line["step"]) / float(FADE_STEPS)
		var killer := str(entry["killer"])
		var victim := str(entry["victim"])
		var suicide: bool = bool(entry["suicide"])
		# A suicide has no killer to name, so the line states the death alone
		# rather than inventing an attacker — "PLAYER 3 ▸ PLAYER 3" reads as a
		# teamkill on yourself, which is not what a fall does.
		var head := "" if suicide else killer
		var mid := "" if suicide else ARROW
		var tail := victim + ("  ✖" if suicide else "")
		var head_col := _team_color(int(entry["killer_team"])) if not suicide \
			else Color(1, 1, 1)
		var tail_col := _team_color(int(entry["victim_team"]))
		# HEADSHOT is marked on the ARROW rather than as another word: the line is
		# already two names long on a quarter screen, and the eye picks a changed
		# glyph out of a column far faster than it reads an appended noun.
		if bool(entry["headshot"]) and not suicide:
			mid = "  ◆  "
		var w_head := _width(head)
		var w_mid := _width(mid)
		var w_tail := _width(tail)
		var x := x_right - (w_head + w_mid + w_tail)
		_text(head, Vector2(x, y), head_col, alpha)
		_text(mid, Vector2(x + w_head, y), Color(0.85, 0.85, 0.85), alpha)
		_text(tail, Vector2(x + w_head + w_mid, y), tail_col, alpha)
		y += float(_font_size) + LINE_GAP


func _width(s: String) -> float:
	if s == "":
		return 0.0
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x


## Drawn with a dark shadow under it. The feed sits over open sky on half these
## maps and over Boreal's snow on one of them, and white text on snow is nothing —
## the same reason every other readout in this HUD carries an outline.
func _text(s: String, at: Vector2, color: Color, alpha: float) -> void:
	if s == "":
		return
	draw_string(_font, at + Vector2(1.0, 1.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1,
		_font_size, Color(0, 0, 0, 0.7 * alpha))
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size,
		Color(color.r, color.g, color.b, alpha))


func _team_color(team: int) -> Color:
	if team < 0 or team >= GameState.team_colors.size():
		return Color(0.85, 0.85, 0.85)
	return GameState.team_colors[team]
