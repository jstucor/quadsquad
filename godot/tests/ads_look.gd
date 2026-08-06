extends Node3D
## WINDOWED. WHAT YOU CAN ACTUALLY SEE DOWN THE SIGHTS.
##
##   godot --path godot --display-driver x11 --resolution 1280x720 tests/ads_look.tscn
##
## The ADS slide is SOLVED — `Viewmodel._build` cancels the Weapon anchor's
## offset and the fitted sight's own offset so the sight lands on the camera
## axis — and that solve is correct and still leaves guns you cannot see past,
## because it only ever asked where the SIGHT is and never what is standing in
## front of it. A carry handle, a front sight block, a heat shroud or a fat
## barrel sits on the same line the sight was just aligned to.
##
## This cannot be measured off geometry alone (whether a shape "blocks" the view
## depends on how far down the barrel it is and how wide it is at that range), so
## it is a LOOK test: every primary, aimed, at the centre of the screen, with a
## body at fighting range to be aimed AT. The question each shot answers is
## whether you could take that shot.

const MAIN := preload("res://scenes/main.tscn")

## The guns worth photographing: one from every silhouette family, plus the four
## new LMGs, which are the ones most likely to have a shroud in the way.
const SHOWN := [
	Weapon.Class.SOLDIER, Weapon.Class.CARBINE, Weapon.Class.BURST,
	Weapon.Class.HEAVY, Weapon.Class.HMG, Weapon.Class.SEMI,
	Weapon.Class.RT9, Weapon.Class.DK19D, Weapon.Class.SAW7,
	Weapon.Class.GAUSS_CANNON,
	Weapon.Class.AR7, Weapon.Class.BR3, Weapon.Class.SHELLGUN,
	Weapon.Class.GAUSS_RIFLE, Weapon.Class.SLUGTHROWER,
]


func _ready() -> void:
	GameState.human_players = 1
	GameState.debug_kbm = true
	GameState.mode = GameState.Mode.DEATHMATCH
	GameState.map_index = 0
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _frames(24)
	# WAIT FOR THE MATCH TO BE CALLED ON. `match_live` gates aiming along with
	# everything else (house rule 14), so a shot taken during "GET READY" is a
	# photograph of the HIP pose no matter how long the aim button is held —
	# which is exactly what the first version of this test produced.
	# CALL THE MATCH ON BY HAND. `match_live` is false until every human has
	# DEPLOYED off the buy screen (house rule 14), and this test drives the body
	# through `_respawn` directly rather than pressing through that screen — so
	# the countdown would sit on "GET READY" forever and every shot would be a
	# photograph of the HIP pose, which is exactly what the first version
	# produced. Aiming is gated on this flag, so it has to be set before the
	# aim button means anything.
	GameState.match_live = true
	await _frames(10)
	var p: Player = _find(main)
	if p == null:
		push_error("no player")
		get_tree().quit(1)
		return
	for cls in SHOWN:
		var l := Loadout.new()
		l.adopt_kit(Loadout.Kit.LEGION)
		l.weapon = Loadout.weapon_index(cls)
		# IRON SIGHTS ON PURPOSE. A red dot floats its reticle above the receiver
		# and hides the fault; irons are the case where you are looking THROUGH
		# the gun, and every optic still has to clear the same furniture.
		l.sight = Loadout.Sight.NONE
		l.primary_override = cls
		p.pending = l
		p._respawn()
		await _frames(8)
		Input.action_press("kb_ads")
		# Long enough for the ADS slide to finish (Viewmodel.AIM_TIME) plus the
		# camera FOV ease behind it.
		await _frames(40)
		await _grab("ads_%s" % str(Weapon.PROFILES[cls]["name"]).to_lower().replace(" ", "_"))
		Input.action_release("kb_ads")
		await _frames(4)
	get_tree().quit()


func _find(n: Node) -> Player:
	if n is Player:
		return n
	for c in n.get_children():
		var found := _find(c)
		if found != null:
			return found
	return null


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _grab(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "user://shots/%s.png" % name
	DirAccess.make_dir_recursive_absolute("user://shots")
	img.save_png(path)
	print("  %s -> %s" % [name, ProjectSettings.globalize_path(path)])
