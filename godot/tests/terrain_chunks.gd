extends Node
## WINDOWED. What cutting the heightfield into chunks actually bought.
##
## The claim being tested is narrow and easy to get wrong by assertion: a single
## map-spanning terrain mesh has an AABB covering the level, so it can never be
## frustum-culled and every viewport draws all of it every frame. Chunks can be
## culled per camera. Whether that MATTERS on a frame this project has measured
## as fill-bound is exactly the question, so it is measured rather than argued.
##
## THE A/B IS DONE IN ONE PROCESS, by welding the chunks back into one mesh and
## measuring again. Two runs of two binaries would differ by thermal state as
## much as by the change — the laptop throttles to roughly half clock (CLAUDE.md,
## Smoothness), which is also why this runs A/B/A and reports the two A's.

const MAIN := preload("res://scenes/main.tscn")

const WARMUP := 90
const SAMPLE := 150


func _ready() -> void:
	Quality.governor_enabled = false   # it makes resolution inconsistent
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.class_mode = GameState.ClassMode.CUSTOM
	GameState.team_count = 2
	GameState.team_size = 6
	GameState.human_players = 4
	GameState.map_index = GameState.procedural_map_index()
	GameState.rotate_maps = false

	var main: Node = MAIN.instantiate()
	add_child(main)
	for i in 150:
		await get_tree().process_frame

	var terrain := _find_terrain()
	if terrain == null:
		print("FAIL: no Terrain node — nothing to measure")
		get_tree().quit(1)
		return

	var chunks: Array[MeshInstance3D] = []
	for c in terrain.get_children():
		if c is MeshInstance3D:
			chunks.append(c)
	print("\n==== terrain chunking ====")
	print("  map %.0f m, %d chunks" % [GameState.map_extents.x * 2.0, chunks.size()])
	if chunks.size() < 2:
		print("FAIL: terrain is not chunked (%d mesh) — the whole point" % chunks.size())
		get_tree().quit(1)
		return
	var aabb: AABB = chunks[0].get_aabb()
	print("  a chunk's AABB is %.0f x %.0f m against a %.0f m map — an object is"
		% [aabb.size.x, aabb.size.z, GameState.map_extents.x * 2.0])
	print("  culled as a WHOLE, so this is the granularity culling can work at.")

	# --- A: chunked ----------------------------------------------------------
	var a1 := await _measure()
	# --- B: welded back into one mesh (what it used to be) --------------------
	var welded := _weld(terrain, chunks)
	var b := await _measure()
	# --- A again: thermal control --------------------------------------------
	welded.queue_free()
	for c in chunks:
		c.visible = true
	var a2 := await _measure()

	print("\n  %-22s %8s %9s %9s" % ["state", "ms", "draws", "tris"])
	print("  %-22s %8.2f %9.0f %9.0f" % ["chunked (A)", a1["ms"], a1["draws"], a1["tris"]])
	print("  %-22s %8.2f %9.0f %9.0f" % ["one mesh (B)", b["ms"], b["draws"], b["tris"]])
	print("  %-22s %8.2f %9.0f %9.0f" % ["chunked again (A)", a2["ms"], a2["draws"], a2["tris"]])
	var a_ms: float = (a1["ms"] + a2["ms"]) * 0.5
	var a_tris: float = (a1["tris"] + a2["tris"]) * 0.5
	print("\n  chunking is worth %+.2f ms and %+.0f triangles a frame at 4 viewports"
		% [b["ms"] - a_ms, b["tris"] - a_tris])
	print("  (A-to-A spread %.2f ms — anything inside that is noise)"
		% absf(a1["ms"] - a2["ms"]))
	get_tree().quit(0)


func _find_terrain() -> Node:
	for n in get_tree().get_nodes_in_group("_never_"):
		pass
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "Terrain":
			return n
		for c in n.get_children():
			stack.append(c)
	return null


## Rebuild the old single map-spanning mesh from the chunks' own surfaces, and
## hide the chunks. Same triangles, same material, one object — which is the only
## variable that moves.
func _weld(terrain: Node, chunks: Array[MeshInstance3D]) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in chunks:
		st.append_from(c.mesh, 0, Transform3D.IDENTITY)
		c.visible = false
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = chunks[0].material_override
	terrain.add_child(mi)
	return mi


func _measure() -> Dictionary:
	for i in WARMUP:
		await get_tree().process_frame
	var total := 0.0
	var draws := 0.0
	var tris := 0.0
	for i in SAMPLE:
		await get_tree().process_frame
		total += Performance.get_monitor(Performance.TIME_PROCESS)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		tris += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	return {
		"ms": total / SAMPLE * 1000.0,
		"draws": draws / SAMPLE,
		"tris": tris / SAMPLE,
	}
