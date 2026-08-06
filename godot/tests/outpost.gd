extends Node3D
## THE GENERATED BASE MAKES WHAT IT CLAIMS TO MAKE, on every seed.
##
##   godot --headless --path godot tests/outpost.tscn
##
## `nav_grid` already proves the base is walkable and that its rooms really do
## break the sight lines (22 of 24 straight lines blocked, 0 routes through
## geometry). What it cannot see is whether the interesting parts got BUILT: a
## generator that rolls a base with no tunnel, no big rooms, or a one-cell "run"
## that is a pit rather than a passage is a map somebody plays once and calls
## broken, and every one of those still routes perfectly.
##
## THAT IS NOT HYPOTHETICAL — it is what this map did on its second seed. The
## tunnel start is rolled in the middle third and stops at anything already
## spoken for, so a first cell inside a hall left the run EMPTY and the base
## simply had no basement. It was found by a screenshot that came back without
## one, which is luck; this is the check that does not depend on luck.
##
## Across SEEDS separate rolls, because "it worked on the seed I looked at" is
## the whole failure mode.

const OUTPOST := preload("res://scenes/levels/outpost.tscn")
const SEEDS := 12

var _fails: Array[String] = []


func _ready() -> void:
	var halls_seen := 0
	var tunnel_cells := 0
	var massive_seen := 0
	for i in SEEDS:
		GameState.planet_seed = 1000 + i * 7717
		GameState.reset_match()
		var level: Node3D = OUTPOST.instantiate()
		add_child(level)
		await get_tree().process_frame

		var halls: Array = level._halls
		var sunk: Dictionary = level._sunk
		halls_seen += halls.size()
		tunnel_cells += sunk.size()
		_ok(halls.size() >= 1, "seed %d: the base has a big room (%d)" % [i, halls.size()])
		# A ONE-CELL TUNNEL IS A PIT, NOT A PASSAGE. Two is the minimum that has a
		# direction, and the run is planned with retries precisely so this holds.
		_ok(sunk.size() >= 2, "seed %d: the tunnel is a run, not a hole (%d cells)"
			% [i, sunk.size()])
		# ...and it has to be reachable: the ramp cell must touch the deck.
		if not sunk.is_empty():
			var ramp: Vector2i = level._ramp
			var out := false
			for dir: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var to: Vector2i = ramp + dir
				if to.x >= 0 and to.y >= 0 and to.x < level.GRID and to.y < level.GRID \
						and not level._is_sunk(to.x, to.y):
					out = true
			_ok(out, "seed %d: the ramp climbs out to a cell you can stand on" % i)

		# THE MASSIVE CRATES, which are the point of a big room: taller than a body
		# and therefore cover you cannot see over — the one place this map breaks
		# its own chest-height rule.
		var tall := 0
		for c in level.cover_boxes:
			if float((c["size"] as Vector3).y) >= 2.0:
				tall += 1
		massive_seen += tall
		_ok(tall >= 2, "seed %d: the halls are stacked with massive crates (%d)" % [i, tall])

		# Nothing may be built outside the base, which is the cheapest way to catch
		# a layout that has walked off its own grid.
		var half: float = level.size * 0.5
		var stray := 0
		for c in level.cover_boxes:
			var at: Vector3 = c["pos"]
			if absf(at.x) > half or absf(at.z) > half:
				stray += 1
		_ok(stray == 0, "seed %d: nothing is built outside the base (%d strays)" % [i, stray])

		level.queue_free()
		await get_tree().process_frame

	print("\n  across %d seeds: %.1f halls, %.1f tunnel cells, %.1f massive crates each"
		% [SEEDS, float(halls_seen) / SEEDS, float(tunnel_cells) / SEEDS,
		float(massive_seen) / SEEDS])
	print("\n==== %s ====" % ("THE OUTPOST BUILDS ITSELF" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _ok(cond: bool, what: String) -> void:
	if not cond:
		print("  FAIL %s" % what)
		_fails.append(what)
