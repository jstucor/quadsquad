class_name AbilityGauge
extends Control
## AN ABILITY, THE WAY BATTLEFRONT DRAWS ONE: a round icon that is WHITE while it
## is ready, flips to the SIDE'S colour the moment it is spent, and then refills
## from the bottom until it comes back.
##
## It replaces a line of text ("CABLE 3s", "JET 62%"). The text was accurate and
## useless: reading a number costs a beat, four of them stack into a wall of
## words in the corner of a quarter screen, and none of it can be taken in from
## the edge of vision — which is the only way a HUD is ever actually read while
## someone is shooting at you. A shape that is either full or filling is read
## without looking at it.
##
## WHY THE COLOUR FLIPS THE WAY IT DOES. White is "you have this", and it is the
## brightest thing available so it wins at the edge of vision. Spent, the icon
## takes the SIDE's colour rather than going grey, so a charging ability reads as
## a thing you own that is coming back rather than as a control that has been
## disabled. The refill climbs in white, so what you are watching is white
## coming back.
##
## Everything is drawn (`_draw`) rather than textured. Twelve abilities would be
## twelve images to author, import, keep in step with the catalogue and ship;
## they are a dozen lines of vector art each and they scale to any HUD size.

const DIAM := 46.0
const READY := Color(0.96, 0.97, 1.0)
const EMPTY := Color(0.06, 0.07, 0.09, 0.80)
const RIM := Color(0.90, 0.93, 0.98, 0.65)
## An ability that has just come back FLASHES, briefly and once. Without it the
## moment a gadget becomes available is the one thing on this gauge with no
## signal at all — the fill simply stops, silently, while you are looking
## somewhere else.
const FLASH_TIME := 0.35

var _player: Player
var _slot := -1               # 0/1 for a gadget slot; see the KIND constants
var _kind := KIND_GADGET
var _color := Color.WHITE
var _fill := 1.0              # 0..1, how charged it is
var _live := false            # ACTIVE right now (cloaked, guard up, thrusting)
var _last := -1               # last drawn fill, quantised — see _process
var _flash := 0.0
var _icon := Loadout.Gadget.NONE

## The three things this can be pointed at. A gadget slot is the common case; the
## dash and the guard are not gadgets but are read exactly the same way by a
## player, so they get the same widget rather than a second kind of readout.
const KIND_GADGET := 0
const KIND_DASH := 1
const KIND_GUARD := 2


func setup(player: Player, color: Color, kind: int, slot := 0) -> void:
	_player = player
	_color = color
	_kind = kind
	_slot = slot
	custom_minimum_size = Vector2(DIAM, DIAM)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_read()
	_last = _quantised()


## What this gauge is pointed at, in one place. Returns nothing — it writes
## `_fill`, `_live` and `_icon`, which is what `_draw` reads.
##
## Note it asks the gadget's ACTION rather than what was bought (the catalogue's
## `gadget_action`), so a jump pack shows the jetpack's fuel and an iron halo
## shows the barrier's icon — the same rule `Player._use_gadget` follows.
func _read() -> void:
	_live = false
	match _kind:
		KIND_DASH:
			_icon = Loadout.Gadget.DASH
			_fill = 1.0 - clampf(_player.dash_cooldown() / Player.DASH_COOLDOWN,
				0.0, 1.0)
			return
		KIND_GUARD:
			_icon = Loadout.Gadget.NONE   # drawn as the blade, see _draw_icon
			_fill = _player.guard_level()
			_live = _player.guard_up()
			return
	var fitted := _player.gadget_in(_slot)
	_icon = Loadout.gadget_action(fitted)
	match _icon:
		Loadout.Gadget.NONE:
			_fill = 0.0
		Loadout.Gadget.JETPACK:
			_fill = _player.jet_fuel     # fuel, not a cooldown: same widget
			_live = _player.jet_fuel < 0.999
		Loadout.Gadget.CABLE:
			_fill = 1.0 - clampf(_player.cable_cooldown() / Player.CABLE_COOLDOWN,
				0.0, 1.0)
		Loadout.Gadget.OVERSHIELD, Loadout.Gadget.FURY:
			# A SUSTAINED ability reads its WINDOW while the window is open and
			# its recharge after — one gauge doing both jobs, draining and then
			# refilling, which is exactly what the player is watching for.
			var left: float = _player.overshield_left() \
				if _icon == Loadout.Gadget.OVERSHIELD else _player.fury_left()
			if left > 0.0:
				var full: float = Player.OVERSHIELD_TIME \
					if _icon == Loadout.Gadget.OVERSHIELD else Player.FURY_TIME
				_fill = clampf(left / full, 0.0, 1.0)
				_live = true
			else:
				_fill = _cooldown_fill()
		Loadout.Gadget.CLOAK:
			# Cloaked, the fill DRAINS: while it is up the number that matters is
			# how much invisibility is left, not how long until the next one.
			if _player.cloak_left() > 0.0:
				_fill = clampf(_player.cloak_left() / Player.CLOAK_TIME, 0.0, 1.0)
				_live = true
			else:
				_fill = _cooldown_fill()
		_:
			_fill = _cooldown_fill()


## A gauge with no player behind it, for `tests/hud_look.tscn`. Every icon in
## the match is drawn at one size in one corner of one viewport, so the only way
## to judge the whole set is to lay them out side by side.
func preview(icon: int, fill: float, colour: Color, live := false) -> void:
	_icon = icon
	_fill = fill
	_color = colour
	_live = live
	custom_minimum_size = Vector2(DIAM, DIAM)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	queue_redraw()


func _cooldown_fill() -> float:
	var full := Loadout.cooldown_of(_player.gadget_in(_slot))
	if full <= 0.0:
		return 1.0   # nothing to wait for: a placeable or a toggle
	return 1.0 - clampf(_player.gadget_cooldown(_slot) / full, 0.0, 1.0)


## Redraw only when the picture would actually CHANGE. Cooldowns tick every
## frame, so a naive gauge re-records its canvas item sixty times a second per
## player — four of those per HUD, four HUDs. Quantising to 64 steps means a
## six-second cooldown redraws about ten times a second while it runs and not at
## all when it is full, which is what the rest of the HUD already does.
func _quantised() -> int:
	return roundi(_fill * 64.0) * 4 + (2 if _live else 0) + (1 if _flash > 0.0 else 0)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	var before := _fill
	_read()
	if before < 0.999 and _fill >= 0.999 and not _live:
		_flash = FLASH_TIME
	var now := _quantised()
	if now != _last:
		_last = now
		queue_redraw()


func _draw() -> void:
	var mid := size * 0.5
	var r := DIAM * 0.5 - 2.0
	if _icon == Loadout.Gadget.NONE and _kind == KIND_GADGET:
		return   # an empty slot draws nothing at all, rather than an empty ring
	# The dish: dark when spent, and the player's colour washes it as it charges
	# so a half-charged ability is legibly half from the corner of the eye.
	draw_circle(mid, r, EMPTY)
	if _fill > 0.001:
		# THE FILL IS A VERTICAL WIPE, not a pie slice. A radial sweep reads as a
		# clock — "how long" — and a bar reads as "how much", which is the honest
		# question for fuel, for a guard pool and for a cooldown alike. It is
		# clipped to the circle by drawing the disc and then masking the top with
		# the background colour, which needs no stencil and no shader.
		var full := _fill >= 0.999
		draw_circle(mid, r, _color if not full else READY)
		var cut := r * (1.0 - _fill) * 2.0
		if cut > 0.0:
			draw_rect(Rect2(mid.x - r, mid.y - r, r * 2.0, cut), EMPTY)
			draw_arc(mid, r, 0.0, TAU, 32, EMPTY, 2.0)
	if _flash > 0.0:
		var k := _flash / FLASH_TIME
		draw_circle(mid, r + 3.0 * k, Color(1, 1, 1, 0.5 * k))
	draw_arc(mid, r, 0.0, TAU, 32, RIM, 2.0)
	# The icon sits ON the dish and takes the opposite value to it, so it is
	# legible whether the gauge is white (ready) or dark (spent).
	var ink: Color = Color(0.05, 0.06, 0.09) if _fill > 0.55 else READY
	_draw_icon(mid, r * 0.62, ink)
	if _live:
		draw_arc(mid, r + 3.0, 0.0, TAU, 32, READY, 2.0)


## LITTLE VECTOR PICTURES, one per ability. They are deliberately crude: at 46
## pixels on a quarter screen an icon is a SILHOUETTE and nothing else, and the
## job is only to tell this ability apart from the other one the player is
## carrying — the same argument the character styles make about accessories.
func _draw_icon(mid: Vector2, s: float, ink: Color) -> void:
	if _kind == KIND_GUARD:
		# A blade, standing up: the guard is the saber's, and no other gauge on
		# the HUD is a vertical line.
		draw_line(mid + Vector2(0, s), mid + Vector2(0, -s * 0.9), ink, 3.0)
		draw_line(mid + Vector2(-s * 0.4, s * 0.45),
			mid + Vector2(s * 0.4, s * 0.45), ink, 3.0)
		return
	match _icon:
		Loadout.Gadget.JETPACK:
			for side: float in [-1.0, 1.0]:
				draw_rect(Rect2(mid.x + side * s * 0.62 - s * 0.22, mid.y - s * 0.9,
					s * 0.44, s * 1.2), ink)
				_flame(mid + Vector2(side * s * 0.62, mid.y * 0.0 + s * 0.45), s, ink)
		Loadout.Gadget.CABLE:
			# A line with a CLAW on the end. The old one was a line and a smooth
			# arc, which at this size read as a spanner.
			draw_line(mid + Vector2(-s * 0.85, s * 0.85), mid + Vector2(0.0, -s * 0.1),
				ink, 3.0)
			var head := mid + Vector2(0.0, -s * 0.15)
			for a: float in [-0.95, -0.35, 0.25]:
				draw_line(head, head + Vector2(cos(a - PI * 0.5), sin(a - PI * 0.5))
					* s * 0.75, ink, 2.5)
			draw_circle(head, s * 0.16, ink)
		Loadout.Gadget.CLOAK:
			draw_arc(mid, s * 0.85, 0.0, TAU, 20, ink, 2.0)
			for k in 3:
				var y: float = mid.y - s * 0.4 + k * s * 0.4
				draw_line(Vector2(mid.x - s * 0.7, y), Vector2(mid.x + s * 0.7, y),
					Color(ink, 0.55 - k * 0.12), 2.0)
		Loadout.Gadget.SHIELD:
			var pts := PackedVector2Array([
				mid + Vector2(-s * 0.75, -s * 0.7), mid + Vector2(s * 0.75, -s * 0.7),
				mid + Vector2(s * 0.75, s * 0.15), mid + Vector2(0, s * 0.9),
				mid + Vector2(-s * 0.75, s * 0.15)])
			draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 2.5)
		Loadout.Gadget.TURRET:
			draw_rect(Rect2(mid.x - s * 0.5, mid.y - s * 0.35, s, s * 0.5), ink)
			draw_line(mid + Vector2(s * 0.45, -s * 0.1),
				mid + Vector2(s * 0.95, -s * 0.1), ink, 3.0)
			draw_line(mid + Vector2(-s * 0.5, s * 0.15),
				mid + Vector2(-s * 0.8, s * 0.9), ink, 2.5)
			draw_line(mid + Vector2(s * 0.5, s * 0.15),
				mid + Vector2(s * 0.8, s * 0.9), ink, 2.5)
		Loadout.Gadget.MORTAR:
			draw_line(mid + Vector2(-s * 0.5, s * 0.8), mid + Vector2(s * 0.2, -s * 0.6),
				ink, 4.0)
			draw_arc(mid + Vector2(0, s * 0.2), s * 0.9, PI * 1.15, PI * 1.85,
				12, ink, 2.0)
		Loadout.Gadget.SCAN_DART:
			draw_line(mid + Vector2(-s * 0.8, s * 0.5), mid + Vector2(s * 0.3, -s * 0.6),
				ink, 3.0)
			for k in 2:
				draw_arc(mid + Vector2(s * 0.3, -s * 0.6), s * (0.35 + k * 0.3),
					PI * 1.1, PI * 1.9, 10, Color(ink, 0.8 - k * 0.25), 2.0)
		Loadout.Gadget.WRIST_ROCKET:
			# An actual rocket rather than a diagonal stroke: a body, a nose, two
			# fins and exhaust. A bare line read as "something sharp" and was
			# indistinguishable from the dart at gauge size.
			var tail := mid + Vector2(-s * 0.55, s * 0.55)
			var nose := mid + Vector2(s * 0.65, -s * 0.65)
			draw_line(tail, nose, ink, 5.0)
			draw_line(nose, nose + Vector2(-s * 0.3, -s * 0.02), ink, 2.0)
			draw_line(nose, nose + Vector2(-s * 0.02, s * 0.3), ink, 2.0)
			for side: float in [-1.0, 1.0]:
				var fin := tail + Vector2(s * 0.22, s * 0.22) * 0.0
				draw_line(fin, fin + Vector2(side * s * 0.34, -side * s * 0.34) * 0.9,
					ink, 2.0)
			_flame(tail + Vector2(-s * 0.12, s * 0.12), s * 0.9, ink)
		Loadout.Gadget.FORCE_PUSH, Loadout.Gadget.FORCE_PULL:
			# THE WHOLE ICON IS MIRRORED, not just the arcs. Drawn as "a hand with
			# waves coming off it", push and pull came out identical — the arcs
			# were centred on the hand either way, so the only difference was a
			# radius nobody can see. The palm faces the way the force goes: push
			# from the left with the waves leaving to the right, pull from the
			# right with the waves arriving from the left.
			var m := 1.0 if _icon == Loadout.Gadget.FORCE_PUSH else -1.0
			var palm := Vector2(mid.x - s * 0.7 * m, mid.y)
			draw_line(palm + Vector2(0.0, -s * 0.55), palm + Vector2(0.0, s * 0.55),
				ink, 4.0)
			for k in 3:
				var span := PI * 0.38
				var centre := 0.0 if m > 0.0 else PI
				draw_arc(palm, s * (0.42 + k * 0.34), centre - span, centre + span,
					12, Color(ink, 0.9 - k * 0.24), 2.5)
		Loadout.Gadget.FORCE_LEAP:
			draw_line(mid + Vector2(0, s * 0.85), mid + Vector2(0, -s * 0.7), ink, 3.0)
			draw_line(mid + Vector2(-s * 0.5, -s * 0.2), mid + Vector2(0, -s * 0.8),
				ink, 3.0)
			draw_line(mid + Vector2(s * 0.5, -s * 0.2), mid + Vector2(0, -s * 0.8),
				ink, 3.0)
		Loadout.Gadget.FORCE_LIGHTNING:
			draw_polyline(PackedVector2Array([
				mid + Vector2(s * 0.35, -s * 0.9), mid + Vector2(-s * 0.25, -s * 0.05),
				mid + Vector2(s * 0.2, -s * 0.05), mid + Vector2(-s * 0.35, s * 0.9)]),
				ink, 3.0)
		Loadout.Gadget.OVERSHIELD:
			# A shell over a figure: the same shield outline as the barrier, but
			# doubled, because it is worn rather than planted.
			for k in 2:
				var r := s * (0.55 + k * 0.32)
				draw_arc(mid + Vector2(0, s * 0.15), r, PI * 1.05, PI * 1.95,
					14, Color(ink, 1.0 - k * 0.35), 2.5)
			draw_circle(mid + Vector2(0, s * 0.2), s * 0.22, ink)
		Loadout.Gadget.FURY:
			# A roar: three rising strokes. Nothing else on the sheet is a burst.
			for k in 3:
				var x: float = mid.x - s * 0.55 + k * s * 0.55
				var h: float = s * (0.5 + 0.28 * (1 - absi(k - 1)))
				draw_line(Vector2(x, mid.y + s * 0.7), Vector2(x, mid.y - h),
					ink, 3.0)
		Loadout.Gadget.DASH:
			for k in 2:
				var x: float = mid.x - s * 0.5 + k * s * 0.6
				draw_polyline(PackedVector2Array([
					Vector2(x - s * 0.3, mid.y - s * 0.6), Vector2(x + s * 0.2, mid.y),
					Vector2(x - s * 0.3, mid.y + s * 0.6)]), ink, 3.0)
		Loadout.Gadget.GRENADE_FRAG, Loadout.Gadget.GRENADE_STICKY, \
		Loadout.Gadget.GRENADE_SMOKE:
			draw_arc(mid + Vector2(0, s * 0.15), s * 0.62, 0.0, TAU, 18, ink, 2.5)
			draw_line(mid + Vector2(-s * 0.1, -s * 0.45),
				mid + Vector2(-s * 0.1, -s * 0.85), ink, 3.0)
			# The three grenades have to be told APART, since a kit can only fit
			# one and the choice is the whole point: smoke puffs, a sticky has
			# tack coming off it, and the frag is the plain one.
			if _icon == Loadout.Gadget.GRENADE_SMOKE:
				for k in 3:
					draw_arc(mid + Vector2(-s * 0.5 + k * s * 0.5, -s * 0.55),
						s * 0.22, 0.0, TAU, 10, Color(ink, 0.7), 2.0)
			elif _icon == Loadout.Gadget.GRENADE_STICKY:
				for k in 4:
					var a: float = PI * 0.25 + k * PI * 0.5
					var from := mid + Vector2(0, s * 0.15) \
						+ Vector2(cos(a), sin(a)) * s * 0.62
					draw_line(from, from + Vector2(cos(a), sin(a)) * s * 0.3,
						ink, 2.5)
		_:
			draw_circle(mid, s * 0.45, ink)


func _flame(at: Vector2, s: float, ink: Color) -> void:
	draw_polyline(PackedVector2Array([
		at + Vector2(-s * 0.2, 0.0), at + Vector2(0.0, s * 0.55),
		at + Vector2(s * 0.2, 0.0)]), Color(ink, 0.9), 2.5)
