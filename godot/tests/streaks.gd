extends Node
## KILL STREAK REWARDS.
##
## Most of what this protects is a GATE holding — that a Spartan cannot call down
## a LAAT, that a Wookiee is not offered a Force master's saber, that a reward
## fires ONCE. Gates are the part that fails silently: a reward wrongly available
## still works perfectly, it is just somebody else's.
##
## The rest is the one thing a transformation is most likely to get wrong. A
## BECOME reward runs `_apply_loadout`, which is also what a fresh DEPLOY runs —
## so it resets the kill counter and the taken-set unless something puts them
## back, and a Juggernaut that re-earns itself heals to full on every kill.

const PLAYER := preload("res://scenes/actors/player.tscn")
const GUNSHIP := preload("res://scripts/gunship.gd")

var _fails: Array[String] = []
## Which check functions reached their last line — see the note in `_ready`.
var _done := {}


func _ready() -> void:
	print("\n==== kill streak rewards ====")
	if GameState == null or not GameState.has_method("crowded"):
		print("  FAIL: GameState did not load — every check below would be hollow")
		print("==== 1 FAILURES ====")
		get_tree().quit(1)
		return
	_check_table()
	_check_gates()
	_check_thresholds()
	await _check_become()
	await _check_gunship()
	await _check_third_person()
	# EVERY SECTION MUST HAVE FINISHED. A GDScript error aborts the enclosing
	# function silently (house rule 6), so a bad call halfway down a check skips
	# the rest of its assertions and the run still reports success — which is
	# exactly what happened here the first time, on a mistyped GameState call.
	# Each check signs off at its own end and this counts the signatures.
	var want := ["table", "gates", "thresholds", "become", "gunship",
		"third person"]
	for name in want:
		if not _done.has(name):
			_fails.append("the `%s` checks did not run to the end — something in "
				% name + "them errored, and every assertion after it was skipped")
	print("")
	if _fails.is_empty():
		print("==== STREAKS HOLD ====")
	else:
		for f in _fails:
			print("  FAIL: ", f)
		print("==== %d FAILURES ====" % _fails.size())
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


## Every row has to state the keys the granting switch reads, or a reward is
## earned and nothing happens — which reads as a bug in the streak counter.
func _check_table() -> void:
	print("\n-- every row is grantable --")
	for row in Streaks.REWARDS:
		var name: String = str(row.get("name", "?"))
		for key in ["name", "kills", "kind", "blurb"]:
			_ok(row.has(key), "%s has no `%s`" % [name, key])
		match int(row.get("kind", -1)):
			Streaks.Kind.VEHICLE:
				var id: String = str(row.get("vehicle", ""))
				_ok(Vehicle.STREAK_VEHICLES.has(id),
					"%s names vehicle `%s`, which is not in Vehicle.STREAK_VEHICLES"
						% [name, id])
			Streaks.Kind.BECOME:
				_ok(row.has("preset"), "%s is a BECOME with no preset" % name)
			Streaks.Kind.RECON, Streaks.Kind.BOMBARDMENT, Streaks.Kind.GUNSHIP:
				_ok(row.has("duration"), "%s has no duration" % name)
			_:
				_fails.append("%s has an unknown kind" % name)
		print("  %-16s %2d kills  %s" % [name, int(row.get("kills", 0)),
			Streaks.Kind.keys()[int(row.get("kind", 0))]])
	# A BECOME PRESET MUST DEPLOY THE GUN IT NAMES. Same strict question
	# kit_rules asks of every AI preset: `weapon_index` answers NO_PRIMARY for a
	# gun the catalogue does not sell, which is legal and completely wrong.
	for row in Streaks.REWARDS:
		if int(row.get("kind", -1)) != Streaks.Kind.BECOME:
			continue
		var built := Loadout.preset_build(row["preset"])
		var want: int = int(row["preset"]["primary"])
		_ok(built.deploy_class() == want,
			"%s asked for weapon class %d and deployed %d — silently disarmed"
				% [str(row["name"]), want, built.deploy_class()])
	_done["table"] = true


## THE GATES. Checked from both directions: the owner gets it and nobody else
## does. Only the second direction catches a `kits` key that was never read.
func _check_gates() -> void:
	print("\n-- every faction, and what it alone can earn --")
	var universes := {
		Loadout.Universe.STAR_WARS: ["REPUBLIC", "SEPARATIST", "EMPIRE", "REBEL"],
		Loadout.Universe.HALO: ["UNSC", "COVENANT"],
		Loadout.Universe.WARHAMMER: ["ULTRAMARINES", "BLOOD ANGELS", "NECRONS", "ORKS"],
	}
	# Which faction each signature belongs to, so a reward reachable by two sides
	# is reported by NAME rather than as a count that does not say what broke.
	var owner := {}
	var counts := {}
	for u: int in universes:
		GameState.universe = u
		var sides: Array = universes[u]
		for t in sides.size():
			var got := _names(Streaks.available(t))
			var who: String = "%s %s" % [Loadout.UNIVERSES[u]["name"], sides[t]]
			print("  %-26s %s" % [who, str(got)])
			counts[who] = got.size()

			# THE UNIVERSAL RUNGS. The orbital strike especially: it is the one
			# reward that asks nothing of what you are, so it is what keeps the
			# ladder the same height for every side in every setting.
			_ok(got.has("ORBITAL STRIKE"),
				"%s cannot call an ORBITAL STRIKE — it is meant to be universal" % who)
			_ok(got.has("RECON SWEEP"), "%s cannot call a recon sweep" % who)

			# ...and exactly ONE signature, which is one nobody else has.
			var sig := []
			for name in got:
				if name in ["RECON SWEEP", "ORBITAL STRIKE"]:
					continue
				if str(name) == "FORCE MASTER":
					continue     # deliberately shared, and marked so in the table
				sig.append(name)
			_ok(sig.size() == 1,
				"%s has %d signature rewards (%s); every faction gets exactly one"
					% [who, sig.size(), str(sig)])
			for name in sig:
				_ok(not owner.has(name),
					"%s and %s SHARE `%s` — a signature belongs to one faction"
						% [str(owner.get(name, "?")), who, name])
				owner[name] = who

	# A SIDE WITH FEWER REWARDS THAN THE ONE ACROSS THE MAP is a balance bug that
	# nothing else in the project would report.
	GameState.universe = Loadout.Universe.STAR_WARS
	for who: String in counts:
		var want := 4 if who.begins_with("STAR") else 3
		_ok(counts[who] == want,
			"%s has %d rewards, expected %d" % [who, counts[who], want])

	# The Force is ALLEGIANCE: all four Star Wars sides reach a master, and which
	# one they draw is the side's answer.
	for t in 4:
		var preset := Streaks.become_preset(_row("FORCE MASTER"), t)
		var want_name := "JEDI MASTER" if t in [0, 3] else "SITH MASTER"
		_ok(str(preset["name"]) == want_name,
			"team %d should draw a %s, got %s" % [t, want_name, preset["name"]])

	# NO KIT ANYWHERE. What you bought this life must not change what you are
	# playing for.
	for row in Streaks.REWARDS:
		_ok(not row.has("kits"),
			"%s still gates on KIT — rewards are faction-only" % row["name"])
	print("  %d signatures, one per faction, none shared" % owner.size())
	_done["gates"] = true


func _row(name: String) -> Dictionary:
	for r in Streaks.REWARDS:
		if str(r["name"]) == name:
			return r
	return {}


## THE GUNSHIP IS THE ONE REWARD THAT TAKES YOU OFF THE MAP, so the thing that
## matters is that it puts you back. A ride that ends with the player still
## hidden, still collision-less and still slaved to a freed airframe is a
## spectator for the rest of the match — and it would look exactly like a crash.
func _check_gunship() -> void:
	print("\n-- the gunship flies itself and gives you back --")
	GameState.match_live = true
	GameState.map_center = Vector3.ZERO
	var p: Player = PLAYER.instantiate()
	add_child(p)
	await get_tree().process_frame
	p.team = 0
	p.pending = Loadout.new()
	p._apply_loadout()
	await get_tree().process_frame
	var stood_at := Vector3(11.0, 0.0, -4.0)
	p.global_position = stood_at

	var ship: Node3D = GUNSHIP.new()
	add_child(ship)
	ship.begin(p, 0, 1.2)
	await get_tree().physics_frame
	_ok(p.in_vehicle(), "the gunner is not seated")
	_ok(not p.model.visible, "the gunner's body is still visible")
	var up := ship.global_position.y
	_ok(up > 20.0, "the gunship is at %.0f m — it should be at altitude" % up)

	# IT FLIES ITSELF. Nobody is steering, so the only proof it is on a circuit is
	# that it MOVED and stayed at the same height and radius.
	var was := ship.global_position
	for i in 30:
		await get_tree().physics_frame
	var now: Vector3 = ship.global_position
	_ok(was.distance_to(now) > 1.0,
		"the gunship did not move (%.2f m in half a second)" % was.distance_to(now))
	_ok(absf(now.y - up) < 0.5, "the gunship did not hold its altitude")
	var r1 := Vector2(was.x, was.z).length()
	var r2 := Vector2(now.x, now.z).length()
	_ok(absf(r1 - r2) < 1.0,
		"the gunship is not on a circle (radius %.1f then %.1f)" % [r1, r2])
	print("  seated, circling at %.0f m up and %.0f m out" % [now.y, r2])

	# ...and it hands them back on the ground they called it from.
	for i in 140:
		await get_tree().physics_frame
	_ok(not is_instance_valid(ship) or ship.is_queued_for_deletion(),
		"the gunship outlived its duration")
	_ok(not p.in_vehicle(), "the gunner was never let out")
	_ok(p.model.visible, "the gunner got their body back")
	_ok(not p.get_node("CollisionShape3D").disabled,
		"the gunner got their collision back")
	# HORIZONTALLY. There is no floor in this scene, so the returned body falls
	# from the moment it is handed back — which says nothing about whether it was
	# put down in the right PLACE, and that is the only thing being asked.
	var here := p.global_position
	var back := Vector2(here.x - stood_at.x, here.z - stood_at.z).length()
	_ok(back < 3.0,
		"put down %.1f m across from where they called it" % back)
	print("  returned %.1f m across from where it was called" % back)
	p.queue_free()
	_done["gunship"] = true


func _names(rows: Array[Dictionary]) -> Array:
	var out: Array = []
	for r in rows:
		out.append(str(r["name"]))
	return out


## ONE REWARD PER KILL, and the thresholds are crossed rather than reached — a
## body already past a threshold when the list is built must not collect it.
func _check_thresholds() -> void:
	print("\n-- thresholds are crossed, one at a time --")
	var rows := Streaks.available(0)
	_ok(Streaks.earned(rows, 3, 4).get("name", "") == "RECON SWEEP",
		"crossing 4 kills did not pay the recon sweep")
	_ok(Streaks.earned(rows, 4, 5).is_empty(),
		"a kill between thresholds paid a reward")
	_ok(Streaks.earned(rows, 0, 4).get("name", "") == "RECON SWEEP",
		"jumping straight to 4 did not pay")
	# Two thresholds crossed at once pays the LOWER, so the announcements stay
	# one to a kill rather than stacking.
	var both := Streaks.earned(rows, 3, 99)
	_ok(both.get("name", "") == "RECON SWEEP",
		"crossing every threshold at once paid `%s`, not the lowest"
			% str(both.get("name", "-")))
	print("  3->4 %s   4->5 %s   3->99 %s" % [
		Streaks.earned(rows, 3, 4).get("name", "-"),
		Streaks.earned(rows, 4, 5).get("name", "-"),
		both.get("name", "-")])
	_done["thresholds"] = true


## The transformation, on a real Player. This is the half that would regress
## silently: everything still WORKS if the counter resets, it just quietly
## becomes impossible to climb past the first BECOME reward you earn.
func _check_become() -> void:
	print("\n-- becoming something else keeps the streak --")
	GameState.match_live = true
	var p: Player = PLAYER.instantiate()
	add_child(p)
	await get_tree().process_frame
	# TEAM 3 (the Rebels), because the Juggernaut is a FACTION reward now and the
	# Republic does not get it — it gets the gunship. Deliberately deployed on an
	# ORDINARY kit, which is the point of the rework: what you bought this life
	# must not decide what you are playing for.
	p.team = 3
	p.pending = Loadout.new()
	p.pending.adopt_kit(Loadout.Kit.CLONE)
	p._apply_loadout()
	await get_tree().process_frame

	var before_health := p.max_health
	for i in Streaks.KILLS_SIGNATURE:
		p.credit_kill()
	await get_tree().process_frame

	# A REWARD IS OFFERED, NOT APPLIED. Nothing may have happened yet.
	_ok(not p.pending_reward().is_empty(), "the signature threshold offered nothing")
	_ok(str(p.pending_reward().get("name", "")) == "WOOKIEE CHIEFTAIN",
		"the signature offer was `%s`" % str(p.pending_reward().get("name", "-")))
	_ok(p.max_health == before_health,
		"the reward applied itself before it was accepted")
	print("  offered `%s` and waited" % str(p.pending_reward().get("name", "-")))
	p.accept_reward()
	await get_tree().process_frame

	_ok(p.kills_this_life == Streaks.KILLS_SIGNATURE,
		"the streak was reset by the transformation: %d, want %d"
			% [p.kills_this_life, Streaks.KILLS_SIGNATURE])
	_ok(p.loadout.build_name == "WOOKIEE CHIEFTAIN",
		"the Rebel signature did not deploy (got `%s`)"
			% p.loadout.build_name)
	_ok(p.max_health > before_health,
		"the signature is not tougher than what it replaced (%.0f vs %.0f)"
			% [p.max_health, before_health])
	_ok(p.overshield_left() > 0.0, "the signature got no overshield")
	_ok(is_finite(p.overshield_left()),
		"the overshield lifetime is not finite — the HUD gauge reads it directly")
	print("  %d kills: %s, %.0f HP (was %.0f), overshield %.0f for %.0fs"
		% [Streaks.KILLS_SIGNATURE, p.loadout.build_name, p.max_health, before_health,
			p._over_pool, p.overshield_left()])

	# AND IT MUST NOT RE-EARN ITSELF. Another kill past the threshold would
	# re-run `_apply_loadout` — healing to full and re-issuing the shield.
	p.health = 10.0
	p.credit_kill()
	await get_tree().process_frame
	_ok(p.health == 10.0,
		"the signature re-earned itself and healed to %.0f" % p.health)
	print("  a 7th kill does not re-issue it (health stayed %.0f)" % p.health)

	# AND IT DOES NOT REGENERATE — the pool it came with is the whole budget for
	# the rest of the life. This is the counterweight to seven-to-eleven times a
	# trooper's health, and it is INVISIBLE: nothing about the body says so, so
	# nothing but a test would notice it quietly coming back. Wound it, wait past
	# REGEN_DELAY, and assert it stayed wounded.
	p.health = 10.0
	p._since_damage = Player.REGEN_DELAY + 1.0
	for _i in 8:
		p._update_regen(0.25)
	_ok(p.health == 10.0,
		"a BECOME reward regenerated to %.0f — the pool has to be finite" % p.health)
	print("  and it does not regenerate (%.0f hp after %.1fs idle)"
		% [p.health, 2.0])

	# ...while an ORDINARY body still does, or the rule leaked onto everybody.
	var plain: Player = PLAYER.instantiate()
	add_child(plain)
	await get_tree().process_frame
	plain.team = 3
	plain.pending = Loadout.new()
	plain.pending.adopt_kit(Loadout.Kit.CLONE)
	plain._apply_loadout()
	await get_tree().process_frame
	plain.health = 10.0
	plain._since_damage = Player.REGEN_DELAY + 1.0
	for _i in 8:
		plain._update_regen(0.25)
	_ok(plain.health > 10.0,
		"an ordinary body stopped regenerating — the BECOME rule leaked")
	print("  an ordinary trooper still heals (%.0f hp)" % plain.health)
	plain.queue_free()
	p.queue_free()

	# DECLINING SPENDS THE OFFER. Otherwise every further kill re-offers the thing
	# you just said no to, which is the most annoying possible prompt.
	var q: Player = PLAYER.instantiate()
	add_child(q)
	await get_tree().process_frame
	q.team = 3
	q.pending = Loadout.new()
	q.pending.adopt_kit(Loadout.Kit.CLONE)
	q._apply_loadout()
	await get_tree().process_frame
	var kept := q.max_health
	for i in Streaks.KILLS_SIGNATURE:
		q.credit_kill()
	q.decline_reward()
	_ok(q.pending_reward().is_empty(), "declining left the offer up")
	_ok(q.max_health == kept, "declining applied the reward anyway")
	q.credit_kill()
	_ok(q.pending_reward().is_empty(),
		"the declined reward was offered again on the next kill")
	print("  declined, and not re-offered on the next kill")
	q.queue_free()
	_done["become"] = true


## THE FORCE MASTER IS WATCHED, NOT LOOKED THROUGH.
##
## Three things have to move together and each is silent when wrong: the flag,
## the CAMERA (which is what the player actually experiences) and the CULL MASK
## (which decides whether they can see the body the camera is now pointed at).
## Get the mask wrong and you play third person looking at empty air with your
## own rifle floating in it — a picture no assertion on `third_person` alone
## would catch.
##
## And the half that regresses quietly: an ordinary respawn has to put it ALL
## back. `_apply_loadout` is what a fresh deploy calls, so a reset left out there
## means dying once as a Force Master and playing the rest of the match over your
## own shoulder as a trooper.
func _check_third_person() -> void:
	print("\n-- the Force Master is played in third person --")
	GameState.match_live = true
	var p: Player = PLAYER.instantiate()
	add_child(p)
	await get_tree().process_frame
	p.team = 0                      # Republic: reaches the FORCE MASTER
	p.pending = Loadout.new()
	p.pending.adopt_kit(Loadout.Kit.CLONE)
	p._apply_loadout()
	# A camera to actually drive, since the whole point is where it ends up.
	var cam := Camera3D.new()
	add_child(cam)
	p.bind_camera(cam)
	await get_tree().process_frame

	var body_bit: int = 1 << (1 + p.player_index)
	var gun_bit: int = 1 << (Player.VIEWMODEL_BIT + p.player_index)
	_ok(not p.third_person, "an ordinary trooper deploys in third person")
	_ok((cam.cull_mask & body_bit) == 0,
		"a first-person trooper can see its own body")
	_ok((cam.cull_mask & gun_bit) != 0,
		"a first-person trooper cannot see its own weapon")

	for i in Streaks.KILLS_FORCE:
		p.credit_kill()
	await get_tree().process_frame
	_ok(str(p.pending_reward().get("name", "")) == "FORCE MASTER",
		"the top rung offered `%s`" % str(p.pending_reward().get("name", "-")))
	p.accept_reward()
	# Let the chase camera ease all the way out — it is deliberately NOT a cut.
	for i in 90:
		await get_tree().physics_frame

	var back: float = p.remote_cam.position.z
	print("  camera pulled back %.2f m, signature `%s`" % [back, p.signature_name])
	_ok(p.third_person, "the Force Master is still in first person")
	_ok(back > 1.0,
		"the Force Master's camera never left the head (%.2f m back)" % back)
	_ok((cam.cull_mask & body_bit) != 0,
		"the Force Master cannot see its own body — third person looking at nothing")
	_ok((cam.cull_mask & gun_bit) == 0,
		"the Force Master still draws its first-person weapon, inside its own head")
	_ok(p.signature_name == "FORCE MASTER" or p.signature_name == "JEDI MASTER"
			or p.signature_name == "SITH MASTER",
		"the HUD was told the wrong signature name: `%s`" % p.signature_name)

	# AND AN ORDINARY DEPLOY PUTS IT ALL BACK.
	p.pending = Loadout.new()
	p.pending.adopt_kit(Loadout.Kit.CLONE)
	p._apply_loadout()
	for i in 90:
		await get_tree().physics_frame
	_ok(not p.third_person, "a respawned trooper is still in third person")
	_ok(p.remote_cam.position.z < 0.05,
		"the chase camera never came back in (%.2f m back)" % p.remote_cam.position.z)
	_ok((cam.cull_mask & body_bit) == 0,
		"a respawned trooper can see its own body")
	_ok((cam.cull_mask & gun_bit) != 0,
		"a respawned trooper lost its first-person weapon")
	_ok(p.signature_name == "", "a respawned trooper is still named a signature")
	p.queue_free()
	cam.queue_free()
	await get_tree().process_frame
	_done["third person"] = true
