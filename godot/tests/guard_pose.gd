extends Node3D

## Checks the third-person guard stance the same way the carry pose was checked:
## the hands must actually be ON the weapon, and the feet must not sink into the
## floor. Both are solved rather than dialled in, so this is what proves it.
##
##   godot --headless --path godot tests/guard_pose.tscn

const CLIPS := ["idle", "walk", "run", "crouch_idle", "crouch_walk",
	"guard_idle", "guard_walk"]


func _ready() -> void:
	var c := CharacterModel.new()
	add_child(c)
	await get_tree().process_frame

	var anim: AnimationPlayer = c.anim_player
	var hands := {
		"R": c.get_node(CharacterModel.PATHS["eR"]),
		"L": c.get_node(CharacterModel.PATHS["eL"]),
	}
	var gun: Node3D = c.get_node(CharacterModel.PATHS["gun"])
	var reach := CharacterModel.LOWER_ARM + CharacterModel.HAND_REACH
	# Probe the hand and the ankle along the rig's OWN bone directions, which is
	# where _build_body puts the meshes. Measuring straight down -Y instead asks
	# the pose the same question the solver asked itself, so it agreed with the
	# solver at 0.0 mm while the actual hands hung 8-14 cm off the weapon.
	var at: Dictionary = c._joint_offsets()
	var feet := {
		"L": c.get_node(CharacterModel.PATHS["kL"]),
		"R": c.get_node(CharacterModel.PATHS["kR"]),
	}

	var worst_grip := 0.0
	var worst_foot := 0.0
	for name in CLIPS:
		var a: Animation = anim.get_animation(name)
		var clip_grip := 0.0
		var clip_foot := 0.0
		for i in 17:
			var t := a.length * float(i) / 16.0
			anim.play(name)
			anim.seek(t, true)
			await get_tree().process_frame
			# Where each hand lands: the wrist is HAND_REACH down the forearm.
			for side in ["R", "L"]:
				var el: Node3D = hands[side]
				var hand: Vector3 = el.global_transform * (
					at["e" + side].normalized() * reach)
				var grip: Vector3 = gun.global_transform * (
					CharacterModel.GRIP_REAR if side == "R" else CharacterModel.GRIP_FORE)
				clip_grip = maxf(clip_grip, hand.distance_to(grip))
			# Ankle = LOWER_LEG down from the knee. Below y=0 is through the floor.
			for side in ["L", "R"]:
				var kn: Node3D = feet[side]
				var ankle: Vector3 = kn.global_transform * (
					at["k" + side].normalized() * CharacterModel.LOWER_LEG)
				clip_foot = minf(clip_foot, ankle.y)
		print("%-13s hand-to-grip max %6.2f mm   lowest ankle %7.2f mm" % [
			name, clip_grip * 1000.0, clip_foot * 1000.0])
		worst_grip = maxf(worst_grip, clip_grip)
		worst_foot = minf(worst_foot, clip_foot)

	print("\nWORST hand-to-grip %.2f mm, WORST ankle %.2f mm" % [
		worst_grip * 1000.0, worst_foot * 1000.0])
	get_tree().quit()
