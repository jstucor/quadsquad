extends Node
class_name FrameGovernor

## THE GOVERNOR: hold the frame to its interval by moving the render scale.
##
## WHY THIS EXISTS, AND WHY A SETTING CANNOT DO ITS JOB. Every static quality
## number in `Quality` was measured, and then the same configuration was measured
## again later in the session and came back two to three times slower — a 4-viewport
## match on the development machine runs at 26 ms cold and 48 ms after two minutes
## at full tilt, because the GPU drops to a fraction of its clock when hot. The
## LOW tier held 58.8 fps in one run and 42.6 fps in another with nothing changed
## but the temperature of the chip.
##
## So there is no tier that is correct for this machine. There is only a tier that
## is correct for this machine RIGHT NOW, and a setting picked to survive the worst
## case throws away most of the picture for the first minute of every match.
##
## THE KNOB IS RESOLUTION, because the frame is fill-bound and resolution is the
## only lever that is both continuous and certain. The ablation sweep in
## `tests/render_cost.gd` cleared the plausible alternatives: the terrain's
## 48-sin-per-fragment shader costs 0.07 ms, the sky costs nothing, and glow and
## the shadow filter are inside the noise. Shadow map size is worth real
## milliseconds but it comes in factor-of-two steps, which is far too coarse to
## steer with. Pixels come in any quantity you like.
##
## IT ALSO BREAKS THE THROTTLE SPIRAL, which is the part that matters most. A GPU
## held at 100% gets hot and slows down, which makes the frame miss, which keeps it
## at 100%. Giving the frame back its headroom lets the chip idle between frames,
## and a cooler chip is a faster one — so the governor is not just trading picture
## for smoothness, it is buying back some of the performance it spent.

## Sampled over this long before deciding anything. Long enough that one bad frame
## — a death, a shader compile, the map screen opening — cannot move the scale, and
## short enough to react inside the couple of seconds it takes a chip to throttle.
const WINDOW := 0.6
## How much the scale moves per decision. Coarse on purpose: changing it
## reallocates every viewport's render target, which is exactly the kind of thing
## the project's no-per-frame-allocations rule is about, so this is a step taken
## rarely rather than a value tracked continuously.
const STEP := 0.05
## Never go below this. Past it the game is legible but no longer worth looking at,
## and the honest answer for a machine that needs it is a lower frame cap.
const MIN_SCALE := 0.55
## Drop when the window's average is past this much of the interval. Slightly over
## 1.0 rather than exactly, because a frame that lands within a few percent of its
## interval is on time and chasing it just oscillates.
const DROP_AT := 1.06
## How many clean windows before climbing back a resolution step. Asymmetric on
## purpose: dropping late costs a visible stutter, climbing early costs a visible
## change in sharpness, and of the two the stutter is worse — so it falls fast and
## rises slowly. What counts as "clean" is in `_process`, and is not what you would
## first guess: see the note there about measuring headroom you are sleeping through.
const RAISE_WINDOWS := 4

## How many windows of missing at the FLOOR before giving up on this frame rate
## and taking the next rung down. Slower than a resolution step, because halving
## the frame rate is the most visible thing here and must never happen on a rough
## patch — only on a machine that genuinely cannot hold the rate.
const RUNG_WINDOWS := 5
## A miss bigger than this much of the interval goes straight to the next frame
## rate instead of trimming resolution. Below two, because the interesting case is
## a frame that is ALTERNATING between hitting and missing — which averages around
## 1.5 intervals and is the worst-looking thing a frame can do.
const RUNG_NOW := 1.45
## ...or this fraction of the window's frames arriving late, whichever fires first.
## A fifth is about where a run of dropped frames stops reading as one hitch and
## starts reading as the game being rough.
const LATE_FRAC := 0.2
## ...and how many windows of real headroom before trying to climb back up a rung.
## Much slower still: a wrong climb costs a stutter and then a visible drop back.
const RUNG_RAISE_WINDOWS := 14
## A probe that fails doubles the wait before the next one, up to this. About a
## minute, which is long enough that a machine which simply cannot hold the higher
## rate stops asking, and short enough that one which has cooled down gets another
## go within a match.
const PROBE_WINDOWS_MAX := 100

var _views: Array[SubViewport] = []
var _ceiling := 1.0        # how far the picture may climb back
var _scale := 1.0
var _t := 0.0
var _frames := 0
var _quiet := 0
var _missing := 0
var _late := 0
var _probing := false
var _probe_survived := 0
var _probe_windows := RUNG_RAISE_WINDOWS
var _rung := 0
## The frame rates this governor may settle on, worst last. Built from the
## player's own cap, which is a CEILING and not a target — see `_build_ladder`.
var _rungs: PackedInt32Array = PackedInt32Array([60, 30])
## Purely for the report at the end of a match and for the tests: what it did.
var drops := 0
var raises := 0
var rung_drops := 0


## `start` is where the tier put the render scale and `ceiling` is how far this may
## climb — separate arguments because they answer different questions. Under AUTO
## the ceiling is full resolution however low the start is: after halving the frame
## rate there is twice the budget, and the governor has to be able to spend it on
## the picture rather than sitting at a scale the tier chose for a rate that is no
## longer being attempted.
func setup(views: Array, start: float, ceiling := 1.0) -> void:
	_views.clear()
	for v in views:
		_views.append(v)
	_ceiling = maxf(ceiling, start)
	_apply(start)
	_build_ladder()
	Engine.max_fps = _rungs[0]


## THE FRAME RATE IS A LADDER, NOT A NUMBER, and this is the half of the governor
## that matters most on hardware like this. Resolution alone ran out: measured at
## four viewports on a hot GPU the scale bottomed out at 0.55 and the frame was
## still arriving at 41 fps, missing 70% of its intervals. There was nothing left
## to give.
##
## Dropping to 30 gives the frame TWICE THE BUDGET, which is far more than the
## whole resolution range was worth — and the measurement that settles the argument
## is that MEDIUM at a 30 cap came back p50 33.28, p95 33.57, worst 33.89. Six
## tenths of a millisecond of variance across 240 frames, at FULL resolution. That
## is not a compromise, it is the smoothest the game has ever measured.
##
## So a rung drop also hands the resolution back (`_apply(_ceiling)`): at half the
## rate the pixels are affordable again, and picture is what the player would
## rather have once the pacing is fixed.
##
## A cap the player chose is respected as a CEILING. Picking 30 explicitly means 30
## and nothing lower; picking DISPLAY means the governor may try 60 and settle at
## 30 rather than run uncapped, because an uncapped frame on this hardware is the
## throttle spiral the whole file is about.
func _build_ladder() -> void:
	var cap := Controls.fps_cap()
	var top := cap if cap > 0 else 60
	var out := PackedInt32Array()
	for fps in [120, 60, 30]:
		if fps <= top:
			out.append(fps)
	if out.is_empty():
		out.append(top)
	_rungs = out
	_rung = 0


func _process(delta: float) -> void:
	if _views.is_empty():
		return
	var interval := 1000.0 / float(_rungs[_rung])
	_t += delta
	_frames += 1
	# COUNT THE LATE FRAMES, not just the time. Smoothness is a property of the
	# TAIL and the average hides it: the 100-body case measured a comfortable 32.9 ms
	# mean with a 42.4 ms 95th percentile, so one frame in ten was arriving a whole
	# interval late while the mean said everything was fine and the governor
	# consequently did nothing. A fraction-late trigger is what a player actually
	# perceives.
	if delta * 1000.0 > interval * 1.05:
		_late += 1
	if _t < WINDOW:
		return
	var avg_ms := (_t / float(_frames)) * 1000.0
	var late_frac := float(_late) / float(_frames)
	_t = 0.0
	_frames = 0
	_late = 0

	if avg_ms > interval * DROP_AT or late_frac > LATE_FRAC:
		_quiet = 0
		# THE SIZE OF THE MISS CHOOSES THE LEVER. A frame arriving at nearly twice
		# its interval is not going to be rescued by five percent of resolution, and
		# walking it down a step at a time spends several seconds of visible stutter
		# finding that out — measured on the 100-body case, which spent six windows
		# reaching the floor before it was allowed to consider the thing that would
		# actually fix it. Past this much of a miss, go straight for the frame rate.
		if avg_ms > interval * RUNG_NOW and _rung + 1 < _rungs.size():
			_drop_rung()
			_missing = 0
			return
		if _scale > MIN_SCALE:
			_apply(maxf(_scale - STEP, MIN_SCALE))
			drops += 1
			return
		# Out of pixels to give. Take the next frame rate down.
		#
		# AND DO NOT HAND THE RESOLUTION BACK, which is the obvious move and was the
		# first version: halving the rate doubles the budget, so surely the pixels
		# are affordable again. Measured at 100 bodies on four viewports it produced
		# a SAWTOOTH — floor, drop to 30, jump to full resolution, immediately start
		# walking back down to the floor — and every one of those steps is a visible
		# change in sharpness. The rate drop and the resolution are answers to the
		# same question and giving both back at once asks it again.
		#
		# The raise path below already knows how to spend real headroom, and its test
		# ("is the frame comfortably inside its interval") is exactly the right one.
		# So this only ever takes: monotone down, gradual up, no sawtooth.
		_missing += 1
		if _missing >= RUNG_WINDOWS and _rung + 1 < _rungs.size():
			_missing = 0
			_drop_rung()
		return
	_missing = 0
	# WHAT "COMFORTABLE" HAS TO MEAN UNDER VSYNC, and getting this wrong made the
	# first version a one-way ratchet that never gave anything back.
	#
	# The obvious test is "the average is well under the interval". It cannot work:
	# with vsync or a frame cap, a frame that has headroom SLEEPS until the interval
	# is up, so a machine coasting at half the work still measures exactly the
	# interval. The condition was therefore never true, every measurement came back
	# `0 raises`, and a match that hit one rough patch stayed degraded for the rest
	# of the session.
	#
	# What IS observable through a cap is whether anything is arriving late. No late
	# frames at all across a whole window, and an average that has not drifted above
	# the interval, is as much headroom as a capped frame can ever report.
	if late_frac <= 0.0 and avg_ms <= interval * 1.02:
		_quiet += 1
		if _scale < _ceiling:
			if _quiet >= RAISE_WINDOWS:
				_quiet = 0
				_apply(minf(_scale + STEP, _ceiling))
				raises += 1
			return
		# Full resolution and nothing late: the chip may have cooled, or the player
		# may have walked somewhere cheap. The only way to find out whether the rate
		# above is affordable is to TRY it — there is no way to measure headroom you
		# are sleeping through — so this is a probe, and the drop path above is what
		# catches it if the answer is no.
		if _rung > 0 and _quiet >= _probe_windows:
			_quiet = 0
			_rung -= 1
			_probing = true
			_probe_survived = 0
			Engine.max_fps = _rungs[_rung]
		elif _probing:
			# Survived a while at the higher rate: it was not a fluke, so stop
			# treating it as a probe and put the backoff back to normal.
			_probe_survived += 1
			if _probe_survived >= RUNG_WINDOWS:
				_probing = false
				_probe_windows = RUNG_RAISE_WINDOWS
		return
	_quiet = 0


## Take the next frame rate down. If we only just probed UP to the rate we are
## leaving, that probe has been answered — back off so the next one is much further
## away, or a machine that cannot hold 60 spends the whole match discovering it
## every eight seconds, and each discovery is a visible rough patch.
func _drop_rung() -> void:
	_rung += 1
	rung_drops += 1
	Engine.max_fps = _rungs[_rung]
	if _probing:
		_probing = false
		_probe_windows = mini(_probe_windows * 2, PROBE_WINDOWS_MAX)


func _apply(to: float) -> void:
	if is_equal_approx(to, _scale):
		return
	_scale = to
	for v in _views:
		if is_instance_valid(v):
			v.scaling_3d_scale = _scale


func scale() -> float:
	return _scale


func target_fps() -> int:
	return _rungs[_rung]
