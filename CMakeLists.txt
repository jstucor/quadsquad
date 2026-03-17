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

# EnTT — header-only
find_package(EnTT QUIET)
if(NOT EnTT_FOUND)
    add_library(EnTT INTERFACE)
    target_include_directories(EnTT INTERFACE /usr/include)
endif()

# GLAD — compile the single-file loader bundled in vendor/
add_library(glad STATIC vendor/glad/src/glad.c)
target_include_directories(glad PUBLIC vendor/glad/include)

# ── Executable ───────────────────────────────────────────────────────────────

add_executable(quadsquad
    src/main.cpp
)

target_include_directories(quadsquad PRIVATE src)

target_link_libraries(quadsquad PRIVATE
    glad
    SDL2::SDL2
    OpenGL::GL
    glm::glm
    EnTT
)
