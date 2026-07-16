class_name Weapon
extends Node3D
## Hitscan blaster: damage lands instantly along the aim ray; a glowing bolt
## tracer flies the same path for the Star Wars look. Sits under the player's
## Head so its -Z is always the aim direction. Swap constants (or subclass)
## per Battlefront weapon class later.

const FIRE_INTERVAL := 0.18
const MAX_RANGE := 120.0
const DAMAGE := 25.0
const BOLT_SCENE := preload("res://scenes/fx/blaster_bolt.tscn")

var _cooldown := 0.0


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## Call from _physics_process (the space state is only safe to query there).
func try_fire(shooter: CollisionObject3D) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = FIRE_INTERVAL

	var from := global_position
	var to := from - global_transform.basis.z * MAX_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [shooter.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end: Vector3 = hit.get("position", to)
	if hit and hit.collider != null and hit.collider.has_method("take_damage"):
		hit.collider.take_damage(DAMAGE)

	var bolt := BOLT_SCENE.instantiate()
	get_tree().current_scene.add_child(bolt)
	bolt.launch(from - global_transform.basis.y * 0.12, end)
