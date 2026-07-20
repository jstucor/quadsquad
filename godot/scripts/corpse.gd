extends RigidBody3D
## Death "flop": a throwaway rigid-body corpse spawned when a player dies. It's
## a single stiff body (not an articulated ragdoll) roughly matching the blocky
## character, launched with an impulse + spin so it topples and tumbles on the
## floor during the respawn countdown, then frees itself. Collides only with
## the world (layer 1), never with players, so it never blocks anyone.

const LIFETIME := 9.0  # safety self-free if the player doesn't clean it up


func launch(xform: Transform3D, team_color: Color, push_dir: Vector3) -> void:
	global_transform = xform
	collision_layer = 0        # nothing collides *with* the corpse
	collision_mask = 1         # ...but it rests on the world floor/walls
	_build(team_color)
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


func _build(team_color: Color) -> void:
	# Collision roughly covers torso+legs; the body tips over as one piece.
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.5
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	var suit := _mat(team_color)
	var dark := _mat(Color(0.28, 0.30, 0.36))
	var head := _mat(Color(0.82, 0.80, 0.78))
	_box(Vector3(0.42, 0.62, 0.24), Vector3(0, 1.2, 0), suit)      # torso
	_box(Vector3(0.28, 0.30, 0.28), Vector3(0, 1.68, 0), head)     # head
	# arms out to the sides, legs splayed — reads as a limp flop
	_box(Vector3(0.5, 0.12, 0.12), Vector3(-0.34, 1.35, 0), dark)  # left arm
	_box(Vector3(0.5, 0.12, 0.12), Vector3(0.34, 1.35, 0), dark)   # right arm
	_box(Vector3(0.16, 0.85, 0.17), Vector3(-0.12, 0.42, 0), suit) # left leg
	_box(Vector3(0.16, 0.85, 0.17), Vector3(0.12, 0.42, 0), suit)  # right leg
