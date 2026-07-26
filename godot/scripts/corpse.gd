extends RigidBody3D
## Death: a throwaway rigid body carrying the dead unit's OWN model, launched
## with an impulse and a spin so it topples and tumbles during the respawn
## countdown, then frees itself. Collides only with the world (layer 1), never
## with players, so it never blocks anyone.
##
## It wears the style the unit deployed as — a clone stays a clone, a B2 stays a
## B2 — collapsed into a limp pose (CharacterModel.collapse_pose). The body is
## one stiff piece rather than an articulated ragdoll on purpose: the motion the
## eye reads as "they went down" is the tumble, which costs one rigid body, and
## a jointed solver would be four viewports of work per death on the Pi budget
## to say the same thing. The model is built with no AnimationPlayer at all
## (static_pose), so a corpse is meshes and nothing else.
##
## CLASSIC DEATH (Controls.classic_death, on the controls screen) brings back
## the original: a generic box figure with its arms straight out. It reads as a
## T-posing mannequin, which is exactly why it is worth keeping as an option.

const LIFETIME := 9.0  # safety self-free if the player doesn't clean it up
## How much the limbs vary between one corpse and the next. Enough that two
## bodies dropped on the same spot are not the same silhouette.
const POSE_SPREAD := 1.0


## `style` is a CharacterModel.Style — which body this was. -1 falls back to the
## generic trooper, which is also what the classic flop always drew.
func launch(xform: Transform3D, team_color: Color, push_dir: Vector3,
		style := -1) -> void:
	global_transform = xform
	collision_layer = 0        # nothing collides *with* the corpse
	collision_mask = 1         # ...but it rests on the world floor/walls
	_build_collision()
	if Controls.classic_death():
		_build_classic(team_color)
	else:
		_build_model(team_color, style)
	var push := push_dir
	push.y = 0.0
	if push.length() < 0.1:
		push = -global_transform.basis.z
	linear_velocity = push.normalized() * randf_range(2.5, 4.5) + Vector3.UP * randf_range(2.5, 3.5)
	angular_velocity = Vector3(randf_range(-7, 7), randf_range(-4, 4), randf_range(-7, 7))
	get_tree().create_timer(LIFETIME).timeout.connect(_safe_free)


func _safe_free() -> void:
	if is_instance_valid(self):
		queue_free()


## The unit's own body, collapsed. Rendered on layer 1 (the default) like the
## boxes it replaced, so every camera sees it — including the dead player's, who
## is watching their own corpse from where they were standing.
func _build_model(team_color: Color, style: int) -> void:
	var model := CharacterModel.new()
	model.static_pose = true          # one pose; it never animates
	add_child(model)
	model.set_style(style if style >= 0 else CharacterModel.Style.GENERIC)
	model.set_team_color(team_color)
	model.apply_pose(model.collapse_pose(POSE_SPREAD),
		CharacterModel.COLLAPSE_HIP_DROP)


## Collision roughly covers torso+legs; the body tips over as one piece.
func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.5
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.0
	m.roughness = 0.75
	return m


func _box(size: Vector3, center: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	mi.material_override = mat
	add_child(mi)  # layer 1 (default) so every camera, incl. the dead player, sees it


## The original flop: a generic figure with its arms out to the sides. Kept
## behind the CLASSIC DEATH option.
func _build_classic(team_color: Color) -> void:
	var suit := _mat(team_color)
	var dark := _mat(Color(0.28, 0.30, 0.36))
	var head := _mat(Color(0.82, 0.80, 0.78))
	_box(Vector3(0.42, 0.62, 0.24), Vector3(0, 1.2, 0), suit)      # torso
	_box(Vector3(0.28, 0.30, 0.28), Vector3(0, 1.68, 0), head)     # head
	# arms out to the sides, legs splayed
	_box(Vector3(0.5, 0.12, 0.12), Vector3(-0.34, 1.35, 0), dark)  # left arm
	_box(Vector3(0.5, 0.12, 0.12), Vector3(0.34, 1.35, 0), dark)   # right arm
	_box(Vector3(0.16, 0.85, 0.17), Vector3(-0.12, 0.42, 0), suit) # left leg
	_box(Vector3(0.16, 0.85, 0.17), Vector3(0.12, 0.42, 0), suit)  # right leg
