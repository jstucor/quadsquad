#pragma once

#include <glm/glm.hpp>

// Identifies a live grenade (thermal detonator) entity.
// The entity also carries a Transform for world position.
struct GrenadeComponent {
    glm::vec3 velocity   {0.f};
    float     timer      = 3.f;   // seconds until detonation
    float     bounciness = 0.4f;  // fraction of speed retained after each surface bounce
};
