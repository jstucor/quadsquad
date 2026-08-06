extends Node3D
## HOW A BODY GETS UP TO SPEED, AND HOW IT STOPS — in seconds and metres.
##
##   godot --headless --path godot tests/movement_feel.tscn
##
## Movement used to be `velocity.x = dir.x * speed`, written straight in every
## frame. That is not a slow body or a fast one, it is a body with NO MASS: full
## sprint from standing in one frame, a dead stop in one frame, and a right-angle
## turn at full speed for free. It is the single loudest tell that a thing on
## screen is a game object rather than a person, and no amount of animation over
## the top of it helps — a lean, a stride and a hip swivel are all describing a
## motion that is not happening underneath them.
##
## The numbers below are the ones a player feels. They are asserted as RANGES on
## purpose: too quick and the body is still weightless, too slow and the controls
## have gone soft, and the whole value of the change lies between those.

const PLAYER := preload("res://scenes/actors/player.tscn")

## A walk should arrive in about a tenth of a second — quick enough that the
## stick stays sharp, slow enough to read as a body being carried.
const START_MIN := 0.05
const START_MAX := 0.30
## ...and stopping takes longer than starting. That asymmetry IS the weight.
const STOP_MIN := 0.06

var _fails: Array[String] = []
var _done: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_match()
	GameState.match_live = true
	_floor()
	await get_tree().physics_frame

	await _check_ramp()
	await _check_air()
	await _check_turn()
	await _check_camera()
	await _check_slide()
	await _check_steps()
	await _check_shake()

	print("")
	for want in ["ramp", "air", "turn", "camera", "slide", "steps", "shake"]:
		_ok(want in _done, "the `%s` section aborted part way" % want)
	if _fails.is_empty():
		print("==== MOVEMENT HOLDS ====")
	else:
		for f in _fails:
			print("  FAIL: %s" % f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func _floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, -1, 0)
	body.collision_layer = 1
	add_child(body)


func _spawn() -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = -1
	add_child(p)
	await get_tree().process_frame
	p.pending = Loadout.new()
	p.pending.adopt_kit(Loadout.Kit.CLONE)
	p._apply_loadout()
	p._dead = false
	p.global_position = Vector3(0, 0.2, 0)
	# Let it settle onto the floor before anything is timed.
	for _i in 20:
		await get_tree().physics_frame
	return p


## DRIVE IT THROUGH THE REAL INPUT PATH. An earlier version called `_accelerate`
## from the test while the body's own `_physics_process` was also calling it with
## an empty stick — so the two fought and the body never reached walking pace at
## all, which the test then reported as a snap. Pressing the same InputMap
## actions a keyboard would is both honest and the only way `is_on_floor()`,
## the sprint state and the speed multipliers are the real ones.
const KEYS := {
	"fwd": "kb_forward", "back": "kb_back", "left": "kb_left", "right": "kb_right",
	"sprint": "kb_sprint", "crouch": "kb_crouch",
}


func _hold(names: Array) -> void:
	for k in KEYS:
		if k in names:
			Input.action_press(KEYS[k])
		else:
			Input.action_release(KEYS[k])


func _speed_of(p: Player) -> float:
	return Vector2(p._move_vel.x, p._move_vel.z).length()


## Hold `names` for `seconds` and report when the body reached `target` speed
## (or came to rest, when target is 0).
func _run(p: Player, names: Array, target: float, seconds: float) -> float:
	_hold(names)
	var t := 0.0
	var reached := -1.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var speed := _speed_of(p)
		if reached >= 0.0:
			continue
		if target > 0.01 and speed >= target * 0.95:
			reached = t
		elif target <= 0.01 and speed <= 0.05:
			reached = t
	return reached


func _check_ramp() -> void:
	print("== getting up to speed, and back down ==")
	var p := await _spawn()
	var walk: float = Player.WALK_SPEED

	var start := await _run(p, ["fwd"], walk, 1.0)
	print("  0 -> walk (%.1f m/s): %.3f s" % [walk, start])
	_ok(start > START_MIN,
		"a body reaches walking pace in %.3f s — that is still a snap, not a start" % start)
	_ok(start < START_MAX,
		"a body takes %.3f s to reach walking pace — the controls have gone soft" % start)

	var halt := await _run(p, [], 0.0, 1.0)
	print("  walk -> 0:            %.3f s" % halt)
	_ok(halt > STOP_MIN,
		"a body stops dead in %.3f s — nothing with mass does that" % halt)
	# THE ASYMMETRY IS THE WEIGHT. A body that stops as fast as it starts still
	# reads as weightless however long both take.
	_ok(halt > start,
		"stopping (%.3f s) is not slower than starting (%.3f s) — that asymmetry IS the weight"
			% [halt, start])
	p.queue_free()
	await get_tree().process_frame
	_done.append("ramp")


## WHAT YOU KEEP IN THE AIR IS WHAT YOU LEFT THE GROUND WITH. The old line ran
## while airborne too, so a jump could be steered as freely as a walk — leap
## forward, arrive sideways.
func _check_air() -> void:
	print("\n== air control is not ground control ==")
	var p := await _spawn()
	var walk: float = Player.WALK_SPEED
	await _run(p, ["fwd"], walk, 0.6)      # up to speed on the ground
	var before: Vector3 = p._move_vel

	# Off the ground, and now demand a hard right-angle change.
	p.global_position.y += 3.0
	p.velocity.y = 4.0
	await get_tree().physics_frame
	_ok(not p.is_on_floor(), "the test body did not leave the ground")
	_hold(["right"])
	var t := 0.0
	while t < 0.25 and not p.is_on_floor():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var turned := rad_to_deg(Vector2(before.x, before.z).angle_to(
		Vector2(p._move_vel.x, p._move_vel.z)))
	print("  a quarter second of hard steering in the air turned it %.0f deg" % absf(turned))
	_ok(absf(turned) < 60.0,
		"a body turned %.0f degrees mid-air in a quarter second — that is not momentum"
			% absf(turned))
	p.queue_free()
	await get_tree().process_frame
	_done.append("air")


## A RIGHT-ANGLE TURN AT FULL SPEED COSTS SOMETHING. It used to cost nothing at
## all: the velocity was simply rewritten, so a body could reverse instantly with
## no arc and no loss of pace.
func _check_turn() -> void:
	print("\n== turning at speed costs ground ==")
	var p := await _spawn()
	var run: float = Player.SPRINT_SPEED
	await _run(p, ["fwd", "sprint"], run, 0.8)
	var top := _speed_of(p)

	# Demand the opposite direction and watch what the speed does through it.
	var lowest := top
	var t := 0.0
	_hold(["back", "sprint"])
	while t < 0.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		lowest = minf(lowest, _speed_of(p))
	_hold([])
	print("  reversing at %.1f m/s dipped the body to %.2f m/s" % [top, lowest])
	_ok(lowest < top * 0.35,
		"a body reversed at speed without slowing below %.2f m/s — the turn was free"
			% lowest)
	p.queue_free()
	await get_tree().process_frame
	_done.append("turn")


## WHAT THE CAMERA DOES ABOUT ALL OF THE ABOVE.
##
## The three checks above measure the BODY, and the body was the half that had
## already been fixed. The camera was still on rails: a constant height in a
## dead-level frame, at one field of view, whatever the body underneath it was
## doing. The weapon bobbed and the horizon did not, which reads as a loose gun
## rather than as a walking man.
##
## ALL FOUR NUMBERS HERE ARE ASSERTED AS RANGES, for the same reason the ramp is:
## zero is a camera on rails and too much is seasickness, and the whole value is
## between them. They are measured in MILLIMETRES and DEGREES because those are
## the units the argument is actually about — "0.024" in a constant says nothing.
const BOB_MIN_MM := 4.0
const BOB_MAX_MM := 90.0
## Standing still, the head must be genuinely still. A bob that idles is a body
## breathing hard enough to be a fault.
const STILL_MAX_MM := 1.0
## And the lean, at a full sideways run.
const LEAN_MIN_DEG := 0.3
const LEAN_MAX_DEG := 3.0


func _check_camera() -> void:
	print("\n== what the camera does about it ==")
	var p := await _spawn()

	# STANDING STILL. Measured first, because every number below is only
	# meaningful against a head that is otherwise motionless.
	var still := await _head_travel(p, [], 0.7)
	print("  standing still:      %.1f mm of head travel" % (still * 1000.0))
	_ok(still * 1000.0 < STILL_MAX_MM,
		"the head moves %.1f mm while standing still — the bob never settles"
			% (still * 1000.0))

	var walking := await _head_travel(p, ["fwd"], 1.2)
	print("  walking:             %.1f mm" % (walking * 1000.0))
	_ok(walking * 1000.0 > BOB_MIN_MM,
		"the camera moves %.1f mm over a walk cycle — that is a camera on rails"
			% (walking * 1000.0))
	_ok(walking * 1000.0 < BOB_MAX_MM,
		"the camera moves %.1f mm over a walk cycle, which is seasickness rather than weight"
			% (walking * 1000.0))

	var running := await _head_travel(p, ["fwd", "sprint"], 1.2)
	print("  sprinting:           %.1f mm" % (running * 1000.0))
	# THE PHASE IS DRIVEN BY DISTANCE, NOT TIME, so a sprint puts MORE footfalls
	# through the same window rather than the same number of bigger ones. Both
	# amplitude and rate rise, so the travel over a fixed window has to rise too;
	# if it did not, the bob is running off a clock and is a wobble.
	_ok(running > walking,
		"sprinting (%.1f mm) does not move the camera more than walking (%.1f mm) — the bob is on a timer rather than on the stride"
			% [running * 1000.0, walking * 1000.0])

	# AIMING STEADIES IT. A braced sight picture is the one time a real body is
	# deliberately holding its head still, and it is also when the player most
	# needs the frame to stop moving.
	p._ads_t = 1.0
	var aimed := await _head_travel(p, ["fwd"], 1.2)
	p._ads_t = 0.0
	print("  walking, aimed:      %.1f mm" % (aimed * 1000.0))
	_ok(aimed < walking,
		"aiming does not steady the camera (%.1f mm aimed vs %.1f mm hip)"
			% [aimed * 1000.0, walking * 1000.0])

	# THE LEAN, at a full sidestep.
	_hold(["right"])
	for _i in 45:
		await get_tree().physics_frame
	var lean := absf(rad_to_deg(p._view_roll))
	_hold([])
	print("  sidestepping:        %.2f deg of lean" % lean)
	_ok(lean > LEAN_MIN_DEG,
		"a full sidestep leans the camera %.2f deg — the horizon does not acknowledge lateral movement at all"
			% lean)
	_ok(lean < LEAN_MAX_DEG,
		"a sidestep leans the camera %.2f deg, which is a broken horizon rather than weight" % lean)

	# AND THE SPEED YOU CAN SEE.
	var cam := Camera3D.new()
	add_child(cam)
	p.bind_camera(cam)
	_hold(["fwd", "sprint"])
	for _i in 90:
		await get_tree().physics_frame
	var sprint_fov := cam.fov
	_hold([])
	for _i in 90:
		await get_tree().physics_frame
	var rest_fov := cam.fov
	print("  field of view:       %.1f at rest, %.1f sprinting" % [rest_fov, sprint_fov])
	_ok(sprint_fov > rest_fov + 0.5,
		"sprinting does not widen the frame (%.1f vs %.1f) — a sprint that changes nothing but a number in `velocity` is one nobody can feel"
			% [sprint_fov, rest_fov])
	cam.queue_free()
	p.queue_free()
	await get_tree().process_frame
	_done.append("camera")


## Peak-to-trough travel of the HEAD's local height over a window, in metres.
## Local and not global on purpose: what is being measured is the camera moving
## against the body, and a global read would include the body walking up a slope.
func _head_travel(p: Player, names: Array, seconds: float) -> float:
	_hold(names)
	# Let the amplitude ease in before sampling — it is deliberately not
	# instant (`BOB_EASE`), so a window that starts at the press measures the
	# ramp rather than the bob.
	for _i in 20:
		await get_tree().physics_frame
	var lo := INF
	var hi := -INF
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var y: float = p.head.position.y
		lo = minf(lo, y)
		hi = maxf(hi, y)
	_hold([])
	return maxf(hi - lo, 0.0)


## THE SLIDE, AND THE ONE QUESTION THAT DECIDES WHETHER IT IS ALLOWED TO EXIST.
##
## A slide is easy to make feel good and easy to make broken, and the broken
## version is always the same one: if sliding and re-sliding covers ground faster
## than simply holding sprint, then it stops being a tactical option and becomes
## the way everybody is obliged to move for the whole match. Every shooter that
## has shipped one has had this argument. So the headline assertion here is not
## about the slide at all — it is that a player spamming it over a long distance
## ARRIVES LATER than a player who just ran.
##
## The rest is the feel: it has to actually boost you (or it is a crouch with
## extra steps), it has to end (or it is a vehicle), and it must not be startable
## from a standstill (or it is a dash).
const SLIDE_MIN_GAIN := 1.15     # x sprint speed, at the moment it starts
const SLIDE_MIN_DIST := 2.0      # metres of travel, or it is not worth pressing
const SLIDE_MAX_DIST := 12.0     # ...and past this it is a vehicle


func _check_slide() -> void:
	print("\n== the slide ==")
	var p := await _spawn()

	# YOU CANNOT SLIDE FROM A STANDSTILL. Sprint held, crouch pressed, but the
	# body has not gone anywhere — if this launches you it is a dash, and a dash
	# from cover is a completely different mechanic with completely different
	# balance.
	_hold(["sprint"])
	for _i in 10:
		await get_tree().physics_frame
	await _tap_crouch(["sprint"])
	_ok(not p.sliding(), "a slide started from a standing body — that is a dash")
	_hold([])
	p._crouched = false
	for _i in 20:
		await get_tree().physics_frame

	# AT A RUN IT GOES. Driven through the same function the crouch button calls,
	# rather than by poking `_begin_slide` — what is being checked is that the
	# BUTTON does this, and the button is shared with the stance toggle.
	_hold(["fwd", "sprint"])
	for _i in 60:
		await get_tree().physics_frame
	var run_speed := _speed_of(p)
	# HELD, not tapped: the last check below is that riding it out with the
	# button down leaves the body crouched, which is the whole of "hold to slide".
	await _tap_crouch(["fwd", "sprint", "crouch"])
	_ok(p.sliding(), "the crouch button at a run did not start a slide")
	var boost := _speed_of(p) if not p.sliding() else p._slide_speed
	print("  sprint %.2f m/s -> slide opens at %.2f m/s (%.2fx)"
		% [run_speed, boost, boost / maxf(run_speed, 0.01)])
	_ok(boost >= run_speed * SLIDE_MIN_GAIN,
		"the slide opens at %.2fx sprint — that is a crouch with extra steps"
			% (boost / maxf(run_speed, 0.01)))

	# ...AND IT ENDS, on its own, having covered a sensible distance.
	var from := p.global_position
	var t := 0.0
	while p.sliding() and t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var dist := Vector2(p.global_position.x - from.x,
		p.global_position.z - from.z).length()
	print("  ran for %.2f s and covered %.2f m" % [t, dist])
	_ok(not p.sliding(), "the slide never ended on its own")
	_ok(dist > SLIDE_MIN_DIST,
		"a slide covers only %.2f m — not worth the button" % dist)
	_ok(dist < SLIDE_MAX_DIST,
		"a slide covers %.2f m, which is a vehicle rather than a movement option"
			% dist)

	# HOLDING THE BUTTON LEAVES YOU CROUCHED, which is what makes it "hold to
	# slide" rather than "tap to slide" — you finish in cover already low.
	_ok(p._crouch_held(),
		"riding the slide out with the button held did not leave the body crouched")
	_hold([])
	p._crouched = false
	for _i in 30:
		await get_tree().physics_frame

	# THE ONE THAT MATTERS: spamming it must LOSE to simply running.
	var spam := await _travel(p, true, 6.0)
	var plain := await _travel(p, false, 6.0)
	print("  over 6 s: sprinting %.1f m, slide-spamming %.1f m" % [plain, spam])
	# THE CLAIM IS "NEVER FASTER", NOT "SLOWER", and the difference matters.
	# A slide is speed-NEUTRAL on purpose (see `Player.SLIDE_COOLDOWN`): it opens
	# at 1.48x sprint and decays to below it, averaging almost exactly a sprint.
	# So the property that keeps it optional is that chaining it buys no ground —
	# demanding it be measurably SLOWER would be an arbitrary tax, and demanding
	# it be strictly less than sprint at all is a coin-flip on a 1% margin.
	# What must never happen is it coming out AHEAD.
	_ok(spam <= plain * 1.02,
		"slide-spamming covers %.1f m against %.1f m of plain sprinting (%.0f%%) — a slide that gains ground is a slide everybody is obliged to spam"
			% [spam, plain, 100.0 * spam / maxf(plain, 0.01)])
	p.queue_free()
	await get_tree().process_frame
	_done.append("slide")


## Run forward for `seconds` and report the ground covered, optionally mashing
## crouch the whole way. The press goes through `_toggle_crouch_input` because
## that is the one place the crouch edge is read.
func _travel(p: Player, spam: bool, seconds: float) -> float:
	p._slide_left = 0.0
	p._slide_cd = 0.0
	p._crouched = false
	p.global_position = Vector3(0, 0.2, 0)
	p._move_vel = Vector3.ZERO
	for _i in 15:
		await get_tree().physics_frame
	_hold(["fwd", "sprint"])
	var from := p.global_position
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if spam and not p.sliding() and p._slide_cd <= 0.0:
			# A FRESH EDGE each time — `_edge`/`is_action_just_pressed` is a
			# press, not a hold, so a button left down slides exactly once.
			Input.action_release(KEYS["crouch"])
			await get_tree().physics_frame
			Input.action_press(KEYS["crouch"])
			await get_tree().physics_frame
			await get_tree().physics_frame
			t += get_physics_process_delta_time() * 3.0
			p._crouched = false   # the press is spent on the slide, not the stance
	_hold([])
	p._crouched = false
	return Vector2(p.global_position.x - from.x,
		p.global_position.z - from.z).length()


## Press the crouch control for real and let the BODY read it on its own physics
## tick. `Controls.kb_pressed` is `is_action_just_pressed`, so the edge only
## exists across a frame boundary — calling `_toggle_crouch_input()` from here
## finds no edge and does nothing, which is the same trap this file already
## records about calling `_accelerate` directly.
## TWO frames, not one, and that is the whole reason this helper exists.
## `Input.action_press` lands AFTER the physics tick that is already in flight,
## so the body's `_physics_process` sees the edge on the frame after the press —
## an earlier version awaited a single frame, read `sliding()` as false and
## reported a working mechanic as broken.
func _tap_crouch(hold_after: Array) -> void:
	Input.action_release(KEYS["crouch"])
	await get_tree().physics_frame
	_hold(hold_after + ["crouch"])
	await get_tree().physics_frame
	await get_tree().physics_frame
	_hold(hold_after)


## FOOTFALLS, IN STEPS PER METRE.
##
## The game had no footstep audio at all, which is the loudest thing that can be
## missing from a shooter — and it is not only feel: hearing somebody come round
## a corner is how half of every firefight starts.
##
## WHAT THIS MEASURES IS CADENCE AGAINST GROUND COVERED, not against time, and
## that is the whole property. Footfalls are paced off the SAME `STRIDE` table
## the animation is paced by, so the sound lands on the step; anything driven by
## a clock drifts against the legs the moment speed changes, which is constantly.
## Expressed per METRE, a walk and a sprint must come out at nearly the same
## number even though the sprint fires far more often per second — if they do
## not, the cadence is running off a timer.
##
## `Audio` is deliberately not involved: the bank renders on a worker thread and
## is a no-op under `--headless`, so this counts what `Locomotion` DECIDES rather
## than what came out of a speaker. The decision is the part that can be wrong.
const STEP_TOLERANCE := 0.25    # allowed drift from the clip's own stride


func _check_steps() -> void:
	print("\n== footfalls ==")
	var p := await _spawn()
	# EACH CLIP AGAINST ITS OWN STRIDE. Steps per METRE is the honest unit — a
	# cadence driven by a clock would drift against the legs the moment speed
	# changed — but walk and run must NOT match each other, and an earlier
	# version of this asserted that they should. A sprinting body takes LONGER
	# strides (`STRIDE["run"]` is 5.0 m per cycle against the walk's 2.6), so it
	# covers more ground per footfall, which is what running is. The property is
	# that each clip fires at `STEPS_PER_STRIDE / STRIDE[clip]`.
	for probe: Array in [["walk", ["fwd"]], ["run", ["fwd", "sprint"]]]:
		var clip: String = probe[0]
		var got := await _steps_per_metre(p, probe[1], 2.0)
		var want: float = Locomotion.STEPS_PER_STRIDE / float(Locomotion.STRIDE[clip])
		print("  %-5s %.2f steps per metre (its stride wants %.2f)"
			% [clip, got, want])
		_ok(got > 0.05,
			"a body playing `%s` takes no steps at all — the game is silent when it moves"
				% clip)
		_ok(absf(got - want) / want < STEP_TOLERANCE,
			"`%s` fires %.2f steps per metre against the %.2f its own stride length implies — the cadence is not coming from the stride table, so the sound drifts off the legs"
				% [clip, got, want])

	# AIRBORNE BODIES DO NOT TAKE STEPS. Obvious, and exactly the sort of thing
	# that regresses when somebody moves where the tick is called from.
	_hold(["fwd"])
	for _i in 10:
		await get_tree().physics_frame
	Input.action_press("kb_jump")
	await get_tree().physics_frame
	Input.action_release("kb_jump")
	# PRIME THE PROBE. `_steps_this_frame` reports everything since it was last
	# ASKED, and it was last asked during the sprint run above — so without this
	# the first in-air read hands back every step taken walking up to the jump
	# and reports them as having happened in mid-air.
	_steps_this_frame(p)
	var air := 0
	var t := 0.0
	while t < 0.35:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not p.is_on_floor():
			air += _steps_this_frame(p)
	_hold([])
	_ok(air == 0, "a body in the air took %d footsteps" % air)
	print("  airborne:  %d steps, as it should be" % air)
	p.queue_free()
	await get_tree().process_frame
	_done.append("steps")


## Count the footfalls over a run and divide by the ground actually covered.
func _steps_per_metre(p: Player, names: Array, seconds: float) -> float:
	_hold(names)
	# Let it reach pace first — the ramp is real and would otherwise be counted
	# as ground covered with no steps in it.
	for _i in 30:
		await get_tree().physics_frame
	var from := p.global_position
	var steps := 0
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		steps += _steps_this_frame(p)
	_hold([])
	var gone := Vector2(p.global_position.x - from.x,
		p.global_position.z - from.z).length()
	return float(steps) / maxf(gone, 0.01)


## Did the module take a step this frame? Read off `steps_taken`, which only ever
## goes up.
##
## An earlier version watched the distance ACCUMULATOR for a drop, which is the
## obvious probe and is wrong: a landing resets that accumulator so the stride
## restarts from the foot that arrived, and the probe therefore counted every
## landing as a footfall — reporting a step taken in mid-air. A monotonic counter
## cannot be read ambiguously.
var _last_steps := 0


func _steps_this_frame(p: Player) -> int:
	var now: int = p._loco.steps_taken
	var took := maxi(now - _last_steps, 0)
	_last_steps = now
	return took


## SCREEN SHAKE, AND THE ONE PROPERTY THAT MAKES IT ACCEPTABLE.
##
## The world had no physical effect on the view — a rocket could go off at your
## feet and the camera would not acknowledge it. But a shake that spoils your aim
## is not a feel improvement, it is an input bug, so the assertion that matters
## here is not that the camera MOVES: it is that **the gun still points where the
## crosshair points while it is moving**.
##
## That is what confines the rotation to ROLL. Rolling about the view axis cannot
## move where the centre of the screen points; yaw or pitch would put the reticle
## and the barrel on different lines, which is precisely the fault that made the
## LAAT's ball turret unusable and is not worth reintroducing for an effect.
func _check_shake() -> void:
	print("\n== screen shake ==")
	var p := await _spawn()
	var cam := Camera3D.new()
	add_child(cam)
	p.bind_camera(cam)
	for _i in 4:
		await get_tree().physics_frame

	var aim_before: Vector3 = -p.head.global_transform.basis.z
	p.add_shake(1.0)
	var moved := 0.0
	var worst_aim := 0.0
	var worst_yawpitch := 0.0
	for _i in 30:
		await get_tree().physics_frame
		moved = maxf(moved, p.remote_cam.position.length())
		moved = maxf(moved, absf(p.remote_cam.rotation.z))
		# THE GUN MUST NOT HAVE MOVED. `head` carries the weapon.
		var aim: Vector3 = -p.head.global_transform.basis.z
		worst_aim = maxf(worst_aim, rad_to_deg(aim.angle_to(aim_before)))
		# ...and the camera must be rolling ONLY.
		worst_yawpitch = maxf(worst_yawpitch,
			absf(p.remote_cam.rotation.x) + absf(p.remote_cam.rotation.y))
	print("  camera displaced %.3f, gun moved %.3f deg, off-roll %.4f rad"
		% [moved, worst_aim, worst_yawpitch])
	_ok(moved > 0.002, "an explosion at point blank did not move the camera at all")
	_ok(worst_aim < 0.01,
		"screen shake moved the AIM by %.3f degrees — a shake that spoils your aim is an input bug, not an effect"
			% worst_aim)
	_ok(worst_yawpitch < 0.0001,
		"screen shake is rotating the camera in yaw or pitch (%.4f rad), which puts the crosshair and the barrel on different lines"
			% worst_yawpitch)

	# ...AND IT ENDS. A camera that never quite settles is worse than one that
	# never moved.
	for _i in 120:
		await get_tree().physics_frame
	_ok(p.remote_cam.position.length() < 0.0005
			and absf(p.remote_cam.rotation.z) < 0.0005,
		"the shake never settled — the camera is still %.4f off"
			% p.remote_cam.position.length())
	print("  settles back to rest")
	cam.queue_free()
	p.queue_free()
	await get_tree().process_frame
	_done.append("shake")
