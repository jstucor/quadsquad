#include "systems/GrenadeSystem.hpp"

#include "components/GrenadeComponent.hpp"
#include "components/Transform.hpp"
#include "components/DroidAI.hpp"
#include "particle/ParticleSystem.hpp"
#include "physics/AABB.hpp"
#include "renderer/Shader.hpp"
#include "renderer/CubeMesh.hpp"

#include <glad/glad.h>
#include <glm/gtc/matrix_transform.hpp>

#include <algorithm>
#include <cfloat>
#include <vector>

// ── Constants ─────────────────────────────────────────────────────────────────

static constexpr float GRENADE_RADIUS    = 0.15f;   // collision / render radius
static constexpr float EXPLOSION_RADIUS  = 10.f;    // blast radius in world units
static constexpr float EXPLOSION_MAX_DMG = 80.f;    // damage at dead-centre
static constexpr float GRENADE_GRAVITY   = -22.f;   // m/s² (matches player gravity)

// ── Bounce helper ─────────────────────────────────────────────────────────────

// Expands an AABB by the grenade radius (Minkowski sum with a sphere) and tests
// whether `pos` is inside.  On hit, sets `outNormal` to the shallowest-penetration
// face normal (unit vector pointing outward) and `outDepth` to the overlap distance.
static bool checkWallBounce(const glm::vec3& pos, float radius,
                             const AABB& aabb,
                             glm::vec3& outNormal, float& outDepth)
{
    const glm::vec3 expMin = aabb.min - glm::vec3(radius);
    const glm::vec3 expMax = aabb.max + glm::vec3(radius);

    if (pos.x < expMin.x || pos.x > expMax.x ||
        pos.y < expMin.y || pos.y > expMax.y ||
        pos.z < expMin.z || pos.z > expMax.z)
        return false;

    // Walk all six faces and pick the one with the smallest overlap — that face
    // is the one the grenade is resting against / just passed through.
    float     minDepth = FLT_MAX;
    glm::vec3 normal{0.f};

    for (int i = 0; i < 3; ++i) {
        const float d0 = pos[i]     - expMin[i];  // depth into min-face
        const float d1 = expMax[i]  - pos[i];     // depth into max-face
        if (d0 < d1) {
            if (d0 < minDepth) {
                minDepth    = d0;
                normal      = glm::vec3{0.f};
                normal[i]   = -1.f;
            }
        } else {
            if (d1 < minDepth) {
                minDepth    = d1;
                normal      = glm::vec3{0.f};
                normal[i]   =  1.f;
            }
        }
    }
    outNormal = normal;
    outDepth  = minDepth;
    return true;
}

// ── Public API ────────────────────────────────────────────────────────────────

entt::entity GrenadeSystem::spawn(entt::registry& reg,
                                   const glm::vec3& origin,
                                   const glm::vec3& velocity)
{
    auto e = reg.create();
    reg.emplace<Transform>(e, origin,
        glm::length(velocity) > 0.01f ? glm::normalize(velocity)
                                      : glm::vec3{0.f, 0.f, -1.f});
    auto& gren    = reg.emplace<GrenadeComponent>(e);
    gren.velocity = velocity;
    return e;
}

float GrenadeSystem::update(entt::registry& reg,
                             float dt,
                             const std::vector<AABB>& obstacles,
                             ParticleSystem& particles,
                             const glm::vec3& playerPos,
                             int* playerScores)
{
    std::vector<entt::entity> toExplode;
    float playerDamage = 0.f;

    auto view = reg.view<Transform, GrenadeComponent>();
    for (auto [entity, xform, gren] : view.each()) {
        // -- Countdown --
        gren.timer -= dt;
        if (gren.timer <= 0.f) {
            toExplode.push_back(entity);
            continue;
        }

        // -- Gravity --
        gren.velocity.y += GRENADE_GRAVITY * dt;

        // -- Integrate --
        xform.position += gren.velocity * dt;

        // -- Floor bounce (y = 0 ground plane) --
        if (xform.position.y < GRENADE_RADIUS) {
            xform.position.y = GRENADE_RADIUS;
            if (gren.velocity.y < 0.f)
                gren.velocity.y = -gren.velocity.y * gren.bounciness;
            // Lateral friction on ground contact
            gren.velocity.x *= 0.80f;
            gren.velocity.z *= 0.80f;
        }

        // -- Wall bounces --
        for (const auto& wall : obstacles) {
            glm::vec3 normal;
            float     depth;
            if (!checkWallBounce(xform.position, GRENADE_RADIUS, wall, normal, depth))
                continue;

            // Push the grenade out of the wall surface
            xform.position += normal * depth;

            // Reflect and dampen — only if moving toward the surface
            if (glm::dot(gren.velocity, normal) < 0.f)
                gren.velocity = glm::reflect(gren.velocity, normal) * gren.bounciness;
        }

        // Keep forward pointing along travel direction for visual interest
        if (glm::length(gren.velocity) > 0.05f)
            xform.forward = glm::normalize(gren.velocity);
    }

    // -- Explosions --
    for (auto entity : toExplode) {
        if (!reg.valid(entity)) continue;

        const glm::vec3 blastPos = reg.get<Transform>(entity).position;

        // Large particle burst
        particles.spawnGrenadeExplosion(blastPos);

        // Player splash damage (quadratic falloff)
        {
            const float dist = glm::distance(playerPos, blastPos);
            if (dist < EXPLOSION_RADIUS) {
                const float t  = 1.f - dist / EXPLOSION_RADIUS;
                playerDamage  += EXPLOSION_MAX_DMG * t * t;
            }
        }

        // Destroy droids within radius — any hit kills (no HP system for droids)
        {
            std::vector<entt::entity> deadDroids;
            auto droidView = reg.view<Transform, DroidAI>();
            for (auto [droid, dtf, dai] : droidView.each()) {
                const glm::vec3 droidCentre = dtf.position + glm::vec3{0.f, 0.5f, 0.f};
                if (glm::distance(droidCentre, blastPos) < EXPLOSION_RADIUS) {
                    deadDroids.push_back(droid);
                    playerScores[0] += 100;
                }
            }
            for (auto d : deadDroids)
                if (reg.valid(d)) reg.destroy(d);
        }

        reg.destroy(entity);
    }

    return playerDamage;
}

void GrenadeSystem::render(entt::registry& reg,
                            Shader& shader,
                            CubeMesh& mesh,
                            const glm::mat4& vp)
{
    auto view = reg.view<Transform, GrenadeComponent>();
    if (view.begin() == view.end()) return;

    shader.use();

    for (auto [entity, xform, gren] : view.each()) {
        // Colour gradient: orange (full timer) → bright yellow-white (about to blow).
        // frac: 1.0 at spawn, 0.0 at detonation.
        const float frac = std::clamp(gren.timer / 3.f, 0.f, 1.f);
        const glm::vec3 col = glm::mix(
            glm::vec3{1.f, 1.f, 0.4f},   // bright yellow-white near detonation
            glm::vec3{1.f, 0.35f, 0.f},  // deep orange at spawn
            frac);

        const glm::mat4 model = glm::scale(
            glm::translate(glm::mat4{1.f}, xform.position),
            glm::vec3{GRENADE_RADIUS * 2.f});

        shader.setMat4("uMVP",   vp * model);
        shader.setVec3("uColor", col);
        mesh.draw();
    }
}
