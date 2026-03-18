#pragma once

#include <entt/entt.hpp>
#include <glm/glm.hpp>
#include <vector>

struct AABB;
class Shader;
class CubeMesh;
class ParticleSystem;

namespace EnemySystem {

    // Spawn `count` droids at random arena positions, avoiding walls.
    void spawn(entt::registry& reg, int count,
               const std::vector<AABB>& statics);

    // Spawn one droid per entry in `positions` (from level SPAWNER data).
    // Each position is nudged out of any overlapping wall via resolveBox.
    void spawn(entt::registry& reg, const std::vector<glm::vec3>& positions,
               const std::vector<AABB>& statics);

    // Tick state machines, move droids, fire bolts at playerEye.
    void update(entt::registry& reg,
                const glm::vec3& playerPos,
                const glm::vec3& playerEye,
                const std::vector<AABB>& obstacles,
                float dt);

    // Continuous bolt-vs-droid hit test.  Destroys hit droids and the bolts
    // that caused the hit; credits 100 pts to scores[bolt.ownerID].
    // Spawns an explosion at each droid's death position via `particles`.
    void checkHits(entt::registry& reg, float dt, int* scores,
                   ParticleSystem& particles);

    // Render all living droids.  Colour encodes state (gold/amber/orange-red).
    void render(const entt::registry& reg,
                Shader& shader, CubeMesh& mesh, const glm::mat4& vp);

    // Return the number of living droid entities.
    int count(const entt::registry& reg);

} // namespace EnemySystem
