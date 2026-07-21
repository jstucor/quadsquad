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

The player/NPC character is now **procedural** (`scripts/character.gd`, `class_name CharacterModel`): a blocky box humanoid on Node3D joints with idle/walk/run/jump animations built in code — no model asset and no build step. Just edit the script and run. (The old imported trooper GLB and its Blender pipeline, `tools/animate_trooper.py`, are retired but kept in the repo for reference.)

## Architecture

- `godot/scenes/menu.tscn` (`scripts/menu.gd`) is the **main scene**: a code-built map-select listing `GameState.MAPS`, plus a rotation entry and quit. It sets `map_index`/`rotate_maps` and changes to `main.tscn`. Navigation uses the built-in `ui_*` actions so any joypad or the keyboard drives it.
- `godot/scenes/main.tscn` is a bare `Main` node; `scripts/main.gd` does the work: instantiates the current map from `GameState.MAPS[map_index].scene`, builds the 2×2 SubViewport grid, assigns 2v2 teams, spawns players at their team's spawn points, tints characters per team, builds per-viewport HUDs (scoreboard + victory banner), and on `GameState.match_won` either rotates to the next map (`rotate_maps`) or returns to the menu.
- `scripts/game_state.gd` — autoload `GameState`: the map roster (`MAPS`), **team-deathmatch** score (`add_frag`, `SCORE_LIMIT`, `match_won`), team names/colours, spawn-point registry (per team), `map_index` rotation, and code-registered `kb_*` InputMap actions.
- Maps live in `godot/scenes/levels/`. Three are procedural: a map script `extends "res://scripts/arena.gd"` and overrides `_configure()` with a layout table (size/depth — leave `depth` 0 for square — cover, per-team spawns); `arena.gd` builds env/floor/walls/lights/cover and registers the spawns; a map can also override `_build_environment`/`_build_lights`/`_floor_material` (Overgrowth does, for daylight jungle) and add props in `_decorate()`. The hangar is a hand-authored `.tscn`. A map registers its per-team spawns in `_ready` (children ready before Main spawns players).
- `scripts/kit.gd` (`class_name Kit`) — the four classes (Assault/Specialist/Officer/Heavy): each is a weapon list plus health and speed/jump multipliers, the way `Weapon.PROFILES` holds the per-weapon numbers. `Player._apply_kit` adopts one on every deploy/respawn, and `_cycle_weapon` only walks that kit's weapons.
- Class select: nobody spawns directly. `Player.begin_deploy()` (called by Main *after* the HUD is wired — `_ready` would emit `died` into nothing) and every `_die` enter `_enter_select`, which runs the countdown while the player steps their highlight with the movement axis; `_respawn` applies the pending class. Main builds the per-viewport panel in `_build_class_select`.
- `scripts/player.gd` — CharacterBody3D. `input_device` -1 = keyboard/mouse (click captures the mouse, ESC releases), >= 0 = that joypad (polled, so MCP virtual pads work). Each player's model renders on layer `2 + player_index`, cleared from their own camera's cull mask; the first-person weapon viewmodel uses a second per-player layer block (bit `10 + index`) seen ONLY by its owner.
- `scripts/character.gd` (`CharacterModel`) — the procedural blocky humanoid + its code-built animations; `scripts/trooper.gd` extends it for decorative NPCs (looping anim + waypoint patrol). `scripts/weapon.gd` + `scripts/viewmodel.gd` — class-based blaster (ADS zoom, spread, heat) and its animated first-person gun.
- `scripts/weapon.gd` — hitscan + `fx/blaster_bolt.tscn` tracer; call `try_fire` only from physics frames. Death → corpse flop + countdown → respawn at a team marker no living player is standing on (`GameState.get_spawn_point`/`clear_of_bodies`; two overlapping capsules eject each other out of the map, so never spawn onto a body).
- Physics layers: 1 world, 2 players, 3 projectiles.

## Gotchas

- **GL Compatibility + dark sky**: metallic surfaces reflect the near-black starfield and render pitch dark. Keep `metallic <= ~0.15` and use a dim shadowless opposing fill light for shadow sides.
- **Never capture the mouse in `_ready`** — an unfocused/occluded window stalls to ~1 fps and it grabs the desktop pointer during automated runs.
- The character is procedural boxes on clean joints (`scripts/character.gd`), so animations are simple local rotations — no skinning. Retired: the imported Battlefront GLB (`assets/models/rep/`, crude nearest-bone skinning, junk bone tails) and its `tools/animate_trooper.py` pipeline; both were dropped because subtle motion on that rigid-chunk mesh looked uncanny. Kept in the repo but unused.
- **Autoload signals + lambdas leak across scene changes.** Godot drops a connection when its *target object* is freed, but a GDScript lambda that never touches `self` has no target — so a per-HUD lambda connected to `GameState.score_changed`/`match_won` survives the map it was built for and fires into freed labels on the next map ("Lambda capture at index 0 was freed"). Connect a **method of the node** instead: `main.gd` wires those two once in `_ready` and fans out to `_score_labels`/`_victory_banners`. Signals from the Player/Weapon are exempt — they die with the same scene as the HUD.
- **Respawn places the body before clearing `_dead`.** The spawn picker skips dead players, so flipping `_dead` first makes a player treat the body it just left as an obstacle and shove itself off its own marker.
- A new `class_name` (e.g. `Kit`) isn't visible to a CLI run until the global class cache is rebuilt — run `godot --headless --path godot --import` (or restart the editor), or scripts fail with "Identifier not declared".
- After editing `project.godot` (autoloads/input) restart the editor; a game run picks up script/scene changes from disk without a restart.

## Performance rules (Pi 5 target)

- Every mesh renders 4× (one per viewport) plus a shadow pass — keep draw calls and material count low; prefer procedural shaders over textures.
- Directional shadow atlas is capped at 2048 in project.godot.
- No per-frame allocations in scripts; target 60 fps at 1080p (4 × 960×540).
