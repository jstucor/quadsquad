extends Node
## The hit confirmation, one node per HUD (a player only ever confirms their own
## hits). It used to synthesise and pool its own click; both of those jobs moved
## to `Audio`, which every other sound in the game now goes through, so what is
## left here is the rule for WHICH confirmation a hit earns.
##
## THE OLD CLICK WAS THE PROBLEM, not the plumbing. It was two clean sine
## partials with a noise transient, and a headshot was that same click played
## 1.45x faster — so the most-heard sound in the game was a thin beep whose most
## exciting variant was the same beep on a higher note. They are three separate
## sounds now (`Sfx._hit` / `_hit_head` / `_kill`), built to be told apart across
## a room with three other people shouting: a body hit has weight under it, a
## headshot rings, and a kill drops and resolves.
##
## Local co-op caveat, unchanged: sound is NOT split per player the way the
## screen is, so every confirmation is audible to the whole couch. There is no
## per-viewport audio bus to route it to.

## The kill sound lands BEHIND the hit that caused it, not on top of it. Played
## together they mask each other and read as one muddy noise; a short gap reads
## as cause and effect, which is the entire point of having a separate one.
const KILL_DELAY := 0.09


## Your shot landed on someone. Called from the HUD wiring, once per hit.
func play(headshot: bool, killed: bool) -> void:
	Audio.play("hit_head" if headshot else "hit")
	if killed:
		# A bound method, not a lambda: a lambda that never touches self has no
		# target object, so Godot would keep it alive past this node's death.
		get_tree().create_timer(KILL_DELAY).timeout.connect(_kill_click)


func _kill_click() -> void:
	Audio.play("kill")
