cmake_minimum_required(VERSION 3.20)
project(quadsquad LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Compiler warnings
add_compile_options(
    -Wall -Wextra -Wpedantic
    $<$<CONFIG:Release>:-O2>
)

# ── Dependencies ─────────────────────────────────────────────────────────────

find_package(SDL2 REQUIRED)
find_package(OpenGL REQUIRED)

# GLM — header-only, typically installed system-wide
find_package(glm QUIET)
if(NOT glm_FOUND)
    # Fallback: expect headers at /usr/include/glm
    add_library(glm::glm INTERFACE IMPORTED)
    target_include_directories(glm::glm INTERFACE /usr/include)
endif()

# EnTT — header-only, vendored single-header
add_library(EnTT INTERFACE)
target_include_directories(EnTT INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/vendor)
add_library(EnTT::EnTT ALIAS EnTT)

# GLAD — compile the single-file loader bundled in vendor/
add_library(glad STATIC vendor/glad/src/glad.c)
target_include_directories(glad PUBLIC vendor/glad/include)

# Dear ImGui (vendored v1.92.6) — SDL2 + OpenGL3 backends
add_library(imgui STATIC
    vendor/imgui/imgui.cpp
    vendor/imgui/imgui_draw.cpp
    vendor/imgui/imgui_tables.cpp
    vendor/imgui/imgui_widgets.cpp
    vendor/imgui/backends/imgui_impl_sdl2.cpp
    vendor/imgui/backends/imgui_impl_opengl3.cpp
)
target_include_directories(imgui PUBLIC
    vendor/imgui
    vendor/imgui/backends
)
target_link_libraries(imgui PUBLIC SDL2::SDL2 OpenGL::GL)
# Suppress warnings from vendored third-party code
target_compile_options(imgui PRIVATE -w)

# ── Executable ───────────────────────────────────────────────────────────────

add_executable(quadsquad
    src/main.cpp
    src/input/InputManager.cpp
    src/camera/Camera.cpp
    src/physics/CollisionSystem.cpp
    src/renderer/Shader.cpp
    src/renderer/CubeMesh.cpp
    src/renderer/PostProcess.cpp
    src/ui/HUD.cpp
    src/systems/ProjectileSystem.cpp
    src/systems/EnemySystem.cpp
    src/systems/PickupSystem.cpp
    src/systems/GrenadeSystem.cpp
    src/level/LevelManager.cpp
    src/particle/ParticleSystem.cpp
)

target_include_directories(quadsquad PRIVATE src)

target_link_libraries(quadsquad PRIVATE
    glad
    imgui
    SDL2::SDL2
    OpenGL::GL
    glm::glm
    EnTT::EnTT
)

install(TARGETS quadsquad DESTINATION bin)
