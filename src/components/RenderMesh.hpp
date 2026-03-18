#pragma once

#include <glm/glm.hpp>

// Visual geometry for a static scene object.
// Rendered as a unit cube scaled by (halfExtents * 2) at Transform::position.
// Used only on static level entities — never on droids, pickups, or projectiles,
// which ensures registry views stay unambiguous.
struct RenderMesh {
    glm::vec3 halfExtents{0.5f};
    glm::vec3 color{1.f};
};
