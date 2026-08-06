# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

Style note: entries are **rule first, reason second**. The reason is there because
the rule looks arbitrary without it and gets undone by the next edit. Nothing here
is a changelog — if something is no longer true, delete it rather than append to it.

## Project Overview

**QuadSquad** — 4-player local split-screen Star Wars-style FPS for Linux, built in
**Godot 4.7** with the **GL Compatibility** renderer. Target is Ubuntu laptops on
integrated graphics; the Raspberry Pi 5 target was dropped (see PERFORMANCE). The
former custom C++/SDL2/EnTT engine was removed in 2026-07; its features are the
roadmap in README.md.

Everything is **procedural and built in code** — characters, weapons, maps, props,
UI and sound. No imported meshes, no textures, no audio files, no build step. A new
unit, gun, map or sound is a table row plus a builder function.

## Commands

```bash
godot --path godot                       # run the game
godot --editor --path godot              # open the editor (needed for the MCP tools)
godot --headless --path godot --import   # headless parse/import check
godot --path godot -- --debug            # DEBUG: player 1 on keyboard + mouse, solo
```

**The game is pad-first, so `-- --debug` is how you play it at a desk.** It puts P1
on keyboard+mouse and defaults to one viewport; nothing else changes. The flag is
read from USER args (after the bare `--`) because plain `--debug` is Godot's own
engine switch and never reaches the project. `--kbm` works in either position.

Godot 4.7.1 binary: `~/.local/bin/godot`. The godot-mcp addon
(`godot/addons/godot_mcp/`, port 6550) gives editor control, input injection (incl.
virtual joypads), runtime state and screenshots — the editor must be running.

## Repo layout

- `godot/scenes/front.tscn` — **main scene**, the door in. → `sign_in.tscn` (who is holding
  which controller) → `playlist.tscn` (build the night's rounds) → `team_select.tscn` →
  `main.tscn`. `lobby.tscn` is the online branch off the front screen. `menu.tscn` is the
  ORIGINAL single-match setup grid, kept and unchanged: it is off the local path now and is
  what the online and fallback routes still come back to.
- `godot/scenes/main.tscn` — a bare `Main` node; `scripts/main.gd` does all the work.
- `godot/scenes/levels/` — maps. All procedural except the hand-authored hangar.
- `godot/scripts/` — everything. `godot/tests/` — see TESTS.
- Autoloads, in order: `Net` (`net.gd`), `GameState` (`game_state.gd`), `Audio` (`audio.gd`).
- Physics layers: **1 world, 2 players, 3 projectiles, 4 shields** — all four NAMED in
  `project.godot`, so the inspector agrees with `FrontShield.SHIELD_LAYER`.

## House rules

These apply to every change, and each one is here because it was broken at least
once. The per-system sections below assume them rather than repeating them.

1. **No per-frame allocations — MATERIALS above all.** `CommandPost._paint` built
   three `StandardMaterial3D`s per post per physics frame: five posts cost 1.7 ms,
   more than one feature's share of a 16.7 ms budget. Build materials ONCE and write
   `albedo_color`, only when the colour actually moved.
2. **Per-SHOT allocation is the same rule and easier to miss.** 13 rounds/s per
   shooter × up to 12 shooters. `blaster_bolt` duplicated its material per impact
   (which also made the rendering server log `Parameter "material" is null` ~30×
   a match) and `impact.gd` built six materials and six meshes per burst. Bolts
   animate SCALE only (per-instance state, free); impacts share static meshes.
   A per-colour cache keyed by a small fixed TABLE is fine (`blaster_bolt._mats`,
   `Meshes.chamfer_box`) — it stops growing and never depends on rate of fire.
3. **Nothing is spawned for an effect no human could see.** `Weapon.IMPACT_VIEW_RANGE`,
   `Corpse.VIEW_RANGE`, `Audio.HEARING`. In a 4v4 on a 220 m map most rounds are bots
   shooting bots elsewhere. Humans only — bots have no camera.
4. **Anything unbounded gets a POOL with a ceiling and a claim TOKEN.** Impact lights
   (14), loop voices (3), corpses (`MAX_ALIVE`). The token lets an owner that has been
   outbid do nothing quietly instead of switching somebody else's off.
5. **When N things ask the same question every frame, ask it once.**
   `GameState.sample_combatants()` takes validity/`is_alive()`/position/team into
   packed arrays once per physics frame; every command post reads that snapshot
   (2.65 ms → 0.05 ms). `Main._tick_overlays` is the same for HUD redraws.
6. **A GDScript error ABORTS the enclosing function, silently as far as play is
   concerned.** An out-of-bounds index did it (`Player._force_shown` was 2 wide where
   `_force_cd` was 3, so a slot-3 cooldown killed the jetpack, cable and dash for that
   frame); so did a bad `%` (`mode_blurb` — never `%` a table entry at the call site,
   the argument count is part of the blurb, so a blurb formats itself).
7. **A table indexed by an enum must be checked against that enum**
   (`kit_rules.check_enum_tables`, comparing NAMES not just length). `GADGETS` drifted
   one row and twelve gadgets silently took the next one's behaviour, price and name.
8. **Index-addressed tables are APPEND-ONLY.** `WEAPONS`, `SECONDARIES`,
   `FACTION_BUILDS` — inserting a row silently re-arms every preset below it. Look guns
   up by class (`weapon_index()`); the second four of every roster lives at the END of
   `FACTION_BUILDS` (index 32+), never beside its own faction.
9. **A field is only as real as its membership of the copy / compare / price / reset
   set.** `gadget3` was wired into the enum, the kits, the buy screen, the HUD and
   `_use_gadget`, and left out of `_copy_from`, `_same_as`, `cost()`, `adopt_kit` and
   `uses()` — so it never existed at all (nothing reads a Loadout without duplicating
   it first). `foregrip` was missing from the same set. `kit_rules` now checks copy
   fidelity GENERICALLY off `get_property_list()` — naming fields is how this happened.
10. **Physics interpolation makes teleports something you DECLARE.** Anything that
    MOVES a body rather than letting it walk — respawn, spawn placement, corpse landing
    — must call `reset_physics_interpolation()` or it is drawn smeared across the whole
    distance for one frame.
11. **Autoload signals + lambdas leak across scene changes.** Godot drops a connection
    when its target object is freed; a lambda that never touches `self` has no target,
    so a per-HUD lambda on `GameState.score_changed` fires into freed labels on the next
    map. Connect a **method of the node**. `get_tree().process_frame` is the same trap
    one signal further out — the SceneTree outlives every scene.
12. **`metallic` is 0.0 on EVERYTHING** — every weapon part, every character `Finish`,
    every prop, every deployable. It is a switch to leave off, not a value to tune.
    Metallic takes albedo OUT of the diffuse and puts that energy into the reflection,
    and under GL Compatibility the only thing to reflect is the sky — so a metallic
    surface stops being its own colour and becomes a picture of the sky gradient. That
    is what "the guns/characters look see-through" was, at 0.75, 0.45 and 0.30.
    **A dielectric still shines**: low `roughness` + `metallic_specular` off the DIRECT
    lights every map has. What separates steel from polymer is ALBEDO and ROUGHNESS —
    steel is lighter albedo and low roughness, polymer dark and rough.
13. **Decoration never collides.** Set dressing goes through `Props.batch()` (one
    MultiMesh per prop TYPE). The cover layout is what a map PLAYS like and it is tuned;
    anything meant to be shot around belongs in `cover_boxes`. It also keeps the map
    screen and nav grid a clean read, since both scan colliders.
14. **`GameState.match_live` gates the whole match** — false from map load until every
    human has deployed and Main's `_tick_countdown` finishes. Add the check to anything
    new that acts on its own, or it gets a free few seconds.
15. **Anything that can be shot or shoved must be in `GameState.combatants`**, or it
    won't block spawn markers and will re-trigger capsule-stacking ejection. Combatants
    are **duck-typed, not a shared base class**: `is_alive()` / `team` / `take_damage()` /
    `body_height()`.
16. **Nothing may name a key or pad button in UI text.** Prompts go through
    `Controls.label(device, id)` or they go stale on the first rebind. `label()` is
    PLAYER-facing (device < 0 means keyboard) — use `pad_label()` when you mean the
    `ALL_PADS` profile, which is also negative.
17. **Measure, don't reason.** Engine `TIME_PROCESS`/`TIME_PHYSICS_PROCESS` monitors
    ranged 14.6–27.1 ms across identical runs — use `Time.get_ticks_usec` or count
    occurrences. Anything GPU-side needs an **A/B/A sandwich** plus warm-up, because the
    laptop thermally throttles to roughly half clock and a straight sweep reports every
    later option as more expensive.

## Architecture

### Catalogue: universes, kits, weapons

- **A UNIVERSE is a set of CLASSES, the SIDES they fight for, and which of the
  catalogue those classes can reach** (`Loadout.UNIVERSES`, `Loadout.Universe`, the
  UNIVERSE dropdown). STAR WARS / HALO / WARHAMMER 40,000. Nothing about the rules,
  modes, maps or shooting knows a universe exists: every weapon lives in the ONE
  `Weapon.Class` enum and every body in the ONE `CharacterModel.Style` enum, so a
  bolter is a hitscan with a heavy round and a Spartan is a table row. Every row states
  its universe; **no key means STAR WARS** (what the catalogue was before this existed),
  `ANY_UNIVERSE` for rows belonging to nobody. Star Wars and Warhammer field four sides,
  Halo two.
- **The universe enum lives in `Loadout`, not `GameState`; `GameState` MIRRORS it into
  `Loadout.active_universe`.** `tests/kit_rules.gd` runs under `--script`, which has no
  autoloads, so Loadout may never name GameState. `Loadout.ttk_health` is the same trick.
  Both are pushed by GameState's property setters **and by `_init`**, because a
  `var x := v` initialiser does not run its own setter.
- **Allow-lists check the universe FIRST, derived from the KIT rather than read off the
  setting** (`Loadout._allows_entry`). Only `Row.KIT` reads `active_universe`, because it
  is the row that chooses which universe's class you are on — and it is WALKED, not
  clamped, or a step off the last Star Wars class lands on a Spartan.
- **THE BUY SCREEN'S CLASS ROW OFFERS THE UNIVERSE'S AUTHORED CHARACTERS, NOT THE KIT
  ARCHETYPES** (`Loadout.custom_classes`, `adopt_character`). There are only fourteen `Kit`s
  and they are shared three ways, so measured, the row put **five** classes in front of a Star
  Wars player and four in Warhammer — while the game has **thirty-two authored characters in
  each** (sixteen in Halo). A player building a custom loadout chose between CLONE TROOPER and
  WOOKIEE while the roster next door fielded a Clone Commando, an ARC Trooper, a Death Trooper
  and an Ewok Hunter: classes that existed, were balanced, were tested, and that the mode most
  people play could not reach. It is the SAME rows FACTION mode deploys, so this adds no
  catalogue and nothing to keep in step — a class authored for a roster turns up here for free.
  **`kit` is now DERIVED from the character** (a character states its own), and the row can be
  CLAMPED rather than walked, because `custom_classes()` is already this universe's.
- **CUSTOM OPENS THE WHOLE ARMOURY; FACTION HANDS YOU A CLASS AS AUTHORED**
  (`Loadout.custom_pool`, mirrored from `GameState.class_mode` exactly as `active_universe` is,
  and **default false** so `kit_rules` still asks about the restricted catalogue). The per-kit
  `primaries`/`secondaries` lists exist to make a CLASS mean something, and they did that job
  when the row offered five archetypes; now that it offers all thirty-two, the CHARACTER is the
  meaning — its body, its physique and the guns it walks in with — and the restriction was only
  stopping a player from rebuilding the thing they had just been handed. Measured: a Spartan
  reached 9 primaries and now reaches 20, an Ultramarine 9 and now 26, a Wookiee **two**.
  **What it does NOT relax is `"kit"` exclusivity** — a saber, a bowcaster, a thermal holo are
  MECHANISM (a saber needs the guard, a Force power needs the button) where a per-kit list is
  only balance. Same line `royale_items` already draws.
- **A CHARACTER CLASS (`Loadout.Kit`) is a set of ALLOW-LISTS over the one catalogue,
  not a catalogue of its own.** `KITS` states what each may reach (`gadgets`, `sustain`,
  `secondary_mods`, `armor`, `default_armor`, `gadget_slots`, `grenades`, optional
  `speed`/`health`, and optional `primaries`/`secondaries`/`sights`/`grenade_types`
  meaning ONLY those). All four allow-list rows share one rule: a `"kit"`-marked entry
  belongs to its owner alone and is always reachable by them (saber, bowcaster, smoke,
  thermal holo); otherwise a per-kit list restricts, else anything ordinary goes. Adding
  a gun is one table entry plus a decision about who may have it — never a parallel shop.
- **Moving an item to a class takes it off everyone who already had it, INCLUDING the AI
  presets.** A `"kit"` key is a re-balance of the whole roster, not a label. `kit_rules`
  is what says so — the Wookiee taking the T-21 made the clone GUNNER preset illegal.
- **A gadget from another universe is usually the same verb in different words**, so a
  GADGETS row may carry `"like"` naming the gadget whose behaviour it uses
  (`Loadout.gadget_action`). A bubble shield, an iron halo and a kustom force field are
  three rows and one barrier. Everything that ACTS resolves the action first
  (`Player._use_gadget`, `has_gadget`/`slot_of`, `Bot`'s `loadout.uses(action)`); the HUD
  still NAMES what was bought. No `"like"` means its own case in `_use_gadget`.
- **Presets name their gun by CLASS (`"primary"`/`"sidearm"`), not by index** —
  `_build_from` translates through `weapon_index`/`secondary_index`. **A preset naming a
  gun the catalogue does not sell in that slot is silently disarmed**: `weapon_index`
  answers `NO_PRIMARY` and `secondary_index` answers 0, both legal and completely wrong.
  `kit_rules` asks the strict question — *did you get the gun you asked for?* — across
  all 126 presets. Fix by APPENDING the gun, never inserting.
- **`secondary: 0` means "the cheapest row"**, which for Star Wars is the DL-44 — so all
  32 Star Wars classes drew Han Solo's pistol, B1 droids included. `kit_rules` now
  requires every authored class to NAME its sidearm; AI presets are exempt (a shop build
  picking the free row is a budget decision).
- **Primary and sidearm have SEPARATE modification slots.** SIGHT/COOLING/GRIP fit the
  primary (`primary_mods()`); the sidearm gets one pick from `SECONDARY_MODS`.
  `mods_for(on_secondary)` picks the set and everything calling `Weapon.set_class` must
  go through it. `adopt_kit` seeds the sidearm with `_first_allowed` — a kit left holding
  an illegal row 0 is one the cursor cannot step off, since every direction is refused.
- **Weapon upgrades never mutate `Weapon.PROFILES`**: `set_class(c, mods)` folds flags
  into a private `_upgraded_profile`.
- **`Row.KIT` sits at index 0 and the `row_*` functions fall through to `_upgrade_index`
  (`row - Row.COOLING`)** for anything they do not name — so a new row above COOLING
  computes a NEGATIVE index instead of failing where the mistake is. That function
  asserts. COOLING/GRIP/FOREGRIP must stay contiguous and in UPGRADES order.
- **TIME TO KILL is a multiplier on HEALTH and nothing else** (`GameState.ttk`,
  `TTK_HEALTH`, applied in `Loadout.max_health()` — the one function Player, `Bot.setup`
  and the bot heal ceiling already share). REALISTIC/LOW/MEDIUM/HIGH = ×0.35/0.65/1.0/1.6;
  MEDIUM is the game as it was. Scaling DAMAGE would mean every gun, splash, melee swing
  and the guard pool, and any one missed becomes the best weapon in the game.
- **Kit speed/health MULTIPLY the armour frame; UNIT physique REPLACES the kit's.** See
  THE PHYSIQUE TABLE. Everything that sets health goes through `Loadout.max_health()`.
- **Changing class RESETS the build** (`adopt_kit`) rather than converting it — half the
  selections would be illegal, and it guarantees the result is inside BUDGET in one pass.
- **Rows a kit does not have are HIDDEN and the cursor skips them** (`row_available` /
  `next_row`): four players shop at once and a line you cannot move reads as a broken
  game. Sight/cooling/grip vanish for a melee primary.
- `BUDGET` is 200 per life, not earned or banked. `step()` applies a change only if it
  stays in budget. **AI presets must fit it too** — they are legal player loadouts.

### Sides: factions and colours

- **A MATCH NO LONGER HAS A UNIVERSE — IT HAS SIDES THAT EACH NAME ONE**
  (`GameState.team_faction`, an index into `Loadout.factions()`). That is what lets UNSC fight the
  Republic. `UNIVERSES` still groups the CATALOGUE — which classes and guns a faction can reach is
  its universe's answer and that is unchanged — but `universe` is now the dropdown that DEALS a
  setting's sides out in order, not a claim that only one catalogue is on the field.
- **THE FLAT LIST IS DERIVED, NEVER AUTHORED TWICE.** A faction's name, colour and bolt already live
  in `UNIVERSES`, and a hand-written second table would be one edit from a side whose chip and whose
  tracer disagree with the roster it fields. **It walks `FACTION_ROSTERS`, not the name list** —
  Halo names four sides and authors two, and a side you can select but cannot field is worse than
  absent.
- **THE SIDE INDEX IS THE FACTION'S OWN SLOT, NOT THE TEAM NUMBER**, and this is the one that fails
  silently. In a mixed match team 1 might be UNSC, which is slot 0 of Halo; wrapping the team number
  into Halo's two rosters fields the Covenant instead, with the right name and the right colour on
  it. Everything that knows a team goes through `GameState.classes_for` / `team_build_for`;
  `Loadout` takes the pair apart because it may never name an autoload (`kit_rules` has no
  autoloads, so `faction_classes` and `Streaks.available` TAKE a universe rather than reading one).
- **AND A HUMAN'S DEPLOY IS A THIRD RESOLUTION, WHICH IS THE ONE THAT WAS WRONG.** The bot's path
  (`team_build_for`) and the screen's (`classes_for`) both resolved the side properly; `Player`'s deploy
  called `Loadout.team_build(team, spawn_class)` — a function that takes a SIDE SLOT and a UNIVERSE,
  handed a TEAM NUMBER and nothing else, so it read the roster out of `active_universe` at the team's own
  index. Those coincide on the menu's default deal-out, which is why every check passed while the game
  shipped the fault; pick a side its own faction, which is the entire point of the row, and the character
  select lists one roster while the body that stands up comes from another (measured: choosing UNSC and
  deploying a B1 BATTLE DROID). The fix is that `faction_class_build()` reads
  `faction_class_index()` — the function the NAME and the blurb already read — so the three are three
  reads of one answer and no later edit can move one without moving all three.
- **A COLOUR CHOICE DRIVES THE ARMOUR AND THE TRACER TOGETHER** (`GameState.team_tint`,
  `Loadout.TEAM_TINTS`, index 0 = the faction's own). Purple clones that still fire blue is half a
  setting. **The bolt is DERIVED from the chip rather than picked separately**, because the two exist
  for different jobs — a chip is read against a HUD, a tracer against terrain — and the existing note
  on `bolts` is that the Empire's grey plate would make a grey tracer no tracer at all. `tint_bolt`
  pushes saturation and value up with a FLOOR rather than a multiplier: BLACK is a fine chip and as a
  bolt would be nothing at all.
- **VEHICLES ARE ASKED PER SIDE.** `Vehicle.spawns_for` is still the one place the Star-Wars-only rule
  lives; it is simply consulted per team, so the Republic keeps its speeder when the enemy is
  Covenant. A vehicle's HULL comes from its faction's slot and its COLOURS from the team flying it,
  and with a chosen tint those are different answers — hence `Vehicle.set_team_color`.
- **A STREAK SIGNATURE MAY NOT SHARE A NAME WITH AN ORDINARY CLASS.** Five did (SPARTAN-II, DROIDEKA,
  WOOKIEE WARRIOR, SANGUINARY GUARD, NECRON LORD are all line classes), which made the ten-kill prize
  a unit that side already deploys at zero. `tests/factions.gd` checks every reward and every reward
  PRESET against `FACTION_BUILDS`.

### Classes and rosters

- **EIGHT CLASSES A SIDE.** Star Wars fields Republic, Separatist, Empire and Rebel
  Alliance; Halo two of eight; Warhammer four. `FACTION_ROSTERS` is keyed by universe and
  names classes by index into `FACTION_BUILDS` (see house rule 8). AI presets are not
  keyed by universe — a preset's universe is derivable from the class it names
  (`universe_builds`).
- **A ROSTER IS BUILT FROM THE FANBASE'S OWN VOCABULARY, not from adjectives.** The first
  attempt produced CLONE PILOT and REBEL HEAVY carrying recycled rifles, which is what a
  roster looks like when it is generated rather than designed. Battlefront's structure is
  four LINE classes (assault, heavy, officer, specialist) plus four REINFORCEMENTS, and
  the reinforcements are the units people queue for: Droideka, Clone Commando, ARC
  Trooper, BX Commando Droid, B2, Death Trooper, Flametrooper, Wookiee Warrior, Ewok
  Hunter. **Halo works the other way round — the sandbox IS the roster**, so no two Halo
  classes share a primary and each is named by the gun it walks in with.
- **THE TEST OF A CLASS IS WHETHER IT NEEDED A NEW NOUN.** Sixteen weapons and nine
  gadgets exist because a class could not be itself without them: a Droideka firing a
  DC-15 is not a Droideka. `DROIDEKA_TWIN` is the highest sustained output behind the
  shortest heat pool; `FLAMETHROWER` is the only weapon with no reach and no way to miss;
  `EWOK_SPEAR` is the shortest reach and highest melee damage; `DC17M` is the only
  three-round burst; the `DC17` exists so the ARC can carry TWO. All sixteen went into the
  SHOP as well — a weapon only a faction class can hold is one most players never see.
- **A CLASS IS A BODY, NOT A COLOUR — the PHYSIQUE table** (`Loadout.unit_speed` /
  `unit_health` / `unit_jump` / `unit_stature`, read through `move_speed()` /
  `max_health()` / `jump_power()` / `stature()`). Speed and health had only ever been
  per-KIT, so all sixteen Clone Wars classes on the default kit were **byte-identical** —
  a Droideka moved at a Scout Trooper's pace. Unit numbers REPLACE the kit's; the CLONE
  TROOPER states nothing and is 1.0 by definition, every other number is read against it.
  This is also what fixed the Royal Guard, who was on the FORCE kit and inheriting ×1.2
  speed under heavy plate.
- **STATURE IS ONE NUMBER AND EVERYTHING FOLLOWS IT** (`Player._apply_stature`, mirrored
  in `Bot`): model scale, capsule HEIGHT, camera/eye height and the headshot line, because
  the moment they disagree you get a head you can see but cannot hit. The capsule's RADIUS
  is deliberately NOT scaled — width is what the nav grid, the unstick loop and every
  doorway were tuned against. Capped at 1.16 for the same reason.
- **Everything that AIMS AT a body must ask how tall it is** (`GameState.aim_height`,
  duck-typed on `body_height()`). Bot, Turret and ForcePowers all used a flat 1.0 m chest,
  which over a 1.12–2.09 m roster puts rounds over the small ones and into the belt of the
  big ones — and does the same to the sight checks deciding if they are seen at all.
- Notable kits: **WOOKIEE** heavy (T-21 and PLX-1 exclusive, front shield, plate only,
  ×1.3 health ×0.9 speed; bowcaster sidearm is a 3-pellet hitscan, and its kit forbids the
  SCOPE there on purpose — zero spread would collapse all three quarrels onto one point).
  **TRANDOSHAN** skirmisher (×1.15 speed ×0.95 health, owns SMOKE and the THERMAL HOLO —
  throw smoke, then read bodies inside it nobody else can see; gadgets CLOAK and DASH).
  **FORCE** adept (×1.25 health — it can only close while everyone else shoots on the way
  in; double jump intrinsic, dash both intrinsic and selectable as `Gadget.DASH`).
  `kit_rules` allows DASH on the adept and Trandoshan and nobody else.

### Kill streak rewards

- **A STREAK IS `Player.kills_this_life`, WHICH ALREADY EXISTED** — the HUD has counted it since long
  before there was anything to spend it on. Nothing is banked, nothing is bought, and dying costs you
  everything you were working toward. **Per LIFE and not per match on purpose**: a reward kept across
  deaths is one the best player accumulates and the worst player watches.
- **TWO KINDS OF REWARD, AND THE SPLIT IS THE DESIGN** — the same distinction the third gadget slot
  makes. **CALL-IN** (recon, orbital strike, a walker delivered to you) happens somewhere else and you
  carry on being what you were; **BECOME** (a Droideka Prime, an Ork Warboss, a Force master) happens
  to YOU and the rest of that life is played as something else.
- **A REWARD IS OFFERED, NOT APPLIED** — D-UP takes it, D-DOWN turns it down (`reward_accept` /
  `reward_decline`, and the prompt names them through `Controls.label` so it follows a rebind). **The
  reason DECLINE is a real answer and not a politeness is that some of these COST you something**: a
  BECOME replaces the build you chose and are in the middle of using, and the gunship takes you off the
  ground for twenty seconds while your side is holding a post. Forcing that on somebody at the moment
  they are doing best is the opposite of a reward. **The offer is spent when it is MADE, not when it is
  taken**, or every further kill re-offers the thing you just refused.
- **D-UP and D-DOWN were SECOND bindings on gadget 1 and gadget 2.** Both keep their face button and
  lose only a duplicate; the reward had no control at all and could not be offered without one.
- **A BECOME REWARD'S ROW IS AN ORDINARY PRESET** in the same format as every AI build and authored
  class (`Loadout.preset_build`, the public door onto `_build_from`). So a reward that names a gun the
  catalogue does not sell in that slot is **silently disarmed** exactly like any other preset, and
  `tests/streaks.gd` asks the same strict question `kit_rules` asks — *did you get the gun you asked for?*
- **A SIGNATURE PRESET MUST STATE ITS WHOLE KIT, because leaving a field out is not neutral.**
  `_build_from` writes only the keys the row names onto a FRESH Loadout, so a row stating a body and two
  guns REPLACES the build you spent 200 tokens and ten kills on with iron sights, no cooling, no grip and
  three empty gadget slots. That is what made the best reward in the game a downgrade in everything but
  health, and it is most of why they did not feel like rewards. Every row names all three gadget slots,
  and `sight`/`cooling`/`grip`/`foregrip` on a RANGED primary — a melee signature hides those rows, so it
  states `secondary_mod: DUAL` instead and walks in with two sidearms, which is also the only answer to
  the one thing a sword-only body cannot do. **A gadget here is NOT checked against the kit's allow-list**,
  exactly as an authored faction class's is not: a Droideka Prime carries the Wookiee's front shield
  because a droideka IS a shield, and the allow-lists are a SHOP rule, not a physics one.
- **A SIGNATURE IS SUPPOSED TO BE TOO STRONG.** That is the design and the pools were raised to make it
  true: roughly 12-16x a trooper's effective health, against 7-11x before. The argument is what a
  ten-kill streak COSTS — ten kills without dying once, in a mode where everybody respawns and nobody
  else has to string anything together — and a reward that rare has to change the shape of the fight
  when it lands, or the correct play on earning it is to carry on exactly as before. What keeps it from
  being a round-ender is NOT a smaller pool: it is `_no_regen` (which scales with how big the pool gets,
  and is therefore the right counterweight for turning that dial UP), the slot-3 exception, and the fact
  that a signature dies with you and takes its streak with it.
- **AND IT IS ANNOUNCED** (`Player._signature_entry`). A BECOME reward used to be a silent substitution
  between two frames — same position, different silhouette, a bigger number behind the health bar — so
  ten kills bought a thing the player mostly noticed by reading the HUD and everyone else noticed by
  dying. It is now a shockwave through `Blast.pop` (the same call every explosion in the game makes), the
  streak sting played AT THE BODY so the people about to have a problem hear where it came from, and the
  chase camera easing out where the reward is watched. **`ENTRY_TIME` is brief invulnerability, and it
  is not generosity**: the reward lands mid-firefight by definition, and a transformation whose animation
  can be interrupted by a round already in the air is one that gets taken away at the moment it is given.
- **THE HUD NAMES WHAT YOU BECAME, AND STATES THE COST** (`Player.signature_name` →
  `Main._add_signature_banner`). The second line is the one that matters: `_no_regen` is the rule the
  whole buff rests on, it is invisible — nothing about a body that does not heal looks different — and a
  player who does not know about it will play a signature like a trooper, break contact expecting to come
  back full, and die of a rule nobody told them. **The banner names the BODY, not the row**: one Force
  Master row resolves to JEDI MASTER or SITH MASTER, so it reads `build_name` rather than `row["name"]`.
- **A BECOME REWARD DOES NOT REGENERATE** (`Player._no_regen`, set by `_become` and cleared by every
  ordinary `_apply_loadout`), and that is the counterweight to the pool rather than a smaller pool being
  one. A signature stands up at 7–11× a trooper's effective health; with regen on top the only way to
  end one is to burst it down faster than 18 hp/s heals it, so the correct play against a Warboss becomes
  hiding until it leaves and the correct play AS one is to break contact and come back whole every time.
  Without regen every point spent is a point gone — you can win five fights on one shield and not fifty —
  and it is the only counterweight that SCALES with how big the pool gets. **The SUSTAIN slot is the
  deliberate exception**: an OVERSHIELD or an IRON HALO re-issues the second pool, so slot 3 is the one
  thing that still gives ground back, which is why every signature carries one.
- **The sustain gadgets TOP UP the overshield, they do not assign it.** A signature is issued 400-odd
  points through `Streaks`; `Gadget.OVERSHIELD` writing `OVERSHIELD_POOL` (110) flat would put the
  strongest body in the game one button press from gutting itself, with no error and nothing on screen
  to say what happened. `maxf` on both the pool and its clock — same for `DEFLECTOR`, whose trade is the
  trigger lock and applies to whatever pool is under it.
- **THE PROMPT STATES THE COST, not just the prize** (`Streaks.offer_blurb`, appending
  `NO_REGEN_NOTE` for BECOME rows only). Declining is only a real answer if you were told what you are
  agreeing to, and "this body never heals" is the one thing looking at it would never tell you. Appended
  in ONE place rather than written into nine blurbs, so the rule and the sentence describing it cannot
  drift apart.
- **A REWARD BELONGS TO A FACTION AND TO NOTHING ELSE** (`factions`, a `{universe: [teams]}` map; no
  key means everybody). It was gated on KIT as well, which meant **the prize depended on what you had
  bought that life** — two players on the same side were fighting for different rewards, and switching
  class silently changed the ladder under you. A faction is picked once and is the same answer for all
  eight of that side's classes. Stated as a MAP rather than a `universe` + `teams` pair because a
  reward can belong to different sides in different settings, and the pair cannot express that
  without two rows that then drift. **An absent universe is a refusal, not a fallthrough** — team 0
  is the Republic in Star Wars and somebody else in Halo.
- **ONE SIGNATURE PER FACTION AND NO TWO SIDES SHARE ONE**, across all TEN factions. The first pass
  had SIX of them sharing a generic "Juggernaut", which is the same failure as the first roster
  attempt (CLONE PILOT and REBEL HEAVY carrying recycled rifles): a reward generated from an
  ADJECTIVE rather than designed from the fanbase's own vocabulary. A Necron Lord and an Ork Warboss
  are not two skins on one Juggernaut, and if they were there would be no reason to care which side
  you are on. Republic LAAT GUNSHIP, Separatist DROIDEKA PRIME, Imperial AT-ST WALKER, Rebel WOOKIEE
  CHIEFTAIN, UNSC SPARTAN HEADHUNTER, Covenant SANGHEILI ZEALOT, Ultramarine TERMINATOR, Blood Angel
  SANGUINARY EXEMPLAR, Necron NECRON OVERLORD, Ork ORK WARBOSS. **`tests/streaks.gd` walks every
  faction in every universe and reports the two sides that share one BY NAME** — a count would not
  say what broke. **The names are deliberately NOT the line classes' names** (house rule in
  `tests/factions.gd`): SPARTAN-II, DROIDEKA, WOOKIEE WARRIOR, SANGUINARY GUARD and NECRON LORD are
  all units a side already deploys at zero kills, so a signature carrying one is a ten-kill prize
  that is visibly nothing new. `tests/signature_look.tscn` is the line-up that judges the set.
- **THE TWO UNIVERSAL RUNGS ARE WHAT KEEP THE LADDER LEVEL.** Recon and the ORBITAL STRIKE carry no
  `factions` key at all, and the orbital especially is the one reward that asks nothing of what you
  are — no body to become, no machine to climb into, no faction hardware — so it is the rung that is
  the same height for a Grot and a Space Marine. Every side gets exactly three rewards, four in Star
  Wars (which adds the Force master); a faction with fewer than the one across the map is a balance
  bug nothing else in the project would report.
- **ALL FOUR STAR WARS SIDES REACH A FORCE MASTER**, because which one you get is ALLEGIANCE and not
  class — Republic and Rebels draw a Jedi, Separatists and Empire a Sith. **The top rung may not be the
  squishiest thing on the ladder** and it was: on a LIGHT FRAME with no second pool it stood up at 208
  effective health against the ten-kill Terminator's 795, so the four-kill climb from a signature to the
  master was a downgrade in everything but flair. It keeps the light frame — a Force adept is fast
  because it has to close — and takes its pool as a SHIELD, which is the one that gets spent.
- **JEDI AND SITH ARE ONE ROW**, not two (`preset_by_team` overriding parts of the base `preset`). Same
  mechanism, two names and two bodies; stating them twice is how the two would drift.
- **AND THE FORCE MASTER IS PLAYED IN THIRD PERSON** (`"third_person": true` on the row →
  `Player.third_person`). Everything a saber duellist does happens to the BODY — a two-metre blade swung
  on an arc, a guard raised across the chest, a leap, a shove — and a first-person camera 30 cm from the
  hilt is pointed at the one part of all that which cannot be seen. **It is a TABLE KEY and not a test on
  the reward's name**, so a future saber signature gets it by stating one word.
  **THE PARALLAX QUESTION IS WHY IT IS PER-REWARD RATHER THAN A SETTING.** Moving the camera off the head
  puts the crosshair and the gun on two different lines, which is the fault that made the LAAT's ball
  turret unusable — and there it was fatal. Here it is not, and that is a property of THIS BODY: shots
  trace from the weapon (`Weapon._fire_hitscan`, which is on the head) and a Force Master's weapons are a
  melee ARC, a Force CONE and a sidearm. A trooper on a scoped rifle in this camera would be a different
  question and the answer would be no.
  The camera rides `remote_cam.position` — the RemoteTransform3D already copies its own transform onto
  the camera, so moving it back along the head's +Z IS a chase camera and every existing driver of the
  view (look, recoil, landing dip, a vehicle writing angles) keeps working untouched. `_apply_view_mode`
  owns BOTH cull-mask bits in one function, so the body and the viewmodel can never both be on or both be
  off — which is what "my gun is floating in front of my own face" and "I am invisible to myself" each
  look like. **`_apply_loadout` resets it**, for the same reason it resets `_no_regen`: that function is
  also what a fresh DEPLOY calls, and without the reset, dying once as a Force Master leaves you playing
  the rest of the match over your own shoulder.
- **A TRANSFORMATION MUST PRESERVE THE STREAK *AND* THE TAKEN-SET.** `_apply_loadout` resets both
  because it is also what a fresh DEPLOY calls, and here it is not one. Without the first, a transformed
  body's counter goes to zero and it can never reach the reward above it — the whole ladder. Without the
  second it **re-earns ITSELF on the next kill**, healing to full and re-issuing its own shield each time.
- **A BECOME reward's overshield takes a long FINITE lifetime, never `INF`.** `_over_left` is a countdown
  the HUD gauge reads straight out as its fill fraction, and INF makes that fraction meaningless. The
  intent is "until it is spent", and 90 s outlives any firefight the pool could survive.
- **RECON IS THE SCAN DART WITH THE RADIUS TAKEN OFF** (`GameState.mark_scanned`), which is why it needs
  no mesh, no collider and nothing to shoot down — it is a timer with a team on it. It **re-marks on a
  pulse** rather than marking once, because the roster changes underneath it and a body that spawned
  after a one-shot mark would be the only invisible thing on the field; marks overlap the pulse so a
  contact never blinks. **A cloak still beats it** — same check every AI vision test makes, or a
  four-kill streak would make the Trandoshan's signature ability worthless.
- **AN ORBITAL ROUND ARRIVES; A MORTAR ROUND IS ANNOUNCED** (`OrbitalStrike.SHELL_HANG`, overriding
  `mortar_shell.launch`'s own solve). The mortar's long hang is a FAIRNESS feature — you hear it coming
  and walk out from under it — and inheriting it from 90 m up gave the strike a 6.4 s time of flight on
  a barrage that runs for 7. Measured end to end: the first round landed **12.0 s after the button**, so
  the player saw nothing happen for the whole of their own reward, every salvo re-aimed at a centroid the
  shell would reach six seconds later, and six bots bunched inside 4 m lost **88 of 813 health** to the
  entire thing. 1.5 s is fast enough to land on the group it was aimed at and slow enough that the
  streak overhead is visible first.
- **YOU GO UP TO THE SHIP AND CALL THE FIRE YOURSELF** (`orbital_strike.gd`). It used to aim itself at
  the densest cluster and walk shells across it for seven seconds while the player who earned it carried
  on running around at ground level — everything about that was correct and none of it was a REWARD, the
  one thing a seven-kill streak has to deliver being a moment that belongs to you. The player is now
  SEATED at a fire-control station 210 m up (`VIEW_HEIGHT`, tipped off vertical by `VIEW_TILT` so there
  is sky in the frame and it reads as altitude rather than as a zoomed-out map screen), the stick walks
  the mark across the ground and the trigger brings rounds down on it for `duration`. The auto-aim
  survives as the OPENING mark only (`_densest_enemy_ground`), so it drops you in already pointed at the
  fight. **It reuses the whole of the LAAT's seating** — `enter_vehicle`, `seat_is_eye`,
  `vehicle_owns_view` + `take_view_delta`, and `gunner_readout()` so `gunner_hud.gd` draws both sights
  and neither knows about the other. Nothing re-implements ballistics: the rounds are `mortar_shell.gd`.
- **THE RATION IS THE CLOCK, NOT A MAGAZINE.** Hold the trigger and it keeps firing for the whole
  window; what stops it being a mode rather than a moment is that the window ends. Measured
  (`tests/warmachine_feel.gd`): six bunched inside 4 m with the mark held on them lose **925 of 925 and
  all six die**; the same six standing 18 m apart, with the same aiming effort spent on ONE of them,
  lose **88 of 791 and one dies**. That is the design claim — it punishes bunching, and spreading out is
  the answer to it — stated as an experiment where the only thing that differs is how the enemy stood.
- **A SHELL DROPPED FROM STRAIGHT OVERHEAD IS THE ONE CASE `look_at` CANNOT SOLVE.** Its velocity is
  `(0, -v, 0)`, which is colinear with the up vector `mortar_shell` was passing, so Godot emitted an
  engine warning per shell per physics frame — four rounds every 0.3 s buried every other line of output
  — and picked an arbitrary roll about an axis that is invisible on a capsule. A shell is a body of
  revolution, so any up vector off the flight axis is correct; it only has to not be parallel to it.
- **THE GUNSHIP IS NOT A VEHICLE AND YOU DO NOT DRIVE IT** (`gunship.gd`). A LAAT is not remembered
  for being piloted, it is remembered for the two glass balls on its flanks with a trooper sealed in
  each one hosing green fire downward — so the airframe flies its own circuit and the player rides the
  BALL TURRET. Handing them the stick would make it a slow speeder with good armour. Every answer
  `Vehicle` exists to give is about a machine you meet on the ground and climb into (the interact edge,
  the team gate on the mount, the hover ray, the driver bleed, blocking a spawn marker) and not one of
  them applies to something that arrives in the air and leaves on a timer. What it DOES reuse is the
  seating — `enter_vehicle`/`exit_vehicle` already hide the body, kill its collision and slave it to a
  seat, which is the hard part.
- **IT LOITERS, IT DOES NOT MAKE A PASS** (`Gunship.ORBIT_SPEED`, 0.18 rad/s). At 0.30 the hull
  crossed the ground at 18.6 m/s and came all the way round inside the twenty seconds you are up
  there — a fast pass, when the whole point of the machine is that it hangs over a fight while
  somebody in the ball works. At 0.18 it makes about two thirds of a lap at 11.2 m/s and keeps the
  same piece of battlefield under the guns long enough to shoot it.
  **Slowing it does NOT steady the sight picture, which is worth knowing because it sounds like it
  must**: the aim point's residual walk on a centred stick measures 1.4 m/s at the old speed and
  1.5 at the new one — the same reading twice. That is the tracking model working (the ball holds
  a POINT, so the hull's rotation is already cancelled and only its translation is left), and it
  is also why the speed was safe to change at all.
- **THE TURRET IS ON THE INSIDE OF THE TURN.** Not a detail: it is the entire reason a circling gunship
  works, because the guns stay pointed at the middle and the gunner is looking at the battle for the
  whole lap instead of half of it. **`Player.enter_vehicle` ASKS for the seat (`seat()`) rather than
  pathing to it** — a speeder's is a direct child, a gunship's is buried inside a ball that yaws and
  pitches.
- **THE BALL TRACKS A POINT ON THE GROUND AND THE STICK MOVES THE POINT** (`Gunship._aim_at`), which is
  three separate faults fixed by one model. The first version read the gunner's own WORLD yaw and
  differenced it against the hull's — the natural thing to write, and wrong invisibly: the hull turns a
  full circle every twenty seconds, so that difference changes at 17°/s on its own and a player holding
  NOTHING watched the gun sweep **30.2 m of ground a second** before pinning against its yaw stop for
  the rest of the ride. On top of that only the gunner's POSITION was ever slaved to the seat, so the
  camera and the gun pointed in unrelated directions — there was no crosshair at all. And the cone was
  priced in degrees rather than at the range it fires at: 0.7° over a 124 m shot put the average round
  **2.25 m** from a body half a metre wide. Tracking a point fixes all three (1.4 m/s residual, which is
  the platform's own translation; 0.00° between camera and barrel; 0.18 m average miss), and it is also
  the right model for the machine — a point near the orbit centre needs almost no counter-rotation to
  hold, so aiming at the fight is steady and slewing out to the rim works for its living.
- **A TURRET SEAT IS AN EYE POSITION; A SADDLE IS A FOOT POSITION** (`Player.seat_is_eye`,
  `seat_anchor_offset`). A body is anchored by its FEET and the camera rides `STAND_HEAD_Y` above them,
  which is right for a speeder — the seat is where you sit, and the camera ends up at head height over
  the cowl. In a ball turret it is fatal: the seat is INSIDE a 0.92 m sphere, so anchoring the feet
  there put the camera 1.6 m above it, outside the glass, floating in the open air beside the gunship.
  **And it broke the aim, which is the part no angle check could see.** `_drive_view` points the camera
  down the barrel, so the camera-vs-barrel ANGLE measured 0.00 deg — and two rays can be exactly
  parallel and still land eighty metres apart if they start in different places. Measured
  (`tests/warmachine_feel.gd`, the boresight check): the crosshair covered a point **2.12 m from where
  the shell landed at 76 m**, against a body half a metre wide. With the eye on the seat the camera sits
  2.25 m directly behind the muzzle along the barrel axis and 1 cm off it — **0.02 m**, boresighted by
  construction. The mount also STANDS THE BODY UP, because `_update_crouch` is the only thing that moves
  the head and it does not run while mounted.
- **AN ANGLE CHECK CANNOT SEE A PARALLAX FAULT.** Recorded separately because it is the reusable
  lesson: when a sight and a gun are two different objects, the question is never "do they point the
  same way", it is "do they ARRIVE at the same place". Cast both and compare the landings.
- **A MOUNT THAT AIMS SOMETHING OTHER THAN YOUR OWN HEAD TAKES THE LOOK DELTA, NOT THE ANGLES**
  (`Player.vehicle_owns_view` / `take_view_delta` / `set_view_angles`). `vehicle_look` reports the world
  yaw and pitch the body is already holding, which is right for a speeder and exactly wrong for a turret
  on a rotating hull. Intercepting at `_apply_look` catches the STICK and the MOUSE in one place, which
  is why this is one flag and not two input paths. **The view is written back as yaw and pitch and never
  as a basis**, so the gunner's horizon stays level — the ball hangs off a body banked 24° into its turn
  and the seat inherited 7.8° of that cant permanently, which also rotated the axes the stick worked in.
- **DO NOT RETURN THE GUNNER THROUGH `clear_of_bodies`.** It avoids LIVE players and the gunner is one,
  so it shoves them clear of the very spot it is meant to put them back on (measured: 12.8 m). Their
  body has been hidden and collision-less for the whole ride, so nothing took the ground from them.
- **THE WAR MACHINES ARE DELIVERED, NOT BECOME** — parked beside you, and you climb in. That keeps the
  whole vehicle story exactly as it is (mounting on the interact edge, the team gate on the ACTION, the
  driver bleed, dying at the controls, being a combatant bots shoot at); a vehicle that materialised
  around you would need every one of those answered again. Set down BEHIND the player: on top is the
  documented capsule-ejection bug and in front is a wall between them and what they were shooting at.
- **ONLY THE REPUBLIC AND THE EMPIRE GET A MACHINE** — the LAAT and the AT-ST. Every other side's
  signature is a BECOME, which is a preset and no new hardware; a machine costs a hull, a hover
  height and a `Vehicle.STREAK_VEHICLES` row. See VEHICLES for how the two are built.

### Game modes

- `GameState.mode` picks the rules. **DEATHMATCH** scores on `add_frag`, **ZONES** on
  `add_zone_tick`, both funnelling into `_award` with a per-mode `score_limit()`.
- **The VICTORY threshold is configurable** (`GameState.score_targets`, seeded from
  `SCORE_LIMITS`): kills or zone-hold seconds, from `menu.gd`'s `SCORE_CHOICES`. Royale is
  not tunable (last side standing is not a number).
- **CONQUEST is the Battlefront mode**: sides fight over CAPTURE POSTS (`command_post.gd`)
  laid out by `conquest.gd`, and you DEPLOY on a post your side holds, picked in the
  DEPLOY POST box (`Player._step_spawn_post`, `_conquest_spawn_transform`). `score_limit()`
  is the REINFORCEMENT pool: `report_death` spends one and `conquest_bleed` drains the side
  holding fewer posts by the deficit; zero loses (`_conquest_defeat`). `scores` mirrors
  `tickets` so the scoreboard needs no special case.
- **A CommandPost's ownership field is `owner_team`, NOT `owner`** — `Node.owner` is the
  built-in scene-owner and unrelated. Capture is Zone's head-count (most living combatants
  inside, ties freeze it) run toward a flip over `CAPTURE_TIME`; home posts start owned,
  the rest neutral. Only while `match_live`.
- **ROYALE** is not scored: nobody respawns, `check_last_standing()` awards the one point,
  and `Player.begin_deploy` skips the buy screen because there is nothing to buy.
  **Nothing respawns — and holding the players down is not enough**: Main was still
  reinforcing team-fill AI on `_on_team_bot_lost`, so bots kept coming back while humans
  stayed dead and the last side could never be decided. Anything that replaces a body
  needs a ROYALE early-out.
- **ROYALE HAS NO CLASSES.** Everyone drops in as a plain trooper and `Loadout.royale_items`
  filters anything carrying a `"kit"` key out of the crates — otherwise `_roll_pickup`
  scatters lightsabers over players with no guard to use one. An entry may carry
  `"royale": true` to stay in the crates anyway, for gear that is a class's by BALANCE
  rather than by mechanism (heavy guns, the barrier); `Pickup._grant` sets the field
  directly and never consults `allows`.
- Royale gear is all `Pickup`: every item is a change to the player's LOADOUT which is then
  re-applied, so a rifle found on the ground behaves exactly like a bought one across the
  weapon swap and rotary toggle with no second code path. Bots never collect — they deploy
  with a full preset and would strip the map humans rely on.
- **Standing on a crate does NOT take it.** A crate advertises through
  `Player.pickup_in_reach` and waits for the rebindable `interact` control. The press is
  published as `Player.pickup_pressed` and cleared by whichever crate acts on it — an edge
  is consumed by whoever reads it first, so with overlapping crates only one would see it.
- **THE STORM BURNS A BODY FOR WHERE IT IS, SO IT HAS TO KNOW WHO PUT IT THERE**
  (`Player.off_the_field`, answered by a mount stating `is_call_in()`). The ring exists to punish
  a body that failed to move; a gunner the game has seated at a fire-control station 210 m up on
  a timer did not fail to move and cannot walk back — and the station hangs 68 m from the mark it
  aims at (`VIEW_HEIGHT * tan(VIEW_TILT)`), so it is essentially always outside a closed ring.
  Reported from play as "the orbital strike kills you". Measured: 100 hp to 78 in six seconds at
  the OPENING damage rate, which climbs every phase — so later in a match the seven-kill reward
  simply killed whoever earned it, while they watched, seated, unable to do anything about it.
  **It is deliberately NOT "am I mounted"**: a speeder is on the field, you chose to get in it and
  you can drive it back inside the ring, so that keeps burning. The test asserts BOTH halves,
  because an exemption written one notch too wide leaves royale with no ring at all.
- **AND THE FIRST FIX FOR IT WAS A NO-OP, WHICH IS WORTH MORE THAN THE FIX.** The obvious cause is
  `Player`'s out-of-the-map check (`BOUNDS_MAX_Y` is 60 m and the station is at 210), and guarding
  that read exactly like a fix — but a mounted body returns at `_process_mounted` long before that
  line, so the guard changed nothing and the bug stayed. It was caught by REVERTING the fix and
  re-running the test: it passed either way, which means it had never been testing the fix. Do
  that on any bug whose reproduction was not seen failing first.
- **`Storm` picks its next centre from INSIDE the current circle**, never from anywhere on
  the map — that is what makes moving early a bet rather than a certainty. Damage rises per
  phase so a late ring can break a stalemate. Testing note: forcing `radius` mid-close is
  pointless (`_physics_process` lerps it every frame) — set `_closing = false` and a long
  `_left` first.
- `scripts/zone.gd` owns the capture area and counts `GameState.combatants`, so bots and
  turrets hold ground too. **It places itself on the first PHYSICS frame, not in `_ready`**
  — its placement raycast needs colliders that are not in the physics world yet.
- **WHERE YOUR GEAR COMES FROM IS A SETTING, NOT THE MODE** (`GameState.class_mode`;
  `faction_classes()` is the one question everything asks). CUSTOM opens the BUY SCREEN;
  FACTION opens the CHARACTER SELECT (`spawn_screen.gd`) and deploys one of your side's
  authored classes. Both work in EVERY mode — "Conquest has no buy screen" was never the
  same decision as the rules Conquest plays by. Selecting a mode SEEDS the setting
  (`default_class_mode`) and the player overrides it. ROYALE always answers false: it is
  neither a shop nor a roster, it is scavenging. Bots follow the same switch.
- **A MODE MAY SEED A SETTING NOBODY HAS TOUCHED; IT MAY NEVER OVERWRITE ONE SOMEBODY CHOSE**
  (`GameState.seed_class_mode` / `choose_class_mode`, and the `class_mode_chosen` flag that
  travels in `MATCH_KEYS`). Every mode picker used to write `default_class_mode` straight in,
  which was harmless while the setting sat on screen beside the mode resetting it — you could
  watch it move. On the playlist screen it was a silent bug and a bad one: choose FACTION
  ROSTERS, close the settings panel, build a round, and the MODE step of that build put it back
  to CUSTOM, so the round deployed off the buy screen. **Reported from play, and it is the
  shape of fault a hidden setting creates**: nothing on screen was wrong, the two halves were
  individually correct, and the only symptom appeared one scene later as the wrong deploy
  screen. Its regression test walks the real screen IN THE ORDER A PLAYER DOES IT, because the
  order is the bug.
- **TWENTY A SIDE IN THE ORDINARY MODES** (`MAX_TEAM_SIZE`, offered as the `TEAM_SIZES` ladder rather than
  twenty integers a stick has to walk). It was six, and a 6v6 on 260 m of Boneyard is four people who never
  find each other. What had to change to allow it was NOT performance work — it was splitting `Bot.line`
  from `Bot.thrifty` (see AI), because buying the cheap simulation used to also buy the stripped loadout.
  **Twenty and not fifty because these modes have RULES that scale with the roster** — posts to contest, a
  zone with a headcount in it — and fifty a side turns every one of them into a scrum. Fifty is MASSIVE's.
  Two traps: the size dropdown must be INDEXED into the same ladder it was filled from (adding the index to
  the floor only works while the rungs are contiguous), and **leaving MASSIVE leaves `team_size` at 50**,
  over the ordinary ceiling, unless `_fix_setup` walks it back onto the ladder.
- **A team is just an index**, 0..`active_teams()-1` — 2, 3 or 4 sides, or FREE FOR ALL
  (one team per player, no AI fill). `team_names`/`team_colors` are vars, not constants:
  who the sides ARE comes from the universe. `Team.REPUBLIC`/`CIS` are still 0 and 1 so
  maps naming them are untouched.
- **With 3+ teams `place_corner_spawns` REPLACES the map's authored spawns.** Maps only
  author two sets of markers, so extra sides would otherwise share somebody else's start —
  in a free-for-all, spawning on an enemy. Two-team layouts are left alone. Ground height
  comes from the level's own `height_at`, since colliders are not in the physics world yet.

### Player, combat and gadgets

- `scripts/player.gd` — CharacterBody3D. `input_device` -1 = keyboard/mouse, >= 0 = that
  joypad (polled, so MCP virtual pads work). Main hands out pads to everyone, so -1 is a
  fallback nobody is on by default. Each player's model renders on layer `2 + player_index`
  cleared from their own camera; the first-person viewmodel uses bit `10 + index`, seen
  only by its owner.
- **Death → corpse → countdown → respawn** at a team marker no living player is standing on
  (`GameState.get_spawn_point`/`clear_of_bodies`) — two overlapping capsules eject each
  other out of the map. **Respawn places the body BEFORE clearing `_dead`**: the picker
  skips dead players, so flipping `_dead` first makes a player treat the body it just left
  as an obstacle and shove itself off its own marker.
- **Health regenerates passively — there are no health kits.** `Player._update_regen` /
  `Bot._regen_if_calm` heal `REGEN_RATE`/s back to full once `REGEN_DELAY` has passed since
  the last hit; `take_damage` resets `_since_damage`. The delay is what stops mid-firefight
  healing — you recover by breaking contact.
- **Friendly fire is tested on `team`, not on `attacker is Player`.** `take_damage` used to
  let a friendly BOT through, which was harmless while the only AI weapon was a rifle and
  started mattering the moment AI artillery dropped splash on your own side.
- **FOOT PLANTING IS BUILT AND IS TURNED OFF** (`Locomotion.plant_feet`,
  `CharacterModel._solve_feet` / `_leg_ik`). A clip moves a foot whether or not the foot is on
  anything, so on a slope one boot hangs and the other is buried. Planting locks a foot near the
  ground to the world point it landed on and solves the leg to keep it there — one idea that also
  gives turn-in-place STEPS (the pinned foot holds while the body turns, and releases at
  `PLANT_BREAK`) and a stop-plant, neither of which needed a clip.
  **WHERE IT RUNS IS THE WHOLE TRICK**: the AnimationPlayer rewrites every leg joint every frame,
  so the solve must come after it (`process_priority`, `_process`), but a ray query may only be
  made during physics — so the ground is probed on the physics tick and handed over. A ground
  height one frame old is worth nothing against getting the order wrong.
  **It is off because `_leg_ik` replaces the hip's rotation instead of correcting it**, which
  discards the idle stance's splay and stands a planted body with its legs together — a worse
  artefact than the one being fixed. Measured (`tests/plant_look.tscn`): beside a 0.5 m step the
  worst foot is **39 mm off the ground without planting and 5 mm with it**, so the mechanism
  works; on a slope it is 66 mm against 60 mm with a 66 mm residual, which says the leg never
  reaches. Finishing it means blending the solve onto the animated pose rather than replacing it.
  **Four separate faults were found by measuring rather than looking**, each of which left the
  feature silently doing nothing: the plant band compared the ANKLE to the ground when the SOLE is
  what touches; the reach test measured from `Hips` when the hip JOINT sits 10 cm lower (`HIP_Y` is
  20 cm longer than the leg it carries); the knee kept the clip's Y and Z and swung out of the
  solve plane; and the hip drop ASSIGNED `HIP_Y` instead of subtracting, undoing every pose that
  drops its own hips. Two more were in the harness itself — a residual that was a running max
  never reset, and a settle loop that awaited only physics frames and so starved the idle-side
  solve 40 probes to 5 solves.
- **A BODY HAS MASS, AND THIS IS WHERE THE GAME MOST OBVIOUSLY DID NOT**
  (`Player._accelerate`, `Bot._drive`). Movement was `velocity.x = dir.x * speed` written straight
  in every frame — not a slow body or a fast one but a body with NO MOMENTUM: full sprint from
  standing in one frame, a dead stop in one, and a right-angle turn at full speed for free.
  **Nothing in the animation can rescue that**; the lean, the stride and the hip swivel were all
  describing a motion that was not happening underneath them. The input picks a TARGET and the body
  moves toward it. Measured (`tests/movement_feel.tscn`): **0.117 s to a walk, 0.167 s to stop** —
  and stopping being SLOWER than starting is the asymmetry that reads as weight; reversing at
  6.0 m/s costs you down to 0.23 m/s.
- **AIR CONTROL IS NOT GROUND CONTROL** (`AIR_ACCEL`). The same line ran while airborne, so a jump
  steered as freely as a walk and momentum meant nothing — you could leap forward and arrive
  sideways. A quarter second of hard steering now turns you 26°, not 90.
- **A WALL TAKES YOUR MOMENTUM.** `move_and_slide` resolves the collision into `velocity`, but
  `_move_vel` is the script's own accumulator and knows nothing about it — so without folding the
  result back, a body held against a wall keeps building speed into a surface it is not moving
  along and slides off it the moment you turn away.
- **THRIFTY BODIES KEEP THE DIRECT WRITE**, deliberately. A line trooper steps on alternate ticks at
  double velocity (`MOVE_EVERY`), and a ramp under that would be smoothing a signal that is
  sampled at half rate on purpose. Same line `crowded()` draws everywhere else: the bodies you can
  pick out get the fidelity, the crowd gets the frame. Bot references `Player.GROUND_ACCEL` rather
  than restating it — a bot that accelerated differently from a player would be a tell.
- **Recoil is three things off one `fired(cam_recoil, kick_back)` signal**: the viewmodel
  kick (`Viewmodel.kick`), the camera climb (`Player._recoil_pitch`, settling at
  `RECOIL_RECOVER`) and a backwards shove for the big guns. A gun's real cost is
  `cam_recoil / (fire_interval * RECOIL_RECOVER)` of steady climb, so raising a fast gun's
  recoil costs far more than the same bump on a single-shot one.
- **THE GUN KICKS AS MUCH AS THE SCREEN KICKS, AND THAT IS ONE NUMBER.** There was a
  separate `recoil` key for the viewmodel beside `cam_recoil` for the camera, and being two
  numbers they disagreed — the ratio ran 5.9 on the sniper to 12.0 on the rifle, so some guns
  flipped hard while the view behind them barely moved and others did the reverse. The
  viewmodel's climb is DERIVED (`Weapon.VIEW_KICK_PER_RAD`); the `recoil` key is gone from all
  92 profiles. The eye believes the sight picture, so a weapon that says one thing about a shot
  while the sight says another is the commonest reason a shooter feels wrong.
- **`cam_recoil` IS WHAT A TRIGGER PULL COSTS, NOT WHAT ONE ROUND COSTS** (`Weapon._shot_recoil`
  divides by `burst_count`). A burst's rounds leave 55 ms apart against a 6/s settle, so barely
  7% of the first round's kick has decayed before the third lands — they stack. Charging the
  full number three times threw the EL-16's camera up **13.7° on one pull**, and the
  first-shot weighting took it past 18: not a hard gun, a gun that cannot be fired twice at the
  same man. It also makes the column comparable across fire modes for the first time.
- **A RECOIL PATTERN IS SOMETHING YOU LEARN; RANDOM SPRAY IS SOMETHING YOU ENDURE.** The
  sideways kick was `randf_range` per shot, so no two bursts from one gun ever climbed the same
  way and practice bought nothing. It is deterministic in `Player._recoil_step` now — the first
  rounds climb hardest and taper (`RECOIL_FIRST_SHOT` over `RECOIL_SETTLE_SHOTS`), the sideways
  component weaves on a smooth curve (`RECOIL_WEAVE`), and only `RECOIL_YAW_JITTER` is random.
  **The pattern restarts after `RECOIL_PATTERN_RESET` off the trigger**, which is what makes
  TAPPING a real technique rather than a slower way to spray.
- **A MACHINE GUN IS THE STEADIEST THING YOU CAN CARRY, AND IT WAS THE WORST.** The T-21 ran at
  7.6°/s of steady climb against the DC-15's 3.1 — a belt-fed weapon climbing two and a half
  times as fast as a rifle, which made every one of them a three-round weapon with a long tail
  of wasted rounds. They are the most controllable guns in the game now and still pay for it in
  the widest cones in the catalogue. `tests/recoil_feel.tscn` measures both figures on every gun
  through the real signal path, because a table column cannot be read — per-pull kick, rate and
  settle only mean anything together.
- **THE LMGs ARE A CATEGORY, NOT A RATE** (`RT97C` / `DLT19D` / `M739_SAW` / `GAUSS_CANNON`).
  There were three sustained-fire guns and all three were one idea at three rates: a lot of small
  rounds through a wide cone. The four new ones are spread along the rate/damage axis (3 rounds
  in 0.52 s at one end, 7 in 0.36 s at the other) and every setting gets one, so an LMG player is
  not forced into Star Wars. Appended to `Class`, `PROFILES` and `WEAPONS` (house rule 8).
- **HOLD THE CROUCH BUTTON AT A RUN AND YOU GO TO GROUND** (`Player.sliding()`,
  `_begin_slide`/`_update_slide`/`_end_slide`). It is the first movement decision in the game that
  COMMITS you: everything else here is free and instant — crouch is a toggle, sprint is a modifier, the
  stance flips on a frame — and a slide costs you steering and the ability to stop for a second in
  exchange for closing ground fast and low. That trade is the reason to have one, not the familiarity.
  **ONE FUNCTION READS THE BUTTON.** `_edge` is CONSUMED by whoever asks first, so the slide and the
  stance toggle are decided together in `_toggle_crouch_input` — two readers of one press would work or
  not depending on the order two unrelated functions happen to be called in. At a run the press means
  SLIDE; standing, it means crouch; it never does both, because which stance you end in has to be
  predictable.
  **`_crouch_held()` ANSWERS TRUE WHILE SLIDING, and that one line is most of the integration**: the
  capsule shrinks, the spread and recoil multipliers apply, the sprint carry drops, the sights become
  available and the animation picks a crouched clip, all through paths that already existed. A slide is
  therefore automatically a small target that shoots straight, with no second code path anywhere.
  **The slide OWNS `_move_vel`** rather than easing through `_accelerate` — for that second the stick
  may only curve the heading — and the wall fold-back after `move_and_slide` still applies, so sliding
  into cover stops you exactly as walking into it does. A jump cancels it and still pays the cooldown.
  **WHETHER YOU STAND UP AT THE END IS WHETHER YOU ARE STILL HOLDING THE BUTTON**, which is what makes
  it hold-to-slide: ride it out and you finish in cover, crouched and already aiming.
- **A SLIDE IS SPEED-NEUTRAL ON PURPOSE, AND THE DRAG IS WHAT MAKES IT SO — NOT THE COOLDOWN.** This is
  the balance question every shooter that has shipped a slide has had, and the failure mode is always
  the same: if chaining it beats sprinting, it stops being an option and becomes how everybody is
  obliged to move. Measured (`tests/movement_feel.gd`): it opens at **1.48x sprint**, decays, and covers
  **4.92 m in 0.83 s** — an average of 5.93 m/s against a 6.0 m/s sprint. Over six seconds, spamming it
  covers 35.1 m against 35.6 m of simply running, and **lengthening the cooldown does not move that at
  all** (1.1 and 1.4 measure identically) — so anyone tuning this should reach for `SLIDE_DRAG`, not
  `SLIDE_COOLDOWN`. The test asserts "never AHEAD" rather than "slower", because demanding a measurable
  penalty would be an arbitrary tax and a strict inequality on a 1% margin is a coin flip.
- **THE SLIDE HAS ITS OWN CLIP, AND IT OUTRANKS THE CROUCH IN THE STATE MACHINE**
  (`CharacterModel._slide_pose`, `Locomotion.clip_for`). It has to outrank it: a sliding body IS
  crouched as far as `_crouch_held()` is concerned, so below the crouch the branch is unreachable and
  every slide plays `crouch_walk` — a man squatting at eight metres a second, which is what it looked
  like before the clip existed. **The pose is ASYMMETRIC and that is the whole read** — one leg thrown
  out in front, the other folded underneath, the torso BACK over the trailing hip (the opposite sign to
  the crouch's lean, which is the first thing to check if it ever starts reading as a squat again).
  Symmetric legs are a crouch, whatever else is done to them.
  **THE LEAD LEG HAS TO BE NEARLY HORIZONTAL, AND THAT IS ARITHMETIC.** The hips sit at
  `LEG * cos(trail_hip)` above the ground — barely a quarter of a leg — and a straight leg reaches
  almost a whole one, so at the 34 degrees it was first written with the lead boot finished **368 mm
  through the floor**. For the foot to clear, the lead hip must open FURTHER than the trailing one, not
  less; which is also what a slide looks like.
  **AND `CROUCH_HIP_DROP`'S DERIVATION IS EXACT ONLY NEAR THE CROUCH'S OWN ANGLE.** It assumes thigh and
  shin are equal and they are not, so it lands at 0.00 mm for 55 degrees (what it was calibrated
  against) and drifts ~2.7 mm of foot per degree past that — at 74 degrees the trailing boot was 14.7 mm
  under the floor. The angle was solved by MEASUREMENT (`tests/guard_pose.tscn`, where 0.00 mm is the
  pass mark) rather than by trusting the closed form.
- **BOTS DO NOT SLIDE**, and `Locomotion.tick`'s `sliding` argument defaults false so they cannot
  accidentally be given one. It is a deliberate scope line rather than an oversight: a slide is only
  worth anything as a decision about WHEN, and an AI that slid on a timer would be a body throwing
  itself on the floor at random. Giving them one means answering when a bot should commit, which is a
  behaviour question and not an animation one.
- **CROUCH IS A TOGGLE, NOT A HOLD** (`Player._toggle_crouch_input`, `_crouched`). It lives on R3
  — you press the stick you are steering with — and crouch is a STANCE you fight from, not a
  momentary action like aiming; the AI already treats it that way (`Bot._update_post` holds it
  for `POST_TIME`). Three things stand you up, all of them the opposite decision: jumping,
  breaking into a sprint, and deploying a fresh body. **Everything that asks "is this body
  crouched" goes through `_crouch_held()`**, so the stance, the spread and recoil multipliers,
  the capsule and the animation cannot disagree.
- **`kick_back` cannot just be added to `velocity`** — movement rewrites `velocity.x/z` from
  the stick every frame — so it rides alongside as its own decaying `_kick_vel`, like
  `_unstick_push`. Flattened to horizontal on purpose: firing at the floor should stagger
  you, not launch you. **Same trap for the cable vault, the Force shove and anything else
  that adds velocity to a body that writes its own.**
- **Stance drives spread** (`Weapon.stance_spread_mult`, set by
  `Player._update_stance_spread`, multiplied into `current_spread_deg`): >1 moving, higher
  airborne, <1 crouched. The HUD bloom crosshair reads the same value so the penalty is
  legible. A scope's 0 stays 0. Bots leave it at 1 (they have their own aim-error model).
  Crouch also drops kick via `CROUCH_RECOIL_MULT`.
- **AIMING IS PINPOINT — every gun, every sight, every stance.** It was the SCOPE's promise
  alone and everything else kept a small ADS cone, so aiming an iron-sighted rifle still threw
  rounds inside a cone you could watch the reticle draw. What a sight picture tells a player is
  "the round goes there"; a gun that answers "roughly there" reads as the game cheating, and no
  amount of tuning the number fixes the disagreement — **the eye believes the sight picture**,
  which is the same argument that made the viewmodel's kick DERIVED from the camera's rather
  than authored beside it. The rule is in `current_spread_deg()` (`0.0 if aiming`), not a zeroed
  `ads_spread` column, so no profile can opt out of it. `tests/weapon_feel.tscn` checks all 96
  guns, in the worst stance, with a cone full of spray.
- **WHAT AIMING STILL COSTS**, since the cone is no longer part of it: you move slower
  (`ADS_SPEED_MULT`), you cannot aim at a run, coming out of a sprint takes the weapon's own
  handling time — and RECOIL is untouched, so a held trigger still walks off the target. Hip
  fire keeps its bloom, its stance multipliers and the grip mods that tighten it. A SCOPE now
  buys magnification and a clean sight picture rather than accuracy nobody else has.
- **AND THE RETICLE SAYS SO: aimed, it is a point and nothing else** (`Main._draw_bloom`
  returns early while `aiming`). Ticks around a zero cone are drawing a spread the gun does not
  have, and at the minimum radius they sat as four marks around the sight bead — which reads as
  exactly the bloom that was just removed.
- **`aimed_spread_deg()` IS DELIBERATELY NOT ZEROED WITH IT.** It is the AI's model of the gun:
  `Bot._hit_reach` derives every stand-off from the tier's wobble plus that cone, so zeroing it
  moves every ADS-capable bot's fighting range outward and collapses the difference between a
  scoped rifle and an iron-sighted one. `tests/bot_range.tscn` caught precisely that. A rule
  about what a PLAYER is promised must not turn into an AI rebalance as a side effect — two
  changes, one of them unasked for and invisible.
- **You cannot ADS while RUNNING** (`Player._is_running`: sprint held, not crouched, stick
  pushed). Standing still holding sprint still lets you aim.
- **HANDLING IS ONE NUMBER PER GUN AND IT IS THE OTHER HALF OF WHAT A WEAPON COSTS**
  (`Weapon.handling`, **no key means 1.0** — the DC-15, which everything else in that table is
  already read against). Every column in `PROFILES` was a statement about what a ROUND does —
  damage, reach, cone, heat, kick — and nothing said what the weapon is like to CARRY, so a
  Gauss Cannon came to the eye exactly as fast as a holdout pistol. That is how a catalogue can
  be spread across every ballistic axis and still have all sixty guns feel like one gun.
  Measured (`tests/recoil_feel.tscn`): **0.136 s to the eye on a holdout against 0.350 s on the
  Gauss Cannon, and 0.133 s out of a sprint against 0.333 s** — a 2.6× spread the test asserts,
  because a handling column every gun shares is a column nobody notices. Deliberately NOT
  derived from damage or a weight proxy: a derivation right for forty guns and wrong for twenty
  hides the twenty.
- **THE ZOOM AND THE SIGHT ARE EASED OVER THE SAME DURATION** (`Player.ads_time()`, `_ads_t`,
  and `Viewmodel`'s own `_aim_t` off the same `handling`). They used to be a RATE (14/s on the
  camera) and a DURATION (0.12 s on the viewmodel), authored separately — so the world finished
  magnifying at one moment and the sight arrived at another. That is felt as mush rather than
  seen as a fault, and it is why a fast ADS could still feel slow.
- **THE SPRINT-OUT GATES THE TRIGGER** (`Player._update_stow` / `weapon_ready`). The weapon was
  already stowed across the chest while running, but the trigger cancelled it instantly, so
  sprinting cost nothing — you could be at a full run and firing on the same frame. Coming out
  of a sprint now takes the WEAPON's time and the trigger does nothing until it is up, which is
  what makes running somewhere a commitment you can be caught inside. **Player owns the timer,
  not the viewmodel**, because it decides whether the trigger works and that is a physics
  answer; the viewmodel is HANDED the amount (`Weapon.set_sprint_amount`) rather than running a
  second clock, since two timers is how the gun on screen and the gun in the rules come to
  disagree about whether you can shoot. A Bot has no Player pushing it and keeps its own ease.
- **AIMING COSTS YOU GROUND** (`ADS_SPEED_MULT`). Without a price on it, ADS is strictly better
  than hip fire in every situation — which removes a decision rather than adding an option.
- **FLINCH: BEING SHOT MOVES YOUR AIM** (`Player._flinch`). Taking a round was the last thing in
  the game with no physical answer — a flash and a number, with the body holding the rifle not
  reacting at all, so a duel was settled purely by who fired first at no cost to being second.
  It rides the SAME `_recoil_pitch`/`_recoil_yaw` the gun's kick uses, so it settles at
  `RECOIL_RECOVER`, scales with crouch, and needs no second recovery rule. **Randomised on
  purpose** — a round arriving is not a pattern you can learn, which is exactly why the GUN's
  pattern is not random.
- **THE GAME HAD NO FOOTSTEPS AT ALL, and silence is the loudest thing that can be missing from a
  shooter** (`Locomotion._tick_steps`, `Sfx._footstep` / `_land`). A body that crosses a room without a
  sound has no weight however good the animation on it is — and it costs more than feel: hearing
  somebody come round a corner is how half of every firefight starts, and without it the only warning
  anybody ever got was being shot.
  **IT LIVES IN `Locomotion` FOR THE REASON THAT MODULE EXISTS.** Player and Bot share no base class, so
  anywhere else is two copies of one rule — and the cadence has to agree with the CLIP, which is the
  thing that file already owns. Bots get footsteps for free, and that is not a side effect: the AI
  making noise is most of the value.
  **DRIVEN BY DISTANCE TRAVELLED, OFF THE SAME `STRIDE` TABLE THE CLIP IS PACED BY**, two footfalls per
  cycle. That is what makes a footfall land on a footfall: a timer drifts against the legs the moment
  speed changes, which is constantly, and the clip's playback position would break the moment a clip was
  retimed. Sharing `rate_for`'s own table means the sound and the legs cannot disagree by construction —
  and it is why sprinting steps faster with no extra code. Measured (`tests/movement_feel.gd`): a walk
  fires 0.87 steps per metre against the 0.77 its 2.6 m stride implies, a run 0.50 against 0.40.
  **PER METRE, WALK AND RUN MUST NOT MATCH** — a sprinting body takes LONGER strides, so it covers more
  ground per footfall, which is what running is; an earlier version of the test asserted they should be
  equal and was wrong about the world rather than about the code.
  **CROUCHING IS QUIETER AND SPRINTING IS LOUDER** (`STEP_CROUCH_DB` / `STEP_SPRINT_DB`), which turns a
  stance into a tactic for free: the crouch already costs speed and buys accuracy and a smaller profile,
  and this is a fourth thing it buys.
  **BOOTS DO NOT CARRY AS FAR AS GUNFIRE** (`STEP_HEARING` 26 m, against `Audio.HEARING`'s 90). Honest,
  and also what stops a hundred bodies at a walk drowning the voice pool — hence `Audio.play_at` gaining
  a `max_range`.
- **AN EXPLOSION IS FELT, AND IT MAY NOT SPOIL YOUR AIM** (`Player.add_shake`, broadcast from
  `Blast._shake_nearby`). The world used to have no physical effect on the view at all: a rocket could
  detonate at your feet, a mortar could land beside you, and the only things that ever moved the camera
  were your own gun and your own legs. It is raised in `Blast.pop` because that is the ONE place every
  explosion goes through, so rockets, grenades, mortars, the orbital barrage and a signature's entry all
  shake the screen without any of them knowing screen shake exists. It reaches further than the damage
  does (`SHAKE_RANGE`), because being close enough to be hurt and close enough to be rattled are
  different distances.
  **IT RIDES `remote_cam` AND NOT THE HEAD.** The weapon is a child of the head, so shake applied there
  would move the SHOTS — and a shake that spoils your aim is not an effect, it is an input bug. The
  RemoteTransform3D copies its own transform onto the camera, so offsetting it moves what you SEE and
  nothing else. Same mechanism the chase camera uses.
  **MOSTLY ROLL, BECAUSE ROLL IS THE ONE BORESIGHT-NEUTRAL AXIS** — rotating about the view axis cannot
  move where the centre of the screen points, where yaw or pitch would put the reticle and the barrel on
  different lines. That is the LAAT ball turret's fault, and it is not worth reintroducing for an
  effect. Measured at full trauma: the camera displaces 0.075 and **the gun moves 0.000 degrees**.
  Trauma is SQUARED on the way out, so a big hit reads as violently different rather than merely larger,
  and it decays linearly so it always ENDS.
- **THE LANDING DIP** (`Player._update_landing`, `LAND_DIP_*`). A body that drops four metres and
  carries on at eye level is the most weightless thing a first-person camera can do. It goes on
  `head.position.y` and never on the pitch — a landing bends your knees, it does not tip your
  head back — composed on top of the crouch's own head height. Note the trap: `velocity.y` is
  already zeroed by `move_and_slide` on the landing frame, so the impact speed has to be the one
  carried IN from the frame before.
- **Sights are one slot with ALTERNATIVES** (`Loadout.Sight`), not stackable toggles: iron,
  RED DOT (`has_reddot()`, also sets `holo` to share the no-blackout path), holo ring, SCOPE
  and 4X (differing only in `zoom_fov`), and the Trandoshan's thermal holo. Fitting any one
  CLEARS the others, because `has_scope()` is what grants pinpoint accuracy — the reticle
  drawn and the accuracy dealt must never disagree.
- **The two grip attachments are split by what they touch**: IMPROVED GRIP is HIP-FIRE
  ACCURACY only (`GRIP_SPREAD_MULT` on `hip_spread`), FRONT GRIP is KICK only
  (`FOREGRIP_RECOIL_MULT`).
- Spread is two INDEPENDENT rotations, so the effective corner of a cone is ~1.4× the
  `hip_spread` number. **Bloom stacks fast — reset `_bloom` between pulls** when measuring
  accuracy from a harness, or you are measuring a saturated cone.
- A gun with `pellets` fires that many rays through one cone and **pools damage per target
  before applying it** — seven `take_damage` calls would fire seven hit-ticks for one
  trigger pull and let a single pellet's headshot flag decide the whole shot.
- **DUAL WIELD changes how the gun is CARRIED, not how it shoots**, so it contributes no
  profile flags. A second Weapon node (`Head/WeaponOff`, always in the scene, hidden unless
  active): fire drives the right gun, AIM drives the left, both held fires both. ADS is
  suppressed — two guns and no sights is the trade. `dual_active()` gates it and
  `_refresh_offhand()` must be called anywhere the hands can change.
- Call `try_fire` only from physics frames.

#### Melee, the guard and Force powers

- **Melee connects on a forward ARC, not a pinpoint ray** (`Weapon._melee_strike`, used by
  any `is_melee()` weapon): nearest enemy inside `range` and `MELEE_ARC` (50°) with no wall
  between, so a blade lands at the range it fights at instead of demanding the crosshair be
  dead on a moving target. No headshots on a swing.
- **The LIGHTSABER is an ordinary hitscan with a 3.4 m `range` and a `melee` flag** — no new
  code path, it simply cannot reach. Aim does not zoom it; aim raises the GUARD
  (`Player.guard_up`), a pool paying `BLOCK_COST` per point stopped, only inside `BLOCK_ARC`
  in front, breaking at zero until it recovers past `BLOCK_RECOVER_AT` (without that
  hysteresis a pool refilling to a sliver flickers under fire).
- **The block is CONTINUOUS and never partial**: hold the button and every round in front is
  stopped OUTRIGHT until the pool is spent. Holding costs no time (it used to drain 0.14/s,
  so a guard raised early was gone before the shooting started) and a hit is never split
  between blade and chest — the shot that empties the guard is still fully stopped, the NEXT
  one hurts. Both of those made a raised guard feel randomly broken.
- **The guard has to be VISIBLE, because everything else about it is a number.** Sold three
  ways: the first-person blade comes up across the RIGHT of the frame (never over the
  crosshair — a metre of solid white would blind you exactly when you are being shot); a
  `parry()` knock-and-flare raised inside `_absorb_with_guard`, the one place that knows the
  block was paid for (same rule as the hit marker); and a third-person vertical stance.
- **The ELECTROSTAFF (`Weapon.Class.STAFF`) is the saber's mechanism with a different LOOK**
  — melee hitscan, `range` 4.3 m, `damage` 78, `melee`+`staff` flags, same guard. `staff`
  routes `viewmodel._build_staff`: a dark segmented pole on the saber's swing pivot (so the
  animation is unchanged) with a `_staff_emitter` at each end and purple lightning arcs that
  re-jag each frame (`_crackle_staff`, fixed segment pool like `lightning_arc.gd`). Arcs are
  first-person only; third-person carries static violet tips. The off-hand `_shield` is the
  BX commando-droid shield (`_build_shield`), layered by z AND `render_priority` so the
  transparent panels sort right. Reached via `Loadout.primary_override` (a Weapon.Class that
  beats the WEAPONS lookup, so a faction-only gun needs no WEAPONS row and shifts no index —
  the Super Battle Droid's wrist cannon uses the same door).
- **A melee weapon's LOOK is six profile keys** (`blade_core`, `blade_glow`, `blade_len`,
  `blade_width`, `blade_energy`, `hilt_len` — `Weapon.melee_look()`), read by BOTH viewpoints,
  so a lightsaber, an energy sword, a chainsword and a thunder hammer are one builder and
  four rows. **`blade_energy` 0 is a METAL weapon**, and metal is a LIT surface: only plasma
  is `SHADING_MODE_UNSHADED` (a lit blade goes black on its shadow side, which is where a
  glowing sword is most of the point). **Unshaded bypasses lighting but NOT the tonemap**, so
  a mid-grey steel albedo through AgX at exposure 1.6 came out a flat near-white slab at one
  value on every face — frosted glass, which is why a chainsword looked "shiny, transparent
  and glowing" at once. Steel builds as an ordinary material.
- **AN ADDITIVE AURA MAKES WHATEVER IS UNDER IT TRANSLUCENT** — right for plasma, wrong for
  everything else. So the sleeve is built ONLY around a blade that is actually light.
  `Weapon.BLADE_HEAD_WIDTH` splits a slim blade (builds as a cylinder) from a fat one (builds
  as a boxed HEAD), and **that shape split doubles as the field rule so no profile needs a
  key**: every boxed head is a power weapon and gets a CAP proud of its striking face and
  inside the head's own width; every steel cylinder is a plain length of metal and gets
  nothing.
- **FORCE LIGHTNING is the class's only ranged damage and the only power that kills.** It is
  CHANNELLED — hold and it pours for `CHANNEL_TIME`, biting every `CHANNEL_TICK` and
  re-acquiring the cone on every bite, so cover cuts the stream and following with the
  crosshair is the skill. The cooldown is charged when the channel ENDS, in proportion to
  what was spent. A Bot has to channel too (`_channel_left`/`_zap_once`) or its lightning is a
  single scratch. Each bite arcs to the bodies nearest THAT target, not the caster, so it
  punishes a bunched group: `BOLT_CHAINS` jumps of `BOLT_CHAIN_RANGE`, each at
  `BOLT_CHAIN_FALLOFF` and each re-checking sight from the previous victim. **The jump range
  decides whether it reads as chain lightning at all** — 7 m only caught enemies practically
  touching; 9 m is what makes the chain visible.
- **A combatant's origin is at its FEET, so any line traced between two grazes the ground and
  reports cover that is not there.** `ForcePowers` lifts both ends (`_eye`/`_torso`); the pull
  had traced feet-to-feet since it was written, and lightning inheriting it is what found it —
  on a flat floor it hit nobody at any range.
- **Shoving somebody else is the hard part.** Both Player and Bot rewrite velocity every
  frame, so both expose `apply_impulse` and carry their own decaying shove; `ForcePowers`
  (static, shared) calls it. A turret is bolted down and correctly has no such method.
- `scripts/lightning_arc.gd` draws from a FIXED pool of segments allocated once and only
  repositioned — the obvious ImmediateMesh rebuild allocates every frame, four viewports deep.

#### Gadget slots

- **Every class has THREE gadget slots and the third is a different KIND of thing.** Slots 1
  and 2 are what you THROW or DROP — a press, an effect, a cooldown. Slot 3 (`gadget3`,
  `Row.GADGET3`) is what you PUT UP AND KEEP — cloak, barrier, overshield, fury — where the
  decision is not *when to press it* but *when to be under it*, and the cost is that it runs
  on a clock whether or not it is doing you any good.
- **Slot 3 has its OWN catalogue** (`KITS["sustain"]`), not a filtered view: nothing in
  `gadgets` can reach it and nothing in `sustain` can reach slots 1–2 — `kit_rules` asserts
  both directions, because a barrier fittable in both would put one ability on two buttons.
  Every class has at least one thing to put up; an empty third slot is a class that was
  forgotten, not one that chose nothing.
- Controls: slot 0 = `gadget` (pad X), slot 1 = `grenade` (keyboard G, pad LB), slot 2 =
  `sustain` (keyboard R, pad Y). If slot 1 is empty and the kit `can_dash`, that control is
  the dash; slot 3 has no such fallback. **Anything reading a gadget must ask ALL THREE**
  (`Player.has_gadget` / `slot_of`).
- **THE PAD FACE BUTTONS MOVED, all three.** A sustained ability earns a face button rather
  than a chord, so it took Y; **weapon swap moved to B**; crouch moved off B onto **R3**.
- **Grenades are GADGETS, not a counted consumable** (`Gadget.GRENADE_FRAG/STICKY/SMOKE`,
  mapped by `Loadout.GRENADE_GADGETS`): you fit one in a slot and the recharge IS the ammo.
  FRAG bounces and splashes; STICKY collides with BODIES too (mask 3, not 1) and rides
  whoever it stuck to (never `_thrower`); SMOKE leaves a sightblocking cloud.
- **A GRENADE IS A SMALL FAST SPHERE, WHICH IS THE ONE SHAPE PHYSICS LOSES.** At 22 m/s a 0.11 m
  ball covers 0.37 m in a 60 Hz tick — three times its own diameter — so with discrete collision it
  starts a step above the ground and finishes below it, having touched no triangle. That is
  "grenades fall through the floor", and **it got worse the moment the throw got stronger**: the fix
  for reach made the other fault more likely. `continuous_cd` is the fix; `_keep_above_the_floor`
  (the map's own `height_at`, past a slack the resting case needs) is the backstop, and in testing it
  never has to fire. **A box floor cannot reproduce any of this** — the real ground is one
  `ConcavePolygonShape3D` skin, and `tests/grenade_throw.tscn` builds a trimesh heightfield for that
  reason, having first passed with both defences removed while it used boxes.
- **HOW IT FLIES AND HOW IT SETTLES ARE SEPARATE, and the damping is applied on FIRST CONTACT.**
  Damping the throw would make a strong throw impossible; damping the landing is what stops a grenade
  trickling down a slope away from where it was aimed. Contact monitoring is on for every type now,
  not just the sticky — a frag needs to know it has landed even though it does not stick. Launch spin
  came down from +/-8 rad/s to 3.5: a hard-spinning sphere turns that straight into travel the moment
  it touches friction. Measured on a 14-degree slope: worst roll 2.64 m before, 1.57 m after.
- **The throw is 22 m/s, not 13** (`Player.GRENADE_THROW_SPEED`), which is ~24 m of carry instead of
  ~14 — the old one could not reach the cover you were shooting at on any of the big maps. `GRENADE_LOB`
  is a SHARE of the throw, not a fixed rise, so the arc keeps its shape when the speed changes.
- **Smoke blocks sight without a collider** — a collider would stop bullets and bodies too.
  `smoke_cloud.gd` registers with `GameState.smokes` and every AI vision check calls
  `GameState.sight_blocked()`, a segment-vs-sphere test clamped to the segment so a cloud
  behind the viewer or past the target doesn't count.
- **The CLOAK is invisibility to AI, a shimmer to humans.** `GameState.cloaked` is a set every
  AI vision check skips; the model fades via `CharacterModel.set_cloak` (safe because each
  character owns its own materials). It BREAKS on firing (the drop lives in
  `_on_weapon_fired`, which the wrist rocket routes through), times out, and is cleared on
  death. **`_end_cloak` must guard on the cloaked STATE, not on `_cloak_left`** — the natural
  time-out decrements to zero and *then* calls it, so guarding on the timer made the cleanup
  skip itself and leave a permanent ghost in `GameState.cloaked` no AI could ever see.
- **OVERSHIELD** is a second health pool taking damage FIRST that does not regenerate — spent,
  not worn down, so it buys a fixed number of rounds rather than a percentage. **FURY**
  (aliased by RED THIRST and WAAAGH!) is speed, resistance and a heavier swing at once — one
  buff rather than three gadgets, because a player has to be able to say what a button does in
  four words. Neither suppresses the hit marker or damage flash: the shooter is still landing
  shots and both of you should be told. **BIOFOAM** is the only instant heal since the medkits
  went, priced as a long cooldown rather than a big number so it can never out-sustain
  somebody actually shooting you. **DEFLECTOR** is a bigger pool than the overshield over a
  shorter window and it LOCKS THE TRIGGER — one buys you rounds, the other a reposition.
- **The SCAN DART (`Gadget.SCAN_DART`, `scan_dart.gd`) is a team-wide, wall-piercing reveal**:
  flies like the rocket, STICKS on impact, and every `SCAN_INTERVAL` marks enemies within
  `SCAN_RADIUS` into `GameState.scanned` for the thrower's team. `Main._draw_scan` boxes them
  THROUGH walls — no line-of-sight check, a scan is a ping. Cleared on death/respawn via
  `unregister_combatant` and `reset_match`.
- **The thermal read is a per-viewport HUD overlay** (`Main._draw_thermal`), drawn only while
  that player aims a `has_thermal()` sight, so it is a scope they look through and never a
  shared tracker. Gated on a WORLD-layer raycast (mask 1): a wall blocks it, smoke has no
  collider so a cloud does not — which is what makes it see through the class's own smoke.
- **The MANDALORIAN's WRIST ROCKET reuses the RPG's projectile whole** (`rocket.gd` already
  flies, arms, splashes and credits its shooter), so it is a launch site and three numbers. It
  launches from the HEAD, not the weapon anchor, so it fires at the crosshair without lowering
  whatever gun is in hand, started 0.6 m ahead to clear the shooter's own capsule. Weaker than
  the RPG on purpose: a 7 s-cooldown gadget must not out-damage a 110-token primary.
- **Jetpack gotcha**: pure acceleration never leaves the ground, because `move_and_slide`
  re-zeroes vertical velocity while on the floor — takeoff needs an instant `JET_KICK` on the
  first thrust frame. **Push a readout on BOTH the burn and the refill path** — it refilled on
  the ground and never told the HUD, which reads exactly like a pack that does not recharge.
- **The wrist cable** ends its pull with a ballistic vault (`_begin_vault`): rise is solved
  from the anchor height so it scales to what you grappled, and it holds your heading for
  `CABLE_VAULT_TIME`. The wire (`cable_wire.gd`) is cosmetic — Player owns the timing and
  passes the same flight time so the yank lands on the frame the claw bites. Two details: the
  line starts a little AHEAD of the weapon (its origin sits at the owner's camera, so a line
  from there is blown up by perspective into a white wedge across their view) and its material
  is unshaded (a thin lit line goes black on its shadow side and vanishes on dark maps).
- **The front shield sits on physics layer 4 alone** — on the world layer it would shove its
  owner, on the player layer everyone would walk into it; layer 4 is in nobody's movement
  mask, so it only intercepts rays. Shooting *through your own* shield works via
  `Player.hitscan_exclusions()`, honoured by `Weapon._fire_hitscan`.

#### Aim assist and the torso twist

- **Aim assist only ever changes where the VIEW points** (`Player._assist_*`) — slowdown near
  a target plus a nudge — and never bends a shot. The nudge is gated on stick input: assist
  that keeps working while you hold still is an aimbot. Strength is PER PLAYER
  (`Controls.aim_assist_strength`, cached as `_assist_mult`, refreshed by `refresh_settings()`);
  0 turns it off for that one player even while the match has it on.
- **The upper body turns before the feet do** (`Player._update_torso_twist`,
  `CharacterModel.set_twist`). A `CharacterBody3D` yawing under a look input turns the whole
  body, so panning while standing still pirouettes the model. The legs keep a heading of their
  own (`_feet_yaw`) that the aim may lead by `TWIST_MAX`; the MODEL is counter-rotated back
  onto the feet and the model's twist joint puts the chest back on the aim. Moving, airborne
  or crouched, the feet catch up fast — a twist held through a walk cycle reads as a broken
  hip. `rotation.y` is still the body's true facing.
- **The twist lives on its OWN joint (`Hips/Twist/Spine`), which no clip ever names.** On the
  Spine it would fight the AnimationPlayer, which rewrites every joint in `PATHS` every frame.
  A joint the clips never touch needs no process-ordering rule. **Note this changed every path
  in `PATHS`** — anything reaching for `"Hips/Spine/..."` by string breaks; go through
  `CharacterModel.PATHS`.
- **THE WRISTS AND ANKLES ARE JOINTS, AND THAT IS THE FIX FOR "CHUNKY".** A limb that bends in
  exactly one place reads as a mannequin however good the mesh on it is, and the two worst offenders
  were the two ends: the boot turned rigidly with the shin, so every stride pointed the toe and a
  deep crouch stood the whole unit on its heels; the hand was a block on the end of the forearm, so
  bending the elbow rolled the grip off the weapon. **They cost nothing to add and that is the
  point** — both sit at exactly the position the boot and hand boxes already occupied, so NO
  GEOMETRY MOVED, and a pose that does not name a joint leaves it at rest, so every existing clip
  kept working the moment they appeared and each opted in on its own terms. 11 animated joints → 15.
- **The ankle CANCELS what the hip and knee did** (`_ankle`, one line, because composing about X all
  the way down means the foot's pitch is just the sum above it). Total while crouched (a squat is
  stood on flat feet), partial while striding plus a toe-off (a real foot rolls off, and a fully
  levelled one reads as sliding), least in the air. The wrist does the same to the elbow
  (`WRIST_FOLLOW`), read off the IK solve rather than posed — a hand-set wrist angle is right for one
  gun position and wrong for the guard, the run carry and every unit with different arm lengths.
- **Measured (A/B, 24 bodies, headless): the animation tick costs 0.001 ms across all of them** —
  the four extra joints are free. `tests/rig_cost.tscn` reports it as the DIFFERENCE between playing
  and paused, because the first version timed whole frames and came back with 6.8 ms, which is true
  and says nothing.

### The character model

`scripts/character.gd` (`class_name CharacterModel`) — a fully procedural box humanoid on
Node3D joints with idle/walk/run/jump/crouch animations built in code. `scripts/trooper.gd`
extends it for decorative NPCs.

- **Each unit is its OWN model.** `STYLES` (keyed by `Style`) gives every unit a colour
  scheme, a HEAD shape, a bulk multiplier and accessories. The SKELETON (`_joint_offsets`, the
  retired trooper's bone proportions kept as constants) and every animation are SHARED, so a
  new look is a table row. `set_style(id)` frees the `Hips` subtree and rebuilds in place; the
  sibling AnimationPlayer and its joint-name tracks re-bind.
- **A style has THREE colours, not two** (`armor` / `dark` / `accent`, plus the team accent).
  Two tones was enough for a trooper in one palette; a Spartan's gold visor, a Necron's green
  light and an ork's bare scrap are none of those and were all being painted in the body
  colour. `accent` defaults to `dark`, so a style with nothing to say says nothing.
- **The class colours are the BODY; `set_team_color` rides the ACCENTS** (`_suit_mat`:
  shoulder bells, chest vest, belt, knee pads, helmet crest) — so a unit reads as armour with
  team markings and still calls its side at a glance. `Loadout.character_style()` picks it: a
  faction build sets an explicit `style`, everything else reads the `"style"` key off its KIT
  row (a table lookup, not a match on the enum — a match statement is every class written a
  second time).
- **Plate armour is one COLOUR at several VALUES.** `_build_body` mixes `armor` / `armor_hi` /
  `armor_lo` via `_shade` (an HSV value+saturation shift — a highlight is a *paler* red, not
  just a brighter one). Sky-facing pieces take `armor_hi`, hanging and back-mounted ones
  `armor_lo`. Deliberately three shared materials and not a per-part tint: forty materials a
  character across twelve characters is exactly the allocation rule this project cares most
  about, and the eye reads the BREAK between panels anyway.
- **A surface's FINISH is most of what tells two materials apart** (`Finish` — PLATE / CLOTH /
  METAL / HIDE). Everything used to come back at metallic 0 / roughness 0.75, so ceramic plate,
  a rubber undersuit and a gun barrel caught light identically and a model read as one moulded
  piece. **All four are dielectrics** (house rule 12): `roughness` decides how tight the
  highlight is and `specular` how strong. METAL is the sharpest — brushed steel, not a mirror.
  Every finish also carries `rim`, a fresnel that brightens a surface as it turns away, which
  went in as a stand-in for a CHAMFER. **The parts are genuinely chamfered now, so rim is down
  to a whisper (0.05–0.14)** — it is the same edge paid for twice, and a bright edge all the
  way round a part is itself a translucency cue.
- **THE HELMET IS THE UNIT**, and for a long time Star Wars did not have one: twelve styles
  shared a generic `"helmet"` while every other universe got its own head the moment it landed.
  They are nine heads now (`clone` T-visor and keel, `commando` lit band and rangefinder,
  `stormtrooper` brow/lenses/raised nose/frown, `shoretrooper` centre keel and wide neck guard,
  `scout` wraparound goggle, `deathtrooper` flat visor and red lenses, `rebel` bowl over a
  visible face, `pilot` visor block and oxygen mask, `cap` peaked officer's cap, `royalguard`
  one vertical slit). **Cost is materials, not boxes** — `_merge_parts` collapses every box on
  a joint sharing a material into one mesh — so a head is as detailed as it likes provided it
  reuses `armor`/`dark`/`_suit_mat` and adds at most one of its own.
- **A head kind with no `match` case falls through to the BARE face and says nothing.**
  `GEONOSIAN`, `EWOK` and `JACKAL` all asked for `"muzzle"`, which `_build_head` never had —
  three units shipped with a generic head and no error anywhere. There is no other check.
- **Silhouette accessories are what separate the factions, not colour**: `bigpauldron`
  (Astartes shoulders standing clear of the arm and above the collar — the generic `pauldron`
  sits flush and merges into the torso, which is why a marine was a rectangle), `powerpack`,
  `aquila`, `tank` (the Unggoy methane bottle, bigger than the body carrying it), `ribs`,
  `scrap` and `shoulderplate` (ork armour, deliberately ASYMMETRIC — a matched pair reads as
  issued kit, which orks do not have), `collar`, `gauntlet`, `greaves`, `thighplate`. Two
  calibrations: an accent cap on a pauldron must be a TRIM (0.03) not a lid (0.05) or the
  shoulder reads as a gold-topped crate; and a chest plate must stand PROUD of the team vest,
  not level with it, or the two are coplanar and the chest is one flat inset panel.
- **Armour on the limbs is what stops a heavy unit reading top-heavy** — a slab chest on bare
  pipe-cleaner legs looks wrong however good the torso is.
- **A SMALL PART IS NOT WORTH DRAWING FROM ACROSS THE MAP** (`DETAIL_SMALL`/`DETAIL_MEDIUM`,
  set in `_box`). A unit is thirty-odd meshes drawn four times plus a shadow pass, and most are
  trim and pouches a pixel wide past forty metres. `visibility_range_end` is the engine doing
  this **per camera and for free** — exactly right for split screen, since the same body keeps
  its detail beside its own player and loses it in the other three. **Limbs and heads go
  through `_limb`/`_build_head` and are never culled** — the silhouette that says which unit
  that is stays.
- **`CharacterModel` REMEMBERS its render layer (`set_render_layers`)** rather than being
  stamped from outside once: it rebuilds on a style change and a melee swap, and fresh
  `MeshInstance3D`s default to the shared layer, so a player who stamped at spawn saw its own
  third-person blade hanging in front of its camera. Player must re-stamp after a rebuild
  (`_stamp_model_layers`). Same trap one node out as `Viewmodel.view_layer`.
- **`set_melee(on, staff)` swaps the held blaster for a lit blade on the same `HeldGun`
  joint**, so the solved carry/guard IK is unchanged. Player calls it from `_announce_hand`
  (every swap, not just deploy), Bot from `setup`. Before it, a Force adept charging you looked
  like a trooper standing oddly.

#### The rig, the carry and the poses

- **Every body part is a procedural box hung on a joint** (`_build_body` → `_limb`/`_box`/
  `_build_head`). `_limb(joint, to, ...)` spans a box from a joint to its child joint in local
  space, so a limb always reaches the next joint however the skeleton is proportioned.
- Three things the rig has to get right, all found by looking: joints must sit at the model's
  OWN bone positions rather than nominal vertical limb lengths, or every piece hangs offset
  from the geometry it was cut from and the seams tear into spikes; T-pose arms need a quarter
  turn baked into the MESH and never into the joint, since rotating the joint rotates the axis
  the clips animate about; and triangles that BRIDGE an arm and the torso must be dropped.
  **Filtering bridges by edge length is the obvious approach and is wrong** — the model is
  low-poly enough that real body triangles are as long as the bridges, and it deletes the legs.
- **Re-proportioning the rig costs the animation NOTHING** — every clip is a set of joint
  rotations, so changing a limb's length leaves the motion identical. That is why it was right
  over stretching the mesh.
- **The carry pose is SOLVED onto the gun, not dialled in** (`_carry` + `_arm_ik`). Two-bone IK
  puts both hands on grip points derived from `GUN_POS`, so the hold survives any change to arm
  lengths or weapon position. Hand-tuned shoulder angles only ever hold for one set of
  proportions.
- **The arm does NOT hang along -Y, and `_arm_ik` has to be told so.** The skeleton's elbow
  offset is tilted ~13° back off vertical and `_build_body` runs the forearm along it. The
  solver used to assume a straight-down arm of length `UPPER_ARM` off `(±SHOULDER_X, SHOULDER_Y,
  0)` — three lies about the rig (direction, true bone length, the shoulder's 4 cm z offset) —
  and left every hand 8–14 cm off its grip. **The tell is the SHOULDERS**: the whole chain
  rotates to plant a hand that is not where the solver thinks it is. `_arm_ik` now takes the
  elbow OFFSET (carrying both length and rest direction) and takes the law of cosines about it —
  only the part perpendicular to the elbow's +X axis swings, hence the `rest.x²` term.
- **A pose test must probe where the MESH is, not where the solver thinks it is.**
  `guard_pose.tscn` read each hand as `elbow.global_transform * Vector3(0, -reach, 0)` — the
  same straight-down assumption — so it asked the solver its own question and got 0.0 mm back
  while the hands hung 14 cm off. It probes along the rig's own bone directions now.
- **`_carry()` hands out a COPY of its cached pose.** Every caller mutates what it gets back,
  so returning the cache let `_crouch_base` write its shoulder angles into it and permanently
  clobber the hold for every clip built afterwards.
- **`_carry()` carries the WEAPON's transform, not just the arms.** `_clip` keys the gun joint
  from the pose, so a pose that did not name the gun keyed it back to the origin unrotated —
  putting the weapon in the middle of the chest on every frame of every clip.
- **A rifle is carried on the RIGHT SHOULDER** (`GUN_POS`/`GUN_ROT`), not flat across the chest
  — the old centred pose put the receiver on the sternum and both arms in a symmetric hug, the
  most toy-like thing about the model. **Tune it against the ARM EXTENSION the solve returns**,
  not by eye: at x 0.10 / z -0.235 the left arm came out at 94% of its length, and a two-bone IK
  at 94% is a straight arm that drags the shoulder up and gives every unit a hunch. Drawn in and
  yawed across, left sits ~86% (bent elbow) and right ~52% (tucked at the trigger).
- **The RUN clip carries the weapon ACROSS THE CHEST** (`RUN_GUN_POS`/`RUN_GUN_ROT`). Nobody
  sprints with a rifle in the aim. **The big number is the YAW** — at the standing 20° a running
  figure still reads as aiming, and only past ~55° does it read as stowed. It goes through
  `_hold` like every other pose, so both hands stay on the grips: arms swinging free beside a
  floating gun is worse than no sprint carry at all.
- **The sprint carry shows in FIRST PERSON too** (`Viewmodel.sprinting`, set by Player through
  `Weapon.set_sprinting`) — everyone else could see a sprinting player lower their gun and the
  only person who could not was the one doing it. A first-person camera sits 30 cm from the
  receiver, so it drops the weapon out of the sight line rather than swinging it 62°. It rides
  ON TOP of the bob, ADS slide and recoil. **The trigger cancels it, easing back twice as fast
  as it eases in** — the weapon must be up by the time you can shoot. A blade ignores it.
- **THERE IS ONE ANIMATION MODULE AND BOTH BODIES GO THROUGH IT** (`scripts/locomotion.gd`,
  `class_name Locomotion`, one object per body). Player and Bot are duck-typed and share no base
  class (house rule 15), so each carried its OWN copy of the state machine, the direction rule,
  the blend time and the stride table — the same magic numbers written out twice. **They had
  already drifted**: the player paced `crouch_walk` and `guard_walk` off their own strides and the
  bot's copy had neither case. Neither was wrong *yet*, which is the shape of the fault. It is a
  RefCounted and not a static module because the lean and the swivel carry STATE between frames,
  and a static helper would push that back into the two callers it exists to unify.
- **A BODY DOES NOT WALK SIDEWAYS — IT TURNS ITS HIPS AND WALKS** (`Locomotion.swivel_for`). The
  legs swivel to the direction of travel up to a RIGHT ANGLE and play the ordinary forward stride;
  past that the hip runs out, so the remaining 180° behind the body is the BACKWARD walk with the
  legs at the MIRROR of the travel direction — backing away to your right is hips turned a little
  LEFT and a backpedal, which is what it is in life. It replaces the dedicated sidestep clips.
  **The boundary needs hysteresis** (`SWIVEL_MARGIN`): at exactly sideways both answers are valid
  and they are 180° APART, so without a sticky crossing a body strafing that line flips its legs
  end over end on stick noise. **And the clamp is SEPARATE from the hysteresis** — inside the
  margin the travel angle runs past the right angle, and the legs followed it to 107°, found by
  SWEEPING a full circle of travel rather than by checking the eight cases, every one of which
  sits comfortably inside the band.
- **THE FEET, THE SWIVEL AND THE TWIST ARE ONE JOINT AND SO ONE OWNER.** `feet_yaw` and the
  counter-rotation moved out of Player into the module, because the hip swivel and the torso twist
  write the same transform and two rules on one transform in two files is a fight nobody wins. It
  is also how a BOT got the behaviour at all — one used to turn its whole body, chest and gun, to
  circle a target.
- **THE BODY LEANS INTO A CHANGE OF SPEED** (`Locomotion._tick_lean`), driven by ACCELERATION and
  not velocity: leaning is what a body does while it changes pace, so a sprint held steady stands
  upright and it is the first two steps and the stop that do not. It is written to the model's
  TWIST joint — **the one joint no clip ever names**, the same reason the torso twist lives there
  — so the AnimationPlayer cannot erase it. `set_twist` owns that joint's Y and the lean owns its
  X and Z, so the two compose. Upper body only: the legs are striding and a full-body lean from
  the root would take the feet off the floor on every direction change.
- **A TRANSITION IS NOT ONE NUMBER** (`BLEND` / `BLEND_TO_IDLE` / `BLEND_AIRBORNE`). Everything
  used to blend over a flat 0.12 s, but a body does not start and stop symmetrically: coming to a
  halt is a settle that takes longer than breaking into a stride, and leaving the ground is an
  EVENT that should not ease at all.
- **THE CLIP IS CHOSEN BY DIRECTION, NOT BY SPEED** (`Locomotion.clip_for`).
  The state machine read the MAGNITUDE of the move input and ignored its direction, so every body
  in the game side-stepped and backpedalled under a full forward stride — feet going one way and
  the body another, permanently, on everything on the field. It matters more for a BOT than for a
  player: circling is half of what `_update_post` does, so a bot in contact is sideways most of
  the time. Bot works in WORLD velocity and has to bring it into the body's frame first.
- **THE BACKPEDAL IS NOT THE WALK PLAYED BACKWARDS.** Reversing a clip reverses the KNEE, and a
  knee that leads the shin forward is the one thing a leg cannot do — it reads instantly as broken
  rather than as reversed. What actually changes is the stride SHORTENS, the knee lifts MORE, and
  the toe-off disappears (there is nothing behind you to push off). **A SIDESTEP IS A ROLL IN THE
  FRONTAL PLANE** (about Z, not X) with both hips sharing a phase rather than half a cycle apart,
  the trailing leg tucking to clear as it closes. `_strafe_pose` takes a `dir` and serves both
  sides, because a sidestep is genuinely symmetric.
- **FORWARD WINS TIES, WIDE** (`STRAFE_RATIO` 2.0, not a 45-degree split). Walking forward at a
  slight angle is the commonest input in the game, and a body that flips into a sidestep whenever
  the stick drifts off centre is WORSE than one that never sidesteps: the flicker reads as a bug
  where the wrong clip merely reads as stiff.
- **A directional clip has to be photographed FRONT-ON and SIDE BY SIDE** (`locomotion_look`). A
  sidestep is a frontal-plane roll, so a three-quarter view is precisely the angle that hides it,
  and a body shot alone reads as fine in every clip — what is being judged is whether a sidestep
  reads as DIFFERENT from a stride, which is a comparison and not a picture.
- **Standing still, a body stands with its feet APART** (`_stance`, idle clip only — walk and
  run put the legs back under the body where they have to be to carry it). A splay is a roll at
  the hip, and **it must drop the hips by what the splay costs in height**
  (`STANCE_HIP_DROP = LEG * (cos θ - 1)`) or the feet hang above the floor.
- **Crouch is a posed clip pair (`crouch_idle`/`crouch_walk`), not a squashed model** — scaling
  `model.scale.y` just makes a shorter person, and a pose laid over the others would depend on
  process ordering to survive the AnimationPlayer. Two solved constraints keep the feet honest:
  `CROUCH_KNEE_DEG` is exactly twice `CROUCH_HIP_DEG`, putting the ankle under the hip; and the
  walk's knee only ever tucks FURTHER, never opens, because with a fixed knee a hip swing can
  only shorten the leg.
- **A hip drop is a fraction of the LEG, never of `HIP_Y`.** Both crouch and guard used
  `LEG * cos(angle) - HIP_Y`, silently assuming the hips sit exactly one leg off the ground —
  true of the box rig, false once it took the trooper's proportions (the pelvis is `HIP_DROP`
  above the thigh and the boot hangs below the ankle), so both poses dropped an extra 20 cm and
  the boots vanished into the floor. `CROUCH_HIP_DROP`/`GUARD_HIP_DROP` are `LEG * (cos - 1)`.
  **`tests/guard_pose.tscn`'s ankle column is what catches it.**
- **The crouch does NOT compensate the arms for the torso lean.** The gun hangs off the SPINE,
  so leaning carries the weapon and both hands as one piece; the old pose pitched the shoulders
  back by the lean angle, which now drags the hands off the gun.

#### Corpses

- **A CORPSE IS AN ARTICULATED RAGDOLL wearing the unit's own body** (`corpse.gd`): six
  segments — torso, head, two arms, two legs — thrown by whatever killed it. Six and not eleven
  because a separately hinging forearm costs twice the bodies and joints to say something
  invisible at this scale; these are the segments whose SILHOUETTE changes when a body goes down.
  Measured: 12 concurrent ragdolls (72 bodies) still holds the 60 Hz physics tick. The RENDER
  cost is identical to one rigid body — physics is simulated once however many cameras look.
- **Built by taking a FINISHED model apart** — the `CharacterModel` is built and styled as
  before, then each segment's joints are `reparent`ed onto a RigidBody3D, so every mesh, colour
  and accessory stays right and the ragdoll knows nothing about how a body is made.
  `freeze_all()` stops the lot for anything photographing the pose.
- **RESOLVE EVERY JOINT BEFORE MOVING ANY OF THEM.** The segments are NESTED — Head, ShoulderL
  and HipL are all children of Hips — so the moment the torso reparents Hips, searching for any
  of the others finds nothing. That left five of six bodies empty at the origin, still pinned to
  a torso a metre above, and the joints hauled them up: **that** is what launched corpses into
  the air, and why no limb ever articulated.
- **The joints are PIN joints, not cone-twists, deliberately.** A cone-twist is anatomically
  right and was tried first, but its limits are measured about the JOINT'S OWN AXES — which come
  from a rig where an arm carries a baked quarter turn — so limbs started outside their own cones
  and the solver spent the first frames forcing five joints back inside. A pin joint has nothing
  to violate; what it costs is anatomy, which at box-limb fidelity is a far smaller lie than a
  body launching into the sky. Angular damping is what stops it looking boneless.
- **A ragdoll starts STANDING, in the rest pose.** The old hand-authored curl is the fetal tuck
  it then falls into, and its hip drop put the leg boxes 44 cm THROUGH the floor, which the
  solver resolves by ejecting the whole body.
- **There is no upward impulse anywhere in `corpse.gd`, and masses are anatomical RATIOS.** A
  body that is shot drops; the shove only decides which way it topples. A heavy head on a light
  torso whips, and near-equal masses across a joint make the solver argue with itself.
- **A CORPSE IS THE SIZE THE UNIT WAS** (`launch`'s `stature`). The model is scaled BEFORE its
  joints are read; the rigid bodies are set from an **orthonormalized** transform with their box
  shapes scaled explicitly, because a RigidBody3D with a scaled basis scales its own collision
  shape a second time. Without it an Ewok stood up to full trooper height on landing.
- **A death nobody can see is not built at all** (`VIEW_RANGE`) and the floor holds `MAX_ALIVE`,
  oldest evicted first. A human's own death is `forced` past both: you watch that one. Anything
  spawning a corpse outside a match has to force it too, or it measures an early-out.
- **THERE ARE THREE DEATH STYLES, NOT TWO** (`Controls.death_style()` → RAGDOLL / ANIMATED /
  CLASSIC), and neither of the first two wins outright — which is why both ship. The RAGDOLL lands
  correctly on a slope, against a cover box, half over a ledge, and is thrown by whatever killed you.
  The ANIMATED fall reads more cleanly, plays the same way every time, and **knows nothing about what
  it is landing on** — on the procedural worlds, where the collision mesh already sits above the
  analytic curve, a body will sometimes end part-way into a hillside. That is the cost and it is why
  RAGDOLL is still the default. `Corpse._build_animated` keeps the finished model whole instead of
  taking it apart, which is the entire difference.
- **`OPT_DEATH_STYLE` sits ALONGSIDE the old `classic_death` boolean rather than replacing it.**
  There are real `user://controls.cfg` files with that key in them; read as an int it comes back 1
  and silently selects ANIMATED for anybody who ever turned the classic look on. `death_style()`
  migrates, `set_death_style()` writes both.
- **A CANNED FALL PIVOTS ABOUT THE EDGE IT GOES OVER, and that is four different edges**
  (`CharacterModel.DEATH_PIVOT`). Rotating the Hips alone swings the body about hip height and drives
  the head into the floor; rotating about a point between the FEET fixes that and then puts the
  down-side leg through the ground on a sideways fall, because you go over the OUTSIDE OF A FOOT, not
  over a spot between two. Measured: 26 cm of boot under the floor until the pivot moved out to 0.25 m.
- **THE RIFLE IS THE LONGEST THING ON A BODY AND IT GOES INTO THE GROUND FIRST.** The barrel reaches
  37 cm past the joint it hangs on — further than any limb — so `DEATH_GUN_SHIFT` shoves it toward
  whichever side ends up on top. Note the trap: a sideways topple rotates about Z, and **a Z rotation
  leaves the barrel (which runs along -Z) pointing exactly where it was**, so no amount of changing
  the weapon's ANGLE lifts it — only its POSITION does. Two rounds of tuning went into the arm on the
  down side, which was innocent; `tests/death_clip.tscn` prints WHICH PART is lowest for that reason.
- **A body does not tip a full ninety degrees** (`DEATH_TIP_DEG` 74). A pure quarter turn maps
  everything behind the pivot axis to negative y — the pack, the heels, the rifle — and measured 76 cm
  under the floor at its worst. Stopping short still reads as unmistakably down. Resist raising
  `DEATH_LIE_LIFT` to make the floor test pass: it hides which part is low and a body whose hips end
  half a metre up is hovering, which is the worse artefact.
- **CLASSIC DEATH** (`Controls.classic_death()`, now derived from the above): the original generic box figure
  with its arms straight out. It reads as a T-posing mannequin, which is exactly why it is worth
  keeping.

### Weapons: the viewmodel and the look

`scripts/weapon.gd` + `scripts/viewmodel.gd` — class-based blaster (ADS zoom, spread, heat) and
its animated first-person gun. `viewmodel.gd` rebuilds per class from `SHAPES`.

- **It must `remove_child` before `queue_free` when clearing old parts** — freeing is deferred to
  the end of the frame, so a rebuild in the same frame stacks the new gun on the old one's parts.
- **A viewmodel's render layer must be re-applied on every REBUILD.** `Player._ready` stamped
  `mi.layers` on the meshes that existed at the time — none, since the gun is built by the
  `set_class` on the next line and again on every swap — so every rebuilt viewmodel sat on the
  shared layer and the other three players saw this one's weapon floating at its face. Weapon
  carries the bit (`set_view_layer`) and `Viewmodel.configure` re-stamps it.
- **The ADS slide is SOLVED, not hard-coded**: `_build` cancels the Weapon anchor's offset and
  the fitted sight's own offset so the sight lands on the camera axis. With twelve receiver
  heights a fixed offset drifts off centre. A `TorusMesh`'s hole runs along +Y, so the holo ring
  needs the same `rotation.x = PI/2` the barrels use.
- **THE SOLVE PUTS THE SIGHT ON THE AXIS AND NEVER ASKED WHAT IS STANDING IN FRONT OF IT.**
  Aiming narrows the camera from 75° to as little as 45, and the viewmodel is drawn by that same
  camera — so ADS magnifies the GUN by the same 1.6× it magnifies the world. Photographed
  (`tests/ads_look.tscn`), the receiver filled the bottom 45% of the screen with its top edge at
  the crosshair and the emissive heat cell blooming directly under the reticle: the brightest
  thing on screen sitting on the exact pixels you are shooting at. Real shooters dodge this with
  a second fixed-FOV camera; with four viewports the honest lever is DISTANCE, so
  `ADS_PULL_BACK` now PUSHES OUT (+0.115) rather than pulling in, and `ACCENT_ADS_MULT` dims the
  lit trim as the sights come up. Pushing along Z cannot move the sight off the axis — the solve
  centres it in X and Y, so Z slides it straight down the aim line.
- **THE LIGHTS ON THE GUN ARE THE TEAM'S COLOUR, AND THEY ARE THE BOLT'S COLOUR**
  (`Viewmodel.set_light_color`, pushed from `Weapon.bolt_color()` in `set_class` and on every
  muzzle flash). The lit parts were the last thing still painted from the faction PALETTE, so a
  purple clone carried a gun with a red heat cell and fired blue. Same rule as the tracer, the
  muzzle light and the impact scorch — one colour, now four things read it. Kept at
  `ACCENT_ENERGY` 1.6 and not higher for the reason the turret's sensor slit is on record for:
  past unity AgX takes emission to WHITE, and a white cell carries no team at all.
- **EVERY GUN IS A DIELECTRIC AND EVERY FACTION BUILDS OUT OF THE SAME BOXES** (`Viewmodel.Make`,
  `PALETTES`, `_dress`) — see house rule 12 for why `metallic` is 0.0 in all six palettes. What
  separates a UNSC rifle from a Covenant one is COLOUR, PROPORTION and one or two parts nobody
  else has: Star Wars gunmetal with a red heat cell; UNSC olive drab with a carry handle and a
  lit ammo counter; Covenant violet with **no straight lines** (canted shell fins round a glowing
  plasma core, the only family built from round parts); Astartes dark red with a shell box, a
  purity seal and a muzzle collar; Necron near-black with a lit spine and swept vanes; Ork rust
  scrap, deliberately asymmetric. Unlisted classes are Star Wars.
- **A repeated small feature is what gives a surface SCALE** — the same lesson as the Coruscant
  tower mullions. Viewmodels carry universal furniture sized off the receiver (trigger + guard,
  ejection port and lip, charging handle, top-rail slots, sling loop, barrel heat vents, front
  sight block, stock cheek riser), because a bare extruded box could be any size.
- The lightsaber viewmodel is built under its own PIVOT (`_build_saber`), because the viewmodel
  root's transform is already driven by recoil, bob and the ADS slide and the whole weapon has to
  swing as one piece. The blade is modelled along -Z like every barrel, so a POSITIVE pitch is
  what stands it upright. `kick()` starts a swing instead of a recoil kick when a blade is in
  hand, alternating sides so a held attack reads as a sequence of cuts.
- **Every "box" in the game is a CHAMFERED box** (`scripts/meshes.gd`, `class_name Meshes`,
  static + cached). `CharacterModel._box`/`_limb`, `Corpse._box` and `Viewmodel._box` all funnel
  through `Meshes.chamfer_box(size)`. A true box shades each face at one flat value and reads as
  cardboard however good the material is. Deferred while the Pi was a target (44 tris against 12);
  **measured after the switch it cost nothing** — 20.3 ms against 21.4 ms at 4 viewports, because
  these maps are fill-bound, and sharing one cached mesh per SIZE actually cut mesh resources.
- **Never ship a generated mesh without a signed-volume check** (`tests/chamfer.gd`). The
  chamfer's edge strips were wound inward on half the sign combinations — the surface was all
  there and every normal pointed outward, so it looked *fine*, and the only symptom was that the
  solid quietly subtracted from itself (a 1 m cube came out at 74% of its own volume). Winding
  bugs do not raise errors and do not look like winding bugs; the near-black planet terrain cost
  a whole session to the same class of mistake.
- **AND TAKE THE SIGN FROM THE ENGINE, NEVER FROM MEMORY. `tests/chamfer.gd` demanded a POSITIVE
  signed volume, which is the wrong way round for Godot — so `chamfer_box` was inside out, it
  passed a check that was itself inverted, and since every box in the game comes through it, EVERY
  MODEL IN THE GAME was inside out: characters, weapons, corpses, vehicles, deployables, cover.**
  Godot's front face is the CLOCKWISE one, so for correct geometry `cross(b - a, c - a)` points
  INWARD and a closed solid's `a · (b × c) / 6` comes out NEGATIVE — measured from `BoxMesh`,
  `SphereMesh`, `CylinderMesh`, `PrismMesh` and `QuadMesh`, which all agree and are the authority.
  **The symptom is not "a winding bug".** With back faces culled you see through the near face into
  the far one's interior, so the models read as TRANSPARENT; and those interior faces carry outward
  normals, so they light as though facing away and the whole model goes flat and ambient-only,
  which reads as a LIGHTING fault and sends you off tuning materials, exposure and sun angles.
  Both tests now calibrate against a real `BoxMesh` at run time so the convention cannot be
  written down backwards again, and `tests/mesh_winding.tscn` asks the same question of all 7743
  generated meshes in the game rather than of the chamfer box alone.
  **A/B it with a picture when in doubt**: the game's box beside the engine's, one material, one
  light. Inverted, the difference is unmistakable and takes a minute; reasoning about it does not.

#### Muzzle flash, bolts and impacts

- **A muzzle flash is a REAL LIGHT** (`Weapon._muzzle_light`), built once and toggled, never
  allocated per shot. Shadows off, and it decays rather than switching off (a hard cut reads as a
  dropped frame). It is the best realism-per-line in the game — a shot that lights the wall beside
  you reads as an explosion in a barrel where an emissive sprite reads as a sticker — and it is
  the only dynamic light most maps ever get. Rocket blasts get one too.
- **A GUN HAS ONE COLOUR AND THREE THINGS READ IT** (`Weapon.bolt_color` — tracer, muzzle light,
  impact scorch). They used to disagree: light and scorch took the profile's `flash` while every
  bolt in all three universes was one shared burnt-orange material. Resolved per trigger pull
  rather than once at spawn, because it depends on the profile AND the shooter and those are
  assigned in either order by Player, Bot and Turret.
- **The colour falls through to the SIDE, and that is what makes Star Wars look like Star Wars**
  (`Loadout.UNIVERSES["bolts"]` → `GameState.bolt_colors`). Stated only for EXCEPTIONS, exactly
  like `VOICES`: a weapon with a colour of its own keeps it, so plasma stays plasma. Everything
  unlisted is every ordinary blaster row, and those rows are SHARED by all four Star Wars sides.
  Clone blue against droid red, Imperial green against Alliance orange. A second array rather than
  reusing `team_colors` because the Empire's chip is grey plate and its bolts are green, and a
  grey tracer is no tracer at all. **A look test that hardcodes a colour photographs a colour the
  game does not fire** — `night_look` had its own copy of the old orange.
- **A round that lands leaves a mark** (`scripts/impact.gd`): a scorch on the surface, a brief
  flare and four sparks along the bounce, oriented to the hit NORMAL. Boxes and quads only — no
  particle system, no light by day. Capped at `IMPACTS_PER_SHOT` and spawned for WORLD hits only:
  a body already reports a hit three ways, and sparking off a chest reads as armour rather than
  flesh. Two lessons: `look_at_from_position`'s up vector must be perpendicular to the look axis,
  and here the look axis IS the normal — so `up` may be anything except the normal; and **a
  short-lived effect must clamp its own delta**, or a hitch hands it a whole second, ages it past
  its entire life and frees it before it is ever drawn. Judge these from gameplay distance —
  untextured, a big quad reads as a sticker.
- **`Blast` (`scripts/blast.gd`, static) is every explosion in the game.** A rocket, a grenade and
  a mortar shell were three copies of the same twenty lines that had already drifted — the rocket
  had grown a real light and the other two never had one, so a frag at your feet lit nothing. One
  call, sized off the weapon's own splash radius.
- Hit confirmation (`hit_marker.gd` + `hit_tick.gd`, plain scripts instanced by Main — no
  `class_name`, so no class-cache round trip). **The confirmation is raised inside the VICTIM's
  `take_damage`**, the one place that knows the damage survived the friendly-fire check, which
  covers hitscan, rockets, grenades and turret fire without repeating itself. The victim calls
  `attacker.on_hit_confirmed(headshot, killed)` if it has it. `take_damage` grew an optional third
  `headshot` arg so the target passes it through rather than the shooter guessing from the number.
  The marker is per HUD and added LAST in `_add_reticle` so it draws over the scope blackout. The
  click is one shared pool of voices — audio is NOT split four ways the way the screen is — and
  PITCH carries the detail rather than three separate sounds.

### AI

`scripts/bot.gd` (`class_name Bot`). Duck-typed against Player (house rule 15). Bots deploy a
`Loadout` from `BOT_BUILDS` — gun, sight, armour, gadget all from the preset — and `SKILLS` is
purely intelligence (its `health`/`speed` entries are MULTIPLIERS on the preset's armour). Main
deals presets out in order so a team fields a mix. **Bots apply the same kit multipliers as
players, or a class is only fast in human hands.**

- **WHAT A BODY IS AND WHAT IT COSTS ARE TWO DIFFERENT FLAGS** (`Bot.line` vs `Bot.thrifty`), and
  they were one flag for as long as MASSIVE was the only big mode. **`line`** is a MASSIVE line
  trooper: a rifle, a scope, no gadgets, no squad, a weaker eye and a slower trigger — a DESIGN
  choice and the whole point of that mode. **`thrifty`** is the cheap simulation: soft bodies
  (`collision_mask = 1`), half-rate stepping (`MOVE_EVERY`), crowd drawing, `max_slides = 2` — a
  COST choice that changes no decision the AI makes and nothing it carries. Conflating them is
  what kept 20v20 out of the ordinary modes: **buying the frames also bought the stripped
  loadout**, so any big deathmatch would have thrown away the roster that IS the game.
  **Thrift is decided by BODIES, not by mode** (`GameState.crowded`, `CROWD_AT` 24) — a crowd is
  expensive for the same reason wherever it turns up. A line trooper is always thrifty; a 20v20
  bot is thrifty and keeps its class, gadgets, turret and full skill tier.
  **MASSIVE IS THE ONE EXCEPTION, because it already draws the distinction itself**: its VETERANS
  are deliberately full fidelity and `crowded()` must not demote them. They are a handful per side
  whose whole job is to give a hundred-body battle some texture, they are too few to cost anything
  against the other ninety, and softening them takes away the one thing they were added for. Hence
  `line or (crowded() and not massive())`. `tests/massive.tscn` asserts it and caught it the first
  time it was got wrong.
  **Deliberately NOT under `thrifty`**: the cheap three-candidate scan (measurably worse — 3 of 9
  acquiring against 9 of 9) and skipping A* (a rate-limited queue degrades gracefully at 40 and
  starves at 100). Those stay MASSIVE's alone.
- **A BOT DECIDES FIVE TIMES A SECOND AND ACTS SIXTY** (`Bot.THINK_EVERY` = 12 physics ticks, with the
  phase DEALT AT SPAWN exactly as `_move_phase` is). Everything the AI did used to run on every tick,
  which is a rate nothing about the behaviour needs: a bot re-asked "should I throw a grenade?", "should
  I place a turret?", "which way round this wall?" sixty times a second and answered the same way sixty
  times, because none of the inputs had moved enough to change the answer. That is house rule 5, and it
  is what capped how many bodies a local match could hold.
  **DECIDED on a think tick**: where to walk (`_route` / `_patrol_goal`, the result held in `_want_dir`)
  and the six "should I use this?" tests, every one of which walks the combatant list or casts a ray
  behind an ability whose cooldown is measured in seconds. **ACTED every tick**: aim and facing (the aim
  lerp IS the smoothing — sampled at 5 Hz it is a head that snaps), the trigger and its reaction timer,
  the held movement direction, gravity, shoves, `move_and_slide`, `_watch_for_snag` and the animation.
  **`_throw_lightning_if_in_reach` IS DELIBERATELY EXEMPT**: it is what ticks the CHANNEL, so gating it
  runs the stream at a twelfth of its rate — not a cheaper bot, a broken ability.
  Measured (`QS_CPU=1`, 42 bodies, Kashyyyk): bot scripts **4.117 ms -> 2.833 ms** a tick (-31%), whole
  tick 6.279 -> 5.398 ms, and A* searches across the match fell from ~16/s to **1.5/s**. Phase dealing
  matters as much as the rate: all of them thinking on one tick is the same total work arriving as a
  spike five times a second, and a spike is what a player feels where an average is not.
- **Bot behaviour must stay mode-agnostic.** Presets, gadget use and patrolling run the same in
  every mode, with `GameState.zone_active` only changing WHERE they push. Anything keyed to the
  zone needs a deathmatch answer — turret and mortar placement are keyed to the bot's own patrol
  goal and to making contact for exactly that reason.
- **A Bot with no target does NOT stand still**: `_patrol` sends it after its owner, or (team AI,
  or an orphaned squadmate) to a roaming point near the map centre. Team AI are spawned with a
  null owner, so the owner-follow path alone left them standing on their spawns all match.
- **A bought squadmate is LEASHED to its owner** (`_leashed`): it only engages what is near them
  and gives ground rather than chasing past `LEASH`. That limits where it walks, not what it
  fights. Team-fill AI have no owner and roam freely.
- **A bot in contact ALTERNATES between digging in and circling** (`_update_post`). It used to
  circle for as long as the fight lasted, which reads as a body that cannot keep still and is also
  bad soldiering — the whole reason to stop advancing is to shoot from somewhere. It POSTS UP:
  plants, drops to `crouch_idle` and fires for `POST_TIME`, then circles for `ROVE_TIME`, flipping
  its strafe direction each time so it never steps back into the line it was just shot from.
  Measured over a 4v4: in contact 79% of the time, dug in for 59% of it, still trading normally.
- **Posting has to COST something as well as pay.** Crouched, a bot's aim wobble tightens
  (`POST_STEADY`) exactly as a crouched player's cone does, and its capsule shrinks to
  `CROUCH_HEIGHT` on the same eased curve — so what a shot has to hit matches what is on screen.
  Without the second half the crouch is a free accuracy bonus paid for by nothing.
- **A BOT'S FIGHTING RANGE IS DERIVED, NOT TABLED** (`_hit_reach` / `_hold_range`): a shot lands
  while total angular error keeps it inside a body's width at that distance, so the stand-off
  falls out of the tier's own wobble plus the gun's cone. An elite behind a scoped rifle works out
  ~70 m, the same elite with a scattergun eleven. The tier's `hold` is a FLOOR — this only pushes
  the good tiers OUT.
- **The top two skill tiers AIM DOWN SIGHTS** (`SKILLS[i]["ads"]`), trading nothing (they have no
  camera to zoom) for the weapon's tight `ads_spread`. Gated OUT of `ADVANCE` so a bot closing at
  a run still hip-fires, and cleared when it loses its target. **Aiming steadies the bot's own
  wobble too** (`ADS_STEADY`) — a tight cone around an aim still 1.8° off is nothing. Top tiers
  also compensate for their own aim LAG against a strafing target (`AIM_LAG`; fire is hitscan, so
  this is not projectile lead).
- **BOTS SPRINT.** Their animation used to pick the run clip off a speed threshold of 3.9 m/s
  while their pace was `BASE_SPEED` 4.0 — so they flickered between walk and run at a standstill
  margin and anything in a heavy kit never reached the clip. Sprinting is a STATE now: on while
  closing or patrolling, off the moment the bot is inside its own firing range, multiplying speed
  by `SPRINT_MULT`, picking the run clip, and — like a player — DENYING the sights.
- **Bots eat recoil too** (`_on_weapon_fired`), or raising it across the board would be a
  one-sided nerf to the humans. It goes straight onto the head and `_aim_head` lerping back IS the
  recovery; `_patrol` levels the head out when there is no target. They ignore `kick_back` — a bot
  writes its own velocity every frame and would erase it.
- **Bot AI gotchas, all found by measuring damage per skill tier rather than watching it**: aim
  error must be a **held** offset (per-frame noise fed through the aim lerp averages back out to a
  perfect shot), applied to **both** head axes; pitch must be solved from the head, not the body
  origin, or every shot flies a body height high; a target needs **memory** (`TARGET_MEMORY`) or
  flickering line-of-sight makes it re-acquire forever and never finish a reaction timer; and bots
  need a heat ceiling or they hold the trigger into a lockout. All tiers carry the same rifle on
  purpose so skill is the only variable.
- **Bots fire the mortar** (`_call_mortar_strike`), but a bot has no map, so its knowledge gate is
  its OWN target: it only shells somewhere it has actually seen an enemy, never the whole level.
  It aims at the centroid of the group that target is standing in, so artillery punishes a bunched
  push rather than chasing one runner.
- **A Bot that grappled has to RELEASE its wire** — `_try_cable` keeps `_cable_wire` and calls
  `release()` on arrival OR timeout (either branch), or a cosmetic node hangs in the world forever.
- **A Bot firing the wrist rocket is gated on range** (`_fire_wrist_rocket_if_useful`) so an AI
  never splashes itself.
- Bots read `Weapon.max_range()`, so a saber bot advances instead of holding at its tier's
  stand-off and swinging at air.

#### Navigation

- **The AI plans a route; it does not steer at the goal.** `scripts/nav_grid.gd`
  (`class_name NavGrid`, one shared instance on `GameState.nav`, built by Main) is an occupancy
  grid plus `AStarGrid2D` stamped from `GameState.map_shapes` — the same collider footprints the
  map screen scans. **Reusing that scan is why this needs no navmesh bake and no per-map
  authoring**: a new procedural map becomes navigable for free. `Bot._route` follows the
  waypoints, string-pulls across open ground so it does not walk the grid's staircase, and falls
  back to the straight line when no path is found — an AI that stops when pathing fails is worse
  than one that scrapes a wall. Measured across all ten maps: 94 of 220 journeys have a wall on
  the straight line, 0 planned routes touch one, at a 1.06–1.36× detour.
- Two things that make or break the grid, both measured: **a cell is stamped solid when an
  obstacle reaches its CENTRE**, so a wall thinner than the cell spacing falls between two centres
  and A* routes straight through it — `_stamp` pads by half a cell as well as by CLEARANCE; and
  CLEARANCE plus cell size is what seals a tight map, so cell size is per map
  (`CELL_MIN`..`CELL_MAX`) and Catwalk's corridors need the fine end.
- **A\* IS RATE-LIMITED ACROSS THE WHOLE AI** (`NavGrid.PLANS_PER_FRAME`, asked via `may_plan()`).
  One search costs 2.0 ms on Kashyyyk and 0.10 ms on a small arena, and a loaded match asks for
  ~16 a second — so the average was never the problem. Bots re-plan on their OWN timers, so
  nothing stopped eight landing on one frame: ~16 ms of A* in a 16.7 ms budget, a stutter with no
  visible cause. A refused bot keeps its route and asks next frame, so `_repath_cd` is only reset
  when a plan actually ran. **Rejected on measurement**: skipping the search when the straight
  line is clear — the check costs 17–64% of the search it might avoid and fired 0% of the time on
  the big maps, where the search is expensive.
- **`Bot._watch_for_snag` is the backstop for everything the grid cannot see** (other bodies,
  non-box props, a lip in the terrain): trying to move but not moving for `STUCK_TIME` commits to
  a sidestep for `SIDESTEP_TIME`. It has to COMMIT — re-deciding every frame just jitters — and it
  peels off along the wall rather than reversing, because a bot that backs up walks into the same
  corner again.

### Maps

Maps live in `godot/scenes/levels/`. All but the hangar are procedural: a map script
`extends "res://scripts/arena.gd"` and overrides `_configure()` with a layout table (size/depth —
leave `depth` 0 for square — cover, per-team spawns); `arena.gd` builds env/floor/walls/lights/cover
and registers the spawns. A map may override `_build_environment`/`_build_lights`/`_floor_material`
and add props in `_decorate()`. **A map registers its per-team spawns in `_ready`** (children ready
before Main spawns players).

- **THE OUTPOST IS THE CLOSE-QUARTERS MAP, AND IT IS GENERATED** (`scripts/map_base.gd`, 84 m —
  a bit over a quarter of a planet's span — roofed, and re-planned from the match seed). Every
  other generated world is 270-300 m of open ground; the only thing at the other end of the scale
  was the hand-laid Catwalk, and one authored corridor map is a map everybody learns in an evening.
  **WHAT MAKES IT CLOSE-QUARTERS IS THE SIGHT LINES, NOT THE SIZE** — a small map with long
  diagonals is a sniper's map that happens to be small — so it is a 7x7 grid of rooms behind solid
  walls joined by doorways. Measured by `nav_grid`: **22 of 24 straight lines between random points
  hit a wall**, against 94 of 220 across the big maps, at a 1.37x routing detour.
  The plan is a union-find spanning tree over the cells plus `LOOP_CHANCE` of the rest, because a
  tree alone is a base of dead ends and a dead end in close quarters is a place you die in rather
  than fight in. Two 2x2 HANGARS at opposite corners are the deploys and the only open volume.
  **The perimeter ring is always walkable**, which is layout doing a mechanical job:
  `place_corner_spawns` drops 3- and 4-way matches into the corners, and a corner that happened to
  be a sealed room would spawn a side inside the geometry. Lit by ambient plus emissive ceiling
  strips and two shadowless fills — 49 rooms cannot each have a real light — and the strips take
  each hangar's SIDE COLOUR, which is the cheapest possible landmark in a place where every room
  looks like the last one.
- **AN INTERIOR NEEDS A LIGHTER ALBEDO THAN AN OUTDOOR MAP, WHICH IS THE OPPOSITE OF THE INSTINCT.**
  With no sun and no sky every surface is lit by ambient alone, and a dark albedo under ambient is
  black — the first pass of the Outpost was unplayably dark at the same wall colour the arenas use.
  What makes a place read as indoors is the absence of a key light and a hard shadow, not dark paint.
- **A ROOF IS COLLISION THAT IS NOT AN OBSTACLE, AND THE MAP HAS TO SAY SO**
  (`GameState.MAP_NAV_IGNORE`, set through `Arena._wall(..., nav := false)`). A ceiling spanning the
  level is one world-layer box whose footprint covers everything, so the nav grid stamped the whole
  map solid: `nav_grid` reported the Outpost 100% solid with 0 of 24 journeys routable.
  **THE OBVIOUS FIX IS WRONG AND THE TEST SAID SO WITHIN ONE RUN**: discarding any box whose BOTTOM
  is above head height reads like the floor-slab rule from the other end, and it broke five other
  maps at once (Highridge and every generated planet began routing through real geometry). A box
  high above the ORIGIN is not a box high above the GROUND, and on terrain the ground is wherever
  the hill is — a structure standing on a 20 m ridge is a wall. No height threshold can tell those
  apart without knowing the ground beneath, so the map states it instead.
- **`height_at()` is the ANALYTIC surface; what you collide with is a heightfield MESH on a coarse
  grid, and across a hollow its flat triangles sit ABOVE the curve.** So anything placed at exactly
  `height_at` starts INSIDE the ground and cannot get out — the "characters caught in the ground"
  symptom. Spawn markers get `GameState.SPAWN_LIFT` and crates a similar nudge, then drop the last
  step. The lift must exceed the worst grid-cell sag, so it scales with the map's `CELL`, not with
  the body.
- **`ConcavePolygonShape3D.backface_collision` defaults to false, and the side it keeps is not the
  side the surface normals face.** A generated terrain collider silently lets everything walk
  through it with no error anywhere. Terrain wants it true regardless — it also stops anything
  launched under the map drifting up through the hill. **Symptom to recognise: the collider exists
  with the right face count and y-range, and rays still pass through.**
- **A heightfield is a ONE-SIDED skin over a hollow interior**, so any camera that gets under it
  sees the mountain vanish and the props float. `terrain_ground.gdshader` is `cull_disabled` with a
  `FRONT_FACING` branch painting the underside as cave rock — and **Godot forbids an early `return`
  in `fragment`**, so that branch is a branchless select.
- Two traps when generating terrain: a `PlaneMesh`'s UVs run 0..1 across the WHOLE plane, so a noise
  shader shared with a world-UV mesh renders the entire ground as one flat wash unless told the map
  size; and skipping skin cells below a height cutoff leaves the terrain's leading edge as a lip
  hanging above the base plane, so players walk UNDER the mountain instead of up it — emit from the
  first raised corner so the skin's outer edge sits exactly on y=0.
- `scripts/map_highridge.gd`: `height_at()` is the single source of truth for the mesh, its trimesh
  collider and every prop on the ground. **The walkable-slope guarantee is arithmetic, not luck** —
  a smoothstep falloff's gradient peaks at `1.5 * HILL_HEIGHT / (HILL_RADIUS - PLATEAU_RADIUS)`, so
  those constants plus a tiny `ROLL` and a `LOBE` that varies how far the slope REACHES (varying the
  HEIGHT leaves the flat plateau standing proud of its own flanks, which measured 60°) keep the
  steepest face near 27°.
- **The big maps are big in three different SHAPES, on purpose**: Geonosis is open ground you
  navigate by landmark, Kashyyyk (220 m) is groves-and-clearings where trunks block the view and are
  real `cover_boxes`, Senate District (240 m) is a grid whose avenues are map-length sight lines,
  Boneyard (260 m) is a scatter of enormous hulls whose GAPS are the map. Two things every one needs,
  both measured: **fog at a FRACTION of a small map's** (0.006 over 220 m was a flat green wash that
  buried the layout) and **`directional_shadow_max_distance` pulled in to ~80 m** — the atlas is
  capped project-wide and spreading it over 260 m cost all its depth precision, rendering the whole
  near ground solid black.
- Two lighting traps, both measured: fog density that looks atmospheric in a screenshot buries the
  map (Foundry at 0.026 was a flat orange wash with cover invisible from spawn — 0.010 works), and on
  a light-coloured map everything else must be painted genuinely DARK or cover, props and players all
  wash into the ground. Relay shows the design version: it was given a blizzard, which cancelled the
  long sight lines that are the entire point of the map.
- **The MAP screen (`scripts/map_view.gd`, one per viewport) shows TEAMMATES only** — a live enemy
  tracker on a shared screen would end the game. What it draws of the level is SCANNED, not authored:
  `GameState.scan_map_geometry()` flattens every world-layer box collider to a footprint at match
  start, so a new map appears on it for free. Arena declares exact bounds; anything else falls back
  to the scanned extents.
- **Opening the map STOPS you moving and repurposes movement to steer a cursor** — reading the map is
  a commitment, not a glance. That cursor is also the mortar's aiming surface.

### Deployables

- **THE PLACED HARDWARE IS A TRIPOD AND A BIPOD, built in code** (`Turret._build_model`,
  `Mortar._build_model`; the `.tscn`s are only the collider and the pivots the aiming code drives).
  Both were two primitives — a cone with a box on it, and a cone with a cylinder leaning out of it —
  which is a signpost, not a machine. They are bought from the same screen and cost about the same,
  **so the first thing they must do is tell themselves APART at the twelve metres where you decide
  whether to walk round one**: the turret splays LEGS, the mortar spreads a PLATE, and the only long
  thing on either is the mortar's tube. One repeated small feature each for scale (the turret's vent
  slats, the mortar's three bands) — a bare cylinder could be any length.
- **THE TURRET HAD NO GUN.** Its `Weapon` node has no `Viewmodel` child — that is a first-person rig
  driven by bob, an ADS slide and a sprint carry that mean nothing bolted to a post — so
  `find_children(..., "MeshInstance3D")` in `setup` stamped a render layer onto nothing and it fired
  out of an empty node. It read as a television on legs. Twin barrels at the turret's own scale with
  a jacket bridging them (two bare pipes read as thin from anywhere but head-on).
- **The head YAWS and the cradle PITCHES** (`$Head/Cradle`, and `_track` writes the pitch there). An
  armoured housing tipping its whole self at the sky is a box on a stick; a turret swings and only
  its gun climbs.
- **The sensor slit is EMISSIVE IN THE TEAM COLOUR, at 1.3 and not 2.6.** It is the only part
  carrying information — at forty metres, through smoke, on a night map, a lit eye is what tells you
  whose turret is tracking you. But AgX at exposure 1.6 takes emission much past unity to WHITE, and
  a white slit carries no team, which is the entire reason it is lit rather than painted.
- **The tripod's legs are offset by half a turn** (`LEG_ANGLES` starts at PI), so two face the way
  the gun does and one braces behind. The other way round puts a single leg between you and the post,
  which from the front is a bipod with something odd in the middle — **and a two-legged thing with a
  head on top is a BODY**, the one silhouette an emplacement must never be mistaken for.
- **The MORTAR is placed like a turret but never picks its own targets** — the map cursor marks the
  barrage. Placing the tube opens the map immediately (an unaimed tube does nothing, and the map is
  the only place to aim it); picking it back up does not. Once marked it shells that spot
  INDEFINITELY on a `BURST_TIME`/`REST_TIME` cycle (5 s on, 5 s off) until re-aimed, picked up or
  destroyed.
- **Re-aiming restarts the burst**, which is what a player wants and what silently broke the AI: a
  bot re-aiming every `BURST_TIME` landed in the middle of every rest phase and cancelled it, so AI
  mortars fired continuously and never rested (1499 damage in 16 s against the ~1000 the cycle can
  produce). **`Bot.MORTAR_REAIM` is derived from the tube's FULL cycle, not its burst.**
- **The mortar TRAVERSES to face its barrage** (`_want_yaw`, lerped onto a `Turntable` carrying the
  tube and bipod while the baseplate and ammo rack stay put). Shells solve their own arc from the
  tube's origin, so where the barrel points has never affected where they land — which is exactly why
  it was left aimed wherever it was dropped and looked broken. It is purely cosmetic and it is the
  whole read: a mortar that traverses is a mortar somebody is aiming. **Note the rest pitch in the
  scene was +38° where `_recoil` tweens to -38°**, so the tube pointed backwards until the first
  shell corrected it.
- Shells solve their own ballistic arc (`mortar_shell.gd`) so a barrage lands where the cursor was at
  any range, and detonate on first contact. **Apex scales with the SQUARE of hang time**, so the
  flight-time constants are the arc-height dial: at 57 m it peaks ~23 m up. **A shell needs an
  `ARM_TIME` before its impact ray goes live** — a steep lob leaves the tube travelling almost
  straight up, right past whoever placed it.

#### Vehicles

- **ONLY STAR WARS HAS VEHICLES, and that rule lives in exactly one function**
  (`Vehicle.spawns_for(universe)`, which returns an empty array for Halo and Warhammer).
  Every caller loops over what it returns rather than testing the universe itself, so the
  loop is simply empty elsewhere and a second setting getting vehicles is a table row here
  and no change anywhere else. It is a deliberate scope line: a speeder is what this
  setting is built out of, where a Warthog and a Trukk are whole vehicle families that
  would each want their own handling model, seat count and gunner.
- **One speeder per faction, four rows in `Vehicle.VEHICLES`**: Republic BARC SPEEDER,
  Separatist STAP, Imperial 74-Z SPEEDER BIKE, Rebel T-47 AIRSPEEDER. Everything that
  differs is in the row (health, top speed, accel, turn, hover height, gun, hull, and which
  `_build_*` silhouette); the flying, hovering, shooting, mounting and dying is shared.
- **They are spread across the handling envelope on purpose, not one speeder in four
  colours.** A STAP is the fastest thing on the field and dies to a grenade; a T-47 will
  survive being shot at and cannot turn. If they all flew the same, the faction it belonged
  to would be the only difference and nobody would ever choose one over walking —
  `tests/vehicles.gd` asserts the spread (fastest/slowest, toughest/flimsiest) as a guard
  rail, and that every one of them beats sprinting.
- **A SADDLE IS A FOOT POSITION AND A COCKPIT IS AN EYE POSITION, AND A VEHICLE ROW SAYS WHICH**
  (`"eye"` in `Vehicle.VEHICLES`, which sets `Player.seat_is_eye` and moves the `Seat` node). The
  authored seat is a speeder's saddle — you sit on it and the camera ends up at head height over
  the cowl — and on the AT-ST that put the eye 1.75 m above the hull's origin, which is above the
  pod's own ROOF: a camera floating in clear air over the machine with none of it in frame, no
  cockpit, no gun, nothing to judge the walker's line by. Reported as an unusable point of view,
  and it is only visible from the driver's own camera (`tests/vehicle_pov.tscn`) — from outside,
  which is all `warmachine_look` ever sees, the machine is perfect.
- **AND THE COCKPIT IS HIDDEN FROM THE DRIVER** (`Vehicle._hide_shell_from` / `_show_shell`, the
  same per-player render layer the LAAT's ball and a player's own body already use). Sitting the
  eye behind the viewports puts the camera inside a steel box with a face plate across its eyeline
  — photographed, untextured grey slabs across the corners of the frame. The pod, its face plate,
  its roof hatch, the hip yoke and the chin block go; the chin GUNS and the LEGS stay, because
  they are what says you are driving something. **It is given back on dismount** or the machine is
  invisible to that player for the rest of the match, including to whoever climbs in next.
- **A VEHICLE HAS A SIGHT, AND IT IS DRAWN WHERE THE GUN'S ROUND LANDS** (`Vehicle.gunner_readout`
  → the same `gunner_hud.gd` the LAAT and the orbital station use — a machine with a sight is any
  machine that answers that method). **The vehicles had none at all**, and it was a side effect
  rather than a decision: the rifle's bloom crosshair is hidden while mounted (it was drawing the
  cone of a gun that was not firing), which left a driver with a clear screen and nothing marking
  where the cannon pointed. **Centring it would have been a lie**: the gun is nowhere near the eye
  and is clamped to a cone the camera is not, so past the yaw stop the barrel stops turning while
  the view keeps going. `_trace_gun` casts from the weapon in the physics tick and the sight is
  drawn on what it hits — the LAAT parallax lesson, applied before it could bite again.
- **THE BAR UNDER A SIGHT IS THE RESOURCE THAT RUNS OUT** — seconds for a call-in, HULL for a
  machine you drive. One widget, one slot, whichever the readout carries.
- **A CharacterBody3D, NOT a VehicleBody3D.** Godot's is a wheeled raycast-suspension car,
  and these maps are heightfield terrain: the documented `height_at`-vs-collision-mesh split
  means a wheel would ride flat triangles sitting above the curve, with a seam every cell.
  A repulsorlift does not care — it solves a hover height off one downward ray and rides
  what it actually collides with. It also keeps the vehicle inside `move_and_slide`, so it
  stops at exactly the walls, cover boxes and prop hulls everything else stops at.
- **The hover ray masks WORLD ONLY (layer 1).** Masking bodies too would make a speeder
  ride up over anybody it drove across. The spring is critically damped: softer wallows
  through a dip like a boat, stiffer turns every terrain seam into a kick.
- **Bank and pitch are applied to the `Body` child, never to the vehicle itself** — rolling
  the CharacterBody3D would roll its collision box and its hover ray with it, so the thing
  would climb its own bank.
- **Mount/dismount rides the EXISTING interact edge** (`Player.pickup_in_reach` advertises,
  `Player.pickup_pressed` is consumed), not a control read of its own — an edge is consumed
  by whoever reads it first, so a speeder parked over a royale crate would otherwise race it
  and one of the two would silently never respond.
- **THE TEAM GATE IS ON THE ACTION, NOT ONLY ON THE ADVERTISEMENT** (`Vehicle.may_drive`,
  asked by the mount area AND by `_claim_waiting_driver`). The first version checked team
  only in `_on_body_entered`, and `pickup_in_reach` is a plain public field anything can
  set — so an enemy could take your speeder with no error anywhere. `tests/vehicles.gd`
  sets the field directly for exactly this reason and caught it.
- **A mounted player is hidden, its collision is off, and its transform is slaved to the
  seat.** That reuses the death-cam's precedent and means the existing `RemoteTransform3D`
  on the player's Head is untouched: camera follows head, head follows body, body follows
  seat. Both a mount and a dismount are TELEPORTS and call
  `reset_physics_interpolation()` (house rule 10).
- **`exit_vehicle` must NOT restore the body if the player is DEAD.** Dying at the controls
  reaches it through the vehicle's own `_eject`, and `_enter_buy_screen` has already hidden
  the model and killed the collision for the death cam — restoring them stands a live body
  up next to its own corpse. `_respawn` is what restores those, and always was.
  `_enter_buy_screen` also drops the mount itself, so nothing downstream can ever see a dead
  player who is still flying.
- **The hull does not SHIELD the driver, it exposes them** (`DRIVER_BLEED`, 20%). Without
  it, sitting in a speeder is strictly better than standing anywhere and the vehicle is a
  bunker.
- **The gun follows the driver's look inside a cone and no further** (`GUN_YAW_LIMIT` 38°).
  A speeder whose gun tracks anywhere the camera points is a flying turret, which removes
  the entire reason the thing has a facing; clamping it makes aiming and steering one
  decision.
- **A vehicle is a COMBATANT** (house rule 15), so bots shoot at it and it blocks a spawn
  marker — which also means **a battle FREES them as it runs**, and anything holding a list
  of vehicles across an `await` has to re-check `is_instance_valid` (the same trap already
  on record for the massive-battle roster; the cost harness died on it first time out).
- **Parked at each side's own spawn, offset and lifted.** On the marker it would body-block
  a respawn every life, and at the exact analytic ground height it starts inside the
  collision mesh. ROYALE and MASSIVE field none — royale is scavenging and a faction speeder
  is not scavengeable, and a hundred bodies is already the whole frame budget.

##### The two war machines

The AT-ST and the LAAT are `Vehicle` rows like the speeders — they are just earned rather than
parked (see KILL STREAK REWARDS) and they are the two that stressed the shared code.

- **THE HOVER PROBE MUST OUTREACH THE CLEARANCE IT HOLDS** (`HOVER_PROBE_MARGIN`). Free while
  every vehicle hovered under 2.5 m; the moment a gunship wanted 7.5 against a 6.0 probe, the ray
  could not see the ground from the height it was aiming for, so it sank to the probe length and
  sat there holding a clearance nobody asked for, with no error anywhere.
- **A WALKER'S LEGS ARE DRAWN, NOT SIMULATED, so the leg length and the row's `hover` are two
  numbers that must agree and NOTHING enforces it.** The first AT-ST's feet finished THREE METRES
  in the air. A screenshot does not reliably catch that — the shadow lands under it either way and
  there is no other body in frame at walker scale — so `tests/vehicles.gd` measures the lowest drawn
  point against the ground. The geometry is laid out from the SOLE UP (`ATST_GROUND`), not from the
  pod down. **That the legs do not WALK is a stated approximation**: `Vehicle` is a CharacterBody3D
  holding a hover height off one downward ray, and a gait needs foot placement over the
  heightfield's own flat triangles and a body that lurches — a system, not a row.
- **TWO THIRDS OF AN AT-ST IS LEG, and the knees go BACKWARD.** A big pod on short legs is a bunker;
  what makes the thing unmistakable is a small hunched head carried very high on thin reverse-jointed
  legs, and a walker whose knees bend forward reads as a chicken instantly. The joints are the one
  place a vehicle builder uses a CYLINDER rather than a chamfered box (`_cyl`): a walker's hips, knees
  and ankles are big exposed hubs, and boxed joints read as a folded plank. Struts span two points and
  take their length and angle from them (`_strut`), the same trick as `CharacterModel._limb`, so moving
  a joint cannot leave the piece hanging off it. **One material down the whole leg** — a dark thigh
  against a light shin reads as two objects bolted together, so the contrast goes in a PANEL LINE.
  Side gear is deliberately ASYMMETRIC (cannon one cheek, rangefinder the other), same argument as the
  ork shoulder plate.
- **A GUNSHIP IS ONLY EVER SEEN FROM BELOW, so it is built for that angle.** The first LAAT was a
  1.05 m slab on a 6.4 m body, which from underneath is a rectangle with boxes on it. It needs
  VERTICAL members outboard — high wings with the engine pods hung under them on pylons — or it has no
  silhouette at all from the ground. **`warmachine_look` photographs it from below for that reason**,
  and with a trooper in frame: a reward has to read as bigger than what you were, and every shape
  looks imposing alone.

## Screens, input and controls

- **THE FRONT SCREEN ANSWERS "WHAT ARE WE DOING"; THE MENU ANSWERS "WHAT ARE THE RULES"**
  (`scripts/front.gd`, `scenes/front.tscn`, and it is the project's main scene). `menu.gd` was the front
  screen and it is a good MATCH SETUP screen — fourteen labelled dropdowns on one four-column grid, every
  one a real decision. As the FIRST thing anybody sees it is a form: four people sitting down to play met
  UNIVERSE, PLANET, TIME OF DAY, TIME TO KILL, VICTORY, AI SKILL, AIM ASSIST and four SIDE rows before
  they could establish that the game does split screen at all, and "we are two of us on a sofa, start it"
  was a dropdown called PLAYERS in the middle of that grid. The two jobs are split now. **`menu.gd` is
  UNCHANGED and is no longer the main path**: the sign-in and the playlist took that. It is kept, and
  kept REACHABLE — as SINGLE MATCH, the second entry under LOCAL PLAY — because it is the only screen
  that can build one odd match (an individual side row, a mixed setup, the map rotation) without
  queuing anything, and a playlist of one round is a longer way round for somebody who wants a game
  of deathmatch. A screen that is documented as kept and cannot be reached is a deleted screen with
  a paragraph about it.
- **LOCAL PLAY IS THE FIRST AND LARGEST ENTRY, and it asks ONE question** — how many of you, which is
  the only thing that cannot be defaulted because it is a fact about the room rather than a preference.
  Then on to the SIGN-IN, which asks the other unanswerable one: which controller is each of you
  holding, and who are you.

### Accounts and the sign-in

- **AN ACCOUNT IS AN IDENTITY, A CONTROL CONFIG AND A RECORD** (`scripts/accounts.gd`, static,
  `user://accounts.cfg`). Everything the game knew about a player used to be a VIEWPORT INDEX:
  player 2 was "whoever is in the top-right quadrant", their sensitivity belonged to pad 1, and
  their kills were thrown away with the match. That is fine for one evening and wrong for a game
  people come back to — swap seats and you inherit somebody else's aim settings, and nothing
  anywhere could answer "am I getting better at this".
- **THE CONTROL HALF IS DELEGATED TO `Controls`' NAMED PROFILES, under the account's own name.**
  Those already existed for the settings overlay (a device's feel settings plus its bindings,
  captured and re-applied onto whatever device that player is on next), and they are the tested
  path for exactly this. Two stores of one thing is how a rebind comes to apply on one screen and
  not another. What `Accounts` owns is the RECORD, which is the half that did not exist.
- **SIGNING IN APPLIES; THE END OF THE MATCH CAPTURES.** `sign_in` pushes the account's stored
  configuration onto the device that claimed the seat; `GameState.record_results` writes the
  device's configuration back at the end of the match, so a rebind made in the in-match overlay is
  theirs the next time they sit down. A brand-new account has no profile, so its first sign-in
  CAPTURES rather than overwriting the device with nothing — which is what makes every later
  capture an update and not a special case.
- **THE CAREER IS FOLDED IN ONCE, AT THE END, AND IT IS THE ONLY MOMENT THAT KNOWS WHO WON.**
  A stat written as the kill happens would be written by the wire as well as by the killer online,
  written twice by a rotation that reloads the scene, and could not know the result of the match.
  `player_stats` rows go in as they stand, so recording is addition and never translation.
  **A seat with no account writes nothing** — every test in this project boots matches with nobody
  signed in, and none of them may invent a career on the machine they run on.
- **K/D WITH NO DEATHS IS THE KILLS**, not zero and not a division by zero. The one arithmetic case
  here with a wrong answer that looks plausible.
- **A SEAT IS CLAIMED, NOT DEALT** (`scripts/sign_in.gd`). Press START on whatever controller you
  picked up and it becomes yours — the same gesture every console game has used for twenty years,
  and the only one that works when four pads have been charging in a drawer and nobody knows which
  is which. `GameState.device_for_player` is the ONE place that answer lives; with no sign-in
  (a test, the lobby, `-- --debug`) it falls back to the old rule of P1..P4 on pads 0..3.
- **THE LATCHES ARE ARMED HELD, and that is the property worth testing.** Claiming, choosing and
  continuing are three edges read from two buttons by two owners (`_claim_seats` and `_poll`), so a
  level read where an edge was meant means the press that claims a seat also signs you in as
  whatever the list opened on. A device that already has a seat is that SEAT's to poll — tracking
  its START in both places overwrote the latch a frame before the other read it, and player 1 could
  never leave the screen.
- **A PAD TYPES A NAME ON A CAROUSEL**, not on an on-screen QWERTY: up and down change the letter
  under the cursor, left and right move it, and stepping off the end ADDS one. A stick-driven
  keyboard is twelve presses a letter; this is one, and it is what arcade initials entry has always
  been. The keyboard seat types normally, routed BY DEVICE — with two people naming at once,
  anything else puts one player's typing into the other's box.
- **TWO SEATS CANNOT BE ONE ACCOUNT.** A taken row is shown and refused rather than hidden: the
  interesting case on a couch is two brothers arguing about whose account it is, and a row that
  vanishes reads as the game having lost it.

### The playlist

- **A QUEUE OF MATCHES, NOT A MAP ROTATION** (`scripts/playlist.gd`, `GameState.playlist`).
  `rotate_maps` walks the map roster and keeps every other setting fixed, which answers "we cannot
  be bothered to choose again" and nothing else. What four people at a couch want is what
  Battlefront's front end is built around: three rounds we picked, in the order we picked them,
  set up once and played without going back to a menu between them.
- **AN ENTRY IS A WHOLE MATCH CONFIGURATION** (`capture_match` / `apply_match` over `MATCH_KEYS`,
  plus the two side arrays and the mode's own victory threshold). That is exactly the difference
  between this and the rotation: round one can be a 20-a-side Conquest at REALISTIC time-to-kill and
  round two a four-player deathmatch. **The arrays are DUPLICATED** or every entry shares one, and
  picking the sides for round three silently re-sides rounds one and two. Adding a setting to the
  game adds it to the playlist by adding one line to `MATCH_KEYS` — never at the screen.
- **TWO COLUMNS AND A BUTTON, AND THE SPLIT IS THE DESIGN.** LEFT is a guided pick — MAP, then
  MODE, then the SIDES — because it is a story rather than a grid: which planet, what are we
  playing, who are we. RIGHT is the queue itself and the button that plays it, a COLUMN and not a
  strip at the bottom because its job is to be readable while you are still building.
- **SETTINGS WITHIN SETTINGS: A MODE'S OWN ARE ONE PRESS FURTHER IN.** How many players a side
  fields and what the round is played to are not properties of the match, they are properties of
  the MODE — and in a flat list nothing said so: TEAM SIZE meant four different things depending
  on the row above it, and VICTORY changed its unit under you (kills, then seconds, then
  reinforcements) with nothing to explain why. They live under a heading that names the mode now,
  with the mode's own blurb under it, and the rows are REBUILT on open because a mode with
  nothing to tune has to be able to show fewer of them. B closes the TOP-MOST panel only: two
  modals deep, one press that closed both would drop a player out to the screen when they meant
  to step back.
- **AND THEY ARE STORED PER MODE, which is what makes the nesting true rather than decorative**
  (`GameState.mode_team_size`, alongside the `score_targets` table that was already keyed this
  way because kills, seconds and reinforcements are not one unit). Fifty a side is the whole
  point of MASSIVE and absurd in Conquest; with one shared box the answer to "how many players"
  was whatever the last mode you looked at needed. **This is also the documented MASSIVE trap
  fixed at the root**: leaving that mode used to leave `team_size` at fifty, over the ordinary
  ceiling and matching no item in the dropdown, and `menu.gd`'s `_fix_setup` had to walk it back
  afterwards. `team_size` stays an ordinary property every reader asks unchanged — its setter
  writes through to the current mode's row and the `mode` setter reads that row back, so nothing
  outside `game_state.gd` knows the table exists.
- **THE MATCH SETTINGS ARE BEHIND A BUTTON, and what pays for that is the SUMMARY LINE.** They were
  the middle column, and a dozen dropdowns touched once an evening should not stand permanently
  between the two things the screen is for — but the moment a setting is hidden, "is friendly fire
  on?" costs a press, a read and a press back. So the line under the columns names every setting
  that moved behind the button, in the panel's own order: the panel is where they are CHANGED, the
  line is where they are READ. It is a MODAL over this screen rather than a screen of its own,
  because it is opened in the middle of building a round and a scene change would lose which step
  the builder was on; focus moves INTO it (on a pad the highlight is the only cursor there is) and
  its ring is closed on itself, so the stick cannot walk out into the screen behind.
- **CHOOSING THE SIDES IS WHAT ADDS THE ROUND**, which is why it is last. Every other setting has a
  sensible default; who is fighting does not, and it is the thing people actually argue about.
- **A FACTION SET IS DERIVED FROM `Loadout.factions()`, NEVER WRITTEN OUT** — the classic pairings in
  roster order (which in Star Wars is exactly the Clone Wars and then the Galactic Civil War), an
  ALL-SIDES set per universe, one cross-setting curiosity per pair of settings, and FREE FOR ALL.
  A faction added to a universe turns up here for free and no list can name a side that does not
  exist. **Past a pair the title becomes the COUNT and the names drop to the blurb**: four faction
  names on one row ran off the panel, and what a four-way set offers is the free-for-all between
  armies rather than any particular matchup.
- **THE QUEUE IS PLAYED THROUGH WITHOUT ANYBODY GETTING UP.** `Main._next_map` applies the next
  entry and reloads, exactly as the rotation reloads onto a new map index. **Sides are NOT re-picked
  between rounds** — team select is a conversation between people who can see each other, and having
  it again between every round is the thing a playlist exists to stop. A finished queue returns to
  the playlist screen with everybody still signed in.
- **LEAVING MID-QUEUE ABANDONS IT** (`SettingsOverlay.exit_scene` answers the playlist screen while
  one is active, and drops `playlist_index`). Quitting round two of three is usually somebody wanting
  to change round three, so it goes to the screen that can.
- **THE SETUP SURVIVES THE SESSION** (`GameState.save_setup` / `load_setup`, `user://setup.cfg`).
  Everything behind the settings button plus the queue itself, written as it changes — the same
  discipline `Controls` keeps, because a setup written only on the way out of a screen is a setup
  lost by anybody who closes the game from the match, which is how this game is normally left.
  It is stored in the shape `capture_match`/`apply_match` already define, so one definition of "a
  match configuration" makes a setting both queueable and persistent in the same line.
  **IT IS LOADED BY THE SETUP SCREENS AND NEVER FROM `GameState._init`**, which is a deliberate
  line: every headless test builds that autoload, and loading a developer's saved setup at boot
  would silently give the whole suite whatever map, mode and time-to-kill that machine last
  played — a suite that passes here and fails on the next desk for a reason nothing prints.
  **NOT saved**: how many humans are at the couch, and who is in which seat. Both are facts about
  the room, and the front screen and sign-in ask them every time on purpose.
- **AND `apply_match` CLAMPS THE TWO INDEXES THAT ONLY MEAN ANYTHING AGAINST A ROSTER** — the map
  and the mode. An entry can arrive from a `setup.cfg` written by an older build, and a map_index
  past the end of `MAPS` takes down every function that reads it rather than merely picking the
  wrong map. `team_size` is deliberately NOT clamped: MASSIVE's fifty is legitimately past
  `MAX_TEAM_SIZE`.
- **A BACK GOES WHERE YOU CAME FROM** (`GameState.settings_return`). The controls screen always
  returned to the match-setup menu, which was right while that was the only screen that could reach
  it; from the front screen or the playlist it is a BACK that lands somewhere you have never been,
  which reads as the game having got lost rather than as having gone back. The lobby's BACK moved to
  the front screen for the same reason. **And leaving the controls screen captures into the signed-in
  accounts**, or a rebind made before the match is kept only if you then finish one.
- **THE BACKGROUND IS A FIREFIGHT, RENDERED LIVE, AND EVERY PART OF IT IS THE SHIPPING PATH.** A flat
  colour behind a menu says nothing about what is on the other side of the button, and this project has
  no art to put there — but it has a procedural character generator, a lighting grade and a materials
  system, which already produce the thing key art would be OF. The bodies are real `CharacterModel`s
  playing real clips, the tracers are `blaster_bolt.tscn` taking their colour from `GameState.bolt_color`,
  the explosions are `Blast.pop`, the muzzle flashes are real lights built once and toggled. Nothing is a
  mock-up, so nothing can drift from the game.
  Four things it took measuring or looking to get right, all recorded in the file: **a body FACES what it
  shoots at and that is DERIVED from the aim point** (`look_at`) rather than stated as an angle beside it
  — the hand-written version had both squads standing back to back firing over their own shoulders;
  **the menu's bolts fly slower than the game's** (`BOLT_SPEED`, an override on the same bolt), because
  400 m/s crosses the diorama in three frames and is functionally invisible as decoration; **the muzzle
  flash must not out-read the key light**, or every shot turns the shooter white; and **a floor is a
  plane and a plane has an EDGE**, which at any size draws a hard line across the frame — the fix is fog
  pinned to the background colour, so the edge ceases to exist rather than merely moving.
- **THE WASH BEHIND THE TEXT IS A GRADIENT, NOT A FLAT VEIL.** A uniform one has to be dark enough for
  the worst case — text over the brightest thing in the scene — and at that strength it also puts the
  whole firefight behind a grey sheet, which is the one thing the background exists not to be.
- **THE MENU IS CAPPED AT 60 fps** (`Engine.max_fps`, handed back in `_exit_tree`). A camera-less screen
  renders at whatever the machine can manage — `menu.gd` records three hundred — and this one has a 3D
  scene in it, so uncapped it heats the chip up before the match that needs the clocks has started.

- **`scripts/controls.gd` (`class_name Controls`, all static — no autoload, so it works from
  `GameState._init`) owns every binding.** The keyboard half is applied to the InputMap as `kb_<id>`
  actions, so a key rebind is just rewriting that action. **The pad half cannot work that way** — an
  InputMap action is device-wide and four players are on four pads — so pad input stays polled per
  device: `Controls.held(device, id)`. Stored per device with `ALL_PADS` (-1) as the fallback profile,
  which makes "rebind every pad" and "rebind player 3's pad" one mechanism. Saved to
  `user://controls.cfg`.
- **Player 1's pad is the house layout.** `bindings_for` falls back device-own → PLAYER 1 → ALL_PADS →
  default, so a rebind on P1 is inherited by pads 2–4 — four pads at a couch are four copies of one
  controller. A pad given its OWN binding keeps it. **`tests/controls_inherit.gd` SNAPSHOTS
  user://controls.cfg first, because every mutating Controls call SAVES** — an earlier version wiped a
  real rebind off a real machine.
- **The game is PAD-FIRST** (Main puts every player on a joypad, P1..P4 = pads 0..3; keyboard is a
  fallback that still works). Two things that has to buy, neither of which Godot gives you: the engine
  ships joypad events on `ui_up/down/left/right` and **nothing else**, so out of the box a pad moves
  the menu's focus and then cannot press what it landed on — `Controls.apply_ui_pad()` adds A/B to
  `ui_accept`/`ui_cancel` with `device = -1` (ALL devices, or only P1's pad could work the menu); and
  a rebind listen swallows every input so it can capture any button, which would trap a keyboardless
  player in the row they opened — so **START always cancels and BACK clears a pad's override, and
  neither is bindable.**
- **EVERY SETTINGS ROW ON THE MENU SITS ON THE SAME FOUR COLUMNS** (`menu.gd`'s `COLS` /
  `CELL_W` / `GRID_W`, one `_grid()` helper). It was three grids of two, three and four columns,
  each auto-sized to its own contents and each CENTRED — so the three blocks were 420, 640 and
  880 wide stacked on each other and the whole screen zig-zagged with no two labels lining up.
  Nothing was wrong with any one row, which is exactly why it survived: **the fault only exists
  BETWEEN the blocks**, so no amount of looking at a row finds it. A block short of a full row is
  PADDED (`_pad`) rather than left to centre itself, and each block carries a `_heading` — a
  caption plus a hairline the width of the grid — because six loose dropdowns under a title read
  as a list where three labelled blocks read as a form.
- **THE ONE ACTION A SCREEN EXISTS TO PERFORM DOES NOT LOOK LIKE A SETTING** (`_make_primary`).
  START MATCH was a dark framed box the same weight as QUIT beneath it, which is a primary action
  a player has to go looking for; it is filled in the accent now. **Two primaries is no primary**,
  so nothing else on the screen may take it. Focus is carried by a brighter fill and a light edge
  rather than by the accent border every other control uses — on a filled button an accent border
  against an accent fill is invisible.
- **A CAPTION BELONGS TO THE BLOCK ABOVE IT** (`_caption`, on the grid's own left edge and
  width). Centred lines under a left-aligned grid read as belonging to neither.
- **Godot's geometric focus search is not good enough for a laid-out menu, and `menu.gd` is the
  proof**: from the 400×200 MAP box, RIGHT landed on TEAM SIZE two rows down and the MODE box beside
  it took four presses. `_wire_focus` states all four neighbours from the row table, wrapping in every
  direction (a press that appears to do nothing reads as a hung menu) and crossing rows by POSITION IN
  THE ROW, which needs no layout — nothing has been sized yet when it runs.
- **Every menu setting is a labelled DROPDOWN** (`OptionButton`), map, mode and CLASSES included — a
  cycling chip shows one value at a time, so seeing the range meant walking it. **They are rebuilt on
  every refresh rather than re-selected, because what is legal moves**: team size cannot fall below the
  humans already in a team, FREE FOR ALL needs a second player, and VICTORY's choices and unit depend
  on the mode. **Disabled, not hidden** — an option that vanishes is one nobody learns exists.
- **Players pick their team on a screen between the menu and the match** (`team_select.gd`): each human
  moves a token onto a team box (A locks, B releases), and once all are locked it stores the picks in
  `GameState.chosen_teams`. `team_for_player` returns a player's pick when there is a valid one, else
  the round-robin default — so `humans_on_team`/`ai_needed` follow the picks for free. An out-of-range
  pick falls back safely. FREE FOR ALL skips the screen entirely.
- **THE CHARACTER SELECT WEARS THE SIDE'S COLOUR, NOT THE PLAYER'S**
  (`GameState.team_color(team)`, passed by Main instead of the per-player colour). Everywhere else
  on a four-way split a player finds their quadrant by their OWN colour — but this is the one
  screen whose answer to "who am I" is the ARMY rather than the seat, and it already names the
  faction out loud. Two players on the Republic were reading a red screen and a green one while
  picking off the same roster, which says the seat matters and the side does not. **The quadrant
  is still called by the P1..P4 tag and the health bar**, both in the player's colour, so nothing
  was lost. `team_color` is bounds-checked for the reason `bolt_color` is (house rule 6).
  **It is the colour CHOSEN on the menu when there is one**: `refresh_sides` already folds a
  faction's own chip and its tint into `team_colors`, so this is a wiring question, not a colour
  one. `tests/select_look.tscn` photographs one side on its faction colour and one on a chosen
  tint for exactly that reason — only a picture proves the SCREEN reads the folded answer.
- **THE DEPLOY SCREEN NAMES THE SIDE YOU ARE ABOUT TO JOIN** (`spawn_screen._side_name`). It
  already knew — it is picking from that side's roster — and never said it, so the one thing a
  spawn screen is FOR was the thing it left out. In the side's own colour, under DEPLOY. It also
  **counted** its classes instead of stating them: the blurb read "Your side's four classes" long
  after a roster became eight, and nothing anywhere reports a screen lying about its own contents.
- **SOLO IS A WHOLE SCREEN AND WAS BEING DRAWN LIKE A QUARTER OF ONE** (`BoxScreen.WIDE`). At one
  player the deploy screens own a 1080p display and were a 480 px panel adrift in the middle of
  it — legible, and reading as a dialog box rather than as the screen you join an army from.
  **`tests/select_look.tscn` takes `QS_VIEWS=4`** for the same reason the metrics exist at all: a
  screen judged only at one player is a screen judged in the case that cannot fail, and the
  documented failure mode is the full-size layout running off both edges of a quarter viewport.
- **The two deploy screens are ONE mechanic** (`scripts/box_screen.gd`, `class_name BoxScreen`, all
  static): a grid of bordered boxes with a free cursor, the box under the cursor in the player's
  colour, accept to open (which fills it and gives a caret inside), back to close, accept on SPAWN to
  deploy. Both the buy screen (`Main._build_buy_screen`) and the character select build out of it, so
  "the character select looks just like the buy screen" is true by construction.
- **The cursor opens ON the SPAWN box, closed, every time — that is the whole safety property.** The
  old screen put a live row-cursor on the CLASS row, so a stick still held on the frame you died
  re-rolled your kit, and `adopt_kit` RESETS the build. Moving the cursor never touches the build; only
  accept on a box does; and the ordinary respawn is still one press because the cursor starts on SPAWN.
- **The buy screen's boxes are INPUT, not layout** (`Loadout.BUY_BOXES`, which is why the table lives
  with the catalogue and not with the screen that draws it). It runs on each player's own stick or keys
  — four players shop at once and only P1 has a mouse, so a click-to-select screen would work for
  exactly one of four. Sizing is picked off `human_players`: the full-size layout runs off both edges of
  a quarter-screen viewport.
- **Which box the cursor is over is resolved against the real rects, not by Player**
  (`BoxScreen.resolve`, called from Main), because hidden boxes REFLOW the grid — a Mandalorian has no
  GRENADES panel — so only the code holding the real
  `PanelContainer` rects knows where a box landed. Player owns the normalised cursor and reads back
  `buy_box`; a headless test sets `buy_box` directly. The reticle and the hit-test both map the cursor
  across the union of visible box rects, so they cannot disagree.
- **Three states have to be told apart across a four-way split**, so each gets its own signal:
  selector-on-a-box is a coloured BORDER, open is a coloured FILL too, and the row caret exists ONLY
  inside an open box — a caret on a line you cannot currently change is exactly the lie the old screen
  told.
- **The buy screen's BACK is the pad's B, fixed and unbindable**, like the controls screen's START/BACK:
  a mode you can get stuck inside needs an exit no rebind can take away. Accept stays on the `jump`
  binding (it has always been the deploy button, so it follows a rebind). Not hypothetical — this
  project's own saved config has crouch on R3, so keying "close the box" to crouch would have hidden the
  exit.
- The character select and the buy screen index the SAME `Player.buy_box` field from DIFFERENT box
  tables (`PICK_CLASS_BOX`/`PICK_POST_BOX`/`PICK_SPAWN_BOX` vs `Loadout.BUY_BOXES` + `SPAWN_BOX` +
  `POST_BOX`). They are never up at once and each handler only uses its own set — but
  `_enter_buy_screen` has to open on the right one, which is why it branches on `faction_classes()`.
- **Nobody spawns directly.** `Player.begin_deploy()` (called by Main *after* the HUD is wired —
  `_ready` would emit `died` into nothing) and every `_die` enter `_enter_buy_screen`, which opens on
  the build you last deployed with (`pending = loadout.duplicate_loadout()`). It stays up until
  jump/A; the timer is only a floor before that button arms (`DEPLOY_FLOOR`/`RESPAWN_FLOOR`).
- **THERE IS A WAY OUT OF A MATCH, and until recently there was not.** QUIT TO MENU is the last row of
  the in-game START overlay, behind a CONFIRM. Before it, the only ways out of a match were winning it,
  losing it, or killing the process — which for a 200-ticket Conquest is several minutes of a game
  somebody has already decided to stop playing. It is last because RESUME is what a player reaching for
  that screen actually wants; it is behind a confirm because the row list WRAPS, so "up from the top
  row" is one press away from it. **The confirm STATES THE COST and states it differently depending on
  who else is playing**: on a couch there is one match on one machine and no way for player three to
  walk out while the others carry on, so it says so out loud. **Online it calls `Net.leave()` before
  changing scene** — abandoning a live peer leaves the host holding bodies for a machine that is gone.
  `exit_scene()` is split from `_leave_match()` so the DESTINATION can be asserted without performing
  the navigation, because a test that really changes scene frees itself mid-run.
- **ONE OWNER FOR `get_tree().paused`, AND IT IS A SET OF REASONS** (`GameState.hold` /
  `release_all_holds` / `may_pause`). Two separate things stop the match — a solo player opening the
  overlay, and a controller falling out — and they OVERLAP: unplug a pad while the menu is up, plug it
  back in, and a plain boolean resumes a game the player is still reading a menu over. A set only lets
  go when the last holder does. `reset_match` drops every hold, because a scene loaded into a paused
  tree never runs its first frame.
- **PAUSING IS A SOLO ANSWER** (`GameState.may_pause()`). At more than one human, the overlay opening
  over one viewport while the other three keep playing is the whole design and must not become a freeze;
  solo there is nobody for a pause to be unfair to, so it genuinely stops the tree. The rule lives in one
  function rather than in each caller's `human_players` test. **The overlay itself is
  `PROCESS_MODE_ALWAYS`** — it is the one control that can undo the pause it takes, so if it were
  pausable it would freeze itself and the match could never be resumed.
- **A CONTROLLER FALLING OUT IS THE COUCH FAILURE MODE, and nothing was watching for it**
  (`Main._on_pad_changed`, on `Input.joy_connection_changed`). What used to happen was nothing at all:
  `Controls.held` started returning false, the body stood in the open being shot, and there was no way
  to tell it apart from the game having crashed. Now: a banner on that player's own viewport, and solo,
  the match stops until the pad is back. **It does not pause at more than one player** — same argument
  as the overlay; freezing four people for one set of batteries punishes three of them. **It is also
  asked once at HUD build**, because `joy_connection_changed` only fires on a CHANGE and four players
  set up on three pads would otherwise never be told.
  **A PAD THAT WAS NEVER THERE IS A SETUP PROBLEM, NOT AN INTERRUPTION**, so that startup check shows
  the banner and deliberately takes NO hold. Routing it through the disconnect handler instead made a
  solo match pause itself on its own first frame against a controller that had never existed — the game
  froze before it started, telling you to reconnect something you had not connected. Nothing to pause,
  nobody has lost anything, and the answer is to plug one in, which `_offer_spare_pad` then hands
  straight to that player. Found by `tests/vehicles.gd`, which boots real matches headless where there
  are never any joypads at all, and guarded now in `tests/match_exit.gd`.
- **A SPARE PAD IS OFFERED TO WHOEVER IS WITHOUT ONE** (`Main._offer_spare_pad`, `Player.adopt_device`).
  Godot usually hands a reconnected pad its old index back, so that path needs nothing; the case that
  actually happens is the batteries dying and somebody picking up a DIFFERENT controller, which without
  this is an input nothing is listening to while its owner sits in front of a match they cannot play.
  Two traps, both found by the test rather than by looking: the hold is keyed by the DEAD device and
  must be released against THAT id (releasing the new one leaves the match stopped forever by a
  controller that is never coming back); and **whether a player's pad is alive is tracked from the
  SIGNAL, not re-derived from `Input.get_connected_joypads()`** — that list is the right answer to "is
  this plugged in now" and the wrong one to ask inside the change you are reacting to, where it had not
  yet agreed that a just-adopted pad existed and moved the player straight onto the next one to arrive.
- **AND THE KEYBOARD DRIVES A DISCONNECTED PLAYER'S OVERLAY** (`SettingsOverlay._pad_lost`). Solo, a pad
  falling out stops the match and the only thing that can restart it is a screen driven by the pad that
  just died; a controller that has genuinely broken would otherwise leave the game frozen with no exit
  but killing the process, which is the exact failure this whole pass is about. Gated on being
  DISCONNECTED and never on merely being a pad player, or one keyboard would silently drive four
  overlays at once.
- **The in-game START overlay (`scripts/settings_overlay.gd`) is PER PLAYER, not a pause.** It opens
  over that player's own screen while the other three keep playing; the opener stands still like the map
  screen (`Player.settings_open`). It edits LOOK SENSITIVITY and AIM ASSIST (per-device, in
  `Controls._settings`), rebinds any button in place, and stores/loads whole configs under a CUSTOM NAME
  (sensitivity + assist + that device's bindings, loadable onto whatever device a player is on next
  match). Driven by polling THIS player's own device plus `_input` for rebind capture and name typing —
  verified that **`_input` DOES reach a node inside a SubViewport**, both keys and pad.
- **GAME OPTIONS live in `Controls._options`** (its own `[options]` section in `user://controls.cfg`),
  separate from bindings and per-device feel settings, because they belong to the MACHINE rather than to
  a device or a match. They are shown at the bottom of the CONTROLS screen only because that is the only
  options screen the game has — **a real SETTINGS screen off the menu is owed**, and the storage is
  already split so that is a screen to write and not a migration.

## HUD

- **THE GAMEPLAY HUD WEARS THE SIDE'S COLOUR, NOT THE SEAT'S** (`Main._build_hud` takes
  `GameState.team_color(player.team)`). It used to take `PLAYER_COLORS[player_index]` — P1 red, P2 blue,
  P3 green, P4 yellow — so the minimap ring, the health bar, the ability gauges and the weapon readout
  all announced WHICH CONTROLLER you were holding, which is the one thing a player already knows. What
  the HUD is read for mid-fight is which side everything belongs to: the contacts on the minimap, the
  posts, the bolts coming past your head and the armour in front of you are all in faction colours, and
  the frame around them matched none of it — a Republic player and the Separatist they were shooting at
  could be reading the same red HUD. It follows a chosen TINT for free, since `team_color` is already
  "the colour this side was given on the menu".
  **THE COST IS REAL AND IT WAS ACCEPTED**: four players on one team now read four identically coloured
  quadrants, so finding your own screen by colour stops working. What still calls it is the P1..P4 TAG,
  which keeps its text and its place under the minimap.
  Two notes that follow from it: the health gauge's LOW warning may not be carried by the fill colour
  (one of the sides is red, and RED is a selectable tint), which is why the white edge exists; and the
  ability gauge's spent state takes the side's colour rather than grey.
- **THE MINIMAP IS A WINDOW, NOT A SMALL COPY OF THE MAP SCREEN** (`scripts/minimap.gd`, top left).
  They answer different questions and are priced differently: opening the map STOPS you moving, so it
  can afford the whole level, the mortar cursor, a grid and labels. The minimap is up the whole time and
  costs you nothing, **so it may only answer the two things you can ask mid-fight — where am I facing,
  and who is near me.** Everything else was left out for that reason and not for room. It draws
  `RADIUS_M` (45 m) around you with you at the centre: a 260 m map in 116 pixels is a smear with four
  dots in it, true and useless, where a fixed metres-per-pixel window means a dot's distance from the
  middle is a real distance you can act on.
- **It is a SQUARE because a Control clips to its RECT.** Drawn as a disc first, the footprints ran
  straight out past the rim — nothing in Godot clips a canvas item to a circle, and masking with an
  opaque annulus is not available since the HUD is transparent over the 3D scene. `clip_contents` on a
  square is the whole fix, and a square spends its corners on map instead of nothing. Corner reach is
  1.4× the short axis, hence `CORNER_M` and a BOX test rather than a radius for contacts.
- **NORTH-UP, matching the map screen.** A rotating minimap is easier to steer by and would then
  disagree with the map screen, which is north-up because a level laid out north-up is how everyone has
  already learned it. Two pictures of the same map that turn different ways is worse than either. **What
  carries your heading is that YOU are an arrow and not a dot.**
- **A SCAN DART PUTS THE ENEMY ON YOUR WHOLE SIDE'S MINIMAPS, and that is the only thing that ever
  does.** Teammates are always drawn; an enemy appears only while `GameState.is_scanned_for(body, team)`.
  Same discipline as the map screen and thermal read, but a scan is a thing somebody spent a slot on and
  it expires. **A scanned contact is a HOLLOW DIAMOND, not a coloured dot** — at 116 pixels a marker's
  colour is the first thing to go, and "is that one of mine" has to survive a glance.
- **The shape cull runs in PACKED ARRAYS, and the dictionaries were the cost.** `map_shapes` is an array
  of dictionaries; walking it four viewports deep meant four hashed lookups per footprint per viewport
  over several hundred footprints. Flattened into `PackedFloat32Array`/`PackedVector2Array` once at
  build with a squared-distance reject: **1.68 ms baseline, 2.58 ms as dictionaries, 2.05 ms as packed
  arrays** — the widget costs ~0.35 ms for four, and two thirds of the naive cost was hashing.
- **It redraws on MOVEMENT, per viewport — the opposite of the scan overlay on purpose.** The scan's "is
  anything live" is one answer for everybody so it is ticked globally; a minimap's picture moves when ITS
  OWN player moves, so one player sprinting must not cost the other three a redraw. `should_redraw()`
  gates on `MOVE_EPSILON` (0.35 m), a turn, and the scan/post revisions.
- **The player tag moved BELOW the minimap, not beside it.** The scoreboard is a centred full-rect label,
  so on a quarter-screen viewport at 13pt it starts far enough left that a tag pushed sideways lands on
  "REPUBLIC 0". **Layout is a property of the WHOLE SCREEN**, so a look test building one widget against
  a backdrop cannot see it — `tests/hud_frame.tscn` boots `main.tscn` and photographs a real match.
- **HEALTH IS A NUMBER *AND* A BAR** (`scripts/health_gauge.gd`). It was the number alone, which is exact
  and unreadable: a number has to be *read*, and reading is the one thing nobody is doing mid-fight on a
  quarter screen. The bar carries the glance, the number stays for deciding whether you can take another
  hit. The CHIP (a pale ghost falling to the real value over ~⅓ s) is what makes a hit read as a hit
  rather than as the bar simply being shorter. **Low health cannot be signalled by turning the bar red
  alone: P1's own colour IS red** — it also thickens the outline to white and turns the number red.
- **AN ABILITY IS A ROUND GAUGE, Battlefront-style** (`scripts/ability_gauge.gd`): white while ready, the
  PLAYER'S OWN COLOUR the moment it is spent, refilling from the bottom, with a one-off flash when it
  comes back. It replaced a line of text per gadget ("CABLE 3s") — accurate, and useless at the edge of
  vision where a HUD is actually read. **Spent takes the player's colour rather than grey** because on a
  four-way split every player already reads their own quadrant by that colour, so a charging ability
  reads as *theirs* rather than as a disabled control.
  - **The fill is a VERTICAL WIPE, not a pie slice.** A radial sweep reads as a clock ("how long"); a bar
    reads as "how much", the honest question for fuel, a guard pool and a cooldown alike. Clipped to the
    circle by drawing the disc and masking the top with the background colour — no stencil, no shader.
  - **One widget, three kinds** (`KIND_GADGET`/`KIND_DASH`/`KIND_GUARD`): the dash and the saber guard
    are not gadgets but are read exactly the same way. It asks the gadget's ACTION, not what was bought,
    so a jump pack shows the jetpack's fuel and an iron halo shows the barrier's icon. The cloak DRAINS
    while up — what matters then is how much invisibility is left, not the next cooldown.
  - **Icons are drawn, not textured** — twelve images to author, import and keep in step with the
    catalogue, against a dozen lines of vector art each that scale to any HUD size. Deliberately crude:
    at 46 px an icon is a silhouette whose only job is to be told apart from the other one you carry.
    `tests/hud_look.tscn` renders a contact sheet of every icon at three charge levels, which is the only
    way to judge a set drawn blind — it caught FORCE PUSH and FORCE PULL rendering identically (the icon
    has to MIRROR, not just change an arc radius nobody can see).
  - **Redraw only when the picture changes.** The value is quantised to 64 steps, so a six-second
    cooldown redraws about ten times a second and a full one never.
- **An overlay on `process_frame` re-records its canvas item every frame even when it draws nothing.**
  Scan, thermal, the bloom crosshair and the two royale readouts all go through ONE
  `Main._tick_overlays`: scan and thermal redraw only while something is live plus the one clearing frame
  after, the crosshair only when that player's own cone has moved, the royale readouts on a 10 Hz slow
  group. One tick function rather than six closures, so the per-frame cost of the HUD is visible in one
  place. **`_tick_scans` is ticked ONCE for all four viewports**, because "is anything live" is a global
  answer and a per-overlay check would let the first viewport flip the flag and the other three miss
  their clearing redraw.
- **A HUD that rebuilds itself every frame pays for glyph shaping every frame.** Assigning `Label.text`
  re-shapes whether or not the string changed, and the Conquest spawn screen is up for every dead player
  at once. It compares a handful of scalars first (`GameState.posts_revision` — an O(1) token bumped when
  a post changes hands — plus tickets, the player's picks and the countdown IN WHOLE SECONDS, which is
  all it prints).
- **THE RECORD IS SEPARATE FROM THE SCORE, and that is why `GameState.record_kill` sits BESIDE `add_frag`
  rather than inside it.** What a kill is WORTH is a mode rule and pays nothing in four modes out of five;
  that a kill HAPPENED is true in all of them and is what the killfeed and the post-match table read.
  Folding the record into `add_frag` loses every kill outside deathmatch. **Stats are per HUMAN, keyed on
  `player_index`** — a Bot is freed on death and the next one is a different instance, so there is nothing
  stable to accumulate into; team totals are already in `scores`. **A teamkill and a suicide cost a death
  and pay no kill**, or the quickest route up the table is a grenade at your own feet.
- **WHERE THAT CAME FROM** (`scripts/hit_direction.gd`, fed by `Player.hit_from`). The game told you that
  you had been hit three ways — a red flash, a dull thud, the number going down — and never told you the
  one thing that decides what you do next. On a quarter-screen viewport with eight bodies on the field,
  "I am taking fire" without "from behind me and to the left" is not actionable: you turn the wrong way
  about half the time, and dying to something you never saw reads as the game being unfair rather than
  as having been outplayed.
  **THE BEARING IS RECOMPUTED EVERY FRAME FROM THE WORLD POSITION, never frozen at the angle the hit
  arrived on.** That is the whole mechanic — what a player DOES with this is turn until the wedge is at
  twelve o'clock, so it has to swing as they turn and as they walk. A stored angle is not a weaker
  version of the feature, it is an actively misleading one.
  **`hit_from` IS A SEPARATE SIGNAL FROM `damaged`, AND IT IS RAISED EARLIER.** `damaged` fires only once
  a hit has cost health — the saber guard and a full overshield both return before it — and "where is
  that coming from" is the question you most need answered in exactly those cases: a shield eating a
  burst still means somebody has line of sight on you. Being told where a hit came from is not the same
  information as being told it hurt, so it is not the same signal.
  A burst is ONE marker refreshed rather than six stacked (`MERGE_ANGLE`, compared as angles because two
  men ten metres apart at eighty metres out are one direction to somebody turning), capped at
  `MAX_MARKS` so a crossfire cannot ring the screen.
- **AND IT IS THE ONE PIECE OF HUD THAT IS NOT IN THE SIDE'S COLOUR.** Everything else was moved onto the
  faction's colour because it is all answering "whose is that"; this answers "you are being hurt", which
  is the only thing on screen about HARM rather than about allegiance. In the side's colour it would read
  as a friendly marker, and on a side whose colour IS red it would vanish into the rest of the frame at
  exactly the moment it has to cut through. Same argument as the health gauge's white low-health edge.
- **A KILLFEED DESCRIBES BODIES THAT ARE ON THEIR WAY OUT, so nothing in it may hold a node.** Entries are
  plain dictionaries of STRINGS built at the moment of death, and `combatant_name` is **deliberately
  untyped**: a `body: Node` parameter cannot even be CALLED with a freed object — GDScript refuses the bind
  before the function runs, and a refused call aborts whatever was recording the kill (house rule 6). It is
  ASKED, not required: a combatant with no `combatant_name` gets its class back rather than taking the whole
  record out with it.
- **ONLINE THE FEED IS THE HOST'S AND IS MIRRORED FROM ONE PLACE** (`GameState.log_kill`, guarded by a
  `mirror` flag so a wire entry is not echoed back). A bot dies on the host and a player dies on whichever
  machine owns them, so the alternative is every death path knowing how to replicate itself — which is how
  two machines end up with feeds that disagree about what just happened. Names are resolved on the machine
  that HAS the bodies and travel as strings; a client has no node for a bot that died on the host.
- **THE DEATH CAM TURNS, IT DOES NOT CUT** (`Player._track_killer`, `DEATH_CAM_TURN`). A hard cut onto a
  body somewhere behind you tells you nothing about WHERE it is; watching the view sweep round is what
  places them on the map you just died on. It needs no second camera — the `RemoteTransform3D` on Head
  already drives the camera, so turning the body and pitching the head is the same two dials a live player
  steers with. It stops tracking when the killer dies and **holds the last heading rather than snapping
  back**, and the killer's name is kept as a STRING alongside the reference because the reference is
  usually freed before you finish reading it.
- The HUD picks the reticle in `_add_reticle`'s refresh: reddot → dot, else holo → ring, else scope →
  blackout, else the bloom crosshair.

## Procedural worlds

`map_planet.gd` (`PlanetMap`) generates a map from a PLANET (Geonosis / Kashyyyk / Coruscant /
Mustafar / Hoth), re-seeded every match from `GameState.planet_seed`. A planet is a table row in
`PLANETS`: palette, sky, sun, terrain octaves, weather density and which `_lay_*` function places its
landmarks. **A sixth world is a row and one function.**

- **A PLANET IS A MAP, NOT A SETTING.** There was ONE row called PROCEDURAL WORLD and a PLANET
  dropdown somewhere else deciding which of the five it built — so five of the game's nineteen maps
  were invisible on the screen where you choose a map, reachable only by picking a row that named
  none of them and then finding a second control. Somebody choosing between Hoth and Kashyyyk is
  choosing a MAP by every meaning of the word. Each world is now its own `GameState.MAPS` row
  carrying a `"planet"` key, plus RANDOM WORLD which still rolls.
  **APPENDED, NEVER INSERTED** (house rule 8): `map_index` is stored in a queued playlist and in
  `user://setup.cfg`, so inserting a row re-points every round anybody saved in an earlier session.
  The `"planet"` values are literal INTEGERS because naming `PlanetMap.Planet` from `game_state.gd`
  is a parse-time cycle — so `tests/playlist.tscn` checks the rows against `PlanetMap.PLANET_NAMES`
  BY NAME, which is house rule 7 and the only thing standing between a row and the wrong world.
  **`map_planet()` is asked before the PLANET setting everywhere** (`chosen_planet`, `map_blurb`),
  and the setting survives for the rolled row alone. The names carry (GENERATED) because two of
  them collide with hand-laid maps, and that difference is the point of the row: one is an authored
  220 m forest that is the same every time, the other is a forest rolled fresh at the drop.
  **And `procedural_map_index()` keeps the world already chosen** — MASSIVE needs generated ground,
  not a rolled one, so locking it must not throw away the fact that somebody picked Hoth.

- **THE TERRAIN MESH IS EMITTED IN ~48 m CHUNKS (`CHUNK_METRES`) SO IT CAN BE FRUSTUM-CULLED**, and what
  makes that possible is taking vertex normals from the ANALYTIC surface rather than from
  `SurfaceTool.generate_normals()`. Averaged normals are averaged WITHIN one mesh, so a chunked heightfield
  gets a lighting seam along every chunk edge — geometry continuous, shading not. For a height field the
  normal is `(-dh/dx, 1, -dh/dz)` normalised: exact, independent of how the mesh is cut, seamless by
  construction. `steepness_at` already computed the gradient inline and now goes through **`gradient_at`**,
  so one place computes it and `terrain_math.tscn` still asserts the pair agree. **Size chunks by METRES,
  not by a fixed grid count** — these maps run 120 m to 290 m, so a fixed 4×4 gives one map 30 m chunks and
  another 65 m ones. **The COLLIDER stays whole**: physics does not frustum-cull, so splitting it buys
  nothing and costs thirty broadphase entries instead of one. See PERFORMANCE for what this measured.
- **THE RULE EVERYTHING ELSE FOLLOWS FROM: terrain is always walkable, structures are always boxes.** The
  nav grid is stamped from BOX COLLIDERS only and cannot see a trimesh — so a heightfield allowed to make
  cliffs would have bots pathing into them forever. Terrain carries the LOOK; boxes carry the scale, cover
  and routing, and are understood by the nav grid, the map screen and every sight check for free.
- **The slope budget is arithmetic, not tuning.** The height function is a sum of sines, so each octave
  contributes at most `amp * freq` to the gradient and the sum is normalised under `MAX_GRADIENT`
  (0.50 = 26°). Whatever anyone puts in the octave table stays walkable.
- **A structure's SHAPE and its FOOTPRINT are separate, and physics follows the SHAPE.** `_solid` always
  builds a box (the nav grid needs one) but the mesh may be a cone, a faceted column, a wedge or a crag —
  a world built only from cubes reads as a blockout however well it is lit. Those shapes collide as
  themselves via `mesh.create_convex_shape()`; until that, a spire was solid out to the full width of its
  base all the way to the tip. **The footprint box stays in the tree, DISABLED** —
  `scan_map_geometry` reads the shape resource off the node and never asks physics — so the nav grid and
  map screen keep the conservative box while bullets and bodies get the real silhouette. A hull is never
  larger than the box it replaces, so nothing new can trap anybody.
- **`_solid` clamps every footprint to `NAV_MIN_WIDTH`.** A box thinner than the nav grid's cell spacing
  falls between two cell centres and A* routes straight through it. **Clamping at the call sites was tried
  and is not enough** — `_stack` clamped width but let depth vary below it, and low cover never clamped at
  all, which produced a nav test that passed or failed *by seed*.
- **Caves, bunkers and trenches are built UP, never carved.** A carved passage is a hole the AI cannot see
  with walls too steep to climb out of; a box shell on the ground is a cave you fight through and the grid
  understands its walls and its opening.
- **Rivers and lava are one mechanism**: a plane through the terrain at a level MEASURED from the height
  distribution (`_sea_level`). The height function is a sum of products of sinusoids so its median is ~0
  and nothing about the amplitudes tells you where the 15th percentile is — two hand-picked fractions both
  produced an open ocean.
- **TERRAIN MUST NOT GO BELOW y = 0** (`height_at` adds `terrain_amplitude()`). `scan_map_geometry`
  discards any box whose TOP is at or below `MAP_FLOOR_TOP` — that is how it throws away a map's floor
  slab. With terrain running to -5 m, every structure standing in a hollow had its top below zero and was
  silently dropped: **invisible to the nav grid and the map screen while physics still collided with it.**
  That is the "routes pass through real geometry" failure; it depended on where the generator dropped
  things, which is why it failed *by seed* and survived two wrong fixes. **Any future map with negative
  ground has the same trap.**
- **GREEBLING is what makes box architecture read as built** (`_greeble` / `_lamp` / `_drift`, collected
  during layout and emitted as three MultiMeshes). A flat face has no scale; the moment small repeated
  shapes sit on it the eye reads the whole object as large. None of it collides.
- **A face-mounted greeble's yaw is `PI/2 - a`, not `-a`.** `Basis(UP, t)` sends +Z to
  `(sin t, 0, cos t)`, so that is the rotation putting a piece's thin axis INTO the facade. Using `-a`
  turns every piece ninety degrees, and the lit window bands stuck out of the towers as glowing shelves.
- **A Coruscant tower is a GRAMMAR, not a stack**: podium → shaft segments stepping in at setbacks → crown
  → mast, with vertical mullions, horizontal floor bands and lit window rows on all four faces, plus
  skybridges between neighbours. **Those four masses in the right proportions are what the eye recognises
  as architecture**; no amount of detail rescues the wrong proportions.
- **Hoth is a snowfield people dug into, not a glacier**: the relief lives in the terrain (its octaves are
  the tallest of the five) and what stands on it is low and built — bunkers with a sloped glacis and an
  embrasure, ice revetments, trenches, caves, dark rock outcrops. **Snow is already the brightest albedo in
  the game**, so it is the one planet that wants LESS exposure (1.02 against 1.4–1.6). The dark outcrops
  are the only value contrast on the map and have to be genuinely dark.
- **Kashyyyk's underbrush is decoration, deliberately** — a dense low mat plus taller clumps at head height
  that break a sight line, all of which you walk and shoot straight through. A forest floor you cannot
  cross is worse than a bare one, and the AI needs to know nothing about it. Foliage blobs are squashed
  low-poly SPHERES: a prism at that size reads as a tent from every angle.
- **THE BUG THAT COST THE MOST: the terrain mesh winding was inverted**, so its normals pointed DOWN and
  the sun never touched the ground. It renders as a dark muddy plain under a perfectly good sun while every
  box on it lights correctly — which reads exactly like a palette problem, and the palette and sun angle
  each got "fixed" once while chasing it. **The isolation that finally worked: force `ALBEDO = vec3(1.0)`
  and measure.** A white surface still rendering at 0.30 cannot be an albedo problem. Flipping the winding
  took the same ground from 0.27 to 0.76.
- **A generated map cannot be judged from one screenshot** — it is different every run.
  `tests/planet_look.tscn` shoots all five worlds from a high wide, a real spawn at eye level, and a mid
  three-quarter.

## Night

- **TIME OF DAY is a property of the WORLD, so it belongs to the generated one and nothing else**
  (`GameState.time_of_day`, `is_night()`, the dropdown disabled on hand-laid maps exactly as PLANET is). An
  authored arena's lighting IS that map being itself; a generated world is a table row, and night is
  another row.
- **NIGHT IS A SECOND PALETTE, NOT A DIMMER.** The obvious version — one multiplier over the day table —
  takes the picture to mud and puts the cover boxes into unreadable black, which is a *gameplay* bug.
  **What night changes is the RATIO between things, not their sum**: the ground goes down a long way, the
  ambient goes down less, and anything that is genuinely a light source goes **up**, because in the dark
  being the brightest thing on the map is its entire job. Each planet carries a `"night"` block laid OVER
  its day row (`PlanetMap.world()`, merged one level deep, resolved ONCE per match into `_world` — **nothing
  may read `PLANETS[planet]` any more** or it builds half a night map).
- **The terrain palette is DERIVED, not authored** (`PlanetMap.nightfall`), so a new world gets a night for
  free the way it gets a nav grid for free. Three things move together and all three matter: value,
  **saturation** (a colour only *darkened* stays as saturated as it was, which is the tell that gives away a
  scene merely turned down) and a pull toward the moon's own hue. `NIGHT_EMISSIVE` (`vein_col`) is exempt:
  lava does not get darker when the sun goes down, it gets more important.
- **NIGHT COMPRESSES THE RANGE, IT DOES NOT SCALE IT** — hence `NIGHT_FLOOR` *plus* `NIGHT_ALBEDO` rather
  than a multiplier. A plain multiplier failed on precisely the worlds that needed it most: it took a bright
  desert to a readable dark and a forest floor already dark in daylight to pure black, so the two worlds
  with no light of their own were the two the derivation ruined. **`NIGHT_FLOOR` is deliberately the same
  number as `night_palette.gd`'s `MIN_GROUND_V`**, so a derived colour cannot fail the test by construction
  and only an AUTHORED override ever can — which is where a mistake actually gets made (Hoth's rock did, and
  the test caught it).
- **Each world's night is its own, and the authored block is for where the derivation is wrong.** Geonosis
  is the darkest and the biggest sky — hard starlight, no cloud, and the moon deliberately HIGH, because a
  low light over flat hardpan is grazing light and the plain returns nothing. Kashyyyk has no moon worth
  speaking of (the canopy takes it) so its AMBIENT is the highest of the five and is the only thing holding
  the forest floor up. Coruscant and Mustafar get *brighter* in places: window rows, city glow and lava are
  already emissive, so with the sky pulled to nothing they stop being decoration and become the
  illumination. Hoth is the brightest night for the same reason it was the dimmest day.
- **THE GUNS ARE THE LIGHTING, and that is three changes, not a mood.** The muzzle flash reaches ~20 m
  instead of 6.5 and lasts nearly twice as long (`Weapon.NIGHT_FLASH_*`, **resolved once at spawn** — a
  repeater fires 13×/s and this cannot change inside a match). Every round that LANDS lights the ground it
  landed on (`Impact`), which by day is deliberately not done: **the flash shows the shooter where they are,
  the impacts show everyone else where the shooting is going.** Every explosion reaches 2.4× as far.
- **The impact lights are a FIXED POOL of 14, claimed round robin and never allocated** — so a repeater and
  a hundred-body battle cost the same as one pistol (house rule 4). The pool hangs off the current scene and
  is rebuilt on the next map.
- **Two things had to come DOWN at night, which is the opposite of what you expect.** The blast's additive
  sphere was tuned against a sun; in the dark it saturates flat and comes back as an opaque orange DISC with
  a hard edge and no falloff inside it. It is turned down AND made smaller than the light it throws, so its
  silhouette lands on ground that is already lit. The real light does the work.
- **Measured (Intel UHD 620, 4 viewports, 2x MSAA, generated world):** night by itself is FREE — 25.2 ms
  against the same map by day, within noise. With every light the mode can produce held on at once
  (`QS_NIGHT=2`) it is **~27.9 ms, about +2.7 ms**, for a state that in play lasts a tenth of a second.
- **A night map photographed in silence proves nothing** — the mode is never in that state.
  `tests/night_look.tscn` shoots each world dark and quiet with two bodies in frame (the READABILITY shot),
  the same view with rounds landing and a blast through the real code paths, and a high wide. Its first
  version put the strikes at a height off the camera and photographed six impact lights floating three
  metres up lighting nothing — it managed to photograph the feature and show none of it.

## Rendering: the Grade and the Quality tiers

- **THE GRADE (`scripts/grade.gd`, `class_name Grade`, all static) is how light is RENDERED, in one place.**
  A map builds its own environment and lights — sky, fog colour, sun position — because that IS the map's
  identity. But the response curve, ambient model, glow threshold and shadow settings are not per-map
  decisions, and they had been copy-pasted into thirteen `_build_environment` overrides that then drifted.
  `Grade.apply_to(node, exposure)` runs OVER whatever was built. Five parts: **AgX tonemapping** (before it,
  anything brighter than white clipped — a pale cover box in daylight was a flat white silhouette);
  **sky-sourced ambient BLENDED with the map's own colour** at `SKY_AMBIENT` 0.3, never replacing it;
  **glow on an HDR threshold** with `glow_bloom` zeroed; **aerial perspective + height fog**; and a
  contrast/saturation pass, because AgX is deliberately flat. Per-map override: `grade_exposure`.
- **Exposure was measured, not guessed.** AgX sits well below the Filmic curve these maps were lit under.
  Rendered at 1.15 / 1.6 / 2.0 against the darkest map (Crossfire at night) and the brightest (Overgrowth at
  noon): **1.6 is the only value where the night map's cover boxes stay readable AND the daylight map's pale
  cover keeps a face on it.**
- **Two traps in the grade, both found by looking**: sky ambient at 0.55 took half the fill off every night
  map and put the cover boxes into unreadable black — a *gameplay* bug, hence the 0.3 minority share; and
  glow weighted toward the WIDE levels (1.0 at level 3) turned a muzzle flash lighting the floor into a
  white pool the size of the arena, because the lit ground crossed the HDR threshold and was then smeared
  across ten metres. **The levels are weighted toward the SMALL end now** — that is the difference between a
  halo and a wash.
- **The starfield sky is GRADED, not black, and that is load-bearing rather than decorative.** The grade
  sources part of its ambient from the sky, so whatever the shader paints is what lights the shadow side of
  everything on a night map — a black sky contributes black. It runs zenith → horizon with a tight band at
  the skyline.
- **`Grade` returns early on non-RD renderers.** SSAO/SSIL/volumetric fog do not exist under GL
  Compatibility and setting them raises an error per environment per call, which buried the real output of
  every look test. `RenderingServer.get_rendering_device() == null` is the honest question. `Grade` applies
  the Forward+ half unconditionally; Godot ignores those properties under Compatibility, so switching
  renderer is one line.
- **`Quality` (`scripts/quality.gd`, all static) is what the picture is ALLOWED to cost, in one place.**
  Three tiers (LOW / MEDIUM / HIGH) each state a shadow atlas size, soft-shadow filter, whether blend splits
  and glow run, an MSAA level and a render scale — **and the scale and shadow entries are arrays indexed by
  VIEWPORT COUNT, because one player and four players are not the same machine.** `apply_global` /
  `apply_to_viewport` / `apply_to_light` / `apply_to_environment` are the only places any of this is set —
  same argument as `Grade`. AUTO (the default) starts at MEDIUM and hands the rest to the governor.
- **MSAA is set on the SUBVIEWPORTS (`Quality.apply_to_viewport`, which is also where render scale lands),
  not just in project.godot** — the project setting only reaches the root viewport, and the game never
  renders into that. It is worth more here than in most games: the scene is untextured flat-shaded boxes, so
  essentially all of its aliasing is geometric edges, which is exactly what MSAA fixes and a post-process AA
  smears. Measured (4 viewports, Kashyyyk, vsync off): **off 12.03 ms, 2x 13.87, 4x 14.32, 8x 16.78.** 2x
  ships as the conservative default; 4x costs almost nothing over 2x, so it is the first dial to turn up.
- **Four shadow splits cost ~2 ms and two do not.** `Grade.light` ships `SHADOW_PARALLEL_2_SPLITS`. Four was
  chosen because these maps run to 260 m and one split over that distance makes near-ground shadows crawl;
  two keeps most of that. **If a discrete GPU ever becomes the target, this is the first thing to put back.**

## Smoothness

- **"LAGGY" WAS NEVER A FRAME-TIME PROBLEM, IT WAS A FRAME-PACING PROBLEM.** The averages on record
  (~20 ms at a four-way split) are only 20% over budget, which should read as a slightly soft game and not
  the stutter it was. What makes it stutter is **vsync's failure mode**: a frame that misses is not
  presented slightly late, it is HELD and presented at the next refresh, so 18 ms of work becomes 33 ms of
  latency and every third frame shows a body twice as far along. A game at a rock-solid 30 is smooth; a
  game averaging 55 is not. **The goal is not a lower average, it is a frame time that lands inside its
  interval every time** — pick an interval the machine can hold, then spend what is left on the picture.
- **ADAPTIVE VSYNC AND PHYSICS INTERPOLATION ARE WHAT "SMOOTH" ACTUALLY MEANT** (`project.godot`), and
  neither makes the frame cheaper. Adaptive tears on a missed frame instead of holding it. Physics
  interpolation fixes the other half: bodies step at 60 Hz and are drawn whenever the frame is ready (see
  house rule 10 for what that costs you).
- **THE MACHINE'S SPEED IS NOT A CONSTANT, WHICH IS WHY THIS HAD TO BE ADAPTIVE.** The same scene measured
  **26 ms cold and 48 ms after ten minutes of play** — the GPU thermally throttles to roughly half clock,
  and no static quality setting is right on both sides of that.
- **`FrameGovernor` (`scripts/frame_governor.gd`) HOLDS THE FRAME TO ITS INTERVAL BY MOVING THE RENDER
  SCALE, and drops the RATE only when resolution runs out.** It samples a `WINDOW` (0.6 s) and reads the
  average and the FRACTION OF LATE FRAMES. Over budget → trim `scaling_3d_scale` by `STEP` (0.05) down to
  `MIN_SCALE` (0.55). Bottomed out and still missing → drop an FPS rung (60 → 30), doubling the budget in
  one move. Comfortable for `RAISE_WINDOWS` in a row → give resolution back one step at a time.
  **Resolution is the right first lever because the frame is fill-bound** (three independent measurements
  say so), so it is the one dial whose cost is close to linear and whose reduction is least visible — at
  0.85× on a 960×540 quadrant of flat-shaded boxes, nobody has ever noticed.
- **THE TAIL IS WHAT YOU FEEL, SO THE TAIL IS WHAT IT STEERS BY** (`LATE_FRAC`, 0.2). With vsync on, a
  window where four frames in five hit 16.6 ms and the fifth takes 33 averages to 19.9 ms — comfortably
  "nearly fine" — and what the player sees is a hitch five times a second.
- **A RUNG DROP MUST NOT RESET THE RESOLUTION**, or the governor oscillates and the cure is worse than the
  disease: it walks the scale back down, misses the new rung, drops another and snaps back — a sawtooth in
  *both* dials whose every tooth is a visible stutter. The scale is left where it was and the ordinary raise
  path climbs it back, which makes the whole system monotonic: one dial, one step, one direction per window.
- **CLIMBING BACK IS A PROBE WITH EXPONENTIAL BACKOFF, because under vsync the obvious test is
  unanswerable.** "The average is well under the interval" can never be true — a frame meeting a 30 fps cap
  measures at 33 ms BY DEFINITION. So a rung raise is a PROBE: climb, watch for `RUNG_WINDOWS`, then commit
  or fall back and DOUBLE the interval before trying that rung again (`_probe_windows`, up to
  `PROBE_WINDOWS_MAX`). Without the backoff a machine 5% short of 60 fps re-probes forever, and every probe
  is a second of stutter.
- **A BIG MISS SKIPS THE STAIRCASE** (`RUNG_NOW`, 1.45). Walking the scale down one step per 0.6 s window
  from full to 0.55 is nine windows — five and a half seconds of visible stutter before the rung it was
  always going to need.
- **THE FOUR DIALS THAT ACTUALLY MOVE THE FRAME, measured** (`render_cost.tscn` `QS_ABLATE=1`, 4 viewports,
  generated world, thermally settled): **directional shadow atlas 4096 → 2048 is 8.08 ms**, **render scale
  0.60× is 8.66 ms**, **MSAA off is 2.99 ms**, **shadow blend splits off is 2.97 ms**. Everything else is at
  the edge of noise, glow included (1.3 ms). **The shadow atlas being the single biggest line was a surprise
  worth recording** — it is a full-screen-ish depth pass per split and it was at the engine default, so it
  had never been priced.
- **THE TERRAIN AND SKY SHADERS WERE THE PRIME SUSPECTS AND ARE INNOCENT — 0.07 ms and 0.00 ms.**
  `planet_ground.gdshader` runs several octaves of value noise per fragment and looks *exactly* like the
  cause of a fill-bound frame, which is why it was measured before anything was rewritten. Replacing it with
  a flat albedo changed nothing. **Do not go optimising procedural noise on instinct.**
- **AND THE CPU IS NOT THE PROBLEM EITHER** (`perf.tscn` `QS_CPU=1`): disabling all bot, player and weapon
  processing in turn accounts for a small fraction of the tick. This matters because "laggy" is exactly as
  consistent with a script bottleneck as with a fill one, and the fix for each is the opposite of the other.
- **`QS_SMOOTH=1` IS THE ACCEPTANCE TEST and the only mode that keeps the SHIPPED settings** — vsync, the
  cap and the governor all live, because every other mode in that harness disables exactly what is being
  judged. It reports p50/p95/worst against the rate the governor SETTLED on (not against 60, which would
  fail a perfectly smooth 30), plus the percentage past one interval and past two — **that last is the hitch
  count, and it has to be zero.** Shipped result, 12 bodies, generated world by day: **1 viewport 60 fps at
  full resolution, p50 16.64 / p95 17.18 / worst 19.19 ms, 0% late, 0% hitches. 4 viewports a locked 30 fps
  at FULL resolution** (it dropped the rate, then climbed the scale back), **p50 33.20 / p95 33.79, 0.4%
  late, 0% hitches. 4 viewports at 100 bodies: 30 fps at 0.80×, 2.1% late, 0% hitches.**
- **A SPIKE MUST NOT BECOME A CASCADE** (`max_physics_steps_per_frame` = 4 in `project.godot`, against
  the engine default of 8). One 90 ms frame lets the NEXT frame run five to eight catch-up physics steps
  back to back, and at 4 viewports each step is ~5.4 ms of script and physics — so the frame that was
  meant to recover is guaranteed to miss as well, which produces another catch-up. That is the same
  spiral MASSIVE hit from the other direction (an O(bodies-squared) unstick loop drove it to five steps
  per rendered frame and 5 fps). Capped, a hitch costs the SIMULATION a few milliseconds of real time —
  invisible, because everything is interpolated — instead of costing the player a run of stuttering
  frames. Measured (`QS_SMOOTH=1`, 4 viewports, generated world): **frames past two intervals, which is
  the harness's own definition of a visible hitch, went from 1.7-2.1% to 0.8% and 0.0%**, and the worst
  frame from 92 ms to 26-73 ms.
- **THE RUN-TO-RUN SPREAD ON THIS LAPTOP IS LARGER THAN ANY CHANGE WORTH MAKING, and that has to be
  said out loud or every future measurement here is misread.** Two consecutive runs of the acceptance
  test on the SAME build settled on completely different configurations — one on 30 fps at 0.85 scale
  (p95 50.8 ms), the next on 60 fps at 0.55 (p95 21.3 ms) — because the GPU thermally throttles to
  roughly half clock and the governor is correctly adapting to a machine that is a different machine
  five minutes later. **The shipped figures recorded above were taken cold.** Anything measured after a
  session of test runs is measuring the thermal state; read the HITCH count, which is the number that
  survives it, and take the rest as a three-run average at best.
- **A LOOK TEST MUST TURN THE GOVERNOR OFF** (`Quality.governor_enabled`). It makes frame time consistent by
  making RESOLUTION inconsistent, so a screenshot suite left under it photographs whatever scale the machine
  happened to be at, and two runs disagree for reasons unrelated to the change being reviewed.
- **QUALITY and FPS CAP are machine options on the controls screen** (`Controls.graphics_quality` /
  `fps_cap`). The cap is a real setting, not a debug dial: capping to a rate the machine can hold is what
  stops the GPU sprinting into its own thermal limit, and the governor's rung ladder respects it.

## Performance

See HOUSE RULES 1–5 and 17 first — those are the rules; this section is the measurements behind them.

- **THE PHYSICS ENGINE IS PINNED TO JOLT, and the measurement is why.** It was on `DEFAULT`, which
  in Godot 4.7 silently resolves to Jolt — so the backend had already changed under the project
  without anyone choosing it, and every physics figure recorded before the 4.7 move was taken on the
  other one. Measured on the generated world, 4 viewports: at **14 bodies the two are the same**
  (physics 6.58 vs 6.59 ms). At **100 bodies they are not**: Jolt holds the tick (physics 16.1 ms,
  wall 16.69 ms — it kept up) where GodotPhysics3D does not (22.0 ms, wall 18.12 ms, and a p50 frame
  of **84.9 ms against Jolt's 33.1**, with 289 frames past 50 ms against 6). MASSIVE is the mode that
  decides this and it is not close. Pin it explicitly whatever the engine default becomes.
- **TRANSPARENCY WAS THE PRIME SUSPECT AND IS INNOCENT** (`QS_ABLATE=4`). Smoke clouds, blast spheres
  and bolt tracers are the only things in the game that cannot early-Z, so on a fill-bound frame they
  were the obvious unpriced cost — and the harness had never measured any of them. Held on at once:
  **3 clouds 1.17 ms, 6 blast spheres -0.25 ms, 24 tracers 1.59 ms**, against a 1.5 ms noise floor.
  Cheap because these maps have one directional light and the transparent surfaces are unshaded; if
  either changes, price it again. Still unmeasured: standing INSIDE a cloud.
- **THE EXTENDED RIG IS FREE AT SCALE.** 15 animated joints against the old 11, measured as an A/B
  between playing and paused: **0.003 ms for 100 bodies**. Wrists and ankles cost nothing to tick.
- **THE RASPBERRY PI TARGET HAS BEEN DROPPED.** The renderer is a documented CHOICE in `project.godot`,
  measured on the dev machine (Intel UHD 620, 4 viewports, Kashyyyk): `gl_compatibility` ~26 ms/frame,
  `forward_plus` ~126 ms. Forward+ buys SSAO, SSIL, volumetric fog and soft shadows and looks dramatically
  better — Hoth becomes a real blizzard, Mustafar's lava lights the air above it — and is unplayable on
  integrated graphics. **Even ONE viewport with every screen-space effect disabled measured 68 ms, so the
  cost is the renderer and the geometry, not the effects.** On a discrete GPU that flips.
- **THE FRAME IS FILL-BOUND, NOT DRAW-CALL BOUND, and three plausible culprits were measured and cleared
  before that was believed:** prop shadows off (no change), glow off (no change), and merging every body's
  boxes by joint and material (2620 → 2553 draws at 24 bodies, no change in ms). **At 6 bodies the frame is
  15.0 ms and at 24 it is 15.5** — the bodies are not the cost, the *map* is, drawn once per viewport. The
  merge stayed because it is free at runtime and worth more at a hundred bodies, but nobody should expect a
  millisecond from geometry here.
- **THE 4-VIEWPORT FRAME WAS ALREADY OVER BUDGET, and that is what a "lag spike" actually is.** Measured
  (Intel UHD 620, Kashyyyk, 2x MSAA, vsync off): **12 combatants 18.3 ms, 26 combatants 20.7 ms** against a
  16.7 ms budget. Two changes took it back: 2 shadow splits instead of 4, and per-part visibility ranges on
  the small stuff. Together ~20.7 → ~16.5 ms at 26 bodies. **Run-to-run spread is ±1.5 ms, so read these as
  three-run averages.**
- **WHERE THE CAMERA IS BARELY CHANGES WHAT THE FRAME COSTS, and that was measured to answer a question
  about VEHICLES** (`QS_VEHICLE=1`). The worry was that a vehicle would outrun the draw-distance tuning set
  for walking pace. **It does not, and the reason is worth more than the answer.** At 4 viewports, 12
  bodies: an infantryman at eye height is **20.4 ms and ~1520 draws / 563k tris**; a speeder at 2.8 m is
  **20.0 ms and ~1200 draws / 551k tris**; a gunship at 20 m is **20.9 ms and ~1110 draws / 549k tris**. A
  raised camera draws **27% FEWER calls**, because from up there more small parts fall outside their
  visibility range — the culling vehicles were expected to defeat actually favours them. Note it measures
  the CAMERA, so it says nothing about a vehicle's own mesh or about vehicles bringing more bodies into one
  place.
- **AN OBJECT IS CULLED AS A WHOLE, so a map-spanning object is never culled at all.** Set dressing is one
  MultiMesh per prop TYPE — an AABB covering the level, drawn by every viewport every frame however little
  is on screen. **The batching that made props affordable is the same thing that makes them un-cullable**;
  a trade worth knowing about, not a defect. The TERRAIN used to be the same (one `SurfaceTool` for the
  whole heightfield) and is now emitted in ~48 m CHUNKS so it can be culled per camera — see PROCEDURAL
  WORLDS for the analytic-normal trick that makes chunking possible without lighting seams.
- **CULLING BUYS GEOMETRY AND NOT MILLISECONDS, and that is the clearest statement of fill-bound there is.**
  Measured twice, from opposite directions. Camera pose: draw calls moved 1520 → 1110, a 27% swing, and the
  frame did not move (20.4 → 20.9, inside the ±1.5 ms spread). Terrain chunking (`tests/terrain_chunks.tscn`,
  A/B/A in one process, 4 viewports, 290 m world): **605k triangles chunked against 798k welded — a real 24%
  cut — and 218 MORE draw calls, with the millisecond difference (2.78) INSIDE the A-to-A spread (2.86).**
  The cost is per-pixel work at 4×960×540 with MSAA, not what is in frustum. **Do not expect a millisecond
  from geometry here**; the levers that move it are resolution, MSAA, the shadow atlas and viewport count.
  Chunking is kept for the triangle win and because per-chunk meshes are the prerequisite for terrain LOD,
  NOT because it made the frame faster.
- Every mesh renders 4× (one per viewport) plus a shadow pass — keep draw calls and material count low,
  prefer procedural shaders over textures. Target 60 fps at 1080p (4 × 960×540).

## Massive battle (50v50)

- **MASSIVE is the scale mode**: two sides of up to fifty, **procedural maps only**, playing by deathmatch
  rules. The rules are not the point at that body count — what a player is there for is being one rifle in a
  hundred, and any objective would just be a place the crowd stands. Locked to the generated world in BOTH
  the menu and `Main._ready` (so map rotation cannot walk it onto Hangar): the hand-laid arenas are
  eight-body maps. `GameState.MASSIVE_SIZES` offers 15/25/35/50 because the frame cost is real and a couch
  that cannot hold fifty should be able to play twenty-five.
- **A LINE TROOPER (`Bot.line`) IS DEFINED BY WHAT IT DOES NOT DO.** `Loadout.line_build()` is a rifle, a
  scope and nothing else — no gadget, no grenades, no squad, no mods. **The scope is the one thing they DO
  get**, because a bot's stand-off is derived from its cone, so without it a hundred of them walk into your
  face. The gun comes from the universe's own default kit, so a massive battle in 40k is fought with bolters
  and no table says so.
- **The four things that made a hundred bodies possible, in the order they mattered — every one measured:**
  1. **`_apply_unstick` was O(bodies) PER BODY with three script calls per pair** — `is_alive()` and
     `global_position` on every combatant, ten thousand times a physics tick. **28 ms a tick**, which put the
     loop into a catch-up spiral (five physics steps per rendered frame, 5 fps). It reads the frame's snapshot
     now (`sample_combatants` gained `live_bodies`). Still O(n²) — the constant was the problem, not the
     exponent.
  2. **Line troopers do not sweep against each other** (`collision_mask = 1`, layer unchanged).
     `move_and_slide` was 13.9 ms of a 22 ms tick, and a crowd is nothing but bodies near each other. They
     still stop at walls, are still hit by every ray, are still seen and still block spawns; what separates
     them is `_apply_unstick`, which was already doing that job. **Soft bodies in the crowd, hard geometry
     everywhere else.**
  3. **They step on alternate ticks at twice the velocity** (`MOVE_EVERY`), phase dealt at spawn. Identical
     displacement, thinking still every tick, collision sampled at 30 Hz — thirteen centimetres a step at a
     walk. `_apply_unstick` is gated to the same tick, since velocity written on any other tick is thrown away.
  4. **They are drawn as a crowd** (`CharacterModel.crowd`): no shadow at all, everything culls at 45% of the
     usual distance, the whole body gone past 130 m. One trooper's shadow among a hundred is not information
     anybody uses.
- **The cheap scan takes the nearest THREE, not the nearest one.** One candidate and one ray was cheaper and
  measurably wrong in the situation this mode is made of: in a crowd the nearest enemy is usually standing
  behind a FRIENDLY body, `_can_see` fails, and the bot finds nobody — **three of nine line troopers acquiring
  while stood in a firefight, nine of nine with three candidates.**
- **They also never plan a route.** A* is globally rate limited, so a hundred bots asking would starve the
  queue for the veterans and for each other, and each would then walk a route computed seconds ago through
  ground that has since filled with ninety-nine other people. Straight line plus `_watch_for_snag`, which
  handles what is actually in their way at this density: the crowd.
- **A few per side are ordinary bots** (`Main.MASSIVE_VETERANS`), because a battle of nothing but line
  troopers has no texture — nobody digs in, nothing gets shelled. **Every REPLACEMENT is a line trooper
  whatever it replaced**: the veterans are a seasoning dealt at the start, not a quota.
- **A hundred bodies cannot be built on one frame** — a character model is ~0.6 ms, so a hundred at once is a
  60 ms freeze exactly where the match starts. `Main._deal_massive` deals them out in batches of six across
  frames; nothing waits, because `match_live` is already gated on the humans deploying plus a countdown.
- **Measured (Intel UHD 620, 2x MSAA, 100 bodies, generated world):** script+physics **11.9 ms** a tick (from
  27.9 before the four fixes). Rendering: **1 viewport 11.6 ms / 86 fps, 2 viewports 13.9 ms / 72 fps, 4
  viewports 20.3 ms / 49 fps** (from 29.8).
- **Two traps found writing its test, both about the generated map rather than the mode:**
  `GameState.map_center` is a HORIZONTAL centre — dropping bodies at `map_center + Vector3(x, 2, z)` puts them
  inside the hill, where nothing can see or walk; and a battle FREES bodies as it runs, so any roster
  collected before it has to re-check `is_instance_valid` on the way out.

## Audio

- **EVERY SOUND IS SYNTHESISED IN CODE** (`scripts/sfx.gd`, `class_name Sfx`, static), for the same reasons
  the models are: no assets, no licences, no import step, and a new weapon earns a voice the way it earns a
  silhouette. **A sound is an envelope on a pitch on a timbre**: the envelope makes it an event rather than a
  note, the PITCH SWEEP is what stops it being a beep (struck things fall in pitch as they decay), and noise
  under a tone is what makes it physical rather than electronic. `saturate()` is the punch — a hit folded back
  from a peak of 3.0 is the same loudness and far denser.
- **`Audio` (autoload) owns voices, loudness and distance.** Voices are POOLED (one player is a repeater
  firing 13×/s and there are four of them); per-sound gain and PITCH SPREAD live in one `MIX` table, because
  the same sample fired 13×/s is instantly recognisable as one sample. **Distance is VOLUME, never panning**
  (`play_at`): on a four-way split a shot in player 3's viewport has no honest place in the stereo field, but
  "far away is quieter" is true for everyone — and past `HEARING` it is not played at all, which is also what
  stops two dozen bots saturating the pool.
- **The bank is built ONCE on a worker thread, in two stages.** Effects are ~0.3 s of rendering and the music
  another ~3.4 s, so they are delivered separately: a match started briskly would otherwise have no gunfire
  for four seconds. Until a stage lands its calls are no-ops. **Never render PCM on the main thread** — it is
  a per-sample GDScript loop over millions of samples.
- **A BLASTER IS A STRUCK WIRE, NOT A SWEPT TONE** (`Sfx.pluck`). The real DL-44 is Ben Burtt hitting the guy
  wire of a radio tower, and a guy wire is a STRING: what the ear recognises is not the pitch fall on its own
  but that fall happening to a metallic, inharmonic RING. `_blaster` was a swept saw plus a transient — the
  sweep was right and a swept saw has no ring, so it could only ever be a generic sci-fi zap however well it
  was tuned. **Exactly the shape of mistake as tuning `metallic` when what was missing was the albedo split.**
  The body is Karplus-Strong on a swept fractional delay line: fill a delay line with noise (the strike), feed
  it back through a lowpass (the string losing its high partials first), and the delay LENGTH is the pitch.
  **Read at a FRACTIONAL offset and interpolate**, or the glide steps between whole samples and buzzes.
- **A gun announces itself in the first ten milliseconds or it does not read as a gun.** The plasma and gauss
  voices were built as a swelling fizz and a rising whine — accurate to the fiction, and they vanished under
  everything with a crack in it. Both are built like the others now (transient, body, character) with only
  the CHARACTER alien. **Weapon voices are keyed by FAMILY, not per gun** (`Weapon.VOICES` + `_voice()`):
  sixty samples nobody could tell apart, against four families that genuinely differ. Only exceptions are
  listed; anything unlisted falls through a damage threshold to blaster or heavy blaster.
- **THE LIGHTSABER IS FOUR SOUNDS, AND UNTIL RECENTLY IT WAS NONE.** Every blade in every universe shared
  `melee_swing` and `melee_hit`, so a lightsaber, a chainsword, an ork choppa and an energy sword were one
  whoosh and a clang, and a Jedi drew a metre of plasma in silence. It is `saber_on` / `saber_hum` /
  `saber_off` / `saber_clash` plus its own `saber_swing`, and **which blades get them is not a new table**:
  `blade_energy` 0 already separates steel from plasma for the GEOMETRY, so `Weapon.blade_is_energy()` asks
  that same key and the thing that hums can never disagree with the thing that glows. Two details are most of
  the effect — **a saber swing is pitched**, because what you hear is the hum being MOVED (two overlapping
  sweeps in opposite directions, since one oscillator can only bend one way), and the hum's own pitch bends on
  a swing (`HUM_SWING_BEND`, driven off the SHOT rather than off measured motion, so a bot with no viewmodel
  sounds identical to a player). The clash is raised from `Weapon.parry()`.
- **A LOOP HAS AN OWNER, AND THAT IS A DIFFERENT MECHANISM** (`Audio.claim_loop` / `move_loop` /
  `release_loop`). The voice pool is round-robin ONE-SHOTS: nothing can stop a voice because nothing needs to.
  A hum is the first sound that starts when something happens, runs while that stays true, and must be
  SILENCED when it stops. Fixed slots claimed with a **token** (house rule 4). **Three slots and NEAREST
  WINS** — four hums on one couch with no panning is mud, the cap makes that impossible rather than unlikely,
  and taking the nearest is what makes the cap honest. A refused claim returns 0 and the caller carries on
  (a saber with no hum still ignites, swings and blocks); it retries on a timer, never per tick, since a claim
  walks the combatant list. **Past `HEARING` a loop is turned down to inaudible rather than STOPPED**, because
  restarting a loop is an audible re-trigger. **The hum is claimed off what is in hand, POLLED every tick, not
  pushed by the swap that put it there**: `set_class` runs before the weapon is in the tree, and a blade must
  also fall silent when its owner DIES, which is not a swap at all. `Main._ready` calls `stop_all_loops()` as
  the backstop for house rule 11.
- **A LOOPING EFFECT JOINS EXACTLY, BY CONSTRUCTION, RATHER THAN BY CROSSFADE.** `MusicGen._seamless` has to
  crossfade because its material is arbitrary; the hum does not. It is exactly one second long with INTEGER
  partial frequencies, so every partial completes a whole number of cycles and the phase runs dead straight
  through the join. **That also rules out a noise layer and a `fade_out`** — both are random or zero at the
  ends, which is precisely the click. The buzz comes from `saturate` folding the partials instead, and two
  close partials (104 and 109) BEAT at their difference, which is what makes it sound alive rather than like a
  held organ note.
- **A CLICK IS A DISCONTINUITY, NOT A NON-ZERO STEP**, and `audio_bank.gd` was measuring the wrong thing. It
  compared the step across the loop point against ZERO, which silently assumes the waveform is flat there —
  true of the music, whose join sits in a quiet bar, false of anything looping through its own steepest point.
  The hum joins **at a zero crossing**, where a sine moves fastest, so consecutive samples differ by 0.08 with
  nothing wrong: measured against zero that read as a click four times worse than the music's, **and the first
  instinct is to "fix" a sound that is already perfect.** The join is measured against the buffer's OWN worst
  sample-to-sample move, and the hum's comes back exactly equal to it.
- **A generated loop that clicks is a loop nobody can listen to twice** (`MusicGen._seamless`). The tail of the
  last bar does not line up with the head of the first, so the join is a step in the waveform, audible as a
  tick every twenty seconds. It is crossfaded round.
- Two tracks, one progression: `MusicGen.PROGRESSION` is eight bars of D minor with a Phrygian flat second,
  played slow and pad-only for the MENU (**a menu track with a beat starts a clock in the head of four people
  arguing about teams**) and at 104 BPM with drums and a lead for the BATTLE. The match cuts to it on GO, not
  on map load. **Music defaults to 0.45 against effects at 0.85** — the sounds that carry information have to
  win.

## Networking: host and join

- **`Net` (`scripts/net.gd`, autoload) IS THE SESSION, exactly as `GameState` is the MATCH.** Who is playing,
  on what machine, on which side, and what is about to be played. Everything about being online is asked here
  and nowhere else — `Net.online()`, `Net.is_host()`, `Net.authority()`. **Nothing else may test
  `multiplayer.*` directly**, for the same reason nothing reads `PLANETS[planet]` any more: half the code
  would then answer the question a different way and the halves would disagree.
- **A PEER IS A MACHINE, NOT A PLAYER**, carrying one to four humans. That is the shape the game was already
  built for, so "four at one couch" and "four machines with one each" differ only in how many local players a
  peer has. It is why this took a session layer and not a rewrite.
- **THE HOST OWNS THE MATCH; A MACHINE OWNS ITS OWN BODIES.** Bots, spawns, the zone, scores, tickets, the
  countdown and victory run on the host alone and are broadcast — that is the half that must have exactly one
  answer. Everything else stays local: each peer simulates its own humans at zero latency, and everyone else
  draws them as `NetPlayer` proxies. **The trust is deliberate.** Every number in this project — the recoil
  settle, the stance spread, the twist rate, the carry pose — was tuned against input that moves the body on
  the frame it was read, and routing that through a server would change the feel of all of it. **A client can
  lie; this is a friends-and-LAN mode.** To face strangers the line to move is that one — local players become
  inputs sent to the host — and nothing else in `net.gd` changes.
- **HITS ARE DETECTED BY THE SHOOTER AND APPLIED BY THE VICTIM.** `Weapon._trace_pellet` is unchanged: it
  finds a `NetPlayer`, whose `take_damage` forwards to the owning machine instead of applying anything. That
  also answers the lag-compensation question the old notes raised — the only machine that knows whether the
  saber guard was up is the one holding the blade, so it decides, and the confirmation comes back through
  `on_hit_confirmed` the same way it does locally.
- **`Net.authority()` IS TRUE OFFLINE.** That is the whole reason there is no second version of the match
  logic: `if Net.authority():` in Main is the single-player path and the host path at once.
- **`human_players` MEANS VIEWPORTS ON THIS MACHINE, FOREVER** (it sizes the grid, prices the frame in
  `Quality`, picks the minimap size). Anything about the MATCH asks `GameState.session_humans()` /
  `humans_on_team()` instead. Getting this backwards makes every machine fill the same team with its own AI.
- **THE SEED IS THE MAP, AND ONLINE IT BELONGS TO THE SESSION.** `reset_match` must not roll `planet_seed`
  when `Net.online()` — on EITHER side. The first guard was `Net.authority()`, which is wrong in the direction
  nobody looks: `start_match` rolls the seed and sends it, then the host changes scene into `reset_match` and
  throws away the world it just told everybody to build. Two seeds are two worlds, and the symptoms (walking
  into invisible structures, cover that is not there) all read as replication bugs.
- **`NetSync` (`scripts/net_sync.gd`) is the pump, at a FIXED PATH** (`/root/Main/NetSync`) because Godot
  routes an RPC by node path. **No RPC is ever sent to a proxy directly** — a body's path depends on when it
  spawned — so every net_id travels inside a payload that lands on the one node both ends agree about.
- **GUNFIRE IS A COUNTER IN THE MOTION PACKET, NOT AN EVENT.** A repeater fires 13×/s; a reliable RPC per
  trigger pull is 13 acknowledged packets a second per shooter for a muzzle flash. Every body carries a
  wrapping shot count and the receiver plays the difference, capped — so a dropped packet catches up on the
  next one instead of losing the shot, with no reliable channel at all.
- **A MACHINE MAY ONLY MOVE ITS OWN BODIES** (`NetSync._sender_owns`, checked per record). Not a cheating
  question first: it is what stops a stale packet from a peer that just lost a player fighting the machine
  that now owns it.
- **ONLINE MODES ARE DEATHMATCH AND ZONES.** Conquest, Royale and Massive each need a system of their own
  carried over the wire (post ownership, crates on the ground, a hundred bodies) and are gated out of the
  lobby — a mode that half works fails in ways that look like a bug in the game. **Vehicles are off online**
  for the same reason: placed on the host alone they are worse than absent.
- Dev switch, same argument as `-- --debug`: `-- --host` / `-- --join <ip>` / `-- --seats N` walk straight
  into the lobby already in a session, so this is testable with two windows on one desk.
- **A GDScript error ABORTS the send** (house rule 6), so one body missing one field stops EVERY body on the
  machine from moving. That is what `NetSync._health_fraction` guards — `Bot` carried `health` and derived its
  ceiling inline, so it had no `max_health` to read (it has one now).

## Gotchas

- **GL Compatibility rules out most of the modern realism toolkit**: no SSAO, SSIL, SSR, SDFGI, volumetric
  fog or depth of field. Everything in THE GRADE was picked to work without them. If realism ever has to go
  further, the honest next step is Forward+ on the laptops with Compatibility kept for weaker machines — which
  means the two targets would genuinely look different, a design decision rather than a toggle.
- **Never capture the mouse in `_ready`** — an unfocused/occluded window stalls to ~1 fps and it grabs the
  desktop pointer during automated runs.
- **A new `class_name` isn't visible to a CLI run until the global class cache is rebuilt** — run
  `godot --headless --path godot --import` (or restart the editor), or scripts fail with
  "Identifier not declared".
- **After editing `project.godot` (autoloads/input) restart the editor**; a game run picks up script and scene
  changes from disk without a restart.
- **`DisplayServer.keyboard_get_keycode_from_physical` errors on every call under `--headless`.** To print a
  physical key, build an `InputEventKey` and use `as_text_physical_keycode()` — same layout translation, quiet
  with no display server.
- **A look test must apply `Grade`, must PLAY an animation, and must run WINDOWED.** A bare `CharacterModel`
  sits in its rest pose with both arms hanging, which is not a pose the game ever shows — photographing it hid
  the fact that the carry was being judged from geometry alone. Without `Grade` it photographs a lighting model
  the game does not ship, which is the whole failure mode a look test exists to catch.
- **The `universe_look` line-ups are the only thing that catches a shared head or a missing accessory**, and
  until recently not one Star Wars human stood in them — which is exactly how twelve units came to share a
  helmet. Its `_heads` shot must be framed on the HEADS (it was a mid-shot of the whole body, at which distance
  every white helmet is the same white helmet).
- Retired but kept in the repo, unused: the imported Battlefront GLB (`assets/models/rep/`, crude nearest-bone
  skinning, junk bone tails), `trooper_parts.gd` and `tools/animate_trooper.py`. Dropped because subtle motion
  on that rigid-chunk mesh looked uncanny.
- **It took a `git worktree` at HEAD to prove the bolt-material defect was new rather than pre-existing.**
  Worth doing before spending time on any "is this mine?" question.

## Tests

Run these after touching anything they cover. Headless unless marked **WINDOWED** — appearance cannot be judged
without a renderer, and `--headless` draws nothing.

| Test | What it protects |
|---|---|
| `kit_rules.gd` (`--script`) | Every class allow-list, every AI preset against its own kit, per-universe isolation, enum-table drift, copy fidelity, named sidearms. **Runs with NO autoloads**, which is why `Loadout` may never name `GameState`. |
| `universe_match.tscn` | Every universe boots a real match in both class modes; TTK reaches the body. Catches a table that agrees with itself but cannot be played out of. |
| `soak.tscn` | A long busy match ACCUMULATES nothing. The only test that catches per-shot leaks, orphaned nodes and material churn — everything else checks one frame. |
| `plant_look.tscn` | **WINDOWED + numeric.** Feet on ground that is not flat — a slope and a step, planting off and on. A flat floor cannot judge this: every foot is at y=0 whether it was solved or not, the same fault `grenade_throw` records about box floors. It measures each foot against the ground under THAT foot rather than its absolute height, because two bodies side by side on a slope stand at different heights and comparing those made planting look like it lifted the feet 28 cm. |
| `front_look.tscn` | **WINDOWED.** The front screen, in both its states. Everything it is for is appearance — whether the live firefight reads as one, whether the entry list stays legible over it, whether the wordmark and the action are fighting for the same third of the frame — and none of that has a number. It caught two squads standing back to back, a floor edge drawn across the frame as a hard line, and a muzzle flash that erased the man firing it. |
| `movement_feel.tscn` | How a body gets up to speed and how it stops, in SECONDS — the ramp, air control, and what a reversal costs. Asserted as RANGES, because too quick is still weightless and too slow is soft controls, and the whole value lies between. Drives the real InputMap actions: an earlier version called `_accelerate` from the test while the body's own physics called it with an empty stick, so the two fought and it reported a snap that was its own doing. Its FOOTFALL half measures cadence against GROUND COVERED rather than against time, which is the whole property — anything on a clock drifts against the legs — and its SHAKE half asserts the thing that makes screen shake acceptable at all: that the gun still points where the crosshair points while the camera is moving. Its CAMERA half measures the other side of the same feeling in millimetres and degrees — head travel standing still, walking, sprinting and aimed, the strafe lean, and the sprint's field of view — because the body had been given mass while the camera was still on rails at a constant height in a dead-level frame. |
| `locomotion.tscn` | Which clip and which HIP ANGLE a direction asks for. It used to drive Player and Bot separately and compare them, which is a check whose whole job was to catch a divergence between two copies of one rule; there is one copy now (`Locomotion`), so what it asserts instead is that neither body has quietly grown its own again. It sweeps a FULL CIRCLE of travel for the 90° hip limit — the eight named cases all sit inside the hysteresis band and every one of them passed while the legs were reaching 107°. Every section signs off at its own end: this test printed HOLDS while a section was aborting on a call that no longer existed (house rule 6) — they are duck-typed against each other and must agree. All of it is sign conventions, which is the part that goes wrong silently: a backpedal playing `strafe_l` is an axis bug wearing an animation bug's clothes. Also that every clip the state machine can name actually EXISTS, since `_update_anim` guards on `has_animation` and a missing clip is invisible rather than loud. |
| `locomotion_look.tscn` | **WINDOWED.** The ground clips front-on and side by side at two phases of their cycle. The sidesteps are no longer in it: nothing selects them since the hips learned to swivel, and a sheet of clips the game never plays is worse than no sheet. |
| `swivel_look.tscn` | **WINDOWED.** Five bodies all AIMING AT THE CAMERA and each travelling a different way, so the only thing that differs is what the legs did about it — forward, 45°, the full right angle, and the two backpedals. Frozen on one frame of the stride, because the phase of the cycle is a bigger visual difference than the thing being judged. |
| `factions.tscn` | Picking a side independently of the setting, and choosing its colour. UNSC against the Republic, with the ROSTERS following and not just the names — the failure mode is a side whose roster, chip and tracer disagree about who it is, and all three are silent when wrong. Also that a chosen tint reaches the BOLT as well as the armour, that BLACK still fires something visible, and that no streak signature shares a name with an ordinary class. And — the one that was actually broken — that for EVERY class on a side, the name the character select prints is the build that stands up: the screen and the deploy resolve a selection separately, and the deploy was passing a TEAM NUMBER to a function that takes a SIDE SLOT and a UNIVERSE, so picking a side its own faction listed one roster and fielded another. |
| `streaks.tscn` | Kill streak rewards. Mostly GATES, checked from BOTH directions — a reward wrongly available still works perfectly, it is just somebody else's. Plus the transformation on a real Player: that it keeps the streak, that the preset is not silently disarmed, that a BECOME reward cannot re-earn ITSELF and heal to full every kill, and that it does NOT regenerate while an ordinary body still does — the second half is the one that regresses silently, since a rule that leaked onto everybody leaves the game working and no longer the game. Every section signs off at its own end and the run fails if one did not finish, because an aborted check (house rule 6) otherwise reports success having verified nothing. Its THIRD-PERSON section checks all three things that have to move together for the Force Master and are each silent when wrong — the flag, the CAMERA, and the CULL MASK that decides whether the player can see the body the camera is now pointed at — and then that an ordinary respawn puts all three back. |
| `warmachine_look.tscn` | **WINDOWED.** The LAAT and the AT-ST with a trooper and a speeder for scale, the gunship shot from BELOW. Its first version had no floor COLLIDER, so nothing hovered and it photographed a gunship lying on its skids. |
| `signature_look.tscn` | **WINDOWED.** All ten faction signatures in one line-up. The point is the LINE-UP and not the individuals — whether ten of them are ten different things is a comparison, and each one alone photographs fine. Also catches a head kind with no `match` case falling through to the bare face. |
| `kill_record.tscn` | The killfeed's entries and the post-match table: the ring cap, a streak surviving the death that ended it, that a teamkill and a suicide pay nothing, and that a FREED body can still be named. It also asserts it can REACH GameState before checking anything — an earlier version printed success while the autoload was nil and verified nothing at all. |
| `big_teams.tscn` | 20v20 in the ordinary modes, and specifically the `line`/`thrifty` SPLIT. Half its assertions are that the big match got the savings and half are that it kept the GAME (no line troopers, gadgets carried, a mix of builds) — the second half is the one that silently regresses, because re-merging the flags leaves the mode working and no longer the game. |
| `terrain_chunks.tscn` | **WINDOWED.** What chunking the heightfield bought, A/B/A in ONE process by welding the chunks back into one mesh — two runs of two binaries would differ by thermal state as much as by the change. It reports both A's so the noise band is visible next to the result. |
| `massive.tscn` | The 50v50 mode: the line trooper's kit and the four performance rules that make a hundred bodies possible (every one is an ABSENCE, and an absence is what a later edit silently undoes). **Its LAST assertion (`n of m line troopers found a target`) is known flaky** — a sample of five to eight survivors on a map re-seeded every match — and fails roughly half of all runs. Re-run it. Every other assertion is exact. |
| `roster_feel.tscn` | **The play-test bench.** Every class in every universe as one table — health, walk, jump, height, TTK out, TTK once the gun is HOT, TTK in, TRADE ratio, rounds-to-kill, reach, ability slots. Asserts outer guard rails only: absurdity checks, not taste. |
| `conquest.tscn` | Capture, tickets, defeat, spawn transforms, faction rosters (eight per side, every index a real build, no orphans). |
| `vehicles.tscn` | The speeders. Most of what it protects is an ABSENCE or a RESTORE — that Halo and Warhammer field NONE, that royale and massive field none, that a dismount restores the body but a DEATH at the controls does not, that an enemy cannot take yours. It sets `pickup_in_reach` directly on purpose, which is what caught the team gate living only on the advertisement. Its BOARDING check walks a real Player capsule up to every machine and asks whether the interact prompt fires, which is the only question a vehicle exists to answer and the one nothing else asked: the AT-ST shipped unboardable because `MountArea` is authored once for a speeder riding 0.9 m up, and a walker standing on 4.6 m legs floated that trigger a metre over the tallest point of a trooper. Geometry cannot answer it — whether two physics volumes overlap is a question only physics can answer. Also boots six REAL matches and counts what `_place_vehicles` actually put on the field, since a rule that only holds in a unit test does not ship. |
| `vehicle_pov.tscn` | **WINDOWED.** What the DRIVER sees, from inside each machine, forward and looking down. The same argument `gunship_pov` makes: a vehicle photographed from outside — which is all `warmachine_look` does — cannot show whether the seat is in a usable place, and the AT-ST's camera floating over its own roof looked perfect from every other angle. The looking-DOWN shot is the one that matters, because that is how a walker is steered and it is where its own hull is most likely to be in the way. |
| `slide_look.tscn` | **WINDOWED.** The slide SIDE ON and beside a crouch and a run. Both halves matter: a slide's silhouette is asymmetry in the SAGITTAL plane, so the front-on angle `locomotion_look` correctly uses for the walk is exactly the one that hides this; and the question is not whether the pose is nice (alone it photographs fine) but whether it reads as a DIFFERENT THING from a crouch, which is what it was before it had a clip. |
| `guard_pose.tscn` | Hand-to-grip and ankle error on all ELEVEN clips (the directional ones included — add a clip, add it to CLIPS). **0.00 mm is the pass mark**; any pose change shows here first. It is what proved adding the wrist and ankle joints moved nothing. |
| `death_clip.tscn` | The ANIMATED death. Which way a shove drops you, and then the two things a canned fall gets silently wrong: geometry through the floor, and a body that ends up leaning rather than lying. **It names the lowest PART**, not just the depth — the first three fixes went into the wrong limb because a number alone does not say whose it is. |
| `rig_cost.tscn` | What the rig costs to build and to tick, the tick as an A/B against the same frame with every clip paused. Two traps recorded in it: timing whole frames measures the engine, not the animation; and building 24 different styles prices the mesh cache missing, not a squad. |
| `recoil_feel.tscn` | What a gun costs to fire AND what it costs to get into the fight — recoil in DEGREES and handling in SECONDS, both through the real signal path — the per-pull jump and the peak a held trigger settles at. A table column cannot be read on its own: kick, rate and settle only mean anything together. Its own first version reused one body across the catalogue and reported the A280 climbing to 68 degrees, which is what a gun looks like when nothing is decaying — **a measurement that disagrees with arithmetic is a broken measurement**, so each gun gets a FRESH body. Guns under 2 rounds/s are exempt from the STEADY check (a bolt-action has fully settled between shots, so it is the same reading twice) and the rotary is left out entirely rather than measuring 0.00 and passing. The handling half times the SPRINT-OUT by when the trigger starts working again rather than by when the pose looks right — an earlier version stepped `_update_stow` by hand as well as letting physics tick it, and reported every gun at half its real recovery. |
| `warmachine_feel.tscn` | The two CALL-IN rewards, measured rather than watched — they happen at a distance, over seconds, to bodies somewhere else, which is exactly what a play session cannot judge. "The gunship is inaccurate" was four separate faults and only numbers tell them apart: the aim point walking on a centred stick, the camera and the barrel pointing different ways, the cone, and the shells. Its BORESIGHT check is the one the angle check could not do: two rays can point exactly the same way and still land two metres apart if they start in different places, so it casts the camera's centre ray and the gun's and compares where they ARRIVE. Also asserts the orbital strike PUNISHES BUNCHING rather than deleting everyone, stated as an experiment where the only difference is how the enemy stood — six bunched lose all 925 with the mark held on them, six spread 18 m apart lose 88 while it is held on one of them. Both of its damage checks HOLD THE MARK, because the reward is player-aimed now and a test that leaves it where it opened measures a barrage falling on ground the targets have run away from. **Its gunner is a STUB for the measurements and a REAL Player for one section**, and that section exists because a stub has no `_physics_process` and therefore none of the rules a real body lives under — the storm burning a seated gunner 210 m up went unnoticed for exactly that reason, with the barrage measured working perfectly for somebody who was already dying. |
| `ads_look.tscn` | **WINDOWED.** Every silhouette family aimed, on IRON sights, with bodies at fighting range. Whether a shape blocks the view depends on how far down the barrel it is and how wide it is at that distance, so this cannot be computed off geometry — the question each shot answers is whether you could take that shot. It is what caught the receiver filling the bottom 45% of the screen with the heat cell blooming under the reticle. |
| `guard_block.tscn`, `force_lightning.tscn`, `gadgets.tscn`, `trandoshan.tscn`, `wookiee.tscn` | Individual mechanics. |
| `buy_screen.tscn`, `character_select.tscn`, `settings_overlay.tscn` | The screens' state machines. `buy_screen` shoves the stick eight ways on the death frame and asserts the build is byte-identical. |
| `match_exit.tscn` | The three ways a match ends that are not winning it: LEAVING, PAUSING and losing a CONTROLLER. All three fail silently when they break — a quit row that stops doing anything, a pause that is taken and never released, and a disconnect nobody is told about are each indistinguishable from the feature not existing — so nothing but an assertion can tell them apart. Most of what it really tests is the hold SET: that the match resumes when the LAST holder lets go and not the first, which is the property you would only find by unplugging a controller while a menu was open. It also caught a player who had just been handed a working pad being moved onto the next one to arrive. |
| `pause_look.tscn` | **WINDOWED.** The pause screen and the leave-confirm, over a REAL match — this screen is transparent over the game and the whole question is whether it stays readable there. It caught the disconnect banner printing straight through "GET READY 3": nothing was wrong with either widget, and the fault only existed BETWEEN them. |
| `settings_look.tscn`, `team_select_look.tscn` | **WINDOWED.** The CONTROLS screen (the tightest layout in the game — every rebindable row plus chrome, no scrolling, shot on BOTH the pad and the keyboard profile since keyboard adds four movement rows and is the worst case for height) and team select mid-selection. |
| `controls_inherit.gd` (`--script`) | P1-pad inheritance. SNAPSHOTS `user://controls.cfg` first. |
| `accounts.gd` (`--script`) | An account's three halves: the name (folded, never validated — the one refusal is a name that is nothing at all), the RECORD (which is addition, and a key missed there stays at zero forever with nothing to say so), and the CONTROL CONFIG, where what is asserted is the delegation to `Controls`' named profiles in both directions — signing in puts a player's own feel settings back, and a capture follows them onto the next device they pick up. Also the one arithmetic case with a plausible wrong answer: K/D with no deaths is the KILLS. **SNAPSHOTS both `user://accounts.cfg` and `user://controls.cfg`** — every mutating call in either file saves, and an earlier version of `controls_inherit` wiped a real rebind off a real machine. |
| `playlist.tscn` | The whole front-end flow, and almost every assertion in it is something that fails SILENTLY: a seat that never reaches the match plays perfectly on the wrong controller, an entry that shares its arrays fields the wrong side in round one, a setting missing from `MATCH_KEYS` plays with the last round's value. One section drives the sign-in with REAL INPUT rather than by calling what a press calls (`Input.parse_input_event` genuinely moves what `Input.is_key_pressed` reads), because the LATCHES are the part most likely to be wrong and the part nothing else can see — including the case that has to hold a button down before the screen exists. Its last section BOOTS TWO REAL MATCHES either side of a `playlist_advance`, which is the only proof that a queued round comes up as the round it was queued as; it deliberately does not call `Main._next_map`, which reloads the current scene and in a test is the test. It also checks the generated worlds' map rows against `PlanetMap.PLANET_NAMES` (house rule 7 — the rows carry their planet as a literal int, so nothing else stands between a row and the wrong world), and the SETUP round trip: every setting and the whole queue written and read back, plus a config from an older build being clamped rather than fatal. **It snapshots `user://setup.cfg` as well as accounts and controls** — the screens save on every change, so a test that leaves one behind changes what the next run of itself does. |
| `frontend_look.tscn` | **WINDOWED.** Sign-in and playlist, in the states they are read in — including the MATCH SETTINGS panel open over the screen it is modal to, which is the one shot that says whether it reads as being on top of the columns rather than as part of them. It writes a known setup before shooting: a screenshot suite whose contents depend on what the machine last played is a suite whose pictures cannot be compared between runs. Everything the headless test asserts is behaviour, and both screens can pass all of it while being unusable — cards that fit at one player and run off the edge at four, a column taller than the panel holding it, a queue that says nothing when empty. The sign-in shot that matters is the MIXED one (one signed in, one reading the list, one typing, one seat empty): it is the only state with all three card layouts on screen at once. It caught a career line printing out through its own card border and a four-faction title running through the panel beside it. |
| `net_session.tscn` | The session's RULES, without a socket: seating and id allocation, auto sides (a SOFA IS NOT SPLIT UP), the session-vs-machine reads in GameState, the launch config round trip, the client not re-rolling the world, and the snapshot PACK/UNPACK agreeing on every byte. Instant. |
| `net_live.tscn` | **TWO REAL PROCESSES, ONE REAL SOCKET** — it launches its own client. Proves the handshake, that a proxy is built and lands where the remote body actually is, and the ROUND TRIP: shooting a proxy hurts the real body on the other machine and the confirmation comes back. The only test that exercises a hit crossing a machine boundary. |
| `net_match.tscn` | **TWO REAL PROCESSES PLAYING A REAL MATCH.** Both boot Main, the host fills the teams, and the assertion that matters is that **the two worlds AGREE**: same seed, same combatant count, every body owned by exactly one machine. A mismatch is the shape of nearly every networking bug worth having. ~45 s. |
| `audio_bank.gd` (`--script`) | Every synthesised sound is audible, unclipped and mixed, and every LOOP joins without a click. The join is measured against the buffer's own worst sample step, not against zero. |
| `bot_range.tscn`, `nav_grid.tscn` | AI engagement ranges (better aim never fights closer) and routing across every map. `nav_grid` re-tests each planned path against PHYSICS and only counts a BOX hit as a failure — the grid is deliberately flat and a trimesh hit is a hillside the bot is meant to walk up. |
| `prop_shapes.tscn` | Generated props collide as their SHAPE while still showing the nav grid a box footprint. Re-enabling the box or dropping it breaks a different half of the game each way. |
| `chamfer.gd` (`--script`) | Signed volume, outward normals, extents and triangle count of the generated chamfer box — with the SIGN taken from a real `BoxMesh` at run time rather than stated. Stating it is what went wrong: the sign was written down backwards, so an inside-out mesh passed, and every model in the game was inside out behind a green test. |
| `mesh_winding.tscn` | The same question asked of EVERYTHING else the game generates — 45 character styles, every viewmodel, the speeders, both war machines, the turret and mortar, and all five generated worlds with their terrain, structures and props: 7743 meshes. Two checks, because each catches what the other cannot — winding against the stored normals (which works on open surfaces, where a signed volume means nothing) and the signed volume itself (which catches a mesh whose normals are as wrong as its winding). It is also its own cautionary tale: the first version assigned a non-indexed surface's null index buffer to a typed `PackedInt32Array`, which aborts the function (house rule 6), so 205 meshes went unexamined behind a passing run. |
| `grenade_throw.tscn` | Grenades thrown for real over a TRIMESH heightfield: range, roll past the landing point, and whether any of them got through the floor. Its first version used box slabs and passed with both tunnelling defences removed, which is a test proving nothing. |
| `terrain_math.tscn` | The generated surface's two guarantees as ARITHMETIC: that `steepness_at` really is the analytic gradient of `height_at` (checked against a central difference — they agree to 2e-5), that no octave table can break the walkable slope budget, and that ground never goes below y=0. The pair most able to disagree with nothing erroring: the symptom is rock painted on the flats, which sends you into the shader where the fault is not. |
| `rig_cost.tscn` (see above) | `QS_RIG_BODIES=100` for the MASSIVE case. |
| `night_palette.tscn` | Every world's night is still PLAYABLE — a floor under the terrain albedo, a live key light, enough ambient to hold the shadow side up — and a night match actually deploys with the night map and night muzzle flash. A screenshot is a bad detector for "the ground went black"; a number is a good one. |
| `team_and_score.tscn`, `weapon_feel.tscn` | Team assignment, scoring, stance/ADS rules, and BOLT COLOUR reaching a fired round (the half `kit_rules` cannot see, having no autoloads). Also THE BLADE'S VOICE: a lit blade claims a sustained voice on its first tick and gives it back on a swap or a death, and the pool's nearest-wins steal leaves the loser's token STALE rather than live. |
| `render_cost.tscn` | **WINDOWED.** Frame cost per MSAA level. `QS_TEAM`/`QS_TEAMS` set the roster; `QS_VEHICLE=1` prices a VIEWPOINT and then the real HULLS (`QS_HULLS=1` skips the viewpoint sweep and does only the hulls — **it PAUSES the match for the A/B**, because the first version measured across a live firefight and reported that hiding two speeders *increased* the triangle count; read DRAWS, ~94 per speeder at 4 viewports, and ignore tris, which is terrain LOD under a moving camera); `QS_NIGHT` 0/1/2 is day, night, and night with every light held on; `QS_ABLATE=1` prices every rendering dial in an A/B/A sandwich; **`QS_SMOOTH=1` is the acceptance test and the only mode keeping the SHIPPED settings.** The ONLY test that sees rendering. Every other mode disables vsync itself — leave vsync on and every configuration measures at exactly the refresh rate, which reads as "no cost". |
| `perf.tscn` | Physics and A* budget, frame-spike percentiles (p50/p95/p99 and what the worst frames were building), and what one DEATH or RESPAWN costs. `QS_PERF_TEAMS=4` for the 4-team case; `QS_CPU=1` ablates the SCRIPT tick. Headless, so the renderer does nothing. |
| `hud_look` | **WINDOWED.** The health gauge in five states, plus a contact sheet of every ability icon. |
| `hud_frame` | **WINDOWED.** A REAL match photographed whole (`QS_VIEWS=1` for solo), with one side scan-lit. The only test that can see one HUD piece landing on another, because layout is a property of the screen and not of a widget. |
| `hit_direction.tscn` | The bearing maths, and the property that makes the indicator worth having: that turning toward a shooter brings the wedge to twelve o'clock and walking past one puts it behind you. Worth a test rather than a look because the failure is SILENT and the sign conventions are what go wrong — a left/right flip draws a perfectly convincing marker that sends the player the wrong way every time, and it photographs fine. Also that a burst is one marker, that a crossfire is capped, and that a fresh body is not wearing the last life's incoming fire. |
| `hit_direction_look.tscn` | **WINDOWED.** The wedges over a real match, one and then a crossfire. What a picture answers and the headless test cannot: whether it is READABLE over a bright sky and dark ground at once, clear of the reticle, and not competing with the minimap. It caught the first pass drawing arcs so small they read as red ticks — legible only to somebody who knew where to look. |
| `minimap_look` | **WINDOWED.** Both widget sizes, shot BEFORE and AFTER a scan — the after shot alone cannot tell you whether anything changed enough to notice mid-fight. |
| `deployable_look` | **WINDOWED.** Turret and mortar side by side with a trooper for scale, in two team colours, plus each alone from three angles. Side by side is the point. |
| `physique_look` | **WINDOWED.** Every roster at the size it actually plays at, against a 1.80 m yardstick post. The only test that photographs `stature` — every other look test builds a bare `CharacterModel` at scale 1, which is what let the whole roster be one height for as long as it was. |
| `map_look`, `universe_look`, `weapon_look`, `guard_look`, `death_look`, `select_look`, `buy_look`, `menu_look`, `sight_look`, `trandoshan_look`, `planet_look`, `night_look` | **WINDOWED.** Screenshots for judging APPEARANCE. |
