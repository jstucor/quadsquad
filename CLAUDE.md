# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**QuadSquad** — 4-player local co-op Star Wars-style FPS for Linux (Raspberry Pi 5 and Ubuntu laptops), built in **Godot 4.7** with the **GL Compatibility** renderer. The former custom C++/SDL2/EnTT engine was removed in 2026-07; its features are the roadmap in README.md.

## Commands

```bash
godot --path godot                       # run the game
godot --editor --path godot              # open the editor (needed for the MCP tools)
godot --headless --path godot --import   # headless parse/import check
```

Godot 4.7.1 official binary lives at `~/.local/bin/godot`. The godot-mcp addon (`godot/addons/godot_mcp/`, port 6550) gives Claude editor control, input injection (incl. virtual joypads), runtime state, and screenshots — the editor must be running.

Regenerate the animated trooper after changing the animation script:

```bash
blender --background --python tools/animate_trooper.py -- \
  assets/models/rep/p3_heavyglb.glb godot/assets/models/p3_heavyglb.glb
```

Then restart/refocus the editor so it reimports the changed GLB.

## Architecture

- `godot/scenes/main.tscn` + `scripts/main.gd` — bootstrap only: builds the 2×2 SubViewport grid, spawns one `actors/player.tscn` per quadrant at a level spawn point, builds per-viewport HUDs, binds viewport cameras via each player's RemoteTransform3D.
- `scripts/game_state.gd` — autoload `GameState`: teams, reinforcement tickets, spawn-point registry, and code-registered `kb_*` InputMap actions. Match rules (conquest, command posts) grow here.
- Levels live in `godot/scenes/levels/`; a level script registers its `SpawnPoints` markers with GameState in `_ready` (children ready before Main).
- `scripts/player.gd` — CharacterBody3D. `input_device` -1 = keyboard/mouse (click captures the mouse, ESC releases), >= 0 = that joypad (polled, so MCP virtual pads work). Each player's model renders on layer `2 + player_index`, cleared from their own camera's cull mask.
- `scripts/weapon.gd` — hitscan + `fx/blaster_bolt.tscn` tracer; call `try_fire` only from physics frames. Death → `GameState.take_ticket` → respawn at the player's own marker (random markers stack bodies).
- Physics layers: 1 world, 2 players, 3 projectiles.

## Gotchas

- **GL Compatibility + dark sky**: metallic surfaces reflect the near-black starfield and render pitch dark. Keep `metallic <= ~0.15` and use a dim shadowless opposing fill light for shadow sides.
- **Never capture the mouse in `_ready`** — an unfocused/occluded window stalls to ~1 fps and it grabs the desktop pointer during automated runs.
- The trooper source GLB (`assets/models/rep/`) is a Battlefront-era asset: no skinning, junk bone tails (trust joint *positions* only), and hidden junk meshes (`p_mainchunk`, `Icosphere`). `tools/animate_trooper.py` handles all of this; don't hand-edit the exported GLB.
- After editing `project.godot` (autoloads/input) restart the editor; a game run picks up script/scene changes from disk without a restart.

## Performance rules (Pi 5 target)

- Every mesh renders 4× (one per viewport) plus a shadow pass — keep draw calls and material count low; prefer procedural shaders over textures.
- Directional shadow atlas is capped at 2048 in project.godot.
- No per-frame allocations in scripts; target 60 fps at 1080p (4 × 960×540).
