class_name Accounts
extends RefCounted
## WHO IS SITTING AT THE COUCH — a named account per player, carrying their
## controller configuration and their record across every match they ever play.
##
## WHY THIS EXISTS. Everything the game knew about a player was a VIEWPORT INDEX.
## Player 2 was "whoever is in the top-right quadrant", their sensitivity belonged
## to pad 1, and their kills belonged to the match and were thrown away with it.
## That is fine for one evening and wrong for a game people come back to: swap
## seats and you inherit somebody else's aim settings, and nothing anywhere can
## answer "am I getting better at this".
##
## AN ACCOUNT IS AN IDENTITY, A CONTROL CONFIG AND A RECORD, and only the middle
## one already existed. `Controls` has stored NAMED PROFILES since the settings
## overlay was written — a device's feel settings plus its bindings, captured and
## re-applied onto whatever device that player is on next time. So the control
## half is DELEGATED to it under the account's own name rather than copied here.
## Two stores of one thing is how a rebind comes to apply on one screen and not
## another, and the profile code is already the tested path for "this pad's
## layout, moved onto that pad".
##
## WHAT THIS FILE OWNS IS THE RECORD. `GameState.player_stats` is per MATCH and
## keyed by viewport, which is right for the end-of-round table four people argue
## over; this is the thing a player carries BETWEEN rounds, so it is cumulative,
## keyed by name, and written to disk at the end of every match.
##
## Static, and its own file (`user://accounts.cfg`) rather than another section
## of `controls.cfg`: a config is a machine's, and an account is a person's.

const CONFIG_PATH := "user://accounts.cfg"

## A name has to fit a seat card at a glance across a room, and it is typed on a
## PAD (see the sign-in screen's letter carousel) — twelve characters is already
## twelve stick pushes.
const MAX_NAME := 12
## What a name may be made of. Deliberately narrow: this is drawn at 26pt on a
## quarter of a 1080p screen and shouted across a sofa, not a login.
const NAME_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -"

## A fresh record. Every field here is one `GameState.player_stats` already
## counts, plus the two only a career has (matches and wins) — so recording a
## match is an addition and never a translation.
const BLANK_STATS := {
	"kills": 0, "deaths": 0, "headshots": 0, "best_streak": 0,
	"matches": 0, "wins": 0,
}

static var _accounts := {}   # name -> {"created": int, "stats": {...}}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load()


## Every account, alphabetical — the order the sign-in screen lists them in.
static func names() -> Array:
	ensure_loaded()
	var out: Array = _accounts.keys()
	out.sort()
	return out


static func exists(name: String) -> bool:
	ensure_loaded()
	return _accounts.has(sanitise(name))


## Fold a typed name into something that can be stored and drawn. Returns "" for
## anything that survives as nothing, which is the ONE refusal this file makes:
## a nameless account is a row on the sign-in screen that cannot be told from the
## next one and cannot be addressed by any of the callers below.
static func sanitise(name: String) -> String:
	var out := ""
	for c in name.strip_edges().to_upper():
		if NAME_CHARS.contains(c):
			out += c
	# Collapse the spaces a carousel makes it easy to leave lying around.
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out.strip_edges().substr(0, MAX_NAME)


## Make an account. Returns the name it was actually stored under (sanitised), or
## "" if there was nothing left of it. An existing name is returned unchanged
## rather than overwritten — creating a name that is already taken is somebody
## signing in, not somebody wiping a record.
static func create(name: String) -> String:
	ensure_loaded()
	var id := sanitise(name)
	if id.is_empty():
		return ""
	if not _accounts.has(id):
		_accounts[id] = {
			"created": int(Time.get_unix_time_from_system()),
			"stats": BLANK_STATS.duplicate(),
		}
		save()
	return id


static func remove(name: String) -> void:
	ensure_loaded()
	var id := sanitise(name)
	if _accounts.erase(id):
		# The control profile is half of the account and is stored by Controls
		# under the same name, so deleting one and leaving the other would leave
		# a config nothing can ever reach or overwrite.
		Controls.delete_profile(id)
		save()


## An account's record. Always answers a full row — a stats block that grew a
## field after somebody's account was written must not make that account crash
## whatever reads it (house rule 6), so missing keys are filled from BLANK_STATS.
static func stats(name: String) -> Dictionary:
	ensure_loaded()
	var row: Dictionary = BLANK_STATS.duplicate()
	var acc = _accounts.get(sanitise(name))
	if acc != null:
		for k in row:
			row[k] = int((acc["stats"] as Dictionary).get(k, 0))
	return row


## KILLS PER DEATH, and the interesting case is the one everybody gets wrong.
## With no deaths yet the ratio is not infinite and it is not zero: it is the
## kills themselves, which is what every shooter has printed for forty years and
## is the only answer that reads sensibly on a card after one lucky life.
static func kd(name: String) -> float:
	var row := stats(name)
	var deaths := int(row["deaths"])
	return float(row["kills"]) if deaths <= 0 else float(row["kills"]) / float(deaths)


## A career line for the seat card: "K/D 1.42   ·   37 matches   ·   12 won".
static func summary(name: String) -> String:
	var row := stats(name)
	if int(row["matches"]) <= 0:
		return "No matches played yet"
	return "K/D %.2f   ·   %d match%s   ·   %d won" % [
		kd(name), int(row["matches"]),
		"" if int(row["matches"]) == 1 else "es", int(row["wins"])]


## Fold one match into an account. `row` is a `GameState.player_stats` entry, so
## the fields line up and nothing has to be translated on the way in.
static func record_match(name: String, row: Dictionary, won: bool) -> void:
	ensure_loaded()
	var id := sanitise(name)
	var acc = _accounts.get(id)
	if acc == null:
		return
	var s: Dictionary = acc["stats"]
	for key in ["kills", "deaths", "headshots"]:
		s[key] = int(s.get(key, 0)) + int(row.get(key, 0))
	s["best_streak"] = maxi(int(s.get("best_streak", 0)), int(row.get("best_streak", 0)))
	s["matches"] = int(s.get("matches", 0)) + 1
	if won:
		s["wins"] = int(s.get("wins", 0)) + 1
	save()


# --- the control half ---------------------------------------------------------
#
# Delegated to `Controls`' named profiles under the account's own name, for the
# reason in the header. Both directions are needed and they run at opposite ends
# of a session: SIGN IN applies what this player last saved onto whatever device
# they picked up tonight, and CAPTURE takes back whatever they changed in the
# in-match settings overlay so it is theirs the next time they sit down.

## Put this account's controller configuration onto a device. A brand-new
## account has no profile yet, so the first sign-in CAPTURES the device's current
## config instead — which means an account always has one from the moment it
## exists, and `capture` at the end of the match is an update rather than a
## special case.
static func sign_in(name: String, device: int) -> bool:
	ensure_loaded()
	var id := sanitise(name)
	if not _accounts.has(id):
		return false
	if Controls.has_profile(id):
		Controls.load_profile(id, device)
	else:
		Controls.save_profile(id, device)
	return true


## Store a device's current configuration back onto the account.
static func capture(name: String, device: int) -> void:
	ensure_loaded()
	var id := sanitise(name)
	if _accounts.has(id):
		Controls.save_profile(id, device)


# --- persistence --------------------------------------------------------------

static func save() -> void:
	var cfg := ConfigFile.new()
	for id in _accounts:
		cfg.set_value(id, "created", _accounts[id]["created"])
		cfg.set_value(id, "stats", _accounts[id]["stats"])
	cfg.save(CONFIG_PATH)


static func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return   # nobody has ever played on this machine
	for section in cfg.get_sections():
		var stored: Dictionary = cfg.get_value(section, "stats", {})
		var row: Dictionary = BLANK_STATS.duplicate()
		for k in row:
			row[k] = int(stored.get(k, 0))
		_accounts[section] = {
			"created": int(cfg.get_value(section, "created", 0)),
			"stats": row,
		}


## Drop the in-memory table without touching the file. For tests, which snapshot
## the real config and need a clean read afterwards.
static func _forget() -> void:
	_accounts = {}
	_loaded = false
