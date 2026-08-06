extends SceneTree
## ACCOUNTS: the identity, the controller configuration and the record.
##
##   godot --headless --path godot --script tests/accounts.gd
##
## Run as a `--script` test, like `kit_rules`, because none of this needs an
## autoload — and proving that is worth something on its own: an account is read
## by the sign-in screen before a match exists.
##
## WARNING, AND IT IS THE SAME ONE `controls_inherit` CARRIES: every mutating
## call here SAVES, and the control half of an account is a real profile in the
## player's real `user://controls.cfg`. So both files are snapshotted first and
## put back at the end. An earlier version of that other test did not, and wiped
## a rebind off a real machine.
##
## WHAT IS ACTUALLY BEING PROTECTED, in order of how silently it fails:
##   1. SIGNING IN APPLIES THE CONFIGURATION. If it does not, everything still
##      works — the player just has somebody else's sensitivity, which reads as
##      the game feeling wrong rather than as a bug.
##   2. A CAREER ADDS UP. `record_match` is arithmetic on a dictionary; a key
##      missed there is a stat that silently stays at zero forever.
##   3. K/D WITH NO DEATHS. The one arithmetic case with a wrong answer that
##      looks plausible (0.00, or a division by zero taking the screen out).

const ACCOUNTS_CFG := "user://accounts.cfg"
const CONTROLS_CFG := "user://controls.cfg"

var _fails: Array[String] = []


func _init() -> void:
	var accounts_backup := _snapshot(ACCOUNTS_CFG)
	var controls_backup := _snapshot(CONTROLS_CFG)

	_names()
	_record()
	_controls()
	_persistence()

	_restore(ACCOUNTS_CFG, accounts_backup)
	_restore(CONTROLS_CFG, controls_backup)
	# The in-memory table is dropped as well as the file put back, so a later run
	# in the same process cannot read the accounts this one invented.
	Accounts._forget()
	print("\n==== %s ====" % ("ACCOUNTS HOLD" if _fails.is_empty()
		else "%d FAILURE(S):\n  %s" % [_fails.size(), "\n  ".join(_fails)]))
	quit(0 if _fails.is_empty() else 1)


## A name is typed on a PAD, one letter at a time, by somebody in a hurry. What
## comes back has to be storable, drawable and addressable — so it is folded
## rather than validated, and the ONE refusal is a name that is nothing at all.
func _names() -> void:
	print("== names ==")
	_wipe()
	_ok(Accounts.sanitise("  jacob  ") == "JACOB", "a name is trimmed and upper-cased")
	_ok(Accounts.sanitise("!!!") == "", "a name made of nothing storable is refused")
	_ok(Accounts.sanitise("ABCDEFGHIJKLMNOP").length() == Accounts.MAX_NAME,
		"a long name is cut to what fits a seat card")
	_ok(Accounts.sanitise("a  b") == "A B", "the spaces a carousel leaves behind collapse")

	_ok(Accounts.create("") == "", "a nameless account is never made")
	_ok(Accounts.create("jacob") == "JACOB", "created under the name it is stored as")
	_ok(Accounts.exists("JACOB"), "...and it is there afterwards")
	# CREATING A NAME THAT IS TAKEN IS SOMEBODY SIGNING IN, NOT SOMEBODY WIPING A
	# RECORD. Two brothers who both type SAM must not cost the first one his
	# career, and there is nothing on that screen that would say it had happened.
	Accounts.record_match("JACOB", {"kills": 5, "deaths": 1}, true)
	Accounts.create("JACOB")
	_ok(int(Accounts.stats("JACOB")["kills"]) == 5,
		"re-creating an existing name does NOT reset its record")


func _record() -> void:
	print("\n== the record ==")
	_wipe()
	Accounts.create("ADA")
	var fresh := Accounts.stats("ADA")
	_ok(int(fresh["matches"]) == 0 and int(fresh["kills"]) == 0, "a new account is empty")
	_ok(Accounts.summary("ADA") == "No matches played yet",
		"...and says so rather than printing a K/D of nothing")

	# A WON MATCH, in exactly the shape `GameState.player_stats` keeps.
	Accounts.record_match("ADA",
		{"kills": 12, "deaths": 4, "headshots": 3, "best_streak": 6}, true)
	_ok(Accounts.kd("ADA") == 3.0, "12 kills over 4 deaths is 3.00")
	Accounts.record_match("ADA",
		{"kills": 4, "deaths": 8, "headshots": 1, "best_streak": 2}, false)
	var row := Accounts.stats("ADA")
	print("  after two matches: %s" % row)
	_ok(int(row["kills"]) == 16 and int(row["deaths"]) == 12, "kills and deaths accumulate")
	_ok(int(row["headshots"]) == 4, "so do headshots")
	_ok(int(row["best_streak"]) == 6,
		"the best streak is the BEST of them and not the latest")
	_ok(int(row["matches"]) == 2 and int(row["wins"]) == 1, "matches and wins are counted")
	_ok(absf(Accounts.kd("ADA") - 16.0 / 12.0) < 0.0001, "and the ratio follows")

	# THE CASE WITH A PLAUSIBLE WRONG ANSWER.
	_wipe()
	Accounts.create("LUCKY")
	Accounts.record_match("LUCKY", {"kills": 3, "deaths": 0}, true)
	_ok(Accounts.kd("LUCKY") == 3.0,
		"three kills and no deaths is a K/D of 3, not zero and not a crash")

	# An account that does not exist must not be created by recording into it —
	# a career written for a player who never signed in is a row nobody owns.
	Accounts.record_match("NOBODY", {"kills": 9, "deaths": 0}, true)
	_ok(not Accounts.exists("NOBODY"), "recording into an unknown name creates nothing")


## THE CONTROL HALF. It is delegated to `Controls`' named profiles, so what is
## being asserted is the delegation: that signing in APPLIES what was stored, and
## that capturing stores what has since changed.
func _controls() -> void:
	print("\n== the controller configuration ==")
	_wipe()
	Controls.reset_defaults()
	Accounts.create("PILOT")

	# A brand-new account has no profile, so the first sign-in CAPTURES the
	# device rather than overwriting it with nothing.
	Controls.set_sensitivity(0, 1.7)
	Accounts.sign_in("PILOT", 0)
	_ok(Controls.has_profile("PILOT"),
		"the first sign-in gives a fresh account a profile to keep")
	_ok(absf(Controls.sensitivity(0) - 1.7) < 0.001,
		"...and does not wipe the settings the device already had")

	# Somebody else plays on that pad and turns everything down.
	Controls.set_sensitivity(0, 0.5)
	Controls.set_aim_assist(0, 0.0)
	Accounts.sign_in("PILOT", 0)
	print("  sensitivity after signing back in: %.2f" % Controls.sensitivity(0))
	_ok(absf(Controls.sensitivity(0) - 1.7) < 0.001,
		"signing in puts this player's own feel settings back")

	# ...and onto a DIFFERENT device, which is the case the whole thing is for:
	# their pad died and they picked up somebody else's.
	Accounts.sign_in("PILOT", 2)
	_ok(absf(Controls.sensitivity(2) - 1.7) < 0.001,
		"an account carries onto whatever device its owner picks up")

	# CAPTURE is the other direction: what they changed in the in-match overlay
	# tonight is theirs the next time they sit down.
	Controls.set_sensitivity(2, 2.4)
	Accounts.capture("PILOT", 2)
	Controls.set_sensitivity(1, 1.0)
	Accounts.sign_in("PILOT", 1)
	_ok(absf(Controls.sensitivity(1) - 2.4) < 0.001,
		"a captured change follows the account to the next device")

	# Deleting an account takes its profile with it — otherwise the config it
	# left behind is one nothing can ever reach or overwrite again.
	Accounts.remove("PILOT")
	_ok(not Accounts.exists("PILOT"), "a deleted account is gone")
	_ok(not Controls.has_profile("PILOT"), "...and so is its controller profile")


func _persistence() -> void:
	print("\n== across a session ==")
	_wipe()
	Accounts.create("SAVED")
	Accounts.record_match("SAVED", {"kills": 7, "deaths": 2, "headshots": 2}, true)
	Accounts.save()
	# Forget everything in memory and read the file back, which is what the next
	# launch of the game does.
	Accounts._forget()
	var row := Accounts.stats("SAVED")
	print("  read back: %s" % row)
	_ok(Accounts.exists("SAVED"), "an account survives a restart")
	_ok(int(row["kills"]) == 7 and int(row["matches"]) == 1,
		"...and so does its record")


# --- harness ------------------------------------------------------------------

## Start from nothing, without touching the file until something is saved. The
## real config is restored at the end whatever happened in between.
func _wipe() -> void:
	Accounts._forget()
	for name in Accounts.names():
		Accounts.remove(name)
	Accounts.ensure_loaded()


func _snapshot(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _restore(path: String, contents: String) -> void:
	if contents == "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(contents)
		f.close()


func _ok(cond: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails.append(what)
