extends Node3D
## Visual-only blaster bolt tracer. The weapon's hitscan already decided the
## outcome; this just flies the path and frees itself at the end point.

const SPEED := 400.0  # bolts read as fast energy blasts, not lobbed pellets

## THE IMPACT. A round that simply stops existing where it lands is the single
## most obviously fake thing about shooting, and it was free to fix: this node is
## already allocated and already at the impact point, so instead of freeing on
## arrival it spends a few frames as a flash — the bolt mesh flattens, swells and
## fades, which reads as a splash of energy on the surface.
##
## Deliberately NO light here, unlike the muzzle and the rocket blast. A repeater
## puts thirteen of these a second into the world per shooter, and a dynamic
## light per bullet impact is the one version of this that the Pi cannot pay for.
const IMPACT_TIME := 0.07
const IMPACT_SWELL := 5.0     # how much the flash grows over its life

## Black albedo and all the colour in the emission, so the bolt reads as light
## rather than as a painted capsule — and so Grade's HDR glow threshold picks it
## up and blooms it in its own hue.
const EMISSION_ENERGY := 5.0

## ONE MATERIAL PER COLOUR, shared by every bolt that will ever fly in it.
##
## This is the middle ground between two things that both fail. A single material
## in the scene file is one colour for every gun in three universes, which is
## what this was. A material DUPLICATED per bolt is an allocation and a free
## hundreds of times a second, which the rendering server was measurably unhappy
## about — see the note on _burn below, that defect is why it animates scale.
##
## What makes a cache the right answer here is that the colour set is a TABLE:
## four sides in each of three universes, plus the handful of weapons that state
## a colour of their own. So this dictionary stops growing after the first shot
## of each kind and its size never depends on the rate of fire. Same idiom, and
## the same reason, as Meshes.chamfer_box caching per size.
static var _mats := {}

var _dir := Vector3.ZERO
var _remaining := 0.0
var _speed := SPEED
var _impact := 0.0            # seconds of flash left, once it has landed
var _mesh: MeshInstance3D


static func _material(col: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = _mats.get(col)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color.BLACK
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = EMISSION_ENERGY
		_mats[col] = mat
	return mat


## `col` is the firing weapon's own colour (Weapon.bolt_color) — the same one its
## muzzle light and its impact scorch use, so a round matches the flash that threw
## it and the mark it leaves.
## `speed` is an OVERRIDE and gameplay never passes one. It exists for the front
## screen's firefight, which is the same bolt in the same material fired for a
## different purpose: at the shipping 400 m/s a round crosses a twenty-metre gap
## in three frames, which is exactly right when it is settling a fight and
## invisible when it is decoration. A parameter rather than a second tracer node,
## so the menu cannot end up showing a bolt the game does not fire.
func launch(from: Vector3, to: Vector3, col: Color, speed := SPEED) -> void:
	_speed = speed
	global_position = from
	_remaining = from.distance_to(to)
	if _remaining < 0.01:
		queue_free()
		return
	_mesh = get_node_or_null("Mesh") as MeshInstance3D
	if _mesh != null:
		_mesh.set_surface_override_material(0, _material(col))
	_dir = (to - from) / _remaining
	if absf(_dir.dot(Vector3.UP)) < 0.99:
		look_at(to)  # bolt mesh lies along -Z


func _process(delta: float) -> void:
	if _impact > 0.0:
		_burn(delta)
		return
	var step := _speed * delta
	global_position += _dir * step
	_remaining -= step
	if _remaining <= 0.0:
		_land()


## Arrived. Stop, and start the flash.
func _land() -> void:
	if _mesh == null:
		queue_free()
		return
	_impact = IMPACT_TIME


## Swell. SCALE ONLY, and deliberately nothing to do with the material.
##
## This used to duplicate the bolt's material so each one could fade its own
## emission — the scene's material is a SubResource shared by every instance, so
## animating it directly would fade every bolt in the game together. But a
## duplicate is a material CREATED AND DESTROYED per bolt, hundreds of times a
## second across a match, and the rendering server queries a material as it goes:
## a soak of a 4v4 produced a steady drip of `Parameter "material" is null` that
## the pre-change code did not (0 on a clean tree, ~30 a match with this).
##
## Scale is per-instance state and costs nothing. The bolt is unshaded and
## already emissive, so swelling it for 70 ms reads as a splash on the surface —
## the fade was the smaller half of the effect and not worth an allocation and a
## free per round fired.
func _burn(delta: float) -> void:
	_impact -= delta
	if _impact <= 0.0:
		queue_free()
		return
	var t := _impact / IMPACT_TIME          # 1 at the moment of impact, 0 at the end
	_mesh.scale = Vector3.ONE * (1.0 + (1.0 - t) * IMPACT_SWELL)
