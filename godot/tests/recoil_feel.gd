extends Node
## WHAT A GUN COSTS TO FIRE, IN DEGREES, measured through the real signal path.
##
##   godot --headless --path godot tests/recoil_feel.tscn
##
## Recoil is three numbers that only mean anything together — the per-pull kick,
## the rate it is paid at, and the rate it settles — so the table column cannot
## be read on its own. This fires guns the way a player does and reports the two
## figures that decide whether one can be held on a target:
##
##   ONE PULL   how far the view jumps on a single press. What a semi-automatic,
##              a burst rifle and a shotgun are judged on.
##   STEADY     the peak the climb levels off at holding the trigger. What an
##              automatic is judged on, and the figure that made the machine guns
##              unusable at 7.6 deg/s of climb against a rifle's 3.1.
##
## THE BURST RIFLE IS THE CASE THIS EXISTS FOR. Its rounds leave 55 ms apart and
## recoil settles at 6/s, so a pull stacks almost perfectly: charging the
## per-round figure three times threw the EL-16's view up 13.7 degrees on ONE
## press, which is a gun that cannot be fired twice at the same man.
##
## A NOTE ON THE HARNESS, because the first version of it lied. It reused one
## body across every weapon in the catalogue and reported the A280 climbing to 68
## degrees — which is simply what a gun looks like when nothing is decaying, and
## no more real than the 0.00 it printed for that same gun's single pull. A
## measurement that disagrees with arithmetic is a broken measurement: for a held
## automatic the closed form is `kick / (1 - r)` with
## `r = (1 - dt*RECOIL_RECOVER) ** (interval/dt)`, and a focused rerun of the
## A280 against it gave 9.36 degrees where the sweep claimed 68. Each gun gets a
## FRESH body and one measurement now, which is slower and true.

const PLAYER := preload("res://scenes/actors/player.tscn")

## The guns worth measuring rather than all sixty: one of every fire mode, both
## ends of the machine-gun category, and the two that were reported broken.
const CHECKED := [
	Weapon.Class.SOLDIER,      # the rifle everything else is read against
	Weapon.Class.SEMI,         # semi-automatic
	Weapon.Class.BURST,        # <- "the burst gun is unusable"
	Weapon.Class.BR55,         # ...and the other burst rifle
	Weapon.Class.HMG,          # <- "the heavy machine guns are unstable"
	Weapon.Class.HEAVY,
	# NOT the R-90 rotary: it is the rotary GADGET's gun and needs `spinup` held
	# through a path this harness does not drive, so it measures 0.00 here — a
	# number that passes every check and means nothing.
	Weapon.Class.M739_SAW,     # the new LMGs
	Weapon.Class.DLT19D,
	Weapon.Class.RT97C,
	Weapon.Class.GAUSS_CANNON,
	Weapon.Class.SNIPER,       # the hardest single shot in the game
	Weapon.Class.SMG,
]

## Anything past this on ONE pull is a gun you cannot fire twice at the same man.
## The sniper and the tube are exempt: throwing the view IS the shot, and both
## fire under once a second, so there is nothing to hold on target.
const MAX_ONE_PULL := 9.0
## ...and anything past this held is a gun that walks off the target before its
## own heat pool runs out. Only asked of guns that fire fast enough for a climb
## to EXIST: under `SUSTAINED_AT` rounds a second the view has fully settled
## between shots, so "steady" and "one pull" are the same measurement and holding
## the bolt-action to an automatic's standard is asking the wrong question.
const MAX_STEADY := 12.0
const SUSTAINED_AT := 2.0
const EXEMPT_PULL := [Weapon.Class.SNIPER, Weapon.Class.RPG]

var _fails: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_match()
	GameState.match_live = true
	print("%-26s %9s %9s %8s  %s"
		% ["WEAPON", "ONE PULL", "STEADY", "RATE/s", "MODE"])
	for cls in CHECKED:
		await _measure(cls)
	await _handling()
	if _fails.is_empty():
		print("\n==== RECOIL HOLDS ====")
	else:
		print("\n==== %d PROBLEM(S) ====" % _fails.size())
		for f in _fails:
			print("  ! %s" % f)
	get_tree().quit(0 if _fails.is_empty() else 1)


const MODES := ["AUTO", "SEMI", "BURST"]


## A FRESH BODY PER MEASUREMENT. Reusing one across the catalogue is what made
## the first version unreliable, and a Player is cheap next to being wrong.
func _fresh(cls: int) -> Player:
	var p: Player = PLAYER.instantiate()
	add_child(p)
	await get_tree().process_frame
	p.pending = Loadout.new()
	p.pending.adopt_kit(Loadout.Kit.CLONE)
	p._apply_loadout()
	# ALIVE, not merely built: `_apply_loadout` arms the body but only a real
	# deploy clears `_dead`, and a dead Player runs `_process_dead`, which does
	# not settle recoil at all.
	p._dead = false
	p.weapon.set_class(cls, {})
	await get_tree().physics_frame
	p._recoil_pitch = 0.0
	p._recoil_step = 0
	return p


func _measure(cls: int) -> void:
	var prof: Dictionary = Weapon.PROFILES[cls]

	var p := await _fresh(cls)
	var one := await _run(p, 0.45, false)
	p.queue_free()

	var q := await _fresh(cls)
	var steady := await _run(q, 1.6, true)
	q.queue_free()
	await get_tree().process_frame

	var rate := 1.0 / maxf(0.001, float(prof["fire_interval"]))
	var mode: String = MODES[int(prof.get("mode", 0))]
	print("%-26s %8.2f° %8.2f° %8.1f  %s"
		% [prof["name"], one, steady, rate, mode])
	if one > MAX_ONE_PULL and not (cls in EXEMPT_PULL):
		_fails.append("%s throws the view %.1f deg on ONE trigger pull"
			% [prof["name"], one])
	if steady > MAX_STEADY and rate >= SUSTAINED_AT:
		_fails.append("%s climbs to %.1f deg holding the trigger"
			% [prof["name"], steady])


## Fire for `seconds` and return the peak the view reached. `sustained` holds the
## trigger and re-presses whenever the gun is idle — what a player hammering a
## semi-automatic does. Otherwise it is ONE press, then the settle.
func _run(p: Player, seconds: float, sustained: bool) -> float:
	var t := 0.0
	var pressed := true
	var peak := 0.0
	while t < seconds:
		var hold := sustained or t < 0.04
		p.weapon.update_fire(hold, pressed and hold)
		pressed = false
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if sustained and p.weapon._cooldown <= 0.0 and p.weapon._burst_left == 0:
			pressed = true
		peak = maxf(peak, rad_to_deg(p._recoil_pitch))
	p.weapon.update_fire(false, false)
	return peak


## HOW LONG A GUN TAKES TO GET INTO THE FIGHT — the other half of what a weapon
## costs, and the half that had no numbers at all until now.
##
## Both are measured on a REAL body: the sights come up over `Player.ads_time()`
## and the camera zoom is eased over the same duration (so the world and the
## sight arrive together), and the sprint-out is timed by when the TRIGGER starts
## working again rather than by when the pose looks right — those were allowed to
## be two different moments and the gun on screen would have lied about it.
const HANDLING_SHOWN := [
	Weapon.Class.HOLDOUT, Weapon.Class.SMG, Weapon.Class.CARBINE,
	Weapon.Class.SOLDIER, Weapon.Class.SEMI, Weapon.Class.M739_SAW,
	Weapon.Class.HMG, Weapon.Class.GAUSS_CANNON, Weapon.Class.SNIPER,
]
## A weapon nobody can get into the fight with is not a trade, it is a trap.
const MAX_SPRINT_OUT := 0.60
const MAX_ADS := 0.45


func _handling() -> void:
	print("\n%-26s %9s %11s %8s" % ["WEAPON", "ADS", "SPRINT-OUT", "HANDLING"])
	for cls in HANDLING_SHOWN:
		var p := await _fresh(cls)
		var h: float = p.weapon.handling()
		var ads: float = p.ads_time()

		# SPRINT-OUT, timed for real: stow the weapon fully, then let go and count
		# the frames until `weapon_ready()` comes back.
		# DO NOT STEP IT BY HAND. Player's own `_physics_process` already ticks
		# `_update_stow`, and an earlier version of this called it as well —
		# which double-stepped the timer and reported every sprint-out at half
		# its real length. Stow the weapon and then simply wait.
		p._stow = 1.0
		var t := 0.0
		while not p.weapon_ready() and t < 2.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		print("%-26s %8.3fs %10.3fs %8.2f"
			% [Weapon.PROFILES[cls]["name"], ads, t, h])
		if t > MAX_SPRINT_OUT:
			_fails.append("%s takes %.2fs to come out of a sprint"
				% [Weapon.PROFILES[cls]["name"], t])
		if ads > MAX_ADS:
			_fails.append("%s takes %.2fs to get the sights up"
				% [Weapon.PROFILES[cls]["name"], ads])
		p.queue_free()
		await get_tree().process_frame

	# AND THE SPREAD IS THE POINT. A handling column every gun shares is a column
	# nobody notices, which is precisely what the catalogue had before this.
	var fast := await _fresh(Weapon.Class.HOLDOUT)
	var slow := await _fresh(Weapon.Class.GAUSS_CANNON)
	var ratio: float = slow.ads_time() / maxf(0.001, fast.ads_time())
	print("  slowest gun is %.1fx the fastest to the eye" % ratio)
	if ratio < 1.8:
		_fails.append("handling barely differs across the catalogue (%.2fx) — every gun still feels the same to carry"
			% ratio)
	fast.queue_free()
	slow.queue_free()
