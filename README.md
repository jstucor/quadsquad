# QuadSquad

4-player local split-screen FPS for Linux, built in **Godot 4.7** with the **GL
Compatibility** renderer. Target is Ubuntu laptops on integrated graphics.

Everything is **procedural and built in code** — characters, weapons, maps,
props, UI and sound. No imported meshes, no textures, no audio files, no build
step. A new unit, gun, map or sound is a table row plus a builder function.

Three original settings ship: **The Compact Wars**, **Deep Range** and
**Ironhymn**. Nothing about the rules, modes, maps or shooting knows a universe exists — every weapon
lives in one enum and every body in one style table, so a shellgun is a hitscan
with a heavy round and a Paladin is a table row.

The original custom C++/SDL2/EnTT engine was retired in favour of Godot in
2026-07 (history is in git if you need it).

## Running

Requires Godot 4.7+ (official binary).

```bash
godot --path godot                       # run the game
godot --editor --path godot              # open the editor
godot --headless --path godot --import   # headless parse/import check
godot --path godot -- --debug            # P1 on keyboard + mouse, solo
```

**The game is pad-first, so `-- --debug` is how you play it at a desk.** It puts
player 1 on keyboard and mouse and defaults to one viewport; nothing else
changes. The flag is read from user args (after the bare `--`) because plain
`--debug` is Godot's own engine switch and never reaches the project. `--kbm`
works in either position.

## Controls

The game is **pad-first**: Main puts every player on a joypad (P1–P4 = pads
0–3), and keyboard + mouse is a fallback that still works for one player.

| | Pad | Keyboard |
|---|---|---|
| Move / look | Left stick / right stick | WASD / mouse |
| Fire / aim | RT / LT | LMB / RMB |
| Jump · sprint · crouch | A · L3 · **R3** | Space · Shift · Ctrl |
| Swap weapon | **B** | Q |
| Gadget 1 · 2 · 3 | X · LB · **Y** | F · G · R |
| Interact (crates, vehicles) | | E |
| Map · settings | Back · Start | Tab · Esc |

**Every binding is rebindable** and stored per device, with player 1's pad as
the house layout that pads 2–4 inherit — four pads at a couch are four copies of
one controller, and a pad given its own binding keeps it. Two buttons are
deliberately **not** rebindable: START always cancels a rebind listen and BACK
always clears a pad's override, so a keyboardless player can never trap
themselves in a row they opened.

**Nothing in the UI ever names a key or a button in text** — prompts go through
`Controls.label(device, id)`, so they follow a rebind instead of going stale.

Launching drops you on the menu. Every setting there is a labelled dropdown —
map, mode, universe, planet, time of day, teams, team size, victory threshold,
AI skill and where your gear comes from.

## Current State

### Modes

- **DEATHMATCH** — kills score, first side to the threshold.
- **ZONES** — a marked area pays the side with the most bodies inside it a point
  a second. It relocates every 30 s.
- **CONQUEST** — the The Genre mode. Sides fight over **capture posts**, you
  deploy on a post your side holds, and holding more posts bleeds the enemy's
  shared reinforcement pool. Run it to zero and you lose.
- **BATTLE ROYALE** — no respawns, no classes. Everyone drops in with a sidearm
  and scavenges the rest off the ground while a storm closes in. The storm picks
  its next centre from *inside* the current circle, which is what makes moving
  early a bet rather than a certainty.
- **MASSIVE BATTLE** — up to 50 a side on generated ground, playing by deathmatch
  rules. Most of them are **line troopers**: a rifle, a scope and nothing else.

Victory thresholds are configurable per mode. **Up to 20 a side** in the four
ordinary modes; 2, 3 or 4 teams, or a free-for-all.

### Where your gear comes from is a setting, not the mode

- **CUSTOM** opens the **buy screen**: 200 tokens a life, spent on a primary and
  its attachments, a sidearm, three gadget slots, an armour frame and an AI
  squad. Nothing is earned or banked and the budget resets each life, so
  respawning with the same build is one button press.
- **FACTION** opens the **character select** and deploys one of your side's
  authored classes.

Both work in every mode. Four players shop at once on their own sticks, so both
screens are a grid of boxes with a free cursor rather than anything you click.
**The cursor opens on the SPAWN box, closed, every time** — a stick still held on
the frame you died moves a highlight and nothing else.

### Kill streak rewards

A streak is kills on your **current life** — nothing is banked, and dying costs
you everything you were working toward. Rewards fire the moment they are earned;
there is no button, because there is no free one.

| Reward | Kills | Who |
|---|---|---|
| **Recon Sweep** | 4 | everyone |
| **Orbital Strike** | 7 | everyone |
| **HAMMERHEAD Gunship** | 10 | Concord — you ride the ball turret while it circles |
| **Aegis Drone** | 10 | Separatists |
| **MARAUDER Walker** | 10 | Dominion |
| **Ursan Warrior** | 10 | Pact Alliance |
| **Paladin-II** | 10 | COALITION |
| **Sanghelli Zealot** | 10 | Hierophany |
| **Terminator** | 10 | Ultramarines |
| **Choir Guard** | 10 | Blood Angels |
| **Unsleeping Lord** | 10 | Necrons |
| **Ork Warboss** | 10 | Orks |
| **Warden / Reaver Master** | 14 | all four The Compact Wars sides |

**Every faction has a signature nobody else can earn** — ten factions, ten
signatures. The two universal rungs are what keep the ladder the same height for
everyone: the orbital strike in particular asks nothing of what you are, no body
to become and no faction hardware.

**Rewards belong to a FACTION, not to a class** — what you bought this life never
changes what you are playing for, and every The Compact Wars side gets four.

**A reward is offered, not applied**: **D-up** takes it, **D-down** turns it
down. Declining is a real answer, because some of these cost you something — a
transformation replaces the build you are in the middle of using, and the gunship
takes you off the ground for twenty seconds.

Two kinds, and the split is the design. A **call-in** happens somewhere else and
you carry on being what you were. A **become** happens to *you*, and the rest of
that life is played as something else — which is why its table row is an ordinary
class preset in the same format as every other body in the game.

The gunship is the one reward you do not drive. A HAMMERHEAD is remembered for the two
glass balls on its flanks with a trooper sealed in each, so the airframe flies
itself and you ride the turret.

### Sides and colours

**Each side picks its own faction, independently of the setting** — so COALITION can
fight the Concord, or Orks the Dominion. The UNIVERSE dropdown deals that
setting's sides out in order as a one-press default; the per-side rows below it
change any of them. Ten factions across the three settings.

**And each side picks its colour** — purple clones, yellow droids. The choice
rides the model's accent panels *and* the tracer together, because a purple side
that still fires blue is half a setting. The bolt is derived from the chip rather
than chosen separately, brightened so it stays legible as a tracer.

### Classes and rosters

**Eight classes a side**: four line classes and four reinforcements, built from
a setting's own vocabulary rather than from adjectives — Aegis Drone, Legion
Commando, Vanguard Trooper, Infiltrator Drone, heavy automaton, Reaper Trooper, Incinerator Trooper,
Ursan Warrior, Kobb Hunter. The Compact Wars and Ironhymn field four sides each,
Deep Range two.

**A class is a body, not a colour.** Speed, health, jump and **stature** are per
unit, so an Aegis Drone does not move at a Dominion Scout's pace and a Kobb is
genuinely small. Stature drives model scale, capsule height, eye height and the
headshot line together, because the moment they disagree you get a head you can
see but cannot hit.

A class earns its place by needing a new noun: `DROIDEKA_TWIN` is the highest
sustained output behind the shortest heat pool, the flamethrower is the only
weapon with no reach and no way to miss, the Kobb spear is the shortest reach and
highest melee damage, and the ARC carries two DC-17s because that is what an ARC
is.

### Combat

- **Heat instead of ammo.** Sustained fire overheats and locks out.
- **Stance drives spread** — worse moving, worse airborne, better crouched — and
  the bloom crosshair reads the same number, so the penalty is legible. A scope
  means zero spread while aimed, on any gun.
- **You cannot aim down sights while running**, and the first-person weapon drops
  out of the sight line when you sprint. The trigger cancels it, easing back
  twice as fast as it eases in.
- **Recoil is three things off one signal**: the viewmodel kick, the camera climb
  and a backwards shove for the big guns.
- **Health regenerates.** There are no health kits — you recover by breaking
  contact.
- **Melee connects on a forward arc**, not a pinpoint ray. The arc blade is an
  ordinary hitscan with a 3.4 m reach and a melee flag; aiming raises the
  **guard**, which stops every round in front outright until its pool is spent.
- **Force lightning is channelled** and chains between bunched bodies.
- **Three gadget slots**, and the third is a different kind of thing: slots 1 and
  2 are what you throw or drop, slot 3 is what you put up and keep — cloak,
  barrier, overshield, fury. Grenades are gadgets, so the recharge is the ammo.
- **Vehicles**: one repulsorlift speeder per The Compact Wars faction, deliberately
  spread across the handling envelope. A STAP is the fastest thing on the field
  and dies to a grenade; a T-47 survives being shot at and cannot turn.

### The AI

Bots deploy real loadouts from the same catalogue players buy from, and skill is
purely intelligence — aim error, reaction time, sight range and turn speed. **A
bot's fighting range is derived, not tabled**: a shot lands while total angular
error keeps it inside a body's width, so an elite behind a scoped rifle works out
at ~70 m and the same elite with a scattergun at eleven.

They **plan routes** rather than steering at the goal, on an occupancy grid
stamped from the same collider footprints the map screen scans — so a new
procedural map is navigable with no bake and no authoring. Measured across all
ten maps: 94 of 220 journeys have a wall on the straight line, 0 planned routes
touch one.

A bot in contact **alternates between digging in and circling** rather than
strafing forever, and posting up costs it something as well as paying: crouched,
its capsule shrinks on the same curve its aim tightens on.

### Maps

Fourteen maps. Nine hand-laid arenas, four big authored outdoor maps (Aridis,
Silva, Senate District, Boneyard — big in three different *shapes* on
purpose), and the **generated world**.

The generated map builds from a planet chosen on the menu — Aridis, Silva,
Civis, Cinder, Boreal or random — re-seeded every match. A planet is a table
row: palette, sky, sun, terrain octaves, weather and which function places its
landmarks. **Terrain is always walkable and structures are always boxes**, which
is what lets the nav grid understand a world nobody authored.

**Time of day** is a property of the generated world, and night is a second
palette rather than a dimmer: the ground goes down a long way, the ambient less,
and anything that is genuinely a light source goes **up**. At night the guns are
the lighting — muzzle flashes reach three times as far and every round that lands
lights the ground it landed on.

### Presentation

- Per-viewport HUD: minimap, health gauge, round ability gauges, weapon and heat,
  scoreboard, **killfeed**, and a **death cam** that turns the view onto whoever
  killed you and shows the health you left them on.
- A **post-match table** — kills, deaths, headshots and best run per player.
- **Every sound is synthesised in code.** A blaster is a struck wire (the real
  DL-44 is Ben Burtt hitting a radio tower guy wire, and a guy wire is a string),
  a arc blade is four sounds and a hum that bends when you swing it, and the
  music is generated from one eight-bar progression played two ways.
- **Adaptive vsync, physics interpolation and a frame governor.** "Laggy" was
  never a frame-time problem, it was a frame-pacing one: the governor holds the
  frame to its interval by moving render scale, and drops the rate only when
  resolution runs out.

## Project Structure

```
godot/
  project.godot             — GL Compatibility, Jolt, autoloads, physics layers
  scenes/
    menu.tscn               — the main scene → team_select.tscn → main.tscn
    lobby.tscn              — host / join a session over the network
    main.tscn               — a bare Main node; main.gd does all the work
    levels/                 — 14 maps, all procedural but the hangar
    actors/                 — player, bot, turret, mortar, vehicle
    fx/                     — bolts, rockets, grenades, corpses, zones
  scripts/                  — everything (see below)
  shaders/                  — starfield sky, terrain, planet ground, foliage
  tests/                    — see Tests
```

The scripts worth knowing about, by what they own:

| | |
|---|---|
| `game_state.gd` | autoload: the MATCH — teams, scores, modes, spawns, the record |
| `net.gd` | autoload: the SESSION — who is playing, on what machine, on which side |
| `audio.gd` / `sfx.gd` / `music.gd` | voices and loudness / every sound / the two tracks |
| `loadout.gd` | the catalogue: universes, kits, weapons, classes, rosters |
| `main.gd` | map load, split screen, teams, HUD, rotation |
| `player.gd` / `bot.gd` | the two things that fight; duck-typed against each other |
| `character.gd` | the procedural box humanoid and every animation |
| `weapon.gd` / `viewmodel.gd` | what a gun does / what it looks like in your hands |
| `map_planet.gd` | the generated world |
| `nav_grid.gd` | the occupancy grid and A\*, stamped from map colliders |
| `grade.gd` / `quality.gd` / `frame_governor.gd` | how light is rendered / what it may cost / holding the interval |

## Roadmap

- **Heroes and battle points.** The single biggest absence against The Genre:
  there is no earned currency and no hero units. The reinforcement classes exist
  and are free-picked, so gating them — and then heroes — on a battle-point
  economy is the shape of the work.
- **Imported ANIMATION retargeted onto the rig.** The rig has wrists and ankles
  (15 animated joints), which is what makes retargeted humanoid clips worth
  having. Mixamo motion is royalty-free for games and, unlike models, carries no
  IP problem. Clips are sampled joint rotations either way, so the bridge is a
  bone-name map onto `CharacterModel.PATHS`.
- **A settings screen.** There is a controls screen and nowhere else for a game
  option to live, so DEATH STYLE is parked at the bottom of it. Options are
  already stored separately from bindings, so this is a screen to write and not a
  migration.
- **Conquest, Royale, Massive and vehicles ONLINE** — see Multiplayer for what
  each still needs.
- **Terrain shader detail.** `planet_ground.gdshader` measured at 0.07 ms;
  replacing it with a flat albedo changed nothing. That is real budget sitting
  unused in the place most visible to a player.

## Multiplayer: hosting and joining

The game hosts and joins sessions over a local network. MULTIPLAYER on the front
screen opens the lobby: **HOST A SESSION**, or **FIND A SESSION** to see what is
on the network (UDP broadcast discovery — nobody has to read an IP out loud) with
an address box beside it for when broadcast cannot reach.

**A peer is a MACHINE, not a player.** Each one seats one to four humans in
split screen, up to four machines and sixteen players. That is the shape the game
was already built for, which is why this is a session layer rather than a rewrite.

**The host owns the match; a machine owns its own bodies.** Bots, spawns, scores,
the zone, the countdown and victory run on the host and are broadcast. Each
machine simulates its own humans at zero latency and ships their state out at
20 Hz; everyone else draws them as proxies. Hits are detected by the shooter and
applied by the victim — which is also what makes the saber guard work, since the
only machine that knows whether the blade was up is the one holding it.

**This is a LAN mode for friends. A client can lie.** Trusting the client is a
deliberate trade: every feel number in the game was tuned against input that moves
the body on the frame it was read, and routing that through a server would change
all of it. Facing strangers means moving that one line — local players become
inputs sent to the host — and nothing else about the design changes.

**Online modes are DEATHMATCH and ZONES.** Conquest, Royale and Massive are gated
out of the lobby: each needs a system of its own carried over the wire (capture
post ownership, crates on the ground, a hundred bodies), and a mode that half
works fails in ways that look like a bug in the game. Vehicles are off online for
the same reason. Those are the next things to build.

Testing it at one desk, two windows, no second machine:

```bash
godot --path godot -- --host              # open a session and wait
godot --path godot -- --join 127.0.0.1    # join it
godot --path godot -- --host --seats 2    # ...with two split-screen players here
```

## Performance

**The Raspberry Pi 5 target has been dropped.** The renderer is a documented
choice, measured on the dev machine (Intel UHD 620, 4 viewports, Silva):
`gl_compatibility` ~26 ms/frame against `forward_plus` ~126 ms. Forward+ buys
SSAO, SSIL, volumetric fog and soft shadows and looks dramatically better — and
is unplayable on integrated graphics. On a discrete GPU that flips.

The rules that matter, each one here because it was broken at least once:

- **No per-frame allocations, materials above all.** Build materials once and
  write `albedo_color`. Per-*shot* allocation is the same rule and easier to
  miss: 13 rounds a second per shooter, up to twelve shooters.
- **Nothing is spawned for an effect no human could see.** Bots have no camera.
- **Anything unbounded gets a pool with a ceiling and a claim token**, so an
  owner that has been outbid does nothing quietly instead of switching somebody
  else's effect off.
- **When N things ask the same question every frame, ask it once** — the
  combatant snapshot took five command posts from 2.65 ms to 0.05 ms.
- **Measure, don't reason.** Engine frame-time monitors ranged 14.6–27.1 ms
  across identical runs, and the GPU thermally throttles to roughly half clock
  after ten minutes. Anything GPU-side needs an A/B/A sandwich plus warm-up.

**The frame is fill-bound, not draw-call bound**, and three plausible culprits
were measured and cleared before that was believed. At 6 bodies the frame is
15.0 ms and at 24 it is 15.5 — the bodies are not the cost, the *map* is, drawn
once per viewport. The dials that actually move it are resolution, MSAA, the
shadow atlas and viewport count; chunking the terrain cut triangles 24% and did
not move the millisecond figure at all.

Target is 60 fps at 1080p split into 4 × 960×540.

## Tests

Run these after touching anything they cover. Headless unless marked
**WINDOWED** — appearance cannot be judged without a renderer.

The full table lives in `CLAUDE.md`. The ones worth knowing:

| Test | What it protects |
|---|---|
| `kit_rules.gd` | Every class allow-list and all 126 AI presets against their own kit. Runs with no autoloads. |
| `soak.tscn` | A long busy match accumulates nothing — the only test that catches per-shot leaks. |
| `massive.tscn` / `big_teams.tscn` | 50 a side, and 20 a side in the ordinary modes. Both mostly assert ABSENCES, which is what a later edit silently undoes. |
| `kill_record.tscn` | The killfeed and the post-match table, including that a teamkill pays nothing. |
| `net_match.tscn` | Two real processes playing a real match, asserting the two worlds AGREE. |
| `nav_grid.tscn` | Routing across every map, re-tested against physics. |
| `terrain_math.tscn` | The generated surface's guarantees as arithmetic. |
| `render_cost.tscn` | **WINDOWED.** The only test that sees rendering. `QS_SMOOTH=1` is the acceptance test. |
| `*_look.tscn` | **WINDOWED.** Screenshots for judging appearance. |
