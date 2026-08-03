class_name NetSync
extends Node
## THE PUMP. One node under Main, alive only while a match is networked, that
## does four things and nothing else: ships this machine's own bodies out, builds
## and feeds the proxies for everybody else's, routes damage back to whoever owns
## the body that was hit, and mirrors the host's match state onto the clients.
##
## It exists as a node with a FIXED PATH (`/root/Main/NetSync`) because Godot
## routes an RPC by node path, so both ends must agree on where the receiver
## lives. That is also why no RPC is ever sent to a proxy directly: a body's path
## depends on when it spawned, and every net_id in the game is carried INSIDE a
## payload that lands here instead. One receiver, one path, no ordering problem.
##
## WHAT GOES OVER THE WIRE, AND ON WHICH CHANNEL:
##
##   motion       every tick, UNRELIABLE — a lost position is corrected 50 ms
##                later by the next one, and re-sending a stale position is
##                worse than skipping it.
##   gunfire      inside the motion packet as a COUNTER, not as an event. See
##                the note on `_shots` — this is the single most important
##                decision in the file, because a repeater fires 13x a second.
##   body info    reliable, on change and re-stated slowly. Style, stature and
##                weapon: rare, and a proxy that missed one is wearing the wrong
##                unit until it hears again, so it hears again.
##   damage       reliable, POINT TO POINT. Only the owner of the body that was
##                hit ever receives it.
##   match state  reliable, host to all. Scores, tickets, the countdown, victory.
##
## Rates are deliberately modest: this is a LAN mode, and the thing that actually
## breaks a wireless link is packet COUNT, not bytes. One motion packet per peer
## per tick carrying every body it owns beats one per body every time.

## HOW OFTEN MOTION GOES OUT. Physics runs at 60; sending at 60 would triple the
## packet count for motion nobody can see the difference in, because a proxy eases
## between packets anyway (`NetPlayer.EASE_OVER`). 20 Hz is the rate this kind of
## game has shipped at for twenty years.
const SEND_HZ := 20.0
const SEND_INTERVAL := 1.0 / SEND_HZ

## How often every body re-states what it IS. Cheap self-healing: a client that
## missed a spawn record, or joined a beat late, is wrong for at most this long
## rather than for the whole match. Costs a few hundred bytes every two seconds.
const INFO_INTERVAL := 2.0

## Bot ids start above every human id so the two can never collide, and so the
## owner of an id is decidable from the id alone: below the base it belongs to a
## machine in `Net.players`, at or above it, it is the host's.
const BOT_ID_BASE := 1024

## Record layout, in bytes. Kept as named offsets rather than written inline
## because the pack and the unpack are the one pair of functions in this project
## that MUST agree and are written thirty lines apart.
const REC_SIZE := 22
const MAX_BODIES := 512

## Host only: every human in the session has bought a loadout and pressed deploy.
## Main starts the countdown off this, so nobody fights while somebody else is
## still shopping.
signal all_deployed()

## The one instance, so `NetPlayer.take_damage` can reach the pump without a
## tree walk on every round that lands. Cleared in `_exit_tree` — the match is
## torn down and rebuilt on every map, and a stale pointer here would be
## house rule 11 wearing a different hat.
static var current: NetSync = null

var _own := {}            # id -> body (Player or Bot) simulated on this machine
var _own_ids := []        # stable iteration order; ids sort ascending
var _proxies := {}        # id -> NetPlayer
var _ids := {}            # body -> id, for both owned bodies and proxies
var _shots := {}          # id -> wrapping count of shots fired by an owned body
var _next_bot_id := BOT_ID_BASE

var _send_left := 0.0
var _info_left := 0.0
var _buf := PackedByteArray()


func _ready() -> void:
	current = self
	name = "NetSync"
	_buf.resize(2 + REC_SIZE * MAX_BODIES)
	# Host-authoritative match state. Connected as METHODS of this node, never as
	# lambdas — GameState is an autoload that outlives every map, and a lambda
	# with no target object would go on firing into a freed NetSync after the
	# next rotation (house rule 11).
	if Net.is_host():
		GameState.score_changed.connect(_on_score_changed)
		GameState.match_won.connect(_on_match_won)
		GameState.match_countdown.connect(_on_countdown)
		GameState.match_began.connect(_on_match_began)
		GameState.zone_state.connect(_on_zone_state)


func _exit_tree() -> void:
	if current == self:
		current = null


# --- registration ------------------------------------------------------------

## A body this machine simulates. Main calls it for its own players; the host
## calls it for every bot it spawns.
func own(body: Node3D, id: int) -> void:
	_own[id] = body
	_ids[body] = id
	_shots[id] = 0
	if not _own_ids.has(id):
		_own_ids.append(id)
		_own_ids.sort()
	# Count this body's shots so the proxies elsewhere can draw them. Connected
	# to a METHOD carrying the id rather than to a lambda, same rule as above:
	# the weapon dies with the body, but the binding outliving its target is the
	# exact failure this project has already been bitten by.
	var weapon: Node = body.get("weapon")
	if weapon != null and is_instance_valid(weapon) \
			and not weapon.fired.is_connected(_on_own_fired):
		weapon.fired.connect(_on_own_fired.bind(id))
	if body.has_signal("tree_exited"):
		body.tree_exited.connect(_on_own_gone.bind(id), CONNECT_ONE_SHOT)


func own_bot(bot: Node3D) -> int:
	var id := _next_bot_id
	_next_bot_id += 1
	own(bot, id)
	send_info(id)
	return id


func id_of(body: Node) -> int:
	return int(_ids.get(body, -1))


func body_for(id: int) -> Node3D:
	if _own.has(id):
		return _own[id]
	return _proxies.get(id, null)


func proxies() -> Array:
	return _proxies.values()


func _on_own_fired(_cam_recoil: float, _kick: float, id: int) -> void:
	_shots[id] = (int(_shots.get(id, 0)) + 1) & 0xff


func _on_own_gone(id: int) -> void:
	var body: Node3D = _own.get(id, null)
	_own.erase(id)
	_own_ids.erase(id)
	_ids.erase(body)
	_shots.erase(id)
	# A BODY ALSO "GOES" WHEN THE WHOLE MAP DOES. Every combatant leaves the tree
	# on a scene change, and this fires for each of them — by which point THIS
	# node has been detached too, and an RPC from a node that is not in the tree
	# errors once per body with nothing in the message naming the map change as
	# the cause. Nobody needs to be told a body was removed by a teardown: the
	# other machines are tearing the same match down.
	if id >= BOT_ID_BASE and is_inside_tree() and Net.online():
		_drop_body.rpc(id)


# --- outbound motion ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not Net.online():
		return
	_send_left -= delta
	if _send_left <= 0.0:
		_send_left += SEND_INTERVAL
		_send_states()
	_info_left -= delta
	if _info_left <= 0.0:
		_info_left = INFO_INTERVAL
		for id: int in _own_ids:
			send_info(id)


## Pack every body this machine owns into ONE packet.
##
## Written into a buffer allocated once and re-used (house rule 1). The only
## allocation per send is the slice handed to the RPC, which is 20 a second and
## not 60 a frame — the rule is about what a FRAME costs, and this is deliberately
## not on the frame.
func _send_states() -> void:
	if _own_ids.is_empty():
		return
	var n := 0
	var at := 2
	for id: int in _own_ids:
		if n >= MAX_BODIES:
			break
		var body: Node3D = _own[id]
		if not is_instance_valid(body):
			continue
		_pack(at, id, body)
		at += REC_SIZE
		n += 1
	_buf.encode_u16(0, n)
	_take_states.rpc(_buf.slice(0, at))


func _pack(at: int, id: int, body: Node3D) -> void:
	var pos: Vector3 = body.global_position
	_buf.encode_u16(at, id)
	_buf.encode_float(at + 2, pos.x)
	_buf.encode_float(at + 6, pos.y)
	_buf.encode_float(at + 10, pos.z)
	# Angles as quantised int16 rather than floats: a body's facing is read off a
	# model on a quarter screen, where a hundredth of a degree is invisible and
	# four bytes of it per body per tick is not.
	_buf.encode_s16(at + 14, _quantise_angle(body.rotation.y))
	var head: Node3D = body.get("head")
	var pitch := 0.0
	if head != null and is_instance_valid(head):
		pitch = head.rotation.x
	_buf.encode_s16(at + 16, _quantise_angle(pitch))
	_buf.encode_u8(at + 18, _clip_of(body))
	_buf.encode_u8(at + 19, _flags_of(body))
	_buf.encode_u8(at + 20, int(_health_fraction(body) * 255.0))
	_buf.encode_u8(at + 21, int(_shots.get(id, 0)))


## HOW HURT A BODY IS, AS A FRACTION, asked of anything. Combatants are
## duck-typed and this is a new question being put to them, so a body that cannot
## answer has to come back with something sensible rather than bring the send
## down: `float(null)` raises, and a GDScript error ABORTS the enclosing function
## (house rule 6) — which here is the whole packet, so ONE body missing ONE field
## silently stops every body on the machine from moving.
##
## `Bot` was exactly that body: it carried `health` and derived its ceiling
## inline, so it had no `max_health` to read. It has one now, and this stays as
## the guard for the next combatant somebody adds.
func _health_fraction(body: Node3D) -> float:
	var health: Variant = body.get("health")
	if health == null:
		return 1.0
	var full: Variant = body.get("max_health")
	if full == null or float(full) <= 0.0:
		return 1.0
	return clampf(float(health) / float(full), 0.0, 1.0)


func _quantise_angle(radians: float) -> int:
	return int(round(clampf(wrapf(radians, -PI, PI) / PI, -1.0, 1.0) * 32767.0))


func _unquantise_angle(raw: int) -> float:
	return float(raw) / 32767.0 * PI


## Which clip a body is playing, as an index into `NetPlayer.CLIPS`. Read off the
## AnimationPlayer rather than re-deriving the state machine, so a proxy can
## never disagree with the body it stands for about whether it is crouching —
## which matters, because that pose is what a shot has to hit.
func _clip_of(body: Node3D) -> int:
	var model: Node3D = body.get("model")
	if model == null or not is_instance_valid(model):
		return 0
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if anim == null:
		return 0
	var i := NetPlayer.CLIPS.find(anim.assigned_animation)
	return maxi(i, 0)


func _flags_of(body: Node3D) -> int:
	var flags := 0
	if body.has_method("is_alive") and body.is_alive():
		flags |= NetPlayer.F_ALIVE
	var weapon: Node = body.get("weapon")
	if weapon != null and is_instance_valid(weapon) and bool(weapon.get("aiming")):
		flags |= NetPlayer.F_AIM
	if GameState.is_cloaked(body):
		flags |= NetPlayer.F_CLOAK
	return flags


# --- inbound motion ----------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _take_states(packet: PackedByteArray) -> void:
	if packet.size() < 2:
		return
	var sender := multiplayer.get_remote_sender_id()
	var n := packet.decode_u16(0)
	if packet.size() < 2 + n * REC_SIZE:
		return
	for i in n:
		var at := 2 + i * REC_SIZE
		var id := packet.decode_u16(at)
		# A MACHINE MAY ONLY MOVE ITS OWN BODIES. Checked on every record, not
		# once per packet: without it a client could drive anybody's body, and —
		# far more likely than malice — a stale record from a peer that has just
		# lost a player would silently fight the machine that now owns it.
		if not _sender_owns(sender, id):
			continue
		var proxy: NetPlayer = _proxies.get(id, null)
		if proxy == null or not is_instance_valid(proxy):
			continue   # no info record yet; it arrives within INFO_INTERVAL
		proxy.take_state(
			Vector3(packet.decode_float(at + 2), packet.decode_float(at + 6),
				packet.decode_float(at + 10)),
			_unquantise_angle(packet.decode_s16(at + 14)),
			_unquantise_angle(packet.decode_s16(at + 16)),
			packet.decode_u8(at + 18),
			packet.decode_u8(at + 19),
			float(packet.decode_u8(at + 20)) / 255.0,
			packet.decode_u8(at + 21))


func _sender_owns(sender: int, id: int) -> bool:
	if id >= BOT_ID_BASE:
		return sender == 1          # bots are the host's, always
	return Net.machine_of(id) == sender


# --- what a body IS ----------------------------------------------------------

## Style, stature, team and weapon: everything a proxy needs to be built, and
## everything that changes when somebody redeploys as a different class.
func send_info(id: int) -> void:
	var body: Node3D = _own.get(id, null)
	if body == null or not is_instance_valid(body):
		return
	var build: Loadout = body.get("loadout")
	var weapon: Node = body.get("weapon")
	_take_info.rpc(id,
		int(body.get("team")),
		build.character_style() if build != null else 0,
		build.stature() if build != null else 1.0,
		int(weapon.get("weapon_class")) if weapon != null else 0,
		_name_for(id),
		id >= BOT_ID_BASE)


func _name_for(id: int) -> String:
	if id >= BOT_ID_BASE:
		return "AI"
	var n := Net.name_of(id)
	return n if n != "" else "PLAYER"


@rpc("any_peer", "call_remote", "reliable")
func _take_info(id: int, team: int, style: int, stature: float,
		weapon_class: int, body_name: String, bot: bool) -> void:
	if not _sender_owns(multiplayer.get_remote_sender_id(), id):
		return
	if _own.has(id):
		return   # our own body came back to us through the relay; ignore it
	var proxy: NetPlayer = _proxies.get(id, null)
	if proxy == null or not is_instance_valid(proxy):
		proxy = NetPlayer.new()
		_proxies[id] = proxy
		_ids[proxy] = id
		# Under the LEVEL, not under this node, so a map rotation tears the
		# proxies down with everything else that belongs to the match.
		var host_node: Node = get_parent().get("level")
		(host_node if host_node != null else get_parent()).add_child(proxy)
		proxy.setup(id, team, style, stature, weapon_class, body_name, bot)
		return
	# Already standing: a redeploy, a class change or a weapon swap. Rebuilt in
	# place rather than replaced, so the body keeps its position and its easing
	# instead of blinking back to the origin for one packet.
	proxy.team = team
	proxy.display_name = body_name
	proxy.model.set_style(style)
	proxy.model.set_team_color(
		GameState.team_colors[team % GameState.team_colors.size()])
	proxy.set_stature(stature)
	proxy.weapon.set_class(weapon_class)


@rpc("any_peer", "call_remote", "reliable")
func _drop_body(id: int) -> void:
	if not _sender_owns(multiplayer.get_remote_sender_id(), id):
		return
	var proxy: NetPlayer = _proxies.get(id, null)
	_proxies.erase(id)
	if proxy != null and is_instance_valid(proxy):
		_ids.erase(proxy)
		proxy.queue_free()


# --- damage ------------------------------------------------------------------

## A round landed on a proxy here. Sent to the machine that owns the real body,
## and to nobody else — a hit is a conversation between two machines and the
## other two have no use for it.
func report_damage(victim_id: int, amount: float, attacker: Node,
		headshot: bool) -> void:
	var machine := Net.machine_of(victim_id) if victim_id < BOT_ID_BASE else 1
	if machine < 0:
		return
	_take_damage.rpc_id(machine, victim_id, amount, id_of(attacker), headshot)


@rpc("any_peer", "call_remote", "reliable")
func _take_damage(victim_id: int, amount: float, attacker_id: int,
		headshot: bool) -> void:
	var body: Node3D = _own.get(victim_id, null)
	if body == null or not is_instance_valid(body) or not body.has_method("take_damage"):
		return
	# The ATTACKER is resolved to whatever this machine has standing for it — the
	# real body if it is ours, the proxy otherwise. It has to be a node and not an
	# id, because `take_damage` uses it for the friendly-fire check, for the kill
	# credit and for the direction the corpse is thrown.
	var attacker: Node = body_for(attacker_id)
	body.take_damage(amount, attacker, headshot)


## The victim's machine telling a shooter its round connected. Raised from inside
## the victim's own `take_damage`, which is the one place that knows the damage
## survived the friendly-fire check and the guard — exactly where the local game
## already raises it, so the marker, the tick and the kill streak all behave the
## same whether the target was local or not.
func report_hit_confirm(attacker_id: int, headshot: bool, killed: bool) -> void:
	var machine := Net.machine_of(attacker_id) if attacker_id < BOT_ID_BASE else 1
	if machine < 0:
		return
	_take_hit_confirm.rpc_id(machine, attacker_id, headshot, killed)


@rpc("any_peer", "call_remote", "reliable")
func _take_hit_confirm(attacker_id: int, headshot: bool, killed: bool) -> void:
	var body: Node3D = _own.get(attacker_id, null)
	if body != null and is_instance_valid(body) \
			and body.has_method("on_hit_confirmed"):
		body.on_hit_confirmed(headshot, killed)


## The kill streak. Its own message rather than a flag on the hit confirm,
## because a kill and the round that caused it are not always the same event —
## splash, a storm tick and a fall all kill without a hit to confirm.
func report_credit_kill(killer_id: int) -> void:
	var machine := Net.machine_of(killer_id) if killer_id < BOT_ID_BASE else 1
	if machine < 0:
		return
	_take_credit_kill.rpc_id(machine, killer_id)


@rpc("any_peer", "call_remote", "reliable")
func _take_credit_kill(killer_id: int) -> void:
	var body: Node3D = _own.get(killer_id, null)
	if body != null and is_instance_valid(body) and body.has_method("credit_kill"):
		body.credit_kill()


# --- death, and the score ----------------------------------------------------

## A body this machine owns went down: everyone else drops a ragdoll for it.
##
## SEPARATE FROM SCORING ON PURPOSE. A host-side bot dying already ran the score
## through `GameState` on the machine that owns the score, so it needs the
## announcement and must NOT be counted a second time. A player dying on a client
## needs both, and calls both. Folding the two together is how a bot's death ends
## up worth two frags in a networked match and one in a local one.
func announce_death(id: int, shove: Vector3) -> void:
	_take_death.rpc(id, shove)


## Somebody was killed and the score has to move. Runs the real rules on the
## host, wherever the kill happened.
func report_kill(killer_id: int, victim_id: int, victim_team: int) -> void:
	if Net.is_host():
		_score_kill(killer_id, victim_id, victim_team)
	else:
		_report_kill.rpc_id(1, killer_id, victim_id, victim_team)


@rpc("any_peer", "call_remote", "reliable")
func _take_death(id: int, shove: Vector3) -> void:
	if not _sender_owns(multiplayer.get_remote_sender_id(), id):
		return
	var proxy: NetPlayer = _proxies.get(id, null)
	if proxy != null and is_instance_valid(proxy):
		proxy.drop_corpse(shove)


@rpc("any_peer", "call_remote", "reliable")
func _report_kill(killer_id: int, victim_id: int, victim_team: int) -> void:
	if Net.is_host():
		_score_kill(killer_id, victim_id, victim_team)


## A human finished shopping. Tallied on the host, which is the only machine that
## can know when EVERYBODY has — and it is a set of ids rather than a count, so a
## message that arrives twice (a redeploy, a re-sent packet) cannot start the
## match early.
func report_deploy(id: int) -> void:
	if Net.is_host():
		_note_deploy(id)
	else:
		_take_deploy.rpc_id(1, id)


@rpc("any_peer", "call_remote", "reliable")
func _take_deploy(id: int) -> void:
	if Net.is_host():
		_note_deploy(id)


var _deployed_ids := {}


func _note_deploy(id: int) -> void:
	if id < 0 or id >= BOT_ID_BASE:
		return
	_deployed_ids[id] = true
	if _deployed_ids.size() >= Net.player_count():
		all_deployed.emit()


## SCORING RUNS ON THE HOST AND NOWHERE ELSE, through the same GameState calls a
## local match uses. Nothing here re-implements a rule: `add_frag`, `report_death`
## and `check_last_standing` still decide what a kill is worth in each mode, and
## the result is mirrored out by `_on_score_changed`.
func _score_kill(killer_id: int, victim_id: int, victim_team: int) -> void:
	var killer_team := _team_of(killer_id)
	if GameState.mode == GameState.Mode.CONQUEST:
		GameState.report_death(victim_team)
	elif GameState.mode == GameState.Mode.ROYALE:
		GameState.check_last_standing()
	elif killer_team >= 0 and killer_team != victim_team:
		GameState.add_frag(killer_team)
	# THE RECORD IS THE HOST'S TOO, and then it is BROADCAST rather than derived
	# again on each machine: a client has no body for a bot that died on the host,
	# so it could never build the same entry from ids. One authority, one feed,
	# and every machine's killfeed says the same thing in the same order.
	# `log_kill` mirrors this out to every client on its own — see the note there
	# for why the broadcast lives in one place and not in each death path.
	GameState.log_kill(_kill_entry(killer_id, victim_id, victim_team))


## Build a feed entry from ids. Names are resolved HERE, on the machine that has
## the bodies, and travel as strings — the receiving end is not asked to look up
## a body it may never have had.
func _kill_entry(killer_id: int, victim_id: int, victim_team: int) -> Dictionary:
	var killer: Node3D = body_for(killer_id)
	var victim: Node3D = body_for(victim_id)
	var suicide := killer_id < 0 or killer_id == victim_id
	var entry := {
		"killer": "" if suicide else GameState.combatant_name(killer),
		"killer_team": -1 if suicide else _team_of(killer_id),
		"victim": GameState.combatant_name(victim),
		"victim_team": victim_team,
		"headshot": false,
		"suicide": suicide,
	}
	# A net id below BOT_ID_BASE IS a human seat, which is exactly what a stat row
	# is keyed on — so online the table fills for every human in the session and
	# not just the ones on this machine.
	if not suicide and killer_id >= 0 and killer_id < BOT_ID_BASE:
		entry["killer_index"] = killer_id
	if victim_id >= 0 and victim_id < BOT_ID_BASE:
		entry["victim_index"] = victim_id
	return entry


## Push one feed entry to every client. Called by `GameState.log_kill` on the
## host, whatever killed whatever.
func mirror_kill(entry: Dictionary) -> void:
	_take_kill.rpc(entry)


@rpc("authority", "call_remote", "reliable")
func _take_kill(entry: Dictionary) -> void:
	GameState.log_kill(entry, false)   # from the wire: do not echo it back


func _team_of(id: int) -> int:
	var body: Node3D = body_for(id)
	if body != null and is_instance_valid(body):
		return int(body.get("team"))
	return Net.team_of(id) if id < BOT_ID_BASE else -1


# --- host -> client match state ----------------------------------------------

func _on_score_changed(_team: int, _score: int) -> void:
	_take_scores.rpc(GameState.scores, GameState.tickets)


func _on_match_won(team: int) -> void:
	_take_victory.rpc(team)


func _on_countdown(seconds: int) -> void:
	_take_countdown.rpc(seconds)


func _on_match_began() -> void:
	_take_began.rpc()


@rpc("authority", "call_remote", "reliable")
func _take_scores(scores: Dictionary, tickets: Dictionary) -> void:
	GameState.scores = scores.duplicate()
	GameState.tickets = tickets.duplicate()
	# Emitted with the last side that moved unresolved (nothing reads the
	# arguments — every HUD redraws the whole line), so the scoreboard, the
	# ticket readout and the Conquest screen all refresh off one signal.
	GameState.score_changed.emit(0, 0)


@rpc("authority", "call_remote", "reliable")
func _take_victory(team: int) -> void:
	if GameState.match_over:
		return
	GameState.match_over = true
	GameState.match_live = false
	GameState.match_won.emit(team)


@rpc("authority", "call_remote", "reliable")
func _take_countdown(seconds: int) -> void:
	GameState.match_countdown.emit(seconds)


## ZONES. The area's position and who holds it, from the one machine that counts
## heads. Sent on the zone's own tick (once a second) rather than with motion,
## because it changes at that rate and not at sixty.
func _on_zone_state(holder: int, contested: bool, seconds_left: int) -> void:
	var zone: Node3D = get_parent().get("zone")
	if zone != null and is_instance_valid(zone):
		_take_zone.rpc(zone.global_position, holder, contested, seconds_left)


@rpc("authority", "call_remote", "reliable")
func _take_zone(point: Vector3, holder: int, contested: bool, secs: int) -> void:
	var zone: Node3D = get_parent().get("zone")
	if zone != null and is_instance_valid(zone) and zone.has_method("remote_state"):
		zone.remote_state(point, holder, contested, secs)


@rpc("authority", "call_remote", "reliable")
func _take_began() -> void:
	GameState.match_live = true
	GameState.match_began.emit()
	Audio.play_music("battle")
