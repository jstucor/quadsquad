# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**QuadSquad** — 4-player local co-op FPS for Linux (Raspberry Pi 5 and Ubuntu laptop).
Split-screen gameplay, targeting low-power ARM hardware while remaining fully playable on x86 Linux.

## Tech Stack

| Layer | Library |
|---|---|
| Language | C++20 |
| Build | CMake 3.20+ |
| Window/Input | SDL2 |
| Graphics | OpenGL 3.3 Core Profile via GLAD |
| Math | GLM |
| ECS | EnTT |

## Build Commands

```bash
# Configure (from repo root)
cmake -B build -DCMAKE_BUILD_TYPE=Debug

# Build
cmake --build build -j$(nproc)

# Run
./build/quadsquad

# Release build (use for performance testing on Pi)
cmake -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j$(nproc)
```

## Architecture

### Entity Component System (EnTT)

All game objects are entities in an `entt::registry`. Systems are free functions or classes that query the registry each frame. Components are plain data structs — no logic inside them.

- **Components** live in `src/components/` — pure data, no methods beyond constructors.
- **Systems** live in `src/systems/` — stateless functions that iterate views on the registry.
- The main loop calls systems in a fixed order: input → physics → collision → render.

### Rendering

OpenGL 3.3 Core Profile only — no deprecated fixed-function pipeline. The renderer reads `Transform` and `Mesh` components from the registry each frame.

Split-screen is implemented by dividing the SDL2 window into 4 viewports via `glViewport`. Each viewport is rendered with the camera belonging to that player's entity.

### Input

SDL2 events are polled once per frame. Controller/keyboard bindings are mapped per player index (0–3). `InputSystem` writes results into per-player `InputState` components.

### Performance Guidelines (Pi 5 target)

- Prefer SoA (Structure of Arrays) layouts in EnTT views for cache efficiency.
- Avoid heap allocations in the hot path (per-frame systems).
- Keep draw calls low — batch static geometry where possible.
- Target 60 fps at 1080p split into 4 × 540×540 viewports.
