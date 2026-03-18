#pragma once

#include "physics/AABB.hpp"
#include <vector>

class Camera;

// Resolves the player against the floor plane (y=0) and a set of static AABBs.
// Modifies camera.physicsPos, camera.velocity, and camera.isOnGround.
namespace CollisionSystem {
    void resolve(Camera& camera, const std::vector<AABB>& statics);

    // Push an arbitrary foot-position out of the floor and any static obstacles.
    // The AABB used is centred at (pos + vec3(0, halfExtents.y, 0)).
    // Returns the resolved (possibly adjusted) position.
    glm::vec3 resolveBox(glm::vec3 pos,
                         glm::vec3 halfExtents,
                         const std::vector<AABB>& statics);
}
