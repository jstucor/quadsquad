# QuadSquad: Star Wars Skirmish

4-player local co-op arena FPS for Linux. Split-screen gameplay targeting Raspberry Pi 5 and Ubuntu x86 laptops.

## Tech Stack

| Layer | Library |
|---|---|
| Language | C++20 |
| Build | CMake 3.20+ |
| Window / Input | SDL2 |
| Graphics | OpenGL 3.3 Core Profile (GLAD) |
| Math | GLM |
| ECS | EnTT 3.16 |
| UI | Dear ImGui 1.92 |

## Build

```bash
# Debug
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(nproc)
./build/quadsquad

# Release (recommended for Pi 5)
cmake -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j$(nproc)
```

**Dependencies (Ubuntu / Debian):**
```bash
sudo apt install libsdl2-dev libglm-dev
```
EnTT and Dear ImGui are vendored under `vendor/` — no system install needed.

**Using Nix (Optional):**
If you have [Nix](https://nixos.org/) installed, you don't need to install dependencies manually. You can build and run the game using the provided flake:

```bash
# Run the game directly
nix run .

# Enter a development shell with all dependencies available
nix develop
```

**Using Nix (Optional):**
If you have [Nix](https://nixos.org/) installed, you don't need to install dependencies manually. You can build and run the game using the provided flake:

```bash
# Run the game directly
nix run .

# Enter a development shell with all dependencies available
nix develop
```

---

## Controls (Player 1 — keyboard + mouse)

| Input | Action |
|---|---|
| W / A / S / D | Move |
| Mouse | Look |
| Left Mouse | Fire |
| Right Mouse (hold) | Aim down sights (Sniper only) |
| Left Shift | Sprint |
| Left Ctrl | Crouch |
| 1 / 2 / 3 | Switch class (Soldier / Sniper / Heavy) |
| ESC | Quit |

**Respawn screen (while dead):**

| Input | Action |
|---|---|
| W / S | Cycle class up / down |
| D-pad Up / Down | Cycle class (gamepad) |
| Space / A-button | Spawn immediately |
| *(timer)* | Auto-spawns after 5 seconds |

---

## Features

### Game Loop
- **Main Menu** — full-screen sci-fi UI, map selection list, keyboard and gamepad navigation (Enter / A-button to deploy)
- **In-Game** — 4-player split-screen; each quadrant has its own camera and HUD
- **Game Over** — triggers when all enemy droids are eliminated; shows final score

### Split-Screen Rendering
- 1280 × 720 window divided into four 640 × 360 viewports via `glViewport`
- P1 uses a live FPS camera; P2–P4 use fixed observer cameras (SE corner, NW corner, overhead)
- Two-pass HDR bloom post-process on the full scene each frame

### Camera & Movement
- Per-player FPS camera with physics position, eye height, and yaw/pitch
- Three movement states: Walk, Sprint (locked fire), Crouch (reduced crosshair)
- Zoom lerp for Sniper ADS; FOV adjusts per viewport each frame

### ECS Architecture (EnTT)
Components (`src/components/`): `Transform`, `DroidAI`, `Projectile`, `Lifetime`, `WeaponComponent`, `RenderMesh`, `Pickup`

Systems (`src/systems/`): `EnemySystem`, `ProjectileSystem`, `PickupSystem`

### Enemy AI
- Droids spawn at level SPAWNER positions (pushed clear of walls via `resolveBox`)
- Three-state FSM: **Idle** (gold) → **Patrol** (amber, random waypoints) → **Attack** (orange-red)
- Line-of-sight gate: casts a segment from muzzle to player eye against all wall AABBs before firing
- Anti-tunneling: bolt hit-tests use a swept segment each frame, not a point

### Combat
- **Weapon heat** — fires heat per shot; overheats into a timed lockout
- **Three classes** with distinct HP, speed, zoom, and heat profiles:
  | Class | HP | Speed | Heat pool |
  |---|---|---|---|
  | Soldier | 100 | Normal | Medium |
  | Sniper | 60 | Fast | Low (ADS zoom) |
  | Heavy | 150 | Slow | High |
- Droid bolts deal damage on hit; death triggers the respawn timer

### Respawn System
- On death: `isDead` flag set, 5-second countdown starts; game world keeps running
- Class selection overlay drawn **only inside the dead player's viewport** (pure `ImDrawList`, no ImGui windows)
- Cyan countdown bar across the top; pulsing "ELIMINATED" heading; three class cards with live highlight
- W / S or D-pad Up / Down cycle selection (rising-edge via `InputManager`); Space / A-button or timer expiry spawns

### Particle System
- Ring-buffer pool of 1024 `Particle` structs — no heap allocation per frame
- **Impact sparks** on bolt–wall hits; **explosion burst** on droid kill
- Single instanced draw call (`glDrawArraysInstanced`), additive blending for glow
- Billboard particles: camera right/up extracted from view matrix per viewport

### Level System
- Text-based `.lvl` format (`assets/maps/`); keywords: `WALL`, `DECO`, `SPAWNER`, `PICKUP`, `PLAYER_START`
- `LevelManager` parses the file and populates the ECS registry and collision AABB list
- `CollisionSystem::resolveBox` pushes entities clear of walls (used for player, camera, and droid spawn)

### HUD (Dear ImGui + DrawList)
- Per-viewport: crosshair (standard 4-bar + full sniper scope at ADS), health bar, weapon heat bar, player label
- Crosshair scale reflects movement state; heat bar blinks red during lockout
- Dev console (top-right of P2 viewport): FPS, class, heat %, P1 position, score, droid count
- Viewport divider lines between quadrants

### Physics & Collision
- AABB vs swept-segment intersection (slab method) — used for wall hit, LOS checks, and bolt anti-tunneling
- Per-frame `CollisionSystem::resolve` keeps the player outside all static wall AABBs

---

## Project Structure

```
src/
  main.cpp                  — game loop, state machine, viewport rendering
  camera/Camera             — FPS camera, movement states, zoom
  components/               — ECS data structs (no logic)
  input/InputManager        — keyboard + mouse polling, rising-edge detection
  level/LevelManager        — .lvl file parser
  particle/ParticleSystem   — instanced GPU particles
  physics/                  — AABB struct, CollisionSystem
  renderer/                 — Shader, CubeMesh, PostProcess (bloom)
  systems/                  — EnemySystem, ProjectileSystem, PickupSystem
  ui/HUD                    — ImGui HUD, respawn overlay

assets/
  maps/hangar.lvl           — "Hangar Bay 7" arena (30×30 m, 10 spawn points)

vendor/
  glad/                     — OpenGL loader (bundled)
  entt/                     — header-only ECS
  imgui/                    — Dear ImGui + SDL2/OpenGL3 backends
```

---

## Architecture Notes

All game objects are entities in an `entt::registry`. Systems are free functions or namespaces that query typed views each frame. Components are plain data structs with no logic.

Main loop order: **Events → Input → P1 physics (if alive) → World sim (AI / bolts / particles) → Render (4× viewport) → Post-process → ImGui HUD**

**Performance rules (Pi 5 target):**
- No heap allocations in per-frame systems
- Single instanced draw call for all particles
- Prefer SoA layouts in EnTT views
- Target: 60 fps at 1280×720 split into 4 × 640×360 viewports
