#pragma once

#include <glm/glm.hpp>

// Marks an entity as a moving projectile.
struct Projectile {
    glm::vec3 velocity{0.f};          // world-space units per second
    glm::vec3 color   {1.f, 1.f, 1.f}; // bolt + spark tint (set from class data)
    float     damage  = 0.f;
    int       ownerID = -1;           // player index that fired this bolt

    Projectile() = default;
    Projectile(const glm::vec3& vel, const glm::vec3& col, float dmg, int owner)
        : velocity(vel), color(col), damage(dmg), ownerID(owner) {}
};
