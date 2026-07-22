extends StaticBody3D
## Personal front shield: a translucent barrier that hangs in front of its owner
## and moves with them. It stops incoming fire, but NOT its owner's — the player
## lists it in hitscan_exclusions(), so their own shots pass straight through
## while everyone else's stop dead.
##
## It sits on physics layer 4, on its own, because layers 1-3 are all wrong for
## it: on the world layer it would shove its owner around (players collide with
## world), and on the player layer everyone would walk into it. Layer 4 is in
## nobody's movement mask, so it only ever intercepts rays.

const SHIELD_LAYER := 8   # bit 4 -> layer 4, see project.godot / CLAUDE.md
const MAX_HEALTH := 220.0
const WIDTH := 1.9
const HEIGHT := 1.7
const STAND_OFF := 1.15    # metres in front of the owner

var health := MAX_HEALTH


func setup(team_color: Color) -> void:
	collision_layer = SHIELD_LAYER
	collision_mask = 0     # it never collides with anything itself
	position = Vector3(0.0, 0.9, -STAND_OFF)  # -Z is forward
	_build(team_color)


## Same signature as every other damageable thing (see Player.take_damage) — a
## shield is hit by the same calls, so it has to accept the same arguments. It
## confirms nothing back to the shooter: a hit on a barrier is not a hit on a
## body, and reporting it would mark every blocked shot as though it landed.
func take_damage(amount: float, _attacker: Node = null, _headshot := false) -> void:
	health -= amount
	if health <= 0.0:
		queue_free()  # overloaded: the owner can throw up a fresh one


func _build(team_color: Color) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH, HEIGHT, 0.12)
	shape.shape = box
	add_child(shape)

	var mesh := MeshInstance3D.new()
	var quad := BoxMesh.new()
	quad.size = Vector3(WIDTH, HEIGHT, 0.06)
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(team_color, 0.22)
	mat.emission_enabled = true
	mat.emission = team_color
	mat.emission_energy_multiplier = 0.7
	mat.metallic = 0.0  # a dark sky reflects into metal (Gotchas)
	mat.roughness = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # visible from both sides
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
