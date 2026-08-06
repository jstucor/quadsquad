class_name HealthGauge
extends Control
## HEALTH AS A NUMBER **AND** A BAR.
##
## It was a number alone ("HP 74"), which is precise and unreadable: a number
## has to be read, and reading is the one thing nobody is doing in the middle of
## a firefight on a quarter of a screen. A bar is understood at a glance and from
## the corner of the eye, which is where this actually gets looked at — and the
## number stays because there IS a moment it matters, the one where you are
## deciding whether you can take another hit.
##
## Drawn rather than assembled out of a ProgressBar and a theme, for the reason
## everything else here is drawn: it is a dozen lines of `_draw`, it needs no
## theme resource to keep in step, and it can do the two things a stock bar
## cannot — a CHIP that lags behind real damage, and a low-health colour change.

## The chip: a paler ghost of the bar that falls to the real value over about a
## third of a second. It is what makes a hit READ as a hit rather than as the bar
## simply being shorter than it was — you see the size of what you just lost.
const CHIP_FALL := 2.6        # bar-fractions per second
const LOW := 0.30             # below this the bar warns
const LOW_COLOR := Color(0.95, 0.26, 0.22)
const BACK := Color(0.05, 0.06, 0.08, 0.72)
const EDGE := Color(0.85, 0.88, 0.94, 0.55)
const BAR_H := 16.0
const NUMBER_W := 52.0        # room for "100" at font size 20

var _color := Color.WHITE     # the owning player's colour
var _fill := 1.0              # 0..1, where health actually is
var _chip := 1.0              # ...and where the ghost has got to
var _shown := -1              # last number drawn, so text is not re-shaped
var _label: Label
var _player: Player


func setup(player: Player, color: Color) -> void:
	_player = player
	_color = color
	custom_minimum_size = Vector2(190.0, BAR_H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_label.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(NUMBER_W, BAR_H)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	player.health_changed.connect(_on_health)
	player.respawned.connect(_on_respawn)
	_on_health(player.health)
	_chip = _fill


func _on_health(hp: float) -> void:
	_fill = clampf(hp / maxf(_player.max_health, 1.0), 0.0, 1.0)
	# Healing does not chip: the ghost only ever falls, so a regen tick does not
	# leave a pale stripe hanging above the bar.
	_chip = maxf(_chip, _fill)
	var shown := maxi(roundi(hp), 0)
	if shown != _shown:
		_shown = shown
		_label.text = str(shown)
	queue_redraw()


func _on_respawn() -> void:
	_chip = 1.0
	_on_health(_player.health)


## The ONLY per-frame work is the chip catching up, and it stops the moment it
## has. A HUD element that redraws every frame re-records its canvas item every
## frame even when nothing moved — the rule the scan and thermal overlays are
## already built around.
func _process(delta: float) -> void:
	if _chip <= _fill + 0.0005:
		set_process(false)
		return
	_chip = maxf(_fill, _chip - CHIP_FALL * delta)
	queue_redraw()


func _draw() -> void:
	if _chip > _fill + 0.0005:
		set_process(true)
	var bar := Rect2(NUMBER_W, 0.0, size.x - NUMBER_W, BAR_H)
	draw_rect(bar, BACK)
	if _chip > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _chip, bar.size.y)),
			Color(1.0, 1.0, 1.0, 0.28))
	var low := _fill <= LOW
	if _fill > 0.0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * _fill, bar.size.y)),
			LOW_COLOR if low else _color)
	# THE BAR IS ALREADY A SIDE'S COLOUR, AND ONE OF THE SIDES IS RED — the
	# Separatists, and any side given the RED tint on the menu. So "the bar turns
	# red" says nothing at all to those players, and the warning has to be carried
	# by something that is not the fill colour. A white edge is the one treatment
	# no faction colour and no chosen tint can collide with.
	draw_rect(bar, Color(1, 1, 1, 0.95) if low else EDGE, false,
		2.5 if low else 1.5)
	_label.add_theme_color_override("font_color",
		LOW_COLOR if low else Color(0.96, 0.97, 1.0))
	# Quarter ticks. A bar with no marks on it reads as "some" — with marks it
	# reads as "a bit over half", which is the question actually being asked.
	for q in [0.25, 0.5, 0.75]:
		var x: float = bar.position.x + bar.size.x * q
		draw_line(Vector2(x, bar.position.y + 3.0),
			Vector2(x, bar.position.y + bar.size.y - 3.0),
			Color(0.05, 0.06, 0.08, 0.5), 1.0)
