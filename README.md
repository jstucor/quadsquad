# QuadSquad: Star Wars Skirmish

4-player local co-op arena FPS for Linux, built in **Godot 4**. Split-screen
gameplay targeting Raspberry Pi 5 and Ubuntu x86 laptops.

The original custom C++/SDL2/EnTT engine was retired in favor of Godot
(history is in git if you need it); its feature set lives on as the roadmap
below.

## Running

Requires Godot 4.7+ (official binary). The project uses the **GL
Compatibility** renderer for the Pi 5 target.

```bash
godot --path godot            # run the game
godot --editor --path godot   # open the editor
```

Headless sanity check (catches script/scene parse errors):

```bash
godot --headless --path godot --import
```

## Controls

| Input | Player |
|---|---|
| Keyboard + mouse (WASD, Space jump, Shift sprint, Ctrl crouch, LMB fire, RMB aim, Q swap weapon, F gadget, G grenade, H health kit) | Player 1 |
| Joypads (left stick move, right stick look, RT/RB fire, LT/LB aim, B crouch, A jump, L3 sprint, Y swap weapon, X gadget, d-pad up grenade, d-pad down health kit) | Players 2–4 |

On the buy screen: up / down picks a line, left / right changes it, and
**Space / A** deploys once the button goes live.

Launching drops you on the map-select menu — arrows / left stick to move,
Enter / A to select (any joypad can drive it). In a match, click the window to
capture the mouse; ESC releases it.

## Current State

- **Team deathmatch, 2v2** (Republic vs Separatist): kills credit the killer's
  team, friendly fire off, first team to the score limit wins, then the game
  rotates to the next map. Team-tinted characters + a per-viewport scoreboard
- **Map-select menu** on launch: pick any of the four maps, or "Map Rotation"
  to play the whole roster in order. Driven by keyboard, mouse, or any joypad;
  a single-map match returns to the menu when it ends
- **Four maps**: Crossfire, Foundry and the outdoor jungle Overgrowth (built
  procedurally from `scripts/arena.gd`) plus the Imperial hangar. Overgrowth is
  the biggest and the only rectangular one — 86 x 68 m of daylight jungle whose
  64-tree forest is two MultiMeshes, i.e. two draw calls for the whole canopy
- 4-way split-screen with one first-person player per quadrant; you never see
  your own model (render-layer cull masks) but squadmates do
- Procedural blocky characters built in code (no imported model, no skinning)
  with idle / walk / run / jump — clean box limbs on real joints
- **Buy screen instead of classes.** Every life you get **200 tokens** and spec
  a build: a gun, upgrades bolted to it, an armour frame, and consumables.
  Nothing is earned or banked — the budget resets each life — and your build
  persists across deaths, so respawning is one button press unless you want to
  re-spec. **You deploy when you press the button, not on a timer** (there's a
  short floor first: 5 s at match start, 2 s after a death).

  | Row | Options (cost) |
  |---|---|
  | Primary | None 0 · Rifle 45 · Burst 50 · Semi 55 · Repeater 70 · HMG 80 · Sniper 85 · RPG 110 |
  | Sidearm | DL-44 Pistol 0 · RK-3 Holdout 20 · SE-14 Revolver 35 — swap with Q / Y |
  | Gadget | Jetpack 45 · Wrist Cable 30 (grapple + vault onto cover) · Front Shield 50 · Rotary Cannon 75 · Turret 65 |
  | Scope | 25 — zoom optics + scope overlay on any gun |
  | Cooling vanes | 20 — -25% heat per shot, cools faster |
  | Improved grip | 20 — -35% hip spread, so bloom builds less |
  | Armour | Light Frame 20 (80 HP, +12% speed/jump) · None 0 (100 HP) · Plated 25 (130 HP) · Heavy Plate 60 (175 HP, -15% speed) |
  | Grenades | 25 each, up to 3 — bounce off cover, 2 s fuse, radius splash |
  | Health kit | 30 each, up to 2 — heals 60 |
  | AI squad | headcount, up to 4 — priced **per head** at the skill you pick |
  | Squad skill | Recruit 20 · Regular 35 · Veteran 55 · Elite 80 (each) |

  Options you can't afford simply refuse to select, so anything on screen is a
  build you can deploy with — 4 elites (320) won't fit in 200, 2 will. Your
  sidearm is free and "no primary" is a real option, so an all-gadget build
  still deploys armed.

- **Gadgets** (one slot, F / pad X) are verbs rather than more damage:
  - **Jetpack** — hold to fly on a fuel pool that refills on the ground.
  - **Wrist cable** — grapple whatever you're looking at, reel yourself in, then
    vault up and over it. The hop is solved from the anchor height, so it lifts
    you onto cover you grappled instead of leaving you against the side of it.
  - **Front shield** — a barrier that stops incoming fire but not yours: your
    own shots are excluded from it, so you shoot through your own cover. It
    wears down under fire and breaks.
  - **Rotary cannon** — a spin-up heavy gun; enormous output, and you walk
    while it's out.
  - **Turret** — drop an auto-turret that acquires, tracks and fires on its
    own, and can be shot down.

- **AI squadmates** fight for your team: they acquire the nearest enemy they can
  actually see, close to their engagement range, strafe and shoot, and fall in
  behind you when there's nothing to fight. Skill is what you're paying for —
  aim error, reaction time, sight range, turn speed and toughness all scale with
  the tier, and every tier carries the same rifle so intelligence is the only
  variable. They don't respawn; your next deploy tops the squad back up to the
  headcount you bought (survivors are kept).
- Twelve weapons with AUTO / SEMI / BURST fire modes and spin-up support, all
  able to take the three upgrades
- The RPG fires a real travelling rocket with radius splash damage + falloff;
  the rest are hitscan with fast bolt tracers
- Camera recoil per shot (settles back), 2x headshots, and crouch (lower
  profile + smaller hitbox, steadier, slower)
- First-person weapon viewmodel (procedural, one silhouette per class) with
  recoil kick, muzzle flash, and walk bob — rendered only for its owner
- Aim-down-sights that zooms the camera, tightens spread, slows look, and
  raises the viewmodel; the Sniper adds a scoped overlay (and hides its gun)
- Weapon **heat** instead of ammo: sustained fire overheats and locks out until
  it cools (fixed-timestep, so it's framerate-independent on the Pi)
- Decorative squad NPCs (same procedural character) that idle or patrol
- Per-viewport HUD: crosshair, HP, team scoreboard, player tag, weapon name +
  heat bar, and the victory banner

## Project Structure

```
godot/
  project.godot             — GL Compatibility, autoloads, physics layers
  scenes/
    menu.tscn               — map-select menu (the main scene)
    main.tscn               — bare bootstrap node (main.gd loads the map)
    levels/                 — crossfire/foundry/overgrowth.tscn (procedural), hangar.tscn
    actors/player.tscn      — CharacterBody3D FPS player
    actors/bot.tscn         — CharacterBody3D AI squadmate
    actors/turret.tscn      — placed auto-turret
    fx/                     — blaster_bolt.tscn, rocket.tscn, grenade.tscn, corpse.tscn
  scripts/
    menu.gd                 — map-select menu: roster list, rotation, quit
    main.gd                 — map load + split-screen + teams + score HUD + rotation
    game_state.gd           — autoload: map roster, TDM score, teams, spawns, input map
    loadout.gd              — the buy catalogue: weapons, upgrades, armour, gear, squads
    bot.gd                  — AI squadmate: target/advance/engage, skill tiers
    turret.gd               — placed auto-turret: stationary Bot cousin
    front_shield.gd         — shoot-through barrier gadget
    player.gd               — movement, crouch, recoil, damage/frag, buy screen
    character.gd            — procedural blocky humanoid + code-built anims
    arena.gd                — procedural map base (env/floor/walls/lights/spawns),
                              square or rectangular (size x depth)
    map_crossfire.gd, map_foundry.gd, map_overgrowth.gd — map layouts (extend arena)
    weapon.gd               — 9-weapon blaster: fire modes, ADS, spread, heat
    viewmodel.gd            — procedural first-person gun + recoil/flash/bob
    rocket.gd               — RPG projectile: travel + splash damage
    grenade.gd              — thrown grenade: bounces, fuse, splash damage
    trooper.gd              — decorative NPC: extends CharacterModel + patrol
    hangar.gd               — hangar spawn-point registration (both teams)
  shaders/                  — starfield sky, floor panels, jungle ground
assets/models/rep/          — retired Battlefront source GLB (unused)
tools/animate_trooper.py    — retired Blender rig/animation pipeline (unused)
```

## Roadmap (parity with the retired C++ prototype, then Battlefront)

- Droid enemies as a match mode (the AI itself is in — see AI squadmates)
- Conquest mode: command posts, spawn-point capture, ticket bleed
- Game-over flow and a lobby (map select is in — see Current State)
- Particles (impact sparks, explosions) — instanced, Pi-friendly

## Performance rules (Pi 5 target)

- GL Compatibility renderer; no per-frame heap-happy scripts
- Keep draw calls low — every mesh renders 4× (once per viewport) plus shadows
- Directional shadow atlas capped at 2048
- Target 60 fps at 1080p split into 4 × 960×540 viewports
