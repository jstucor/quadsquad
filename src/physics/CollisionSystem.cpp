#include "physics/CollisionSystem.hpp"
#include "camera/Camera.hpp"

#include <algorithm>
#include <optional>

// Returns the minimum translation vector that pushes AABB 'a' out of AABB 'b',
// or std::nullopt if the two boxes are not overlapping.
static std::optional<glm::vec3> computeMTV(const AABB& a, const AABB& b) {
    const float ox = std::min(a.max.x, b.max.x) - std::max(a.min.x, b.min.x);
    if (ox <= 0.f) return std::nullopt;
    const float oy = std::min(a.max.y, b.max.y) - std::max(a.min.y, b.min.y);
    if (oy <= 0.f) return std::nullopt;
    const float oz = std::min(a.max.z, b.max.z) - std::max(a.min.z, b.min.z);
    if (oz <= 0.f) return std::nullopt;

    // Resolve on the axis of minimum penetration.
    const glm::vec3 aC = (a.min + a.max) * 0.5f;
    const glm::vec3 bC = (b.min + b.max) * 0.5f;

    if (ox <= oy && ox <= oz) {
        const float sign = (aC.x < bC.x) ? -1.f : 1.f;
        return glm::vec3{sign * ox, 0.f, 0.f};
    }
    if (oy <= oz) {
        const float sign = (aC.y < bC.y) ? -1.f : 1.f;
        return glm::vec3{0.f, sign * oy, 0.f};
    }
    {
        const float sign = (aC.z < bC.z) ? -1.f : 1.f;
        return glm::vec3{0.f, 0.f, sign * oz};
    }
}

// Maximum height the player can automatically step up (curb / single stair).
static constexpr float STEP_HEIGHT = 0.35f;

glm::vec3 CollisionSystem::resolveBox(glm::vec3 pos,
                                       glm::vec3 halfExtents,
                                       const std::vector<AABB>& statics)
{
    pos.y = std::max(pos.y, 0.f);   // floor plane
    for (const AABB& obs : statics) {
        const auto mtv = computeMTV(
            AABB::fromCenter(pos + glm::vec3(0.f, halfExtents.y, 0.f), halfExtents),
            obs);
        if (!mtv) continue;
        pos += *mtv;
        pos.y = std::max(pos.y, 0.f);
    }
    return pos;
}

void CollisionSystem::resolve(Camera& camera, const std::vector<AABB>& statics) {
    // -- Floor plane (y = 0) --
    if (camera.physicsPos.y < 0.f) {
        camera.physicsPos.y = 0.f;
        if (camera.velocity.y < 0.f) camera.velocity.y = 0.f;
        camera.isOnGround = true;
    }

    // -- Static obstacle cubes --
    for (const AABB& obs : statics) {
        const auto mtv = computeMTV(camera.getAABB(), obs);
        if (!mtv) continue;

        const glm::vec3 m = *mtv;

        // ── Step-offset check ─────────────────────────────────────────────────
        // If the MTV is purely horizontal and the obstacle's top surface is
        // within STEP_HEIGHT of the player's feet, step up instead of bouncing
        // back.  Guard on vertical velocity so we don't "teleport" during a fall.
        if (m.y == 0.f && camera.velocity.y >= -2.f) {
            const float stepH = obs.max.y - camera.physicsPos.y;
            if (stepH > 0.001f && stepH <= STEP_HEIGHT) {
                camera.physicsPos.y  = obs.max.y;
                camera.velocity.y    = std::max(camera.velocity.y, 0.f);
                camera.isOnGround    = true;
                continue;   // obstacle cleared — skip horizontal push-back
            }
        }

        // ── Normal MTV resolution ─────────────────────────────────────────────
        camera.physicsPos += m;

        if (m.x != 0.f) camera.velocity.x = 0.f;
        if (m.z != 0.f) camera.velocity.z = 0.f;
        if (m.y > 0.f) {
            camera.velocity.y = 0.f;
            camera.isOnGround = true;
        }
        if (m.y < 0.f)
            camera.velocity.y = 0.f;   // hit ceiling
    }
}
