#pragma once

#include "physics/AABB.hpp"

#include <entt/entt.hpp>
#include <glm/glm.hpp>
#include <string>
#include <vector>

// Parses a .lvl text file and manages static level data.
//
// ── File format ──────────────────────────────────────────────────────────────
//   Lines beginning with '#' or blank lines are ignored.
//   Inline '#' comments are stripped before parsing.
//
//   WALL    cx cy cz  hx hy hz  r g b   solid box  (collision + render)
//   DECO    cx cy cz  hx hy hz  r g b   visual box (no collision)
//   SPAWNER x z                          droid spawn point  (y = 0)
//   PICKUP  x z  HEALTH|HEAT             collectible pickup (y = 0)
//   PLAYER_START  idx  x y z  yaw       player start pose  (idx 0-3, yaw °)
//
class LevelManager {
public:
    LevelManager();

    // Parse a .lvl file.  Returns false and logs to stderr on failure.
    bool load(const std::string& path);

    // Spawn render + pickup entities into the registry.
    // Call once after load(), before the main loop.
    void spawnEntities(entt::registry& reg) const;

    // Collision AABBs built from every WALL entry.
    const std::vector<AABB>&       collisionAABBs()    const { return m_collisionAABBs; }

    // World positions (y=0) of SPAWNER entries.
    const std::vector<glm::vec3>&  spawnerPositions()  const { return m_spawnerPositions; }

    // Player starting world position (falls back to a safe default if absent).
    glm::vec3 playerStartPos(int idx) const;

    // Player starting yaw in degrees (−180..180).
    float     playerStartYaw(int idx) const;

private:
    struct MapObject {
        enum class Kind { Wall, Deco, Pickup };
        Kind      kind       = Kind::Wall;
        glm::vec3 center     {0.f};
        glm::vec3 half       {0.5f};
        glm::vec3 color      {1.f};
        int       pickupType = 0;    // 0 = Health, 1 = Heat
    };

    std::vector<MapObject>  m_objects;
    std::vector<AABB>       m_collisionAABBs;
    std::vector<glm::vec3>  m_spawnerPositions;

    glm::vec3 m_playerStartPos[4];
    float     m_playerStartYaw[4];
};
