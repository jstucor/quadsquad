#include "systems/PickupSystem.hpp"

#include "components/Pickup.hpp"
#include "components/Transform.hpp"
#include "components/WeaponComponent.hpp"
#include "renderer/Shader.hpp"
#include "renderer/CubeMesh.hpp"

#include <glm/gtc/matrix_transform.hpp>
#include <cmath>
#include <vector>
#include <algorithm>

// Build a model matrix for a spinning diamond pickup.
// The unit cube is tilted 35° on Z (diamond silhouette) and spun on Y.
static glm::mat4 pickupModel(const glm::vec3& basePos, float spinAngle, float bobPhase) {
    const float y = basePos.y + Pickup::HOVER_HEIGHT
                  + std::sin(bobPhase) * Pickup::BOB_AMPLITUDE;

    glm::mat4 m = glm::translate(glm::mat4{1.f}, {basePos.x, y, basePos.z});
    m = glm::rotate(m, spinAngle,              glm::vec3(0.f, 1.f, 0.f)); // spin
    m = glm::rotate(m, glm::radians(35.f),    glm::vec3(0.f, 0.f, 1.f)); // diamond tilt
    m = glm::scale(m, glm::vec3(0.30f * 2.f));                             // 0.30 m half-extent
    return m;
}

// ── Public API ────────────────────────────────────────────────────────────────

void PickupSystem::update(entt::registry& reg,
                          const glm::vec3& playerPos,
                          WeaponComponent& weapon,
                          float dt)
{
    std::vector<entt::entity> collected;

    auto view = reg.view<Transform, Pickup>();
    for (auto [entity, xform, pu] : view.each()) {
        // Advance animation.
        pu.spinAngle += Pickup::SPIN_SPEED * dt;
        pu.bobPhase  += Pickup::BOB_SPEED  * dt;

        // Proximity check (XZ plane only — height doesn't matter for collection).
        const glm::vec2 d = {playerPos.x - xform.position.x,
                             playerPos.z - xform.position.z};
        if (glm::length(d) > Pickup::RADIUS) continue;

        // Apply pickup effect.
        if (pu.type == Pickup::Type::Health) {
            weapon.currentHp = std::min(weapon.currentHp + 50.f, weapon.maxHp);
        } else {
            // Heat reset — clears overheat lockout instantly.
            weapon.currentHeat     = 0.f;
            weapon.overheatLockout = false;
            weapon.lockoutTimer    = 0.f;
        }

        collected.push_back(entity);
    }

    for (auto e : collected)
        if (reg.valid(e)) reg.destroy(e);
}

void PickupSystem::render(const entt::registry& reg,
                          Shader& shader, CubeMesh& mesh, const glm::mat4& vp)
{
    shader.use();

    auto view = reg.view<const Transform, const Pickup>();
    for (auto [entity, xform, pu] : view.each()) {
        // Colours chosen so max-channel ≥ 0.9 → reliably triggers the bloom pass.
        //   Health → bright green  (0.10, 0.95, 0.22)  max = 0.95
        //   Heat   → bright cyan   (0.10, 0.88, 1.00)  max = 1.00
        const glm::vec3 color = (pu.type == Pickup::Type::Health)
            ? glm::vec3{0.10f, 0.95f, 0.22f}
            : glm::vec3{0.10f, 0.88f, 1.00f};

        const glm::mat4 model = pickupModel(xform.position, pu.spinAngle, pu.bobPhase);
        shader.setMat4("uMVP",   vp * model);
        shader.setVec3("uColor", color);
        mesh.draw();
    }
}
