extends Node3D
const IMPACT := preload("res://scripts/impact.gd")
func _ready() -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(6, 4, 0.4)
	mi.mesh = bm; mi.position = Vector3(0, 1.5, 1.0)
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.30, 0.31, 0.35)
	mi.material_override = m; add_child(mi)
	var k := DirectionalLight3D.new()
	k.rotation = Vector3(deg_to_rad(-35), deg_to_rad(20), 0); k.light_energy = 1.0
	add_child(k)
	var we := WorldEnvironment.new(); var en := Environment.new()
	en.background_mode = Environment.BG_COLOR; en.background_color = Color(0.07,0.08,0.11)
	en.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	en.ambient_light_color = Color(0.35,0.38,0.45); en.ambient_light_energy = 0.5
	en.glow_enabled = true; en.glow_intensity = 0.6
	we.environment = en; add_child(we); Grade.apply_to(self)
	var cam := Camera3D.new(); add_child(cam); cam.current = true
	cam.global_position = Vector3(0.0, 1.4, -1.9)
	cam.look_at(Vector3(0.0, 1.4, 1.0), Vector3.UP)
	for _w in 8: await get_tree().process_frame
	var cols := [Color(1.0,0.72,0.35), Color(0.45,0.75,1.0), Color(0.45,1.0,0.55)]
	for i in 3:
		var b: Node3D = IMPACT.new(); add_child(b)
		b.burst(Vector3(-0.7 + i * 0.7, 1.4, 0.8), Vector3(0, 0, -1), cols[i])
	for t in [1, 4, 9]:
		for _w in t: await get_tree().process_frame
		await _grab("imp%d" % t)
	get_tree().quit()
func _grab(t: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://%s.png" % t)
