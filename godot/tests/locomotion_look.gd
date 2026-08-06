extends Node3D
## WINDOWED. What the directional clips LOOK like.
##
##   godot --path godot --display-driver x11 --resolution 1280x400 tests/locomotion_look.tscn
##
## A contact sheet is the only honest way to judge these, because what is being
## judged is whether a sidestep reads as DIFFERENT from a stride — and a single
## body photographed alone reads as fine in every clip. They go side by side, all
## at the same moment of their cycle, front-on: a sidestep is a roll in the
## FRONTAL plane, so a three-quarter view is exactly the angle that hides it.
##
## Shots land in user:// (~/.local/share/godot/app_userdata/QuadSquad/).

## THE SIDESTEPS ARE NOT HERE ANY MORE. Nothing selects `strafe_l`/`strafe_r`
## since the hips learned to swivel (`Locomotion.swivel_for`) — sideways travel
## is now the forward stride with the legs turned — so photographing them would
## be a contact sheet of two clips the game never plays. They are still in the
## library; `tests/swivel_look.tscn` is the sheet for what replaced them.
const CLIPS := ["walk", "walk_back"]
const SPACING := 1.35
## Two moments of the cycle: the legs at full reach and the legs passing. A clip
## caught only at its extreme can be a static pose that never moves.
const PHASES := [0.25, 0.5]


func _ready() -> void:
	_floor()
	_light()
	Grade.apply_to(self, 1.6)

	var bodies: Array[CharacterModel] = []
	for i in CLIPS.size():
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3((i - (CLIPS.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		m.set_style(0)
		m.set_render_layers(1)
		bodies.append(m)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.05, 3.1)
	cam.look_at(Vector3(0.0, 0.85, 0.0), Vector3.UP)
	cam.current = true

	for phase in PHASES:
		for i in CLIPS.size():
			var anim: AnimationPlayer = bodies[i].anim_player
			var clip: String = CLIPS[i]
			if not anim.has_animation(clip):
				push_error("no clip named %s" % clip)
				continue
			# SEEKED, not played, and with `update` true so the pose is written
			# this frame. Playing them would photograph four bodies at four
			# unrelated moments of their own cycles, which is a contact sheet that
			# compares nothing.
			anim.play(clip)
			anim.seek(anim.get_animation(clip).length * phase, true)
			anim.pause()
		await get_tree().process_frame
		await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		var path := "user://locomotion_%02d.png" % int(phase * 100.0)
		shot.save_png(path)
		print("  %s   %s at phase %.2f" % [path, str(CLIPS), phase])
	print("done")
	get_tree().quit()


func _floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.33)
	mat.metallic = 0.0
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-42, 152, 0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.36, 0.44)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.50, 0.58)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
