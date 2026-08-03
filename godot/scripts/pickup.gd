class_name Pickup
extends Area3D
## A piece of gear lying on the ground in battle royale: a gun, a sidearm or a
## gadget (grenades are gadgets now). Stand on it and press the pick-up control
## to take it — deliberately NOT automatic, because walking over a pistol and
## losing the rifle you were carrying is exactly the frustration auto-pickup
## causes.
##
## Everything it can give is expressed as a change to the player's LOADOUT and
## then re-applied, rather than as a special case per item — that way a picked-up
## rifle behaves exactly like a bought one, keeps working across the weapon swap
## and the rotary toggle, and needs no second code path anywhere. It does NOT
## refill health: you keep the damage you were carrying (health regenerates on
## its own once you break contact).

enum Kind { PRIMARY, SIDEARM, GADGET }

const FLOAT_HEIGHT := 0.9
const SPIN_RATE := 1.4
const BOB := 0.12
const RADIUS := 1.3

var kind: int = Kind.PRIMARY
var value := 0          # index into the relevant Loadout table

var _bob_t := 0.0
var _body: Node3D
var _nearby := {}   # players standing in reach right now


## What each kind looks like and is called. The colour is the whole readout at
## range — you should be able to tell a gun from a gadget across a dune.
const LOOKS := {
	Kind.PRIMARY: {"tint": Color(1.0, 0.72, 0.25), "label": "WEAPON"},
	Kind.SIDEARM: {"tint": Color(0.95, 0.85, 0.45), "label": "SIDEARM"},
	Kind.GADGET: {"tint": Color(0.55, 0.75, 1.0), "label": "GADGET"},
}


func setup(item_kind: int, item_value: int) -> void:
	kind = item_kind
	value = item_value
	# Layer 4 is the one nothing moves against (the front shield already uses
	# it), so a pickup never blocks a body or stops a bullet.
	collision_layer = 8
	collision_mask = 2   # watch the player layer only
	monitoring = true
	_build()


func _build() -> void:
	var look: Dictionary = LOOKS[kind]
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	shape.position.y = FLOAT_HEIGHT
	add_child(shape)

	_body = Node3D.new()
	_body.position.y = FLOAT_HEIGHT
	add_child(_body)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = look["tint"]
	mat.emission_enabled = true
	mat.emission = look["tint"]
	mat.emission_energy_multiplier = 2.2
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.42, 0.42)
	mesh.mesh = box
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mesh)

	# A wider, fainter halo so it can be spotted from across open ground.
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_color = Color(look["tint"].r, look["tint"].g, look["tint"].b, 0.22)
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	cyl.height = 3.2
	cyl.radial_segments = 8
	cyl.cap_top = false
	beam.mesh = cyl
	beam.material_override = halo
	beam.position.y = 0.9
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_bob_t += delta
	_body.rotation.y += SPIN_RATE * delta
	_body.position.y = FLOAT_HEIGHT + sin(_bob_t * 2.0) * BOB


func label() -> String:
	return LOOKS[kind]["label"]


## Only living players collect. Bots are skipped deliberately: they deploy with
## a full preset already, so letting them hoover up the ground would strip the
## map of gear the humans are relying on finding.
##
## Standing on a crate does NOT take it. Walking over a rifle and losing the one
## you were carrying is the whole reason auto-pickup is a bad idea, so a crate
## only advertises itself and waits for the pick-up control.
func _on_body_entered(body: Node) -> void:
	if not (body is Player) or not body.is_alive():
		return
	_nearby[body] = true
	body.pickup_in_reach = self


func _on_body_exited(body: Node) -> void:
	if not _nearby.erase(body):
		return
	# Only release the prompt if it is still ours: walking straight from one
	# crate into another hands it over, and we must not clear the new one.
	if body is Player and body.pickup_in_reach == self:
		body.pickup_in_reach = null


func _physics_process(_delta: float) -> void:
	for body in _nearby:
		if not is_instance_valid(body) or not body.is_alive():
			continue
		if not body.pickup_pressed:
			continue
		if _grant(body):
			Audio.play("pickup")
			body.pickup_pressed = false   # one press, one crate
			body.pickup_in_reach = null
			queue_free()
			return


## Fold the item into the player's build and re-apply it. Returns false when
## there is nothing to gain, so the pickup stays for somebody who needs it.
func _grant(player: Player) -> bool:
	var build: Loadout = player.loadout
	match kind:
		Kind.PRIMARY:
			if build.weapon == value:
				return false
			build.weapon = value
		Kind.SIDEARM:
			if build.secondary == value:
				return false
			build.secondary = value
		Kind.GADGET:
			if build.gadget == value:
				return false
			build.gadget = value
	player.collect(self)
	return true
