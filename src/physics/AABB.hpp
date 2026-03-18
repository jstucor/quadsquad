#pragma once

#include <glm/glm.hpp>
#include <algorithm>
#include <cmath>

struct AABB {
    glm::vec3 min{0.f};
    glm::vec3 max{0.f};

    static AABB fromCenter(const glm::vec3& center, const glm::vec3& half) {
        return {center - half, center + half};
    }

    // Slab-method segment test: returns true if the line segment [p0, p1]
    // passes through or starts/ends inside this AABB.
    // Used for high-speed bolt hit detection to prevent tunnelling.
    bool intersectsSegment(const glm::vec3& p0, const glm::vec3& p1) const {
        const glm::vec3 d = p1 - p0;
        float tmin = 0.f, tmax = 1.f;
        for (int i = 0; i < 3; ++i) {
            if (std::abs(d[i]) < 1e-8f) {
                if (p0[i] < min[i] || p0[i] > max[i]) return false;
            } else {
                float t1 = (min[i] - p0[i]) / d[i];
                float t2 = (max[i] - p0[i]) / d[i];
                if (t1 > t2) std::swap(t1, t2);
                tmin = std::max(tmin, t1);
                tmax = std::min(tmax, t2);
                if (tmin > tmax) return false;
            }
        }
        return true;
    }
};
