extends Node3D

## WHAT THE ROSTER LOOKS LIKE AT THE SIZE IT ACTUALLY PLAYS AT.
##
##   godot --path godot --display-driver x11 --resolution 1600x700 tests/physique_look.tscn
##
## Windowed, because a size relationship is exactly the thing no headless test
## can judge — `roster_feel.gd` will happily tell you an Ewok stands at 1.12 m
## and a Wookiee at 2.09, and neither number tells you whether the two of them
## standing next to each other reads as Star Wars or as a bug.
##
## Every OTHER look test builds a bare `CharacterModel` at scale 1, which is what
## let the whole roster be the same height for as long as it was: `universe_look`
## photographs the STYLE table, and stature does not live there. This one walks
## the real `FACTION_BUILDS` and asks each build the same three questions the
## match asks it — `stature()`, `character_style()`, `deploy_class()` — so what
## is in the frame is what deploys.
##
## A trooper-sized grey marker stands at the end of every row. Nothing else in
## the shot has an absolute size (these are untextured boxes on an untextured
## floor, so the eye has nothing to measure against), and without it a row of
## four Necrons is just a row of four Necrons however tall they are.

const YARDSTICK_COLOR := Color(0.34, 0.35, 0.38)

var _models: Array[Node3D] = []


func _ready() -> void:
	GameState.match_live = true
	_build_floor()
	_light()
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true

	for u in Loadout.UNIVERSES.size():
		var rosters: Array = Loadout.FACTION_ROSTERS.get(u, [])
		for side in rosters.size():
			var roster: Array = rosters[side]
			# Eight to a side is too many for one legible row, so each roster is
			# shot as its two halves: the four LINE classes, then the four
			# REINFORCEMENTS. That split is the roster's own structure (see the
			# Battlefront note in CLAUDE.md), and the reinforcements are where
			# the interesting sizes are.
			for half in 2:
				var picks: Array = roster.slice(half * 4, half * 4 + 4)
				if picks.is_empty():
					continue
				var tallest := _lay_out(picks)
				var span := float(picks.size() + 1)
				cam.global_transform = Transform3D(Basis(),
					Vector3(0.0, tallest * 0.52, -(0.7 + span * 0.62)))
				cam.look_at(Vector3(0.0, tallest * 0.46, 0.0), Vector3.UP)
				await _frames(6)
				await _grab("u%d_side%d_%s" % [u, side,
					"line" if half == 0 else "reinforcements"])
	_clear()
	get_tree().quit()


## One model per build, at its own stature, plus the yardstick trooper. Returns
## how tall the tallest body in the row stands, which is what the camera has to
## frame — a row containing a Wookiee needs backing off further than a row of
## Grunts, and a fixed camera crops the head off one or loses the other in the
## middle of the frame.
func _lay_out(picks: Array) -> float:
	_clear()
	var gap := 1.25
	var n := picks.size() + 1
	var start := -gap * (n - 1) * 0.5
	var tallest := 1.0
	for i in picks.size():
		var build := Loadout.faction_build(picks[i])
		var tall := build.stature()
		tallest = maxf(tallest, tall)
		var m := CharacterModel.new()
		add_child(m)
		m.set_style(build.character_style())
		m.set_team_color(GameState.team_colors[0])
		m.scale = Vector3.ONE * tall
		m.position = Vector3(start + gap * i, 0.0, 0.0)
		# PLAY something — a bare model stands in its rest pose with both arms
		# hanging, which is not a pose the game ever shows.
		if m.anim_player != null:
			m.anim_player.play("idle")
			m.anim_player.seek(0.0, true)
		_models.append(m)
		print("  %-20s %.2f m  %s" % [
			Loadout.FACTION_BUILDS[picks[i]].get("name", "?"),
			GameState.TROOPER_HEIGHT * tall,
			Weapon.PROFILES[build.deploy_class()].get("name", "?")])
	_models.append(_yardstick(start + gap * picks.size()))
	return GameState.TROOPER_HEIGHT * tallest


## A plain 1.80 m post: the height a standard trooper stands, at the end of every
## row, so the row can be read against something rather than only against itself.
func _yardstick(at_x: float) -> Node3D:
	var post := Node3D.new()
	add_child(post)
	post.position = Vector3(at_x, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = YARDSTICK_COLOR
	mat.roughness = 0.9
	for band in 6:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.30, 0.28, 0.30)
		mi.mesh = box
		mi.material_override = mat
		# Banded rather than one column, so the eye can count thirds of it
		# instead of judging a featureless slab against a figure.
		mi.position.y = 0.15 + band * 0.30
		mi.visible = band % 2 == 0
		post.add_child(mi)
	var cap := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.42, 0.06, 0.42)
	cap.mesh = cm
	cap.material_override = mat
	cap.position.y = GameState.TROOPER_HEIGHT
	post.add_child(cap)
	return post


func _clear() -> void:
	for m in _models:
		if is_instance_valid(m):
			remove_child(m)
			m.queue_free()
	_models.clear()


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://physique_%s.png" % tag
	img.save_png(path)
	print("wrote %s" % ProjectSettings.globalize_path(path))


func _light() -> void:
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	key.light_energy = 1.1
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-150.0), 0.0)
	fill.light_energy = 0.4
	fill.shadow_enabled = false
	add_child(fill)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.48, 0.55)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	Grade.apply_to(self)


func _build_floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(60.0, 2.0, 60.0)
	mi.mesh = plane
	mi.position = Vector3(0.0, -1.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.25, 0.28)
	mi.material_override = mat
	add_child(mi)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
