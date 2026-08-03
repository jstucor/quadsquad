extends Node3D
## RECON SWEEP — the UAV. For its duration, every living enemy is marked for the
## caller's whole side, on the minimap and boxed through walls.
##
## IT REUSES THE SCAN DART'S MECHANISM ENTIRELY (`GameState.mark_scanned`), which
## is the point: the dart already taught the minimap to draw a hollow diamond,
## `Main._draw_scan` to box a body through a wall, and both to clear themselves
## when the mark expires. A sweep is the same reveal with the radius taken off.
##
## WHAT MAKES IT A REWARD RATHER THAN A BIGGER DART is that it has no position.
## The dart is thrown somewhere and reveals a bubble; this reveals the MAP, so it
## answers "where is everybody" instead of "who is behind that wall". That is
## also why it does not need to exist in the world at all — no mesh, no collider,
## nothing to shoot down. It is a timer with a team on it.
##
## Deliberately NOT line-of-sight gated, exactly as the dart is not: a scan is a
## ping, and a reveal you have to be able to see already is no reveal.

## RE-MARKED ON A TIMER rather than marked once for the whole duration, because
## the roster CHANGES underneath it — bodies die, respawn and are replaced, and a
## body that spawned after a one-shot mark would be the only invisible thing on
## the field. The interval is the dart's, for the same reason it is the dart's:
## it is short enough that a runner cannot cross the map between pings.
const PULSE := 0.5
## How long each ping's mark lasts. Longer than PULSE so the marks OVERLAP and a
## contact never blinks between two pings — the flicker reads as a broken HUD.
const MARK_TIME := 0.9

var team := 0
var _left := 0.0
var _pulse_left := 0.0


func begin(for_team: int, seconds: float) -> void:
	team = for_team
	_left = seconds
	_pulse_left = 0.0


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		# The marks expire on their own (they carry an `until`), so there is
		# nothing to clean up — the sweep just stops renewing them.
		queue_free()
		return
	_pulse_left -= delta
	if _pulse_left > 0.0:
		return
	_pulse_left += PULSE
	_ping()


func _ping() -> void:
	for c in GameState.combatants:
		if not is_instance_valid(c) or not c.is_alive() or c.team == team:
			continue
		# A CLOAK STILL BEATS IT. The cloak's whole promise is that AI and
		# trackers cannot see you, and a reward that ignored it would make the
		# Trandoshan's signature ability worthless to anybody who ever died to a
		# four-kill streak. Same check every AI vision test makes.
		if GameState.is_cloaked(c):
			continue
		GameState.mark_scanned(c, team, MARK_TIME)
