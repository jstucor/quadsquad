extends Node3D
## Where a round LANDS. A shot that ends by simply deleting its tracer is the
## most obviously fake thing about shooting, and it is the cheapest to fix: a
## flat scorch on the surface, a short-lived flare, and a handful of sparks
## thrown off along the bounce.
##
## Built entirely from boxes and one quad, unshaded, no light and no particle
## system. Three reasons, all the same reason: this happens hundreds of times a
## second across four viewports on a Pi. A GPUParticles3D emitter per bullet
## would be a new draw call and a new buffer per hit; a dynamic light per bullet
## is the thing the muzzle flash deliberately does not do (see Weapon).
##
## `normal` is the surface it hit, so the scorch lies ON the wall rather than
## floating at an angle to it and the sparks go the way a real one would.
##
## The pieces are deliberately SMALL. Untextured, a quad is unavoidably a square,
## and a big one reads as a coloured sticker on the wall; at the ten to fifty
## metres a firefight actually happens over, a few pixels of flare and four
## streaks read as a spark burst, which is the whole job. Judge these from
## gameplay distance, not from a close-up.

const LIFE := 0.28
const SPARKS := 4
const SPARK_SPEED := Vector2(4.0, 9.0)    # min/max m/s
const SPARK_GRAVITY := 14.0
const SCORCH_SIZE := 0.07
const SPARK_SIZE := Vector3(0.012, 0.012, 0.06)
const FLARE_SIZE := 0.12

## ONE quad and ONE box for every impact in the game, ever. Size comes from the
## instance's SCALE, which the fade animation is already driving — so a mesh
## resource per piece per hit bought nothing at all. This is the project's
## no-per-frame-allocation rule: a repeater puts thirteen of these a second into
## the world per shooter, and six meshes plus six materials each was the single
## most expensive thing added in this pass.
static var _QUAD: QuadMesh
static var _BOX: BoxMesh

## AT NIGHT, THE FAR END OF THE SHOT IS ALSO A LIGHT. By day the note above holds
## exactly as written — an impact light is invisible against a sun and costs a
## light per bullet to be invisible. In the dark it is the other half of what the
## muzzle flash does: the flash shows the shooter where they are, and the impacts
## show everyone else where the shooting is landing. Rounds walking across a
## ridge line lighting it as they go is the thing the mode exists for.
##
## What makes it affordable is that the lights are a FIXED POOL, claimed round
## robin and never allocated: however many rounds are in the air, at most
## NIGHT_LIGHTS of them are lit, so a repeater and a hundred-body battle cost the
## same as one pistol. That is the per-shot allocation rule with a ceiling on top
## — the count stops depending on the rate of fire at all.
##
## The pool hangs off the current scene, so it is freed with the map and rebuilt
## on the next one. Each light carries a CLAIM token: an impact only ever touches
## the light it was given while that token still matches, so a burst whose light
## has since been re-claimed by a newer one quietly does nothing rather than
## putting somebody else's light out.
## Rendered and looked at: at 5.5 m the pool of light a round threw was smaller
## than the burst's own sparks and the hit read exactly as it did by day. The
## reach is what makes it information — a round landing has to show you a few
## metres of the ground it landed on, or it is a spark and nothing more.
const NIGHT_LIGHTS := 14
const NIGHT_LIGHT_RANGE := 9.0
const NIGHT_LIGHT_ENERGY := 5.0
const NIGHT_LIGHT_TIME := 0.16

static var _lights: Array = []
static var _next := 0
static var _claims := 0

var _age := 0.0
var _light: OmniLight3D = null
var _claim := -1
var _sparks: Array[Node3D] = []
var _vel: Array[Vector3] = []
var _flare: MeshInstance3D
var _scorch: MeshInstance3D
## Three materials per burst, not six: the scorch and the flare fade on their own
## curves, but the four sparks fade together and can share one. They still cannot
## be shared ACROSS impacts — each burst fades on its own clock, and one shared
## material would fade every impact on the map together.
var _scorch_mat: StandardMaterial3D
var _flare_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D


## `color` is the firing weapon's own flash colour, so a plasma hit sparks the
## colour the plasma was — the muzzle, the tracer and the impact agree without
## any of them being told about the others.
func burst(at: Vector3, normal: Vector3, color: Color) -> void:
	global_position = at + normal * 0.01   # off the surface, or it z-fights
	# The up vector has to be PERPENDICULAR to the look axis, and the look axis
	# here IS the normal — so `up` may be anything except the normal itself.
	# World up does for a wall; for a floor or a ceiling, where world up is the
	# normal, fall back to forward.
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	# Looking BACK along the normal puts the quad's +Z (which is the face a
	# QuadMesh presents) pointing out of the surface.
	look_at_from_position(global_position, global_position - normal, up)

	if _QUAD == null:
		_QUAD = QuadMesh.new()
		_BOX = BoxMesh.new()
		# Give the shared meshes a SURFACE material, even though every instance
		# overrides it. A PrimitiveMesh defaults to a null surface material and
		# the renderer still queries the surface for its instance shader
		# parameters — with hundreds of these a second that was a steady drip of
		# `Parameter "material" is null` out of the rendering server. The override
		# is what actually draws; this is only so the surface is never empty.
		var placeholder := StandardMaterial3D.new()
		placeholder.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_QUAD.material = placeholder
		_BOX.material = placeholder

	# The scorch: a quad lying flat on the surface. Dark, not bright — it is the
	# mark left behind, and it is what stops the flare reading as a floating dot.
	_scorch_mat = _fx_mat(Color(0.04, 0.03, 0.03, 0.85), false)
	_scorch = _quad(SCORCH_SIZE, _scorch_mat)
	# Rolled about its own normal: every scorch is the same square, and stamping
	# them all at the same angle reads as a repeated decal rather than as damage.
	_scorch.rotation.z = randf_range(0.0, TAU)
	# The flare: the brief bright core of the hit.
	_flare_mat = _fx_mat(color, true)
	_flare = _quad(FLARE_SIZE, _flare_mat)

	if GameState.is_night():
		_take_light(at + normal * 0.35, color)

	_spark_mat = _fx_mat(color.lightened(0.3), true)
	for i in SPARKS:
		var s := _spark()
		_sparks.append(s)
		# Into the hemisphere around the normal, biased along it: a ricochet
		# comes back off the wall, it does not crawl along it.
		var dir := (normal * 1.4 + Vector3(randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))).normalized()
		_vel.append(dir * randf_range(SPARK_SPEED.x, SPARK_SPEED.y))


func _process(delta: float) -> void:
	# CLAMPED. A hitch — a map finishing its load, a shadow atlas rebuild — hands
	# out a delta of a whole second or more, and an effect that lives for a
	# quarter of one is then born and freed inside a single frame, having never
	# been drawn. Impacts land during exactly the busy moments that cause those
	# hitches, so it is worth an unrealistically slow effect rather than no
	# effect at all.
	_age += minf(delta, LIFE * 0.18)
	var t := _age / LIFE
	if t >= 1.0:
		_drop_light()
		queue_free()
		return
	if _light != null:
		var lt := _age / NIGHT_LIGHT_TIME
		if lt >= 1.0:
			_drop_light()
		elif _light.get_meta("claim", -1) == _claim:
			# Squared falloff: a flash that fades linearly reads as a lamp being
			# turned down, where a hit is bright and then simply over.
			_light.light_energy = NIGHT_LIGHT_ENERGY * (1.0 - lt) * (1.0 - lt)
		else:
			_light = null   # re-claimed by a newer hit; it is not ours to fade
	var fade := (1.0 - t) * (1.0 - t)
	# The flare is a fast pop: bright for a frame or two, then gone well before
	# the sparks are, which is what gives the hit a sharp front edge.
	_flare.scale = Vector3.ONE * FLARE_SIZE * (1.0 + t * 2.5)
	_flare_mat.albedo_color.a = maxf(1.0 - t * 3.5, 0.0)
	_scorch_mat.albedo_color.a = 0.85 * fade   # the scorch outlives it, just
	for i in _sparks.size():
		_vel[i].y -= SPARK_GRAVITY * delta
		_sparks[i].global_position += _vel[i] * delta
		# Streak along travel, so a spark reads as a moving ember rather than a
		# dot: the faster it is going, the longer it draws.
		_sparks[i].scale = SPARK_SIZE \
			* Vector3(1.0, 1.0, clampf(_vel[i].length() * 0.35, 1.0, 6.0))
	_spark_mat.albedo_color.a = fade


## Claim the next light out of the shared pool, building the pool on first use.
## Positioned a little OFF the surface, or half of what it lights is the inside
## of the wall it hit.
func _take_light(at: Vector3, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	# The pool dies with the map it was parented to, so it is validated rather
	# than assumed. One stale entry means the whole pool is stale.
	if _lights.size() != NIGHT_LIGHTS or not is_instance_valid(_lights[0]) \
			or _lights[0].get_parent() != scene:
		_lights.clear()
		for i in NIGHT_LIGHTS:
			var l := OmniLight3D.new()
			l.omni_range = NIGHT_LIGHT_RANGE
			l.shadow_enabled = false
			l.light_specular = 0.4
			l.visible = false
			scene.add_child(l)
			_lights.append(l)
		_next = 0
	_light = _lights[_next]
	_next = (_next + 1) % NIGHT_LIGHTS
	_claims += 1
	_claim = _claims
	_light.set_meta("claim", _claim)
	_light.global_position = at
	_light.light_color = color
	_light.light_energy = NIGHT_LIGHT_ENERGY
	_light.visible = true


func _exit_tree() -> void:
	_drop_light()


## Put our light out — but only if it is still ours.
func _drop_light() -> void:
	if _light != null:
		if is_instance_valid(_light) and _light.get_meta("claim", -1) == _claim:
			_light.visible = false
		_light = null


## Size rides the SCALE, so the shared unit quad serves every piece.
func _quad(size: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _QUAD
	mi.scale = Vector3.ONE * size
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _spark() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _BOX
	mi.scale = SPARK_SIZE
	mi.material_override = _spark_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _fx_mat(color: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	return m
