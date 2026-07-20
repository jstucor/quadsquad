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

Click the window to capture the mouse; ESC releases it.

## Current State

- **Team deathmatch, 2v2** (Republic vs Separatist): kills credit the killer's
  team, friendly fire off, first team to the score limit wins, then the game
  rotates to the next map. Team-tinted characters + a per-viewport scoreboard
- **Three maps on a rotation**: Crossfire and Foundry (built procedurally from
  `scripts/arena.gd`) plus the Imperial hangar
- 4-way split-screen with one first-person player per quadrant; you never see
  your own model (render-layer cull masks) but squadmates do
- Procedural blocky characters built in code (no imported model, no skinning)
  with idle / walk / run / jump — clean box limbs on real joints
- Eight weapon classes — Soldier rifle, Sniper, Heavy repeater, Revolver,
  T-21 HMG, burst rifle, semi-auto rifle, and the PLX-1 RPG — with AUTO / SEMI /
  BURST fire modes; swap between them in-match
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
    main.tscn               — bare bootstrap node (main.gd loads the map)
    levels/                 — crossfire.tscn, foundry.tscn (procedural), hangar.tscn
    actors/player.tscn      — CharacterBody3D FPS player
    fx/                     — blaster_bolt.tscn tracer, rocket.tscn
  scripts/
    main.gd                 — map load + split-screen + teams + score HUD + rotation
    game_state.gd           — autoload: TDM score, teams, spawn registry, input map
    player.gd               — movement, crouch, recoil, damage/frag attribution
    character.gd            — procedural blocky humanoid + code-built anims
    arena.gd                — procedural map base (env/floor/walls/lights/spawns)
    map_crossfire.gd, map_foundry.gd — map layouts (extend arena)
    weapon.gd               — 8-class blaster: fire modes, ADS, spread, heat
    viewmodel.gd            — procedural first-person gun + recoil/flash/bob
    rocket.gd               — RPG projectile: travel + splash damage
    trooper.gd              — decorative NPC: extends CharacterModel + patrol
    hangar.gd               — hangar spawn-point registration (both teams)
  shaders/                  — starfield sky, floor panels
assets/models/rep/          — retired Battlefront source GLB (unused)
tools/animate_trooper.py    — retired Blender rig/animation pipeline (unused)
```

## Roadmap (parity with the retired C++ prototype, then Battlefront)

- Class kits — per-class HP + move speed to go with the weapon classes, and a
  respawn class-select screen (weapons/heat/ADS zoom are in — see Current State)
- Droid enemies: FSM AI (idle → patrol → attack), line-of-sight checks
- Respawn overlay with class select and countdown, per dead player's viewport
- Conquest mode: command posts, spawn-point capture, ticket bleed
- Main menu with map select; game-over flow
- Particles (impact sparks, explosions) — instanced, Pi-friendly

## Performance rules (Pi 5 target)

- GL Compatibility renderer; no per-frame heap-happy scripts
- Keep draw calls low — every mesh renders 4× (once per viewport) plus shadows
- Directional shadow atlas capped at 2048
- Target 60 fps at 1080p split into 4 × 960×540 viewports
