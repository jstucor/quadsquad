class_name Controls
extends RefCounted
## Every rebindable control in the game, for the keyboard and for the pads.
##
## One id per action ("fire", "jump", ...). The KEYBOARD side is applied to the
## InputMap as the kb_<id> actions the rest of the game already asks for, so
## rebinding a key is just rewriting that action's event list.
##
## The PAD side cannot work that way: an InputMap action is device-wide, and
## four players sharing four pads each need their own answer to "is fire down".
## So pad input stays polled per device — Player calls held() with its own
## input_device and the binding is looked up here. Bindings are stored per
## device index with ALL_PADS as the profile a pad falls back to when it has no
## override, which makes "rebind on every pad" and "rebind player 3's pad only"
## the same mechanism. Everything is saved to user://controls.cfg.
##
## Static, not an autoload, so it needs no project.godot change and is usable
## from GameState._init (which is where the keyboard map gets registered).

const CONFIG_PATH := "user://controls.cfg"
const ALL_PADS := -1          # the profile a pad uses when it has no binding of its own
const AXIS_THRESHOLD := 0.5   # a trigger pulled this far counts as a press
const BIND_AXIS_THRESHOLD := 0.6  # ...and this far to be captured as a new binding

## A pad binding is a button press or an axis pushed one way (the triggers).
enum Kind { BUTTON, AXIS }

# The rebindable list, in the order the settings screen shows it. `pad` is false
# for the four that only the keyboard needs a binding for: a pad steers with the
# left stick, which is not up for rebinding.
const ACTIONS: Array[Dictionary] = [
	{"id": "fire", "name": "FIRE", "pad": true},
	{"id": "ads", "name": "AIM DOWN SIGHTS", "pad": true},
	{"id": "jump", "name": "JUMP / DEPLOY", "pad": true},
	{"id": "sprint", "name": "SPRINT", "pad": true},
	{"id": "crouch", "name": "CROUCH", "pad": true},
	{"id": "switch", "name": "SWAP WEAPON", "pad": true},
	{"id": "gadget", "name": "GADGET 1", "pad": true},
	{"id": "grenade", "name": "GADGET 2", "pad": true},
	{"id": "map", "name": "MAP / STRIKE", "pad": true},
	{"id": "interact", "name": "PICK UP", "pad": true},
	{"id": "forward", "name": "MOVE FORWARD", "pad": false},
	{"id": "back", "name": "MOVE BACK", "pad": false},
	{"id": "left", "name": "MOVE LEFT", "pad": false},
	{"id": "right", "name": "MOVE RIGHT", "pad": false},
]

# A keyboard binding is {"key": physical keycode} or {"mouse": button index}.
const DEFAULT_KEYS := {
	"fire": {"mouse": MOUSE_BUTTON_LEFT},
	"ads": {"mouse": MOUSE_BUTTON_RIGHT},
	"jump": {"key": KEY_SPACE},
	"sprint": {"key": KEY_SHIFT},
	"crouch": {"key": KEY_CTRL},
	"switch": {"key": KEY_Q},
	"gadget": {"key": KEY_F},
	"grenade": {"key": KEY_G},
	"map": {"key": KEY_M},
	"interact": {"key": KEY_E},
	"forward": {"key": KEY_W},
	"back": {"key": KEY_S},
	"left": {"key": KEY_A},
	"right": {"key": KEY_D},
}

# Pad defaults. A list per action, because a control can sit on more than one
# input — rebinding replaces the whole list with the one input you pressed.
#
# Fire and aim are the TRIGGERS alone. They used to also carry the shoulder
# above them, which spent both bumpers on a duplicate of a control the player
# already has under a finger; the bumpers are where a shooter expects its two
# throwables, so the two GADGET slots own them. GADGET 1 sits on X (with a d-pad
# button as a second way in) and GADGET 2 on LB — each slot is now its OWN
# rebindable single-button control, not the old LB+RB chord, so the settings
# screen can give slots 1 and 2 independent bindings per pad.
const DEFAULT_PAD := {
	"fire": [{"kind": Kind.AXIS, "index": JOY_AXIS_TRIGGER_RIGHT, "dir": 1}],
	"ads": [{"kind": Kind.AXIS, "index": JOY_AXIS_TRIGGER_LEFT, "dir": 1}],
	"jump": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_A}],
	"sprint": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_LEFT_STICK}],
	"crouch": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_B}],
	"switch": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_Y}],
	"gadget": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_X},
		{"kind": Kind.BUTTON, "index": JOY_BUTTON_DPAD_UP}],
	"grenade": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_LEFT_SHOULDER},
		{"kind": Kind.BUTTON, "index": JOY_BUTTON_DPAD_DOWN}],
	"map": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_BACK}],
	"interact": [{"kind": Kind.BUTTON, "index": JOY_BUTTON_DPAD_LEFT}],
}

# Pads report a normalised layout, so naming the buttons is a fixed table rather
# than anything per-controller.
const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_BACK: "BACK", JOY_BUTTON_START: "START", JOY_BUTTON_GUIDE: "GUIDE",
	JOY_BUTTON_DPAD_UP: "D-UP", JOY_BUTTON_DPAD_DOWN: "D-DOWN",
	JOY_BUTTON_DPAD_LEFT: "D-LEFT", JOY_BUTTON_DPAD_RIGHT: "D-RIGHT",
}
const PAD_AXIS_NAMES := {
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
# Which axes may be bound at all: the triggers. The sticks drive movement and
# look, so capturing them would take a pad's steering away mid-rebind.
const BINDABLE_AXES: Array[int] = [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]

# The pad half of the front-end. Godot ships joypad events on ui_up/down/left/
# right and on NOTHING else, so out of the box a pad can move the menu's focus
# and then cannot press what it landed on — the menus are unusable from a
# controller until these two are added. START is deliberately left off: the
# settings screen keeps it as the way out of a rebind listen, which is the one
# input a pad player cannot otherwise escape.
const UI_PAD := {
	"ui_accept": JOY_BUTTON_A,
	"ui_cancel": JOY_BUTTON_B,
}

const UNBOUND_LABEL := "—"  # em dash: this action has nothing on it
## Returned for an unbound control, so the per-frame lookup never builds one.
const EMPTY_BINDS: Array = []

# Per-player feel settings, edited from the in-game START overlay and stored
# per device the same way bindings are. A look-speed multiplier and an aim-assist
# strength multiplier, both 1.0 by default. The assist multiplier scales the pull
# the aim assist already applies (0 turns it off for that player even while the
# match has assist on); the sensitivity multiplies mouse and stick look speed.
const DEFAULT_SENS := 1.0
const DEFAULT_ASSIST := 1.0
const SENS_MIN := 0.2
const SENS_MAX := 3.0
const ASSIST_MIN := 0.0
const ASSIST_MAX := 2.0

static var _keys := {}    # id -> {"key": kc} / {"mouse": idx} / {} when unbound
static var _pads := {}    # device -> {id -> Array of bindings}
static var _settings := {}   # device -> {"sensitivity": f, "aim_assist": f}
static var _profiles := {}   # name -> a captured device config (see save_profile)
static var _loaded := false


## Load the saved bindings (once) and push the keyboard half into the InputMap.
## Safe to call from anywhere; GameState does it as the game boots.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_reset_tables()
	# Named profiles survive a "reset to defaults" (which only calls _reset_tables),
	# so they are cleared here, at first load, and never by the reset.
	_profiles = {}
	_load()
	apply_keyboard()
	apply_ui_pad()


## Rewrite every kb_<id> action from the current keyboard table. The rest of the
## game only ever asks the InputMap, so this is the whole keyboard rebind.
static func apply_keyboard() -> void:
	for entry in ACTIONS:
		var action: String = kb_action(entry["id"])
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var bind: Dictionary = _keys.get(entry["id"], {})
		if bind.has("key"):
			var ev := InputEventKey.new()
			ev.physical_keycode = bind["key"]
			InputMap.action_add_event(action, ev)
		elif bind.has("mouse"):
			var mb := InputEventMouseButton.new()
			mb.button_index = bind["mouse"]
			InputMap.action_add_event(action, mb)


## Put A and B on the menus' accept/cancel.
##
## These are NOT rebindable and are not part of the ACTIONS list: they are the
## front-end's own controls, not a player's, and every screen that uses them is
## driven by whichever pad reaches it first. Hence device -1 (ALL devices) on
## the events — the default 0 would let only player 1's pad work the menu, and
## the whole point of this screen being pad-driven is that anyone at the couch
## can set the match up.
static func apply_ui_pad() -> void:
	for action in UI_PAD:
		if not InputMap.has_action(action):
			continue
		var ev := InputEventJoypadButton.new()
		ev.button_index = UI_PAD[action]
		ev.device = -1
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


static func kb_action(id: String) -> String:
	return "kb_" + id


# --- what the game asks at runtime -------------------------------------------

## Is this control down for this player? device < 0 is the keyboard/mouse
## player, whose bindings live in the InputMap; anything else is that pad.
static func held(device: int, id: String) -> bool:
	if device < 0:
		return Input.is_action_pressed(kb_action(id))
	return pad_held(device, id)


## The keyboard's own press edge. Pads have no equivalent here on purpose: an
## InputMap action can't be scoped to one device, so each caller tracks its own
## previous state per device (see Player's _*_pressed helpers).
static func kb_pressed(id: String) -> bool:
	return Input.is_action_just_pressed(kb_action(id))


static func pad_held(device: int, id: String) -> bool:
	for bind in bindings_for(device, id):
		match bind["kind"]:
			Kind.BUTTON:
				if Input.is_joy_button_pressed(device, bind["index"]):
					return true
			Kind.AXIS:
				var value := Input.get_joy_axis(device, bind["index"])
				if value * float(bind.get("dir", 1)) > AXIS_THRESHOLD:
					return true
	return false


## What a pad actually uses for an action, in order of preference:
##
##   1. its OWN override, if somebody has rebound this pad specifically
##   2. PLAYER 1's pad, because P1's layout is the house layout
##   3. the shared ALL_PADS profile
##   4. the built-in default
##
## Step 2 is the one worth explaining. Four pads at one couch are four copies of
## the same controller, and somebody who rebinds crouch because the default is
## wrong for them has just as certainly fixed it for players 2, 3 and 4 — asking
## each of them to repeat the same rebind is asking four times for one decision.
## So P1's pad is treated as everyone's starting point. It is still only a
## FALLBACK: a pad that has been given its own binding keeps it, which is what
## the settings screen's per-pad rows are for.
##
## This runs per control per pad player per frame, so it must not allocate:
## `_pads.get(device, {})` would build a throwaway Dictionary on EVERY call
## (GDScript evaluates a default argument eagerly), which is exactly the
## per-frame garbage the Pi 5 budget rules out. Hence the null checks and the
## one shared empty array.
const P1_PAD := 0


static func bindings_for(device: int, id: String) -> Array:
	ensure_loaded()
	var own = _pads.get(device)
	if own != null and own.has(id):
		return own[id]
	if device != P1_PAD:
		var p1 = _pads.get(P1_PAD)
		if p1 != null and p1.has(id):
			return p1[id]
	var shared = _pads.get(ALL_PADS)
	if shared != null and shared.has(id):
		return shared[id]
	return EMPTY_BINDS


## True when this pad has been given its own binding for an action, rather than
## inheriting the shared one. The settings screen marks those.
static func has_override(device: int, id: String) -> bool:
	if device == ALL_PADS:
		return false
	var own = _pads.get(device)
	return own != null and own.has(id)


# --- labels -------------------------------------------------------------------

## What to print for a control on a PLAYER's device, e.g. "SPACE" or "RT / RB".
## Player-facing, so device < 0 means the keyboard player — use pad_label() when
## you mean the shared ALL_PADS profile, which is also negative.
static func label(device: int, id: String) -> String:
	ensure_loaded()
	return key_label(id) if device < 0 else pad_label(device, id)


## The second gadget slot's control, for buy-screen prompts. It is now an
## ordinary rebindable binding on both halves — the `grenade` action — so this is
## just the usual player-facing label, kept as a named helper for the callers
## that speak of "slot 2" rather than of the `grenade` id.
static func slot2_label(device: int) -> String:
	return label(device, "grenade")


static func pad_label(device: int, id: String) -> String:
	var parts := PackedStringArray()
	for bind in bindings_for(device, id):
		parts.append(bind_label(bind))
	return UNBOUND_LABEL if parts.is_empty() else " / ".join(parts)


static func key_label(id: String) -> String:
	var bind: Dictionary = _keys.get(id, {})
	if bind.has("key"):
		# Keys are stored physical (so WASD stays WASD on an AZERTY board) and
		# printed through the event itself, which names them for the layout in
		# use — and, unlike asking DisplayServer directly, does something sane
		# when there's no display server at all (headless runs).
		var ev := InputEventKey.new()
		ev.physical_keycode = bind["key"]
		return ev.as_text_physical_keycode().to_upper()
	if bind.has("mouse"):
		match int(bind["mouse"]):
			MOUSE_BUTTON_LEFT: return "MOUSE L"
			MOUSE_BUTTON_RIGHT: return "MOUSE R"
			MOUSE_BUTTON_MIDDLE: return "MOUSE M"
			_: return "MOUSE %d" % bind["mouse"]
	return UNBOUND_LABEL


static func bind_label(bind: Dictionary) -> String:
	if bind["kind"] == Kind.BUTTON:
		return PAD_BUTTON_NAMES.get(bind["index"], "BTN %d" % bind["index"])
	var name: String = PAD_AXIS_NAMES.get(bind["index"], "AXIS %d" % bind["index"])
	return name if bind.get("dir", 1) > 0 else name + "-"


## Device names for the settings screen's profile picker.
static func device_label(device: int) -> String:
	if device < 0:
		return "ALL PADS"
	return "PAD %d" % (device + 1)


# --- rebinding ----------------------------------------------------------------

## Bind a keyboard/mouse input, taking it off whatever else was using it (two
## actions on one key means both fire, which is never what was meant). Returns
## false for an input we refuse to bind.
static func bind_key(id: String, event: InputEvent) -> bool:
	ensure_loaded()
	var bind := {}
	if event is InputEventKey:
		var kc: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if kc == 0 or kc == KEY_ESCAPE:
			return false  # escape is the way out of the listen, never a binding
		bind = {"key": kc}
	elif event is InputEventMouseButton:
		bind = {"mouse": event.button_index}
	else:
		return false
	# Dictionary == compares by content in Godot 4, so this genuinely matches a
	# binding loaded from the config file, not just the same object.
	for other in _keys:
		if other != id and _keys[other] == bind:
			_keys[other] = {}  # it moved; the old owner is now unbound
	_keys[id] = bind
	apply_keyboard()
	save()
	return true


## Bind a pad input. `device` is a pad index, or ALL_PADS to change the profile
## every pad without an override of its own follows.
static func bind_pad(device: int, id: String, event: InputEvent) -> bool:
	ensure_loaded()
	var bind := {}
	if event is InputEventJoypadButton:
		if not event.pressed:
			return false
		bind = {"kind": Kind.BUTTON, "index": int(event.button_index)}
	elif event is InputEventJoypadMotion:
		if not BINDABLE_AXES.has(int(event.axis)) or absf(event.axis_value) < BIND_AXIS_THRESHOLD:
			return false
		bind = {"kind": Kind.AXIS, "index": int(event.axis), "dir": signi(event.axis_value)}
	else:
		return false
	var profile: Dictionary = _pads.get_or_add(device, {})
	for other in ACTIONS:
		var other_id: String = other["id"]
		if other_id == id or not other["pad"]:
			continue
		# Clear against what this pad EFFECTIVELY uses, inherited rows included:
		# rebinding pad 1's fire onto LB has to take aim off LB for pad 1, or
		# that pad quietly does both and there's nothing on screen to say why.
		# Only the clashing entry goes — aim bound to "LT or LB" keeps its LT —
		# and the survivors are written back as this pad's own override.
		var others: Array = bindings_for(device, other_id)
		if _has_bind(others, bind):
			profile[other_id] = others.filter(
				func(b: Dictionary) -> bool: return not _same_bind(b, bind))
	profile[id] = [bind]
	save()
	return true


## Hand a pad back to the shared profile for one action.
static func clear_override(device: int, id: String) -> void:
	ensure_loaded()
	if device == ALL_PADS:
		return
	var profile: Dictionary = _pads.get(device, {})
	if profile.erase(id):
		save()


static func reset_defaults() -> void:
	ensure_loaded()  # or a later load would put the saved file back over the top
	_reset_tables()
	apply_keyboard()
	save()


static func _has_bind(list: Array, bind: Dictionary) -> bool:
	for b in list:
		if _same_bind(b, bind):
			return true
	return false


static func _same_bind(a: Dictionary, b: Dictionary) -> bool:
	return a["kind"] == b["kind"] and a["index"] == b["index"] \
		and a.get("dir", 1) == b.get("dir", 1)


static func _reset_tables() -> void:
	_keys = DEFAULT_KEYS.duplicate(true)
	_pads = {ALL_PADS: DEFAULT_PAD.duplicate(true)}
	_settings = {}


# --- per-player feel settings -------------------------------------------------
#
# Kept per device, keyed exactly like a pad's bindings (device index, or -1 for
# the keyboard player). No ALL_PADS fallback: these are personal, so an unset
# device just answers the default rather than inheriting somebody else's.

static func sensitivity(device: int) -> float:
	ensure_loaded()
	var s = _settings.get(device)
	return s["sensitivity"] if s != null and s.has("sensitivity") else DEFAULT_SENS


static func aim_assist_strength(device: int) -> float:
	ensure_loaded()
	var s = _settings.get(device)
	return s["aim_assist"] if s != null and s.has("aim_assist") else DEFAULT_ASSIST


static func set_sensitivity(device: int, value: float) -> void:
	ensure_loaded()
	_settings.get_or_add(device, {})["sensitivity"] = clampf(value, SENS_MIN, SENS_MAX)
	save()


static func set_aim_assist(device: int, value: float) -> void:
	ensure_loaded()
	_settings.get_or_add(device, {})["aim_assist"] = clampf(value, ASSIST_MIN, ASSIST_MAX)
	save()


# --- game options -------------------------------------------------------------
#
# Settings that belong to the MACHINE rather than to a device or a match: they
# are the same for all four players at the couch and they outlive a match, so
# they cannot live on GameState (reset every map) or in _settings (per device).
#
# They are here because Controls already owns user://controls.cfg and the
# CONTROLS screen is the only options screen the game has. That is a stopgap:
# these are not bindings, and the moment there are more than a couple of them
# they want a SETTINGS screen of their own off the menu, with this section moved
# behind it unchanged.
static var _options := {}

## Death style. The corpse normally wears the dead unit's own body, collapsed;
## turning this on brings back the original stiff arms-out flop, which is the
## look the game shipped with and is funnier.
const OPT_CLASSIC_DEATH := "classic_death"


static func option(name: String, fallback := false) -> bool:
	ensure_loaded()
	return bool(_options.get(name, fallback))


static func set_option(name: String, value: bool) -> void:
	ensure_loaded()
	_options[name] = value
	save()


static func classic_death() -> bool:
	return option(OPT_CLASSIC_DEATH)


# --- named profiles -----------------------------------------------------------
#
# A profile is a snapshot of ONE device's whole config: its feel settings plus
# its bindings. A player builds theirs once and loads it onto whatever device
# they are on at the start of a match. Bindings are captured for the device's
# KIND (keyboard keys, or pad bindings) and only re-applied to a matching kind;
# the feel settings apply either way.

static func profile_names() -> Array:
	ensure_loaded()
	var names: Array = _profiles.keys()
	names.sort()
	return names


static func has_profile(name: String) -> bool:
	ensure_loaded()
	return _profiles.has(name)


## Capture `device`'s current config under `name`, overwriting any profile of
## that name. Empty names are refused so the save button can't make a nameless
## row that nothing can address.
static func save_profile(name: String, device: int) -> bool:
	ensure_loaded()
	name = name.strip_edges()
	if name.is_empty():
		return false
	var p := {
		"sensitivity": sensitivity(device),
		"aim_assist": aim_assist_strength(device),
	}
	if device < 0:
		p["keys"] = _keys.duplicate(true)
	else:
		var binds := {}
		for entry in ACTIONS:
			if entry["pad"]:
				binds[entry["id"]] = bindings_for(device, entry["id"]).duplicate(true)
		p["pads"] = binds
	_profiles[name] = p
	save()
	return true


## Apply a saved profile onto `device`. The feel settings always take; bindings
## take only when the profile's kind matches the target (pad→pad, keyboard→keys).
static func load_profile(name: String, device: int) -> bool:
	ensure_loaded()
	var p = _profiles.get(name)
	if p == null:
		return false
	_settings.get_or_add(device, {})["sensitivity"] = \
		clampf(p.get("sensitivity", DEFAULT_SENS), SENS_MIN, SENS_MAX)
	_settings[device]["aim_assist"] = \
		clampf(p.get("aim_assist", DEFAULT_ASSIST), ASSIST_MIN, ASSIST_MAX)
	if device < 0 and p.has("keys"):
		_keys = (p["keys"] as Dictionary).duplicate(true)
		apply_keyboard()
	elif device >= 0 and p.has("pads"):
		var profile: Dictionary = _pads.get_or_add(device, {})
		for id in p["pads"]:
			profile[id] = (p["pads"][id] as Array).duplicate(true)
	save()
	return true


static func delete_profile(name: String) -> void:
	ensure_loaded()
	if _profiles.erase(name):
		save()


# --- persistence --------------------------------------------------------------

static func save() -> void:
	var cfg := ConfigFile.new()
	for id in _keys:
		cfg.set_value("keyboard", id, _keys[id])
	for device in _pads:
		for id in _pads[device]:
			cfg.set_value("pad_%d" % device, id, _pads[device][id])
	for device in _settings:
		cfg.set_value("settings", str(device), _settings[device])
	if not _profiles.is_empty():
		cfg.set_value("profiles", "data", _profiles)
	for name in _options:
		cfg.set_value("options", name, _options[name])
	cfg.save(CONFIG_PATH)


static func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return  # never configured, or the file went away: defaults stand
	for section in cfg.get_sections():
		if section == "keyboard":
			for id in cfg.get_section_keys(section):
				_keys[id] = cfg.get_value(section, id)
			continue
		if section == "settings":
			for key in cfg.get_section_keys(section):
				_settings[int(key)] = cfg.get_value(section, key)
			continue
		if section == "profiles":
			_profiles = cfg.get_value(section, "data", {})
			continue
		if section == "options":
			for name in cfg.get_section_keys(section):
				_options[name] = cfg.get_value(section, name)
			continue
		if not section.begins_with("pad_"):
			continue
		var device := int(section.trim_prefix("pad_"))
		var profile: Dictionary = _pads.get_or_add(device, {})
		for id in cfg.get_section_keys(section):
			profile[id] = cfg.get_value(section, id)
