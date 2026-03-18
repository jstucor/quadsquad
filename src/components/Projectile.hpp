#pragma once

#include <glm/glm.hpp>

// Marks an entity as a moving projectile.
struct Projectile {
    glm::vec3 velocity{0.f};   // world-space units per second
    float     damage  = 0.f;
    int       ownerID = -1;    // player index that fired this bolt

    Projectile() = default;
    Projectile(const glm::vec3& vel, float dmg, int owner)
        : velocity(vel), damage(dmg), ownerID(owner) {}
};
