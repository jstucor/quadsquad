#include <glad/glad.h>
#include <SDL2/SDL.h>

#include "imgui.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_opengl3.h"

#include "input/InputManager.hpp"
#include "renderer/Shader.hpp"
#include "renderer/CubeMesh.hpp"
#include "camera/Camera.hpp"
#include "physics/AABB.hpp"
#include "physics/CollisionSystem.hpp"
#include "ui/HUD.hpp"
#include "systems/ProjectileSystem.hpp"
#include "systems/GrenadeSystem.hpp"
#include "renderer/PostProcess.hpp"
#include "systems/EnemySystem.hpp"
#include "systems/PickupSystem.hpp"
#include "particle/ParticleSystem.hpp"
#include "components/DroidAI.hpp"
#include "components/RenderMesh.hpp"
#include "components/Transform.hpp"
#include "components/WeaponComponent.hpp"
#include "level/LevelManager.hpp"

#include <entt/entt.hpp>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <vector>
#include <random>
#include <cmath>

static constexpr int WINDOW_W = 1280;
static constexpr int WINDOW_H = 720;

enum class GameState { MainMenu, Playing, GameOver };

// GL-space viewport rectangle (bottom-left origin, y up).
struct VPRect { int x, y, w, h; };

// ── GLSL shader sources ───────────────────────────────────────────────────────

static const char* k_vertSrc = R"glsl(
#version 330 core
layout(location = 0) in vec3 aPos;
uniform mat4 uMVP;
void main() {
    gl_Position = uMVP * vec4(aPos, 1.0);
}
)glsl";

static const char* k_fragSrc = R"glsl(
#version 330 core
uniform vec3 uColor;
out vec4 FragColor;
void main() {
    FragColor = vec4(uColor, 1.0);
}
)glsl";

// ── Bolt shader — emissive neon with alpha support ────────────────────────────
// Vertex stage is identical to the scene shader.
static const char* k_boltFragSrc = R"glsl(
#version 330 core
uniform vec3  uColor;
uniform float uAlpha;
out vec4 FragColor;
void main() {
    // Overbright pass-through: the two-pass glow technique in ProjectileSystem
    // uses additive blending on the outer shell, making the bolt appear to emit
    // light.  This shader simply exposes uAlpha so the glow pass can be transparent.
    FragColor = vec4(uColor, uAlpha);
}
)glsl";

// ─────────────────────────────────────────────────────────────────────────────

int main()
{
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
        std::fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return EXIT_FAILURE;
    }

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

    SDL_Window* window = SDL_CreateWindow(
        "QuadSquad",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        WINDOW_W, WINDOW_H,
        SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN
    );
    if (!window) {
        std::fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        SDL_Quit();
        return EXIT_FAILURE;
    }

    SDL_GLContext gl_ctx = SDL_GL_CreateContext(window);
    if (!gl_ctx) {
        std::fprintf(stderr, "SDL_GL_CreateContext: %s\n", SDL_GetError());
        SDL_DestroyWindow(window);
        SDL_Quit();
        return EXIT_FAILURE;
    }

    if (!gladLoadGLLoader(reinterpret_cast<GLADloadproc>(SDL_GL_GetProcAddress))) {
        std::fprintf(stderr, "GLAD: failed to load OpenGL function pointers\n");
        SDL_GL_DeleteContext(gl_ctx);
        SDL_DestroyWindow(window);
        SDL_Quit();
        return EXIT_FAILURE;
    }

    std::printf("OpenGL %s | %s\n", glGetString(GL_VERSION), glGetString(GL_RENDERER));

    if (SDL_GL_SetSwapInterval(-1) != 0) SDL_GL_SetSwapInterval(1);

    SDL_SetRelativeMouseMode(SDL_FALSE);  // cursor free for main menu
    glEnable(GL_DEPTH_TEST);

    // ── Dear ImGui ────────────────────────────────────────────────────────────
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange  // respect relative mouse mode
                   |  ImGuiConfigFlags_NavEnableKeyboard    // Enter/arrows navigate ImGui
                   |  ImGuiConfigFlags_NavEnableGamepad;    // gamepad A button navigates ImGui
    ImGui_ImplSDL2_InitForOpenGL(window, gl_ctx);
    ImGui_ImplOpenGL3_Init("#version 330 core");
    HUD::applySciFiTheme();

    // ── GL objects (scoped so destructors fire before context teardown) ───────
    {
        Shader      shader    {k_vertSrc, k_fragSrc};
        Shader      boltShader{k_vertSrc, k_boltFragSrc};
        CubeMesh    cubeMesh;
        Camera      camera;
        InputManager    inputManager;
        entt::registry  registry;
        PostProcess     postProcess{WINDOW_W, WINDOW_H};
        ParticleSystem  particles;
        LevelManager    levelMgr;

        // ── Weapon / class system ─────────────────────────────────────────
        WeaponComponent weapon;
        weapon.applyClass(PlayerClass::Soldier);  // default: Soldier
        camera.classSpeedMult = weapon.classSpeedMult;
        camera.canZoom        = weapon.canZoom;
        camera.adsZoomFOV     = weapon.adsZoomFOV;

        int playerScores[4]  = {};
        GameState gameState  = GameState::MainMenu;
        int menuSelectedMap  = 0;
        int activePlayers    = 1;  // 1–4; chosen on the main menu

        // Map catalogue — add new .lvl files here to extend the selection list.
        struct MapEntry { const char* displayName; const char* filePath; };
        static constexpr MapEntry k_maps[] = {
            { "Hangar Bay 7",  "assets/maps/hangar.lvl" },
        };
        static constexpr int k_mapCount = static_cast<int>(std::size(k_maps));

        // Per-player respawn state — currently only P1 is keyboard-controlled.
        struct PlayerRespawnState {
            bool  isDead        = false;
            float respawnTimer  = 0.f;    // counts down from 5 s
            int   selectedClass = 0;      // 0=Soldier, 1=Sniper, 2=Heavy
        };
        PlayerRespawnState p1Respawn;

        // Load a map, populate the registry, and switch to Playing.
        auto startGame = [&](int mapIdx) {
            registry.clear();
            if (!levelMgr.load(k_maps[mapIdx].filePath)) {
                std::fprintf(stderr, "Failed to load map '%s'\n",
                             k_maps[mapIdx].filePath);
                return;
            }
            levelMgr.spawnEntities(registry);
            camera.physicsPos     = levelMgr.playerStartPos(0);
            camera.yaw            = levelMgr.playerStartYaw(0);
            camera.velocity       = glm::vec3{0.f};
            weapon.applyClass(PlayerClass::Soldier);
            camera.classSpeedMult = weapon.classSpeedMult;
            camera.canZoom        = weapon.canZoom;
            camera.adsZoomFOV     = weapon.adsZoomFOV;
            EnemySystem::spawn(registry, levelMgr.spawnerPositions(),
                               levelMgr.collisionAABBs());
            std::fill(std::begin(playerScores), std::end(playerScores), 0);
            p1Respawn = {};
            int dummy; SDL_GetRelativeMouseState(&dummy, &dummy);
            SDL_SetRelativeMouseMode(SDL_TRUE);
            gameState = GameState::Playing;
        };

        // Apply chosen class, teleport to spawn, resume input.
        auto doRespawn = [&](int classIdx) {
            const PlayerClass nc =
                (classIdx == 0) ? PlayerClass::Soldier :
                (classIdx == 1) ? PlayerClass::Sniper  : PlayerClass::Heavy;
            weapon.applyClass(nc);
            camera.classSpeedMult = weapon.classSpeedMult;
            camera.canZoom        = weapon.canZoom;
            camera.adsZoomFOV     = weapon.adsZoomFOV;
            camera.physicsPos     = levelMgr.playerStartPos(0);
            camera.yaw            = levelMgr.playerStartYaw(0);
            camera.velocity       = glm::vec3{0.f};
            int dummy; SDL_GetRelativeMouseState(&dummy, &dummy);
            SDL_SetRelativeMouseMode(SDL_TRUE);
            p1Respawn.isDead = false;
        };

        // Static view matrices for P2, P3, P4 — scaled for the 30×30 m arena.
        const glm::mat4 k_staticViews[3] = {
            glm::lookAt(glm::vec3{ 18.f,  9.f, 16.f},   // P2: SE elevated corner
                        glm::vec3{  0.f,  1.f,  0.f}, glm::vec3{0,1,0}),
            glm::lookAt(glm::vec3{-18.f,  9.f,-16.f},   // P3: NW elevated corner
                        glm::vec3{  0.f,  1.f,  0.f}, glm::vec3{0,1,0}),
            glm::lookAt(glm::vec3{  0.f, 28.f,  0.f},   // P4: overhead
                        glm::vec3{  0.f,  0.f,  0.f}, glm::vec3{0,0,-1}),
        };

        Uint64 prevTime = SDL_GetPerformanceCounter();
        const Uint64 freq = SDL_GetPerformanceFrequency();

        bool running = true;
        while (running) {
            // -- Delta time --
            const Uint64 now = SDL_GetPerformanceCounter();
            const float  dt  = std::min(
                static_cast<float>(now - prevTime) / static_cast<float>(freq),
                0.05f   // cap at 50ms to prevent physics explosions after a freeze
            );
            prevTime = now;

            // -- Events (must drain before reading relative mouse state) --
            SDL_Event event;
            while (SDL_PollEvent(&event)) {
                ImGui_ImplSDL2_ProcessEvent(&event);
                if (event.type == SDL_QUIT) running = false;
                if (event.type == SDL_KEYDOWN) {
                    switch (event.key.keysym.sym) {
                        case SDLK_ESCAPE: running = false; break;

                        // ── Menu navigation ───────────────────────────────────
                        case SDLK_UP:
                            if (gameState == GameState::MainMenu)
                                menuSelectedMap = (menuSelectedMap - 1 + k_mapCount) % k_mapCount;
                            break;
                        case SDLK_DOWN:
                            if (gameState == GameState::MainMenu)
                                menuSelectedMap = (menuSelectedMap + 1) % k_mapCount;
                            break;

                        // ── Respawn class cycle (Left / Right) ────────────────
                        case SDLK_LEFT:
                            if (p1Respawn.isDead)
                                p1Respawn.selectedClass = (p1Respawn.selectedClass + 2) % 3;
                            break;
                        case SDLK_RIGHT:
                            if (p1Respawn.isDead)
                                p1Respawn.selectedClass = (p1Respawn.selectedClass + 1) % 3;
                            break;

                        case SDLK_RETURN:
                        case SDLK_KP_ENTER:
                            if (gameState == GameState::MainMenu)
                                startGame(menuSelectedMap);
                            else if (gameState == GameState::GameOver) {
                                SDL_SetRelativeMouseMode(SDL_FALSE);
                                gameState = GameState::MainMenu;
                            } else if (p1Respawn.isDead)
                                doRespawn(p1Respawn.selectedClass);
                            break;

                        // ── In-game class hotkeys ─────────────────────────────
                        case SDLK_1:
                            if (gameState == GameState::Playing) {
                                weapon.applyClass(PlayerClass::Soldier);
                                camera.classSpeedMult = weapon.classSpeedMult;
                                camera.canZoom        = weapon.canZoom;
                                camera.adsZoomFOV     = weapon.adsZoomFOV;
                            }
                            break;
                        case SDLK_2:
                            if (gameState == GameState::Playing) {
                                weapon.applyClass(PlayerClass::Sniper);
                                camera.classSpeedMult = weapon.classSpeedMult;
                                camera.canZoom        = weapon.canZoom;
                                camera.adsZoomFOV     = weapon.adsZoomFOV;
                            }
                            break;
                        case SDLK_3:
                            if (gameState == GameState::Playing) {
                                weapon.applyClass(PlayerClass::Heavy);
                                camera.classSpeedMult = weapon.classSpeedMult;
                                camera.canZoom        = weapon.canZoom;
                                camera.adsZoomFOV     = weapon.adsZoomFOV;
                            }
                            break;
                        default: break;
                    }
                }
                // Gamepad buttons
                if (event.type == SDL_CONTROLLERBUTTONDOWN) {
                    switch (event.cbutton.button) {
                        case SDL_CONTROLLER_BUTTON_A:
                            if (gameState == GameState::MainMenu)
                                startGame(menuSelectedMap);
                            else if (gameState == GameState::GameOver) {
                                SDL_SetRelativeMouseMode(SDL_FALSE);
                                gameState = GameState::MainMenu;
                            } else if (p1Respawn.isDead)
                                doRespawn(p1Respawn.selectedClass);
                            break;
                        // D-pad cycles class during respawn (all 4 directions)
                        case SDL_CONTROLLER_BUTTON_DPAD_UP:
                        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
                            if (p1Respawn.isDead)
                                p1Respawn.selectedClass = (p1Respawn.selectedClass + 2) % 3;
                            break;
                        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
                        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
                            if (p1Respawn.isDead)
                                p1Respawn.selectedClass = (p1Respawn.selectedClass + 1) % 3;
                            break;
                        default: break;
                    }
                }
            }

            // -- Input --
            inputManager.update();
            const PlayerInput& p0 = inputManager.getInput(0);

            // -- Respawn class navigation: W/S cycle, Space confirms ──────────
            // Handled here (from InputManager signals) so it works independently
            // of the SDL event loop's Left/Right/Enter fallback path.
            if (p1Respawn.isDead) {
                if (p0.menuPrev)
                    p1Respawn.selectedClass = (p1Respawn.selectedClass + 2) % 3;
                if (p0.menuNext)
                    p1Respawn.selectedClass = (p1Respawn.selectedClass + 1) % 3;
                if (p0.menuConfirm)
                    doRespawn(p1Respawn.selectedClass);
            }

            if (gameState == GameState::Playing) {
                if (!p1Respawn.isDead) {
                    // -- Physics --
                    camera.update(p0, dt);
                    CollisionSystem::resolve(camera, levelMgr.collisionAABBs());

                    // -- Weapon heat cooldown + spin-up --
                    weapon.tick(dt, p0.isFiring);

                    // -- Spawn bolt on fire --
                    if (p0.isFiring
                        && camera.moveState != Camera::MoveState::Sprinting
                        && weapon.tryFire())
                    {
                        static std::mt19937 fireRng{std::random_device{}()};
                        static std::uniform_real_distribution<float> unitDist(-1.f, 1.f);
                        static std::uniform_real_distribution<float> pitchKickDist(1.5f, 3.0f);
                        static std::uniform_real_distribution<float> yawShakeDist(-0.3f, 0.3f);

                        // Hip-fire spread scales with stance; ADS zeroes it entirely.
                        float effectiveSpread = weapon.spread;
                        if (camera.zoomLevel() > 0.05f) {
                            effectiveSpread = 0.f;          // ADS — 100% accurate
                        } else if (!camera.isOnGround) {
                            effectiveSpread *= 2.5f;        // airborne — very inaccurate
                        } else if (std::abs(p0.moveX) + std::abs(p0.moveY) > 0.1f) {
                            effectiveSpread *= 1.5f;        // moving  — moderately inaccurate
                        }

                        // Apply spread by deflecting the aim direction.
                        glm::vec3 shotDir = camera.getFront();
                        if (effectiveSpread > 0.f) {
                            const float spreadRad = glm::radians(effectiveSpread);
                            const glm::vec3 right = glm::normalize(
                                glm::cross(shotDir, glm::vec3{0.f, 1.f, 0.f}));
                            const glm::vec3 up = glm::cross(right, shotDir);
                            shotDir = glm::normalize(
                                shotDir
                                + right * (unitDist(fireRng) * std::tan(spreadRad))
                                + up    * (unitDist(fireRng) * std::tan(spreadRad)));
                        }

                        ProjectileSystem::spawn(registry, camera.eyePosition(),
                                                shotDir, /*ownerID=*/0,
                                                weapon.boltColor, weapon.boltSpeed);

                        // Procedural recoil: random vertical kick + horizontal shake.
                        // 50% of the kick springs back in ~0.2 s; 50% stays as drift.
                        camera.applyRecoil(pitchKickDist(fireRng),
                                           yawShakeDist(fireRng));
                    }

                    // -- Throw grenade (Q/G, Soldier class only) --
                    if (p0.isThrowingGrenade
                        && weapon.playerClass == PlayerClass::Soldier)
                    {
                        const glm::vec3 throwOrigin =
                            camera.eyePosition() + camera.getFront() * 0.5f;
                        const glm::vec3 throwVel =
                            camera.getFront() * 15.f + glm::vec3{0.f, 5.f, 0.f};
                        GrenadeSystem::spawn(registry, throwOrigin, throwVel);
                    }

                    // -- Hit detection: droid bolts vs player --
                    {
                        const float dmg = ProjectileSystem::checkPlayerHit(
                            registry, camera, particles, dt);
                        if (dmg > 0.f)
                            weapon.currentHp = std::max(0.f, weapon.currentHp - dmg);
                    }

                    // -- Pickups --
                    PickupSystem::update(registry, camera.physicsPos, weapon, dt);

                    // -- Death detection --
                    if (weapon.currentHp <= 0.f) {
                        weapon.currentHp = 0.f;
                        p1Respawn.isDead        = true;
                        p1Respawn.respawnTimer  = 5.0f;
                        p1Respawn.selectedClass =
                            (weapon.playerClass == PlayerClass::Soldier) ? 0 :
                            (weapon.playerClass == PlayerClass::Sniper)  ? 1 : 2;
                        SDL_SetRelativeMouseMode(SDL_FALSE);
                    }
                } else {
                    // -- Respawn countdown (game world keeps running) --
                    p1Respawn.respawnTimer -= dt;
                    if (p1Respawn.respawnTimer <= 0.f)
                        doRespawn(p1Respawn.selectedClass);
                }
            }

            // -- World simulation: always ticks while a level is loaded ──────
            if (gameState == GameState::Playing) {
                // -- Advance / expire bolts; detect wall hits and spawn sparks --
                ProjectileSystem::update(registry, dt,
                                         levelMgr.collisionAABBs(), particles);

                // -- Enemy AI (state machine, movement, firing) --
                EnemySystem::update(registry,
                                    camera.physicsPos,
                                    camera.eyePosition(),
                                    levelMgr.collisionAABBs(), dt);

                // -- Hit detection: player bolts vs droids --
                EnemySystem::checkHits(registry, dt, playerScores, particles);

                // -- Grenade physics, bouncing, and explosions --
                {
                    const float grenadeDmg = GrenadeSystem::update(
                        registry, dt,
                        levelMgr.collisionAABBs(), particles,
                        camera.physicsPos, playerScores);
                    if (grenadeDmg > 0.f && !p1Respawn.isDead)
                        weapon.currentHp = std::max(0.f, weapon.currentHp - grenadeDmg);
                }

                // -- Particle simulation --
                particles.update(dt);

                // -- Wave clear: all droids down → mission complete ────────────
                if (EnemySystem::count(registry) == 0) {
                    gameState = GameState::GameOver;
                    SDL_SetRelativeMouseMode(SDL_FALSE);
                }
            }

            // -- Render --
            ImGui_ImplOpenGL3_NewFrame();
            ImGui_ImplSDL2_NewFrame();
            ImGui::NewFrame();

            if (gameState == GameState::Playing) {
                // Redirect scene output to the post-process FBO (HDR colour + depth).
                postProcess.bindScene();

                // Clear the full framebuffer once; each glViewport below writes to a
                // non-overlapping quarter so depth values never bleed across viewports.
                glClearColor(0.08f, 0.08f, 0.12f, 1.0f);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                // Helper: draw the entire scene for one viewport.
                // camRight/camUp are extracted from the view matrix for billboard particles.
                auto drawScene = [&](const glm::mat4& vp,
                                     const glm::vec3& camRight,
                                     const glm::vec3& camUp) {
                    shader.use();

                    // Player cube (green)
                    {
                        const glm::mat4 model = glm::translate(
                            glm::mat4{1.f},
                            camera.physicsPos + glm::vec3{0.f, 0.5f, 0.f}
                        );
                        shader.setMat4("uMVP", vp * model);
                        shader.setVec3("uColor", glm::vec3{0.15f, 0.82f, 0.22f});
                        cubeMesh.draw();
                    }

                    // Level geometry (walls, floors, deco) — Transform + RenderMesh
                    {
                        auto meshView = registry.view<Transform, RenderMesh>();
                        for (auto [entity, xform, rm] : meshView.each()) {
                            glm::mat4 model = glm::translate(glm::mat4{1.f}, xform.position);
                            model = glm::scale(model, rm.halfExtents * 2.f);
                            shader.setMat4("uMVP", vp * model);
                            shader.setVec3("uColor", rm.color);
                            cubeMesh.draw();
                        }
                    }

                    EnemySystem::render(registry, shader, cubeMesh, vp);
                    PickupSystem::render(registry, shader, cubeMesh, vp);
                    GrenadeSystem::render(registry, shader, cubeMesh, vp);
                    particles.render(vp, camRight, camUp);
                    ProjectileSystem::render(registry, boltShader, cubeMesh, vp);
                };

                // Build GL-space viewport rects for the active player count.
                // Layouts:
                //   1p  — full screen
                //   2p  — top half (P1) / bottom half (P2)
                //   3-4p— 2×2 grid; 3p skips bottom-right quadrant
                VPRect glVPs[4]{};
                int vpW = 0, vpH = 0;

                if (activePlayers == 1) {
                    vpW = WINDOW_W; vpH = WINDOW_H;
                    glVPs[0] = {0, 0, vpW, vpH};
                } else if (activePlayers == 2) {
                    vpW = WINDOW_W; vpH = WINDOW_H / 2;
                    glVPs[0] = {0, vpH, vpW, vpH};  // top
                    glVPs[1] = {0, 0,   vpW, vpH};  // bottom
                } else {
                    vpW = WINDOW_W / 2; vpH = WINDOW_H / 2;
                    glVPs[0] = {0,   vpH, vpW, vpH};
                    glVPs[1] = {vpW, vpH, vpW, vpH};
                    glVPs[2] = {0,   0,   vpW, vpH};
                    glVPs[3] = {vpW, 0,   vpW, vpH};
                }

                const float vpAspect = static_cast<float>(vpW)
                                     / static_cast<float>(vpH);
                const glm::mat4 p1Proj = glm::perspective(
                    glm::radians(camera.zoomFOV()), vpAspect, 0.05f, 200.f);
                const glm::mat4 staticProj = glm::perspective(
                    glm::radians(70.f), vpAspect, 0.05f, 200.f);

                for (int p = 0; p < activePlayers; ++p) {
                    const auto& vpr = glVPs[p];
                    glViewport(vpr.x, vpr.y, vpr.w, vpr.h);

                    const glm::mat4 view = (p == 0)
                        ? camera.viewMatrix()
                        : k_staticViews[p - 1];
                    const glm::mat4& proj = (p == 0) ? p1Proj : staticProj;

                    // Extract camera basis from view matrix (GLM column-major):
                    //   right = first row  = {view[0][0], view[1][0], view[2][0]}
                    //   up    = second row = {view[0][1], view[1][1], view[2][1]}
                    const glm::vec3 camRight{view[0][0], view[1][0], view[2][0]};
                    const glm::vec3 camUp   {view[0][1], view[1][1], view[2][1]};

                    drawScene(proj * view, camRight, camUp);
                }

                // Bloom composite → default framebuffer; restores full viewport.
                postProcess.apply();
                glViewport(0, 0, WINDOW_W, WINDOW_H);

                // ── In-game HUD (all 4 viewports) ────────────────────────────
                HUD::PlayerState players[4]{};
                players[0].pos    = camera.physicsPos;
                switch (camera.moveState) {
                    case Camera::MoveState::Sprinting:
                        players[0].crosshairScale = 1.5f;
                        players[0].stateLabel     = "SPRINT";
                        break;
                    case Camera::MoveState::Crouching:
                        players[0].crosshairScale = 0.5f;
                        players[0].stateLabel     = "CROUCH";
                        break;
                    default:
                        players[0].crosshairScale = 1.f;
                        players[0].stateLabel     = "WALK";
                        break;
                }
                for (int p = 1; p < 4; ++p) players[p].health = 1.f;
                players[0].score        = playerScores[0];
                players[0].health       = weapon.currentHp / weapon.maxHp;
                players[0].heat         = weapon.currentHeat / weapon.maxHeat;
                players[0].isOverheated = weapon.overheatLockout;
                players[0].lockoutTimer = weapon.lockoutTimer;
                players[0].zoomLevel    = camera.zoomLevel();
                players[0].className    =
                    (weapon.playerClass == PlayerClass::Soldier) ? "SOLDIER" :
                    (weapon.playerClass == PlayerClass::Sniper)  ? "SNIPER"  : "HEAVY";

                HUD::draw(players, io.Framerate, WINDOW_W, WINDOW_H,
                          EnemySystem::count(registry), activePlayers);

                // Respawn overlay — drawn inside P1's ImGui-space viewport.
                // ImGui uses top-left origin; P1 is always the top-left quadrant.
                if (p1Respawn.isDead) {
                    const float p1VpW = (activePlayers >= 3)
                        ? static_cast<float>(WINDOW_W / 2)
                        : static_cast<float>(WINDOW_W);
                    const float p1VpH = (activePlayers == 1)
                        ? static_cast<float>(WINDOW_H)
                        : static_cast<float>(WINDOW_H / 2);
                    HUD::drawRespawnOverlay(0.f, 0.f, p1VpW, p1VpH,
                        p1Respawn.respawnTimer, p1Respawn.selectedClass);
                }
            }
            else
            {
                // Menu / game-over: render a plain dark backdrop directly to
                // the default framebuffer — no 3D, no post-process overhead.
                glBindFramebuffer(GL_FRAMEBUFFER, 0);
                glViewport(0, 0, WINDOW_W, WINDOW_H);
                glClearColor(0.04f, 0.04f, 0.08f, 1.0f);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                if (gameState == GameState::MainMenu) {
                    // ── Full-screen main menu ─────────────────────────────────
                    const ImGuiIO& menuIO = ImGui::GetIO();
                    const float W = menuIO.DisplaySize.x;
                    const float H = menuIO.DisplaySize.y;

                    ImGui::SetNextWindowPos({0.f, 0.f});
                    ImGui::SetNextWindowSize({W, H});
                    ImGui::Begin("##mainmenu", nullptr,
                        ImGuiWindowFlags_NoDecoration |
                        ImGuiWindowFlags_NoMove       |
                        ImGuiWindowFlags_NoScrollbar  |
                        ImGuiWindowFlags_NoBringToFrontOnFocus);

                    // Title
                    ImGui::SetCursorPosY(H * 0.12f);
                    const char* title = "QUADSQUAD: STAR WARS SKIRMISH";
                    const ImVec2 titleSz = ImGui::CalcTextSize(title);
                    ImGui::SetCursorPosX((W - titleSz.x * 2.f) * 0.5f);
                    ImGui::SetWindowFontScale(ImGui::GetFontSize() * 2.f);
                    ImGui::TextColored({0.0f, 0.85f, 1.0f, 1.0f}, "%s", title);
                    ImGui::SetWindowFontScale(1.f);   // restore

                    ImGui::Spacing(); ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::Spacing(); ImGui::Spacing();

                    const char* sub = "SELECT MISSION";
                    const ImVec2 subSz = ImGui::CalcTextSize(sub);
                    ImGui::SetCursorPosX((W - subSz.x) * 0.5f);
                    ImGui::TextColored({0.6f, 0.6f, 0.7f, 1.0f}, "%s", sub);

                    ImGui::Spacing(); ImGui::Spacing();

                    // Map list — centred, fixed width
                    const float listW = W * 0.45f;
                    ImGui::SetCursorPosX((W - listW) * 0.5f);
                    ImGui::BeginChild("##maplist", {listW, (float)k_mapCount * 28.f + 8.f},
                                      true);
                    for (int i = 0; i < k_mapCount; ++i) {
                        const bool selected = (menuSelectedMap == i);
                        if (selected)
                            ImGui::PushStyleColor(ImGuiCol_Header,
                                                  ImVec4{0.0f, 0.5f, 0.8f, 0.7f});
                        if (ImGui::Selectable(k_maps[i].displayName, selected,
                                              0, {listW - 16.f, 22.f}))
                            menuSelectedMap = i;
                        if (selected) ImGui::PopStyleColor();
                    }
                    ImGui::EndChild();

                    ImGui::Spacing(); ImGui::Spacing();

                    // Player count selector
                    {
                        const char* plLabel = "PLAYERS";
                        ImGui::SetCursorPosX(
                            (W - ImGui::CalcTextSize(plLabel).x) * 0.5f);
                        ImGui::TextColored({0.6f, 0.6f, 0.7f, 1.0f}, "%s", plLabel);

                        ImGui::Spacing();

                        // Four radio buttons for 1–4 players, row-centred.
                        // Measured width: each radio button is ~30 px wide + gap.
                        constexpr float RADIO_GAP = 50.f;
                        ImGui::SetCursorPosX((W - RADIO_GAP * 4.f) * 0.5f);
                        for (int n = 1; n <= 4; ++n) {
                            char buf[4];
                            std::snprintf(buf, sizeof(buf), "%d", n);
                            if (ImGui::RadioButton(buf, &activePlayers, n) && n < 4)
                                {} // selection handled by RadioButton
                            if (n < 4) ImGui::SameLine(0.f, RADIO_GAP
                                - ImGui::CalcTextSize(buf).x - 16.f);
                        }
                    }

                    ImGui::Spacing(); ImGui::Spacing();

                    // Deploy / Quit buttons
                    const float btnW = 140.f;
                    ImGui::SetCursorPosX((W - btnW * 2.f - 16.f) * 0.5f);
                    ImGui::PushStyleColor(ImGuiCol_Button,
                                          ImVec4{0.0f, 0.45f, 0.75f, 1.0f});
                    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                                          ImVec4{0.0f, 0.65f, 1.0f, 1.0f});
                    if (ImGui::Button("  DEPLOY  ", {btnW, 36.f}))
                        startGame(menuSelectedMap);
                    ImGui::PopStyleColor(2);

                    ImGui::SameLine(0.f, 16.f);
                    ImGui::PushStyleColor(ImGuiCol_Button,
                                          ImVec4{0.4f, 0.1f, 0.1f, 1.0f});
                    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                                          ImVec4{0.7f, 0.15f, 0.15f, 1.0f});
                    if (ImGui::Button("   QUIT   ", {btnW, 36.f}))
                        running = false;
                    ImGui::PopStyleColor(2);

                    ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::Spacing();
                    const char* hint = "UP / DOWN   Navigate      ENTER / A   Deploy";
                    ImGui::SetCursorPosX((W - ImGui::CalcTextSize(hint).x) * 0.5f);
                    ImGui::TextDisabled("%s", hint);

                    ImGui::End();
                }
                else if (gameState == GameState::GameOver) {
                    // ── Game-over / mission complete screen ───────────────────
                    const ImGuiIO& goIO = ImGui::GetIO();
                    const float W = goIO.DisplaySize.x;
                    const float H = goIO.DisplaySize.y;

                    ImGui::SetNextWindowPos({0.f, 0.f});
                    ImGui::SetNextWindowSize({W, H});
                    ImGui::Begin("##gameover", nullptr,
                        ImGuiWindowFlags_NoDecoration |
                        ImGuiWindowFlags_NoMove       |
                        ImGuiWindowFlags_NoBringToFrontOnFocus);

                    ImGui::SetCursorPosY(H * 0.30f);
                    const char* heading = "MISSION COMPLETE";
                    ImGui::SetWindowFontScale(ImGui::GetFontSize() * 2.4f);
                    const ImVec2 hSz = ImGui::CalcTextSize(heading);
                    ImGui::SetCursorPosX((W - hSz.x) * 0.5f);
                    ImGui::TextColored({0.0f, 1.0f, 0.5f, 1.0f}, "%s", heading);
                    ImGui::SetWindowFontScale(1.f);

                    ImGui::Spacing(); ImGui::Spacing();
                    ImGui::Separator();
                    ImGui::Spacing(); ImGui::Spacing();

                    char scoreBuf[64];
                    std::snprintf(scoreBuf, sizeof(scoreBuf),
                                  "Final Score:  %d", playerScores[0]);
                    const ImVec2 sSz = ImGui::CalcTextSize(scoreBuf);
                    ImGui::SetCursorPosX((W - sSz.x) * 0.5f);
                    ImGui::TextColored({0.9f, 0.8f, 0.2f, 1.0f}, "%s", scoreBuf);

                    ImGui::Spacing(); ImGui::Spacing(); ImGui::Spacing();

                    const float btnW2 = 200.f;
                    ImGui::SetCursorPosX((W - btnW2) * 0.5f);
                    ImGui::PushStyleColor(ImGuiCol_Button,
                                          ImVec4{0.0f, 0.35f, 0.6f, 1.0f});
                    ImGui::PushStyleColor(ImGuiCol_ButtonHovered,
                                          ImVec4{0.0f, 0.55f, 0.9f, 1.0f});
                    if (ImGui::Button("  RETURN TO MENU  ", {btnW2, 40.f})) {
                        SDL_SetRelativeMouseMode(SDL_FALSE);
                        gameState = GameState::MainMenu;
                    }
                    ImGui::PopStyleColor(2);

                    ImGui::Spacing();
                    const char* hint2 = "ENTER / A   Return to menu";
                    ImGui::SetCursorPosX((W - ImGui::CalcTextSize(hint2).x) * 0.5f);
                    ImGui::TextDisabled("%s", hint2);

                    ImGui::End();
                }
            }

            ImGui::Render();
            ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

            SDL_GL_SwapWindow(window);
        }
    }   // GL objects destroyed here while context is still alive

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();

    SDL_SetRelativeMouseMode(SDL_FALSE);
    SDL_GL_DeleteContext(gl_ctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return EXIT_SUCCESS;
}
