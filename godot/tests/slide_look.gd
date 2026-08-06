extends Node3D
## WINDOWED. Does the slide read as a slide?
##
##   godot --path godot --display-driver x11 --resolution 1280x420 tests/slide_look.tscn
##
## SIDE ON, AND BESIDE A CROUCH. Both of those are the point.
##
## A slide's whole silhouette is asymmetry in the SAGITTAL plane — one leg thrown
## out in front, the other folded underneath, the torso back over the trailing
## hip. Photographed front-on (which is how `locomotion_look` shoots the walk,
## correctly, because a sidestep is a roll in the FRONTAL plane) every one of
## those reads as a body that is simply low. It is the exact angle that hides
## this pose.
##
## And it goes next to `crouch_idle` and `run`, because the question is not "is
## this a nice pose" — alone, it photographs fine. The question is whether it is
## visibly a DIFFERENT THING from a crouch, since that is what it looked like
## before it had a clip of its own: `Player._crouch_held()` answers true while
## sliding, so without this clip the state machine picked `crouch_walk` and every
## slide in the game was a man squatting at eight metres a second.
##
## Shots land in user:// (~/.local/share/godot/app_userdata/QuadSquad/).

const CLIPS := ["run", "crouch_idle", "slide"]
const SPACING := 1.6
## The slide clip does not loop — it eases into its pose and holds — so it is
## photographed at the END of its settle, which is the pose it actually spends
## the slide in. The other two are caught mid-cycle.
const PHASES := [0.55, 1.0]

var bodies: Array[CharacterModel] = []


func _ready() -> void:
	_floor()
	_light()
	Grade.apply_to(self, 1.6)

	for i in CLIPS.size():
		var m := CharacterModel.new()
		m.set_style(CharacterModel.Style.LEGION)
		m.set_team_color(GameState.team_color(0))
		add_child(m)
		m.position = Vector3((i - (CLIPS.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		# TURNED SIDE ON. The bodies face along +X so the camera, which looks
		# down -Z, sees every one of them in profile.
		m.rotation.y = deg_to_rad(90.0)
		bodies.append(m)

	var cam := Camera3D.new()
	add_child(cam)
	# Low and close: a slide is a thing that happens near the ground, and a
	# camera at standing eye height looks down on it and flattens the leg out.
	cam.position = Vector3(0.0, 0.75, 3.4)
	cam.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	cam.current = true

	for phase in PHASES:
		for i in CLIPS.size():
			var anim: AnimationPlayer = bodies[i].anim_player
			var clip: String = CLIPS[i]
			if not anim.has_animation(clip):
				push_error("no clip named %s" % clip)
				continue
			# SEEKED, not played, with `update` true so the pose is written this
			# frame — three bodies playing freely would be three unrelated
			# moments of three cycles, which compares nothing.
			anim.play(clip)
			anim.seek(anim.get_animation(clip).length * phase, true)
			anim.pause()
		await get_tree().process_frame
		await get_tree().process_frame
		var shot := get_viewport().get_texture().get_image()
		var path := "user://slide_%03d.png" % int(phase * 100.0)
		shot.save_png(path)
		print("  %s   %s at phase %.2f" % [path, str(CLIPS), phase])
	print("done")
	get_tree().quit()


## A floor to stand on and catch the shadow. Without one the bodies float and
## the one thing this sheet is judging — how LOW the slide sits — has nothing to
## be low against.
func _floor() -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.0
	mat.roughness = 0.9
	mat.albedo_color = Color(0.20, 0.21, 0.24)
	mi.material_override = mat
	add_child(mi)


func _light() -> void:
	var sun := DirectionalLight3D.new()
	# Across the bodies rather than down the camera axis: a profile shot lit from
	# the camera has no shadow on it, and the shadow is what says which leg is in
	# front of which.
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(-55.0), 0.0)
	sun.light_energy = 1.9
	Grade.light(sun)
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(130.0), 0.0)
	fill.light_energy = 0.4
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)
