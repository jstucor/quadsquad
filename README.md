# QuadSquad

4-player local co-op FPS for Linux. Split-screen gameplay targeting Raspberry Pi 5 and Ubuntu x86 laptops.

## Tech Stack

| Layer | Library |
|---|---|
| Language | C++20 |
| Build | CMake 3.20+ |
| Window/Input | SDL2 |
| Graphics | OpenGL 3.3 Core Profile (GLAD) |
| Math | GLM |
| ECS | EnTT |

## Build

```bash
# Debug
cmake -B build -DCMAKE_BUILD_TYPE=Debug
cmake --build build -j$(nproc)
./build/quadsquad

# Release (use for Pi 5 performance testing)
cmake -B build-release -DCMAKE_BUILD_TYPE=Release
cmake --build build-release -j$(nproc)
```

**Dependencies (Ubuntu/Debian):**
```bash
sudo apt install libsdl2-dev libglm-dev libentt-dev
```

---

## Progress

### Done

- **CMake build system** — C++20, strict warnings (`-Wall -Wextra -Wpedantic`), Release `-O2` flag, all dependencies wired up
- **SDL2 window** — 1280×720, titled "QuadSquad", with `SDL_INIT_GAMECONTROLLER` ready for gamepads
- **OpenGL 3.3 Core context** — double-buffered, 24-bit depth, created and verified
- **GLAD loader** — OpenGL function pointers loaded successfully; GL version/renderer printed on startup
- **Adaptive VSync** — tries `-1` (adaptive) first, falls back to `1` (strict vsync)
- **Main loop skeleton** — polls SDL events, handles `SDL_QUIT` and `ESC`, clears framebuffer each frame, swaps buffers
- **Vendor GLAD** — bundled in `vendor/glad/` so the build works without a system-installed loader

### Not Yet Started

The application currently opens a dark window and exits cleanly. Everything below is still to be built:

- `src/components/` — `Transform`, `Mesh`, `Camera`, `InputState`, `Health`, `Weapon`, ...
- `src/systems/` — `InputSystem`, `PhysicsSystem`, `CollisionSystem`, `RenderSystem`
- Shaders — vertex and fragment GLSL for basic 3D rendering
- Camera — perspective projection, per-player entity
- Split-screen — 4× `glViewport` calls dividing the 1280×720 window into quadrants
- Mesh — triangle/cube geometry, VAO/VBO setup
- Textures — loading and binding
- Player spawning — 4 player entities in the ECS registry
- Weapons and combat
- Level/arena geometry

---

## Before Moving On

The following should be confirmed working **before** adding any game systems:

### Window & Context
- [ ] Window opens without errors on **Ubuntu x86** (development machine)
- [ ] Window opens without errors on **Raspberry Pi 5** (target hardware)
- [ ] OpenGL version printed to stdout is `3.3` or higher on both machines
- [ ] Renderer string looks correct (Mesa/Vulkan-radv/etc on Ubuntu; V3D on Pi)
- [ ] Window closes cleanly with both the `X` button and `ESC` — no crash, no SDL error

### VSync
- [ ] Confirm adaptive vsync (`-1`) is accepted on your GPU/driver; if not, verify the fallback to strict vsync fires without error
- [ ] No tearing visible on a solid clear color (the dark purple background counts)

### Build
- [ ] Debug build compiles clean with **zero warnings** (`-Wall -Wextra -Wpedantic`)
- [ ] Release build compiles clean with `-O2`
- [ ] Cross-compile or native build works on Pi 5 (note: EnTT and GLM must be available there too)

### Controller Detection (Groundwork)
- [ ] Plug in up to 4 gamepads; verify `SDL_INIT_GAMECONTROLLER` doesn't throw errors at startup (actual input handling comes later)

### Frame Timing Baseline
- [ ] On Pi 5 Release build, confirm the blank render loop holds 60 fps (use `glFinish` + a timer or an external tool like `vblankcount`) — this sets the budget for all future systems

---

## Architecture Notes

All game objects will be entities in an `entt::registry`. Systems are free functions that query the registry each frame. Components are plain data structs with no logic.

Main loop order (once implemented): **Input → Physics → Collision → Render**

Split-screen target: **4 × 540×540** viewports inside the 1080p window, one camera per player entity.

Performance rule of thumb for Pi 5: no heap allocations in per-frame systems, prefer SoA layouts in EnTT views, keep draw calls batched.
