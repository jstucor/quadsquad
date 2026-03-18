#pragma once

#include <entt/entt.hpp>
#include <glm/glm.hpp>
#include <vector>

struct AABB;
class ParticleSystem;
class Shader;
class CubeMesh;

namespace GrenadeSystem {

    // Spawn a grenade at `origin` travelling at `velocity`.
    entt::entity spawn(entt::registry& reg,
                       const glm::vec3& origin,
                       const glm::vec3& velocity);

    // Advance all live grenades each frame:
    //   • Applies gravity and integrates position.
    //   • Bounces off the floor and any wall AABB (velocity reflected + dampened).
    //   • On timer expiry: spawns a large explosion effect, destroys any droid
    //     within EXPLOSION_RADIUS, and returns the damage dealt to the player
    //     (quadratic falloff from the blast centre, 0 beyond EXPLOSION_RADIUS).
    float update(entt::registry& reg,
                 float dt,
                 const std::vector<AABB>& obstacles,
                 ParticleSystem& particles,
                 const glm::vec3& playerPos,
                 int* playerScores);

    // Draw all live grenades as small cubes.  Colour shifts orange → bright
    // yellow-white in the final second as a countdown warning.
    void render(entt::registry& reg,
                Shader& shader,
                CubeMesh& mesh,
                const glm::mat4& vp);

} // namespace GrenadeSystem
