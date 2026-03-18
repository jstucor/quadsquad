#pragma once

#include <glad/glad.h>
#include <glm/glm.hpp>
#include <array>

// Pool-based CPU-simulated particle system.
// All live particles are uploaded as a single instance-data VBO and drawn
// with one glDrawArraysInstanced call — no per-particle draw overhead.
//
// Usage per frame:
//   particles.update(dt);
//   particles.render(vp, camRight, camUp);   // called once per viewport
class ParticleSystem {
public:
    ParticleSystem();
    ~ParticleSystem();

    // Sparks when a bolt strikes a surface.
    // `pos`   — world-space impact point
    // `inDir` — normalised bolt travel direction (particles scatter back)
    // `color` — base hue; individual sparks mix toward white for variety
    void spawnImpact(const glm::vec3& pos,
                     const glm::vec3& inDir,
                     const glm::vec3& color);

    // Omnidirectional burst when a droid is destroyed.
    void spawnExplosion(const glm::vec3& pos);

    // Large orange/white fireball when a thermal detonator detonates.
    // Significantly bigger and longer-lived than a droid explosion.
    void spawnGrenadeExplosion(const glm::vec3& pos);

    // Advance all live particles: integrate velocity, apply gravity, age out.
    void update(float dt);

    // Draw all live particles as screen-space billboards with additive blending.
    // camRight/camUp are the first two rows of the current viewport's view matrix
    // (glm column-major: camRight = {view[0][0], view[1][0], view[2][0]}).
    void render(const glm::mat4& vp,
                const glm::vec3& camRight,
                const glm::vec3& camUp);

private:
    // ── Pool ───────────────────────────────────────────────────────────────────
    static constexpr int MAX_PARTICLES = 1024;

    struct Particle {
        glm::vec3 position  {0.f};
        glm::vec3 velocity  {0.f};
        glm::vec3 color     {1.f};
        float     initSize  = 0.07f;
        float     age       = 0.f;
        float     lifetime  = 0.5f;
        bool      alive     = false;
    };

    std::array<Particle, MAX_PARTICLES> m_pool{};
    int m_nextSlot = 0;  // ring-buffer cursor — overwrites oldest on overflow

    void emit(const glm::vec3& pos, const glm::vec3& vel,
              const glm::vec3& color, float size, float lifetime);

    // ── GPU ────────────────────────────────────────────────────────────────────
    GLuint m_vao         = 0;
    GLuint m_quadVBO     = 0;   // 6 vertices, static unit quad  (attrib 0)
    GLuint m_instanceVBO = 0;   // per-instance stream            (attribs 1-3)
    GLuint m_prog        = 0;

    // Instance data layout (8 floats = 32 bytes per particle):
    //   [0-2]  position   (vec3)
    //   [3]    size       (float)
    //   [4-7]  color+alpha (vec4)

    GLint m_locVP       = -1;
    GLint m_locCamRight = -1;
    GLint m_locCamUp    = -1;
};
