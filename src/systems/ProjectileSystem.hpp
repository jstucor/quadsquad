#pragma once

#include <entt/entt.hpp>
#include <glm/glm.hpp>
#include <vector>

class Shader;
class CubeMesh;
class ParticleSystem;
struct AABB;
class Camera;

// Manages bolt entities: spawn, integrate, expire, and render.
// All state lives in the entt::registry; this file contains only free functions.
namespace ProjectileSystem {

    // Create a bolt at `origin` travelling in `forward` at 150 units/sec.
    // Bolt despawns after 3 seconds.
    entt::entity spawn(entt::registry& reg,
                       const glm::vec3& origin,
                       const glm::vec3& forward,
                       int ownerID);

    // Advance positions and destroy expired bolts.
    // Tests swept-segment bolt paths against `obstacles`; on hit, spawns impact
    // sparks via `particles` and destroys the bolt that frame.
    void update(entt::registry& reg, float dt,
                const std::vector<AABB>& obstacles,
                ParticleSystem& particles);

    // Test all droid bolts (ownerID != 0) against the player's AABB.
    // Destroys each bolt that hits and spawns a hit-flash via `particles`.
    // Returns the total damage dealt this frame (hits * 10.0 per bolt).
    float checkPlayerHit(entt::registry& reg,
                         const Camera& camera,
                         ParticleSystem& particles,
                         float dt);

    // Two-pass render: opaque neon-red core then additive glow shell.
    // Manages its own GL blend / depth-mask state and restores it on return.
    void render(entt::registry& reg,
                Shader& boltShader,
                CubeMesh& mesh,
                const glm::mat4& vp);

} // namespace ProjectileSystem
