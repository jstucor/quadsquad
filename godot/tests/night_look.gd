extends Node3D
## EVERY GENERATED WORLD AFTER DARK, and — the half that actually matters —
## every one of them WITH THE GUNS GOING. A night map photographed in silence
## proves nothing: the whole design is that the flashes and the blasts are the
## lighting, so a shot of the map holding still is a shot of the one state the
## mode is never in.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/night_look.tscn
##
## WINDOWED, because appearance is the thing being judged and --headless draws
## nothing at all.
##
## Three frames per world:
##   _dark   eye level on a real spawn, nothing firing. THE READABILITY SHOT —
##           the question is whether the ground, the cover and a body's
##           silhouette are still there, because a night map you cannot fight on
##           is a gameplay bug and not a mood. If a body has gone to a flat
##           black hole in this frame, the palette is wrong.
##   _fire   the same view with rounds landing and a blast going off. THE POINT
##           OF THE MODE. It drives the real code — Impact's pooled night light
##           and Blast.pop — so it photographs what ships rather than a lamp put
##           in the scene by the test.
##   _wide   high and wide, to check the world still reads as ITSELF at night:
##           Mustafar by its lava, Coruscant by its windows, Hoth by its snow.
const LEVEL := preload("res://scenes/levels/planet.tscn")
const IMPACT := preload("res://scripts/impact.gd")

## Where the rounds land, relative to the camera's own view: a burst walking
## away from the shooter, which is what a firefight actually looks like from
## behind the gun.
const STRIKES := [
	Vector2(-2.2, -7.0), Vector2(1.6, -11.0), Vector2(-0.9, -16.0),
	Vector2(3.4, -21.0), Vector2(-3.8, -26.0), Vector2(0.6, -33.0),
]
## What colour those rounds are. Asked of the side firing them rather than stated
## here: a bolt, its muzzle flash and its scorch are one colour now (see
## Weapon.bolt_color), and a hardcoded one in a look test is a second source of
## truth that photographs a colour the game does not fire.
static func bolt_color() -> Color:
	return GameState.bolt_color(GameState.Team.REPUBLIC)


func _ready() -> void:
	# Night belongs to the GENERATED world, so the map has to be that one before
	# GameState.is_night() will answer true for anything.
	GameState.map_index = GameState.procedural_map_index()
	GameState.time_of_day = GameState.TimeOfDay.NIGHT
	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 2000.0
	add_child(cam)
	cam.current = true
	for planet in PlanetMap.PLANET_NAMES.size():
		GameState.planet = planet
		# The same seeds planet_look uses, so a night frame and a day frame are
		# the same layout and can be put side by side.
		GameState.planet_seed = 1234 + planet * 77
		var level: Node3D = LEVEL.instantiate()
		add_child(level)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var tag := str(PlanetMap.PLANET_NAMES[planet]).to_lower()
		var half: float = level.size * 0.5

		# Eye level on a real spawn, with two bodies out in front of it. The
		# bodies are the actual test: a map is readable when you can tell there
		# is a man standing on it.
		var spawn: Vector3 = level.republic_spawns[1]
		cam.global_position = spawn + Vector3(0, 1.7, 0)
		cam.look_at(Vector3(0, 14, 0), Vector3.UP)
		var bodies := _bodies(cam, level)
		await _frames(4)
		await _grab(tag + "_dark")

		# ...and the same frame with the shooting in it.
		var fx := _open_fire(cam, level)
		await _frames(2)
		await _grab(tag + "_fire")
		for n in fx + bodies:
			if is_instance_valid(n):
				n.queue_free()

		cam.global_position = Vector3(-half * 0.62, half * 0.62, -half * 0.62)
		cam.look_at(Vector3(half * 0.10, 12, half * 0.10), Vector3.UP)
		await _frames(4)
		await _grab(tag + "_wide")

		remove_child(level)
		level.queue_free()
		await _frames(2)
	get_tree().quit()


## Two bodies standing on the ground ahead of the camera. A look test must PLAY
## an animation — a bare CharacterModel sits in a rest pose the game never shows.
func _bodies(cam: Camera3D, level: Node3D) -> Array:
	var out: Array = []
	var fwd := -cam.global_transform.basis.z
	for i in 2:
		var m := CharacterModel.new()
		m.set_style(CharacterModel.Style.CLONE if i == 0
			else CharacterModel.Style.B1)
		m.set_team_color(GameState.team_colors[i])
		add_child(m)
		var at := cam.global_position + fwd * (9.0 + i * 7.0) \
			+ cam.global_transform.basis.x * (-3.0 + i * 6.5)
		at.y = level.height_at(at.x, at.z)
		m.global_position = at
		m.look_at(cam.global_position, Vector3.UP)
		m.rotation.x = 0.0
		m.rotation.z = 0.0
		if m.anim_player:
			m.anim_player.play("idle")
		out.append(m)
	return out


## Rounds landing and one blast, through the shipping code paths. The strikes are
## put ON THE GROUND rather than at a height off the camera — a light floating
## three metres up lights nothing you would ever see, which is how the first pass
## of this test managed to photograph the impact lights and show none of them.
func _open_fire(cam: Camera3D, level: Node3D) -> Array:
	var out: Array = []
	var basis := cam.global_transform.basis
	for s in STRIKES:
		var at := cam.global_position + basis * Vector3(s.x, 0.0, s.y)
		at.y = level.height_at(at.x, at.z) + 0.15
		var burst: Node3D = IMPACT.new()
		add_child(burst)
		burst.burst(at, Vector3.UP, bolt_color())
		out.append(burst)
	var boom := cam.global_position + basis * Vector3(5.0, 0.0, -18.0)
	boom.y = level.height_at(boom.x, boom.z) + 1.2
	Blast.pop(self, boom, 5.0)
	return out


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://night_%s.png" % tag)
	print("wrote %s" % tag)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
