#pragma once

#include <entt/entt.hpp>
#include <glm/glm.hpp>

class Shader;
class CubeMesh;
struct WeaponComponent;

namespace PickupSystem {

    // Spin/bob animation + proximity check.
    // Destroys collected pickups and applies their effect to `weapon`.
    void update(entt::registry& reg,
                const glm::vec3& playerPos,
                WeaponComponent& weapon,
                float dt);

    // Render all active pickups as spinning tilted diamonds.
    // Uses the flat-colour scene shader; bloom handles the glow.
    void render(const entt::registry& reg,
                Shader& shader, CubeMesh& mesh, const glm::mat4& vp);

} // namespace PickupSystem
