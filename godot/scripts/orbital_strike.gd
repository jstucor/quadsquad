extends Node3D
## ORBITAL STRIKE — the gunship. A battery walks fire across the ground the enemy
## is densest on, for its duration, and then it is over.
##
## IT PICKS ITS OWN TARGET, and that is what makes it an ORBITAL strike rather
## than a mortar. The mortar is aimed by a player on the map screen because a
## player placed it; this is called down by somebody up there who can see the
## whole field, so it aims at the CENTROID OF THE BIGGEST ENEMY CLUSTER — the
## same question `Bot._call_mortar_strike` asks, and for the same reason: a
## barrage that chases one runner is a barrage that hits nobody, where one that
## lands on a bunched push is the thing a push has to fear.
##
## RE-AIMED EVERY SALVO, not once at the start. Seven seconds is long enough for
## a group to move off a fixed point, and a bombardment that keeps landing where
## the enemy WAS is the most frustrating possible version of this.
##
## Shells are `mortar_shell.gd` — it already solves its own arc from any height
## to any point, arms after a moment and detonates on first contact. Nothing here
## re-implements ballistics; this is a target picker and a metronome.

const SHELL := preload("res://scenes/fx/mortar_shell.tscn")

## Where the rounds come FROM. High enough that the arc reads as vertical and the
## shells appear out of nothing rather than being lobbed from off the map edge —
## an orbital strike whose shells visibly come from the side is a mortar.
const ALTITUDE := 90.0
## Per salvo: how many rounds and how far they scatter. The scatter is what makes
## it a BARRAGE rather than a very slow sniper — a stack of shells on one point
## kills whoever is on that point and nobody else.
const PER_SALVO := 3
const SCATTER := 7.0
const SALVO_EVERY := 0.55

## Harder than a mortar shell and wider, because this is a 8-kill reward and the
## mortar is a 65-token purchase. Still finite: it must not out-damage the RPG
## per round, or the correct play on earning it is to stand still and watch.
const SPLASH := 6.0
const SPLASH_DAMAGE := 95.0

## How far out to look for somebody to shell. The whole map, effectively — it is
## orbital.
const SEARCH := 400.0
## A cluster is everyone within this of the densest body. Roughly a squad's
## spread, so the barrage covers a group rather than a battalion.
const CLUSTER := 12.0

var team := 0

var _shooter: Node          # credited with the kills, so the streak pays its owner
var _left := 0.0
var _salvo_left := 0.0
var _aim := Vector3.ZERO
var _have_aim := false


func begin(by: Node, for_team: int, seconds: float) -> void:
	_shooter = by
	team = for_team
	_left = seconds
	_salvo_left = 0.0


func _physics_process(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		queue_free()
		return
	_salvo_left -= delta
	if _salvo_left > 0.0:
		return
	_salvo_left += SALVO_EVERY
	if _pick_target():
		_fire_salvo()


## The centroid of the biggest cluster of enemies. Two passes over the roster
## rather than a proper clustering: at this body count the exact densest point is
## not worth an algorithm, and "near whoever has the most company" is the
## question that actually matters.
func _pick_target() -> bool:
	var best_n := 0
	var best_at := Vector3.ZERO
	for c in GameState.combatants:
		if not _is_prey(c):
			continue
		var here: Vector3 = c.global_position
		var n := 0
		var sum := Vector3.ZERO
		for d in GameState.combatants:
			if not _is_prey(d):
				continue
			if here.distance_to(d.global_position) <= CLUSTER:
				n += 1
				sum += d.global_position
		if n > best_n:
			best_n = n
			best_at = sum / float(n)
	if best_n == 0:
		# NOTHING TO SHELL IS NOT AN ERROR. Everyone may be dead, or on the far
		# side of a respawn. It keeps its last aim and tries again next salvo
		# rather than ending early — the reward was earned and it should be seen
		# to run its length.
		return _have_aim
	_aim = best_at
	_have_aim = true
	return true


func _is_prey(c: Node) -> bool:
	return is_instance_valid(c) and c.is_alive() and c.team != team \
		and c.global_position.distance_to(global_position) <= SEARCH


func _fire_salvo() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for i in PER_SALVO:
		var at := _aim + Vector3(
			randf_range(-SCATTER, SCATTER), 0.0, randf_range(-SCATTER, SCATTER))
		var shell := SHELL.instantiate()
		scene.add_child(shell)
		# Straight down from directly above the impact point, so the round that
		# lands and the streak overhead read as the same event.
		shell.launch(at + Vector3.UP * ALTITUDE, at, _shooter, SPLASH, SPLASH_DAMAGE)
