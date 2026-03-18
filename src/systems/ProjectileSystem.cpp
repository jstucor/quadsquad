#include "systems/ProjectileSystem.hpp"

#include "components/Transform.hpp"
#include "components/Projectile.hpp"
#include "components/Lifetime.hpp"
#include "physics/AABB.hpp"
#include "particle/ParticleSystem.hpp"
#include "camera/Camera.hpp"
#include "renderer/Shader.hpp"
#include "renderer/CubeMesh.hpp"

#include <glad/glad.h>
#include <glm/gtc/matrix_transform.hpp>

#include <cmath>
#include <vector>

// ── Helpers ───────────────────────────────────────────────────────────────────

// Build a model matrix that places and orients a bolt mesh.
// The unit cube's long axis is Z; we rotate Z → forward, then scale.
static glm::mat4 boltModel(const glm::vec3& pos,
                            const glm::vec3& fwd,
                            float widthScale = 1.f)
{
    glm::mat4 m{1.f};
    m = glm::translate(m, pos);

    // Rotate the default +Z axis to the bolt's forward direction.
    const glm::vec3 base{0.f, 0.f, 1.f};
    const float d = glm::dot(base, fwd);
    if (d < 0.9999f) {
        if (d > -0.9999f) {
            m = glm::rotate(m, std::acos(d), glm::normalize(glm::cross(base, fwd)));
        } else {
            // Anti-parallel: flip 180° around Y
            m = glm::rotate(m, glm::radians(180.f), glm::vec3{0.f, 1.f, 0.f});
        }
    }

    // Core dimensions: 6 cm × 6 cm × 80 cm.  widthScale expands for the glow.
    m = glm::scale(m, glm::vec3{0.06f * widthScale, 0.06f * widthScale, 0.80f});
    return m;
}

// ── Public API ────────────────────────────────────────────────────────────────

entt::entity ProjectileSystem::spawn(entt::registry& reg,
                                     const glm::vec3& origin,
                                     const glm::vec3& forward,
                                     int ownerID,
                                     const glm::vec3& color,
                                     float speed)
{
    auto e = reg.create();
    reg.emplace<Transform>(e, origin, forward);
    reg.emplace<Projectile>(e, forward * speed, color, 10.f, ownerID);
    reg.emplace<Lifetime>(e, 3.f);
    return e;
}

void ProjectileSystem::update(entt::registry& reg, float dt,
                               const std::vector<AABB>& obstacles,
                               ParticleSystem& particles)
{
    std::vector<entt::entity> expired;

    auto view = reg.view<Transform, Projectile, Lifetime>();
    for (auto entity : view) {
        auto& tf = view.get<Transform>(entity);
        auto& pr = view.get<Projectile>(entity);
        auto& lt = view.get<Lifetime>(entity);

        // Record position before moving for swept-segment collision
        const glm::vec3 oldPos = tf.position;

        tf.position  += pr.velocity * dt;
        lt.remaining -= dt;

        if (lt.remaining <= 0.f) {
            expired.push_back(entity);
            continue;
        }

        // Swept-segment vs wall AABBs — prevents tunnelling at high speed
        for (const auto& aabb : obstacles) {
            if (!aabb.intersectsSegment(oldPos, tf.position)) continue;

            // Spark colour inherits the bolt's own colour
            particles.spawnImpact(tf.position,
                                  glm::normalize(pr.velocity),
                                  pr.color);
            expired.push_back(entity);
            break;
        }
    }

    for (auto e : expired)
        if (reg.valid(e)) reg.destroy(e);
}

float ProjectileSystem::checkPlayerHit(entt::registry& reg,
                                        const Camera& camera,
                                        ParticleSystem& particles,
                                        float dt)
{
    static constexpr float DAMAGE_PER_BOLT = 10.f;

    const AABB playerBox = camera.getAABB();
    std::vector<entt::entity> deadBolts;
    float totalDamage = 0.f;

    auto view = reg.view<Transform, Projectile, Lifetime>();
    for (auto [entity, xform, proj, lt] : view.each()) {
        if (proj.ownerID == 0) continue;   // player's own bolts — skip

        // Swept segment for this frame so fast bolts can't pass through
        const glm::vec3 p1 = xform.position;
        const glm::vec3 p0 = p1 - proj.velocity * dt;

        if (playerBox.intersectsSegment(p0, p1)) {
            // Spawn a yellow-white impact flash at the hit point
            particles.spawnImpact(p1, glm::normalize(proj.velocity),
                                  glm::vec3{1.0f, 0.85f, 0.3f});
            totalDamage += DAMAGE_PER_BOLT;
            deadBolts.push_back(entity);
        }
    }

    for (auto e : deadBolts)
        if (reg.valid(e)) reg.destroy(e);

    return totalDamage;
}

void ProjectileSystem::render(entt::registry& reg,
                              Shader& shader,
                              CubeMesh& mesh,
                              const glm::mat4& vp)
{
    auto view = reg.view<Transform, Projectile>();
    if (view.begin() == view.end()) return;

    shader.use();

    // Bolt colour comes from Projectile::color (set at spawn from class data).
    // Three concentric passes:
    //   outer halo  — wide, very transparent, additive
    //   inner glow  — narrower, semi-transparent, additive
    //   core        — full-brightness opaque rod

    // ── Pass 1: additive glow shell ───────────────────────────────────────────
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE);
    glDepthMask(GL_FALSE);

    for (auto entity : view) {
        const auto& tf   = view.get<Transform>(entity);
        const auto& proj = view.get<Projectile>(entity);
        shader.setMat4("uMVP",   vp * boltModel(tf.position, tf.forward, 3.5f));
        shader.setVec3("uColor", proj.color * 0.75f);
        shader.setFloat("uAlpha", 0.10f);
        mesh.draw();
    }

    for (auto entity : view) {
        const auto& tf   = view.get<Transform>(entity);
        const auto& proj = view.get<Projectile>(entity);
        shader.setMat4("uMVP",   vp * boltModel(tf.position, tf.forward, 1.9f));
        shader.setVec3("uColor", proj.color * 0.90f);
        shader.setFloat("uAlpha", 0.22f);
        mesh.draw();
    }

    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);

    // ── Pass 2: opaque core ───────────────────────────────────────────────────
    for (auto entity : view) {
        const auto& tf   = view.get<Transform>(entity);
        const auto& proj = view.get<Projectile>(entity);
        shader.setMat4("uMVP",   vp * boltModel(tf.position, tf.forward, 1.f));
        shader.setVec3("uColor", proj.color);
        shader.setFloat("uAlpha", 1.f);
        mesh.draw();
    }
}
