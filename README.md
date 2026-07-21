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
| Keyboard + mouse (WASD, Space jump, Shift sprint, Ctrl crouch, LMB fire, RMB aim, Q swap weapon) | Player 1 |
| Joypads (left stick move, right stick look, RT/RB fire, LT/LB aim, B crouch, Y swap weapon, A jump, L3 sprint) | Players 2–4 |

On the class screen, move left / right (A / D, left stick, or d-pad) to pick
your class; you deploy with it when the countdown ends.

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
- **Four classes**, picked per player in their own viewport when the match
  starts and again on every death (5 s deploy / 3 s respawn countdown):

  | Class | Weapons | Body |
  |---|---|---|
  | Assault | DC-15 Rifle, EL-16 Burst | 100 HP, standard speed and jump |
  | Specialist | NT-242 Sniper, A280 Semi | 80 HP, +12% speed and jump |
  | Officer | SE-14 Revolver, DL-44 Pistol | 100 HP, standard speed and jump |
  | Heavy | Z-6 Repeater, T-21 HMG, PLX-1 RPG | 140 HP, -12% speed, -10% jump |

- Nine weapons across those classes, with AUTO / SEMI / BURST fire modes; Q / Y
  swaps between the weapons of the class you deployed with
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
    fx/                     — blaster_bolt.tscn tracer, rocket.tscn
  scripts/
    menu.gd                 — map-select menu: roster list, rotation, quit
    main.gd                 — map load + split-screen + teams + score HUD + rotation
    game_state.gd           — autoload: map roster, TDM score, teams, spawns, input map
    kit.gd                  — the four classes: weapons + health/speed/jump
    player.gd               — movement, crouch, recoil, damage/frag, class select
    character.gd            — procedural blocky humanoid + code-built anims
    arena.gd                — procedural map base (env/floor/walls/lights/spawns),
                              square or rectangular (size x depth)
    map_crossfire.gd, map_foundry.gd, map_overgrowth.gd — map layouts (extend arena)
    weapon.gd               — 9-weapon blaster: fire modes, ADS, spread, heat
    viewmodel.gd            — procedural first-person gun + recoil/flash/bob
    rocket.gd               — RPG projectile: travel + splash damage
    trooper.gd              — decorative NPC: extends CharacterModel + patrol
    hangar.gd               — hangar spawn-point registration (both teams)
  shaders/                  — starfield sky, floor panels, jungle ground
assets/models/rep/          — retired Battlefront source GLB (unused)
tools/animate_trooper.py    — retired Blender rig/animation pipeline (unused)
```

## Roadmap (parity with the retired C++ prototype, then Battlefront)

- Droid enemies: FSM AI (idle → patrol → attack), line-of-sight checks
- Conquest mode: command posts, spawn-point capture, ticket bleed
- Game-over flow and a lobby (map select is in — see Current State)
- Particles (impact sparks, explosions) — instanced, Pi-friendly

## Performance rules (Pi 5 target)

- GL Compatibility renderer; no per-frame heap-happy scripts
- Keep draw calls low — every mesh renders 4× (once per viewport) plus shadows
- Directional shadow atlas capped at 2048
- Target 60 fps at 1080p split into 4 × 960×540 viewports
