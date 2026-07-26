extends Node3D
## The in-game START overlay and the per-player settings/preset layer behind it.
##
## Driven by calling the overlay's own methods rather than by injecting pad input
## (which a headless run cannot poll), so this proves the state machine and the
## Controls storage, not the button reading. The overlay is deliberately NOT
## added to the tree, so its _process (which would auto-close on a dead/held
## player) stays out of the way while we step it by hand.
##
##   godot --headless --path godot tests/settings_overlay.tscn
##
## Every mutating Controls call SAVES, so this snapshots user://controls.cfg first
## and restores it at the end — the same guard controls_inherit.gd keeps.

const PLAYER := preload("res://scenes/actors/player.tscn")
const OVERLAY := preload("res://scripts/settings_overlay.gd")
const CONFIG := "user://controls.cfg"

var _fails: Array[String] = []
var _snapshot: PackedByteArray
var _had_snapshot := false


func _ready() -> void:
	_save_snapshot()
	GameState.match_live = true
	_build_floor()
	var p := await _spawn()

	var ov: Node = OVERLAY.new()
	ov.setup(p)
	_expect(not ov.visible, "the overlay starts hidden")
	_expect(not p.settings_open, "and the player is not held")

	ov._show()
	_expect(ov.visible and p.settings_open, "_show opens it and holds the player still")
	_expect(not p.weapon.aiming, "and drops ADS")

	# --- sensitivity slider -------------------------------------------------
	print("\n== sensitivity ==")
	Controls.set_sensitivity(0, 1.0)
	p.refresh_settings()
	ov._row = _kind_row(ov, OVERLAY.Kind.SENS)
	ov._adjust(1)
	print("  after one right: %.2fx (player %.2f)" % [Controls.sensitivity(0), p._sens_mult])
	_expect(absf(Controls.sensitivity(0) - 1.1) < 0.001, "right raises look sensitivity")
	_expect(absf(p._sens_mult - Controls.sensitivity(0)) < 0.001,
		"and the player picked the new value up live")
	for _i in 60:
		ov._adjust(1)
	_expect(Controls.sensitivity(0) <= Controls.SENS_MAX + 0.001
		and Controls.sensitivity(0) >= Controls.SENS_MAX - 0.001,
		"holding right clamps at SENS_MAX")

	# --- aim assist slider --------------------------------------------------
	print("\n== aim assist ==")
	Controls.set_aim_assist(0, 1.0)
	p.refresh_settings()
	ov._row = _kind_row(ov, OVERLAY.Kind.ASSIST)
	ov._adjust(-1)
	print("  after one left: %.0f%% (player %.2f)" % [
		Controls.aim_assist_strength(0) * 100.0, p._assist_mult])
	_expect(absf(Controls.aim_assist_strength(0) - 0.9) < 0.001, "left lowers aim assist")
	for _i in 60:
		ov._adjust(-1)
	_expect(absf(Controls.aim_assist_strength(0) - Controls.ASSIST_MIN) < 0.001,
		"holding left clamps at 0 (assist off for this player)")

	# --- saving a preset under a custom name --------------------------------
	print("\n== save preset ==")
	Controls.set_sensitivity(0, 1.7)
	Controls.set_aim_assist(0, 0.5)
	Controls.bind_pad(0, "jump", _pad_btn(JOY_BUTTON_Y))
	ov._row = _kind_row(ov, OVERLAY.Kind.SAVE)
	ov._activate()
	_expect(ov._mode == OVERLAY.Mode.NAME, "SAVE AS NEW opens the name entry")
	_type_cell(ov, "A")
	_type_cell(ov, "C")
	_type_cell(ov, "E")
	print("  typed name: '%s'" % ov._name_buf)
	_expect(ov._name_buf == "ACE", "the on-screen cells build the custom name")
	ov._name_cell = OVERLAY.NAME_CHARS.length() + 1   # the OK cell
	ov._name_commit_cell()
	_expect(ov._mode == OVERLAY.Mode.NAV, "OK confirms and returns to the list")
	_expect(Controls.has_profile("ACE"), "the preset is stored under its custom name")
	_expect(not Controls.save_profile("   ", 0), "a blank name is refused")

	# --- loading it back onto a device --------------------------------------
	print("\n== load preset ==")
	Controls.set_sensitivity(0, 0.3)
	Controls.set_aim_assist(0, 2.0)
	Controls.bind_pad(0, "jump", _pad_btn(JOY_BUTTON_X))   # move the binding away
	ov._profile_idx = Controls.profile_names().find("ACE")
	ov._row = _kind_row(ov, OVERLAY.Kind.LOAD)
	ov._activate()
	print("  restored: %.2fx / %.0f%% / jump %s" % [
		Controls.sensitivity(0), Controls.aim_assist_strength(0) * 100.0,
		Controls.pad_label(0, "jump")])
	_expect(absf(Controls.sensitivity(0) - 1.7) < 0.001, "load restores the saved sensitivity")
	_expect(absf(Controls.aim_assist_strength(0) - 0.5) < 0.001, "...and the saved aim assist")
	_expect(Controls.pad_label(0, "jump") == "Y", "...and the saved button binding")
	_expect(absf(p._sens_mult - 1.7) < 0.001, "and the player refreshed to the loaded feel")

	# --- deleting it --------------------------------------------------------
	print("\n== delete preset ==")
	ov._profile_idx = Controls.profile_names().find("ACE")
	ov._row = _kind_row(ov, OVERLAY.Kind.DELETE)
	ov._activate()
	_expect(not Controls.has_profile("ACE"), "delete removes the preset")

	# --- rebind listen state ------------------------------------------------
	print("\n== rebind mode ==")
	ov._mode = OVERLAY.Mode.LISTEN
	ov._listen_id = "fire"
	ov._render()   # must not crash while a row shows PRESS AN INPUT
	ov._end_listen()
	_expect(ov._mode == OVERLAY.Mode.NAV and ov._listen_id == "",
		"ending a listen returns to NAV cleanly")

	# --- closing ------------------------------------------------------------
	ov._close()
	_expect(not ov.visible and not p.settings_open, "_close hides it and frees the player")

	ov.free()
	_restore_snapshot()
	print("\n==== %s ====" % ("SETTINGS OVERLAY WORKS" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	get_tree().quit(0 if _fails.is_empty() else 1)


func _kind_row(ov: Node, kind: int) -> int:
	for i in ov._rows.size():
		if ov._rows[i]["kind"] == kind:
			return i
	_fails.append("no row of kind %d" % kind)
	return 0


func _type_cell(ov: Node, ch: String) -> void:
	ov._name_cell = OVERLAY.NAME_CHARS.find(ch)
	ov._name_commit_cell()


func _pad_btn(idx: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = idx
	e.pressed = true
	return e


func _build_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 2.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	body.collision_layer = 1
	add_child(body)


func _spawn() -> Player:
	var p: Player = PLAYER.instantiate()
	p.input_device = 0   # a pad player, so the pad rows and pad bindings are exercised
	add_child(p)
	await get_tree().physics_frame
	return p


func _save_snapshot() -> void:
	if not FileAccess.file_exists(CONFIG):
		return
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f:
		_snapshot = f.get_buffer(f.get_length())
		_had_snapshot = true


func _restore_snapshot() -> void:
	if _had_snapshot:
		var f := FileAccess.open(CONFIG, FileAccess.WRITE)
		if f:
			f.store_buffer(_snapshot)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))


func _expect(ok: bool, what: String) -> void:
	print("  [%s] %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails.append(what)
