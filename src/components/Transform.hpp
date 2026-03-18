#pragma once

#include <glm/glm.hpp>

// World-space position and facing direction for any entity that occupies space.
struct Transform {
    glm::vec3 position{0.f};
    glm::vec3 forward {0.f, 0.f, -1.f};

    Transform() = default;
    Transform(const glm::vec3& pos, const glm::vec3& fwd)
        : position(pos), forward(fwd) {}
};
