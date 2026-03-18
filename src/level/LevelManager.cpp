#include "level/LevelManager.hpp"

#include "components/RenderMesh.hpp"
#include "components/Pickup.hpp"
#include "components/Transform.hpp"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>

// ── Constructor — safe defaults ───────────────────────────────────────────────

LevelManager::LevelManager() {
    // Default player starts at the four arena corners, each facing the centre.
    // Overridden by PLAYER_START lines in the level file.
    m_playerStartPos[0] = { 11.f, 0.f,  11.f};  // SE — yaw -135°
    m_playerStartPos[1] = { 11.f, 0.f, -11.f};  // NE — yaw  135°
    m_playerStartPos[2] = {-11.f, 0.f,  11.f};  // SW — yaw  -45°
    m_playerStartPos[3] = {-11.f, 0.f, -11.f};  // NW — yaw   45°
    m_playerStartYaw[0] = -135.f;
    m_playerStartYaw[1] =  135.f;
    m_playerStartYaw[2] =  -45.f;
    m_playerStartYaw[3] =   45.f;
}

// ── Parsing ───────────────────────────────────────────────────────────────────

bool LevelManager::load(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        std::fprintf(stderr, "LevelManager: cannot open '%s'\n", path.c_str());
        return false;
    }

    m_objects.clear();
    m_collisionAABBs.clear();
    m_spawnerPositions.clear();

    std::string line;
    int lineNum = 0;

    while (std::getline(file, line)) {
        ++lineNum;

        // Strip inline comments and trim.
        const auto hashPos = line.find('#');
        if (hashPos != std::string::npos) line.resize(hashPos);
        if (line.find_first_not_of(" \t\r\n") == std::string::npos) continue;

        std::istringstream ss(line);
        std::string kw;
        ss >> kw;
        if (kw.empty()) continue;

        // ── WALL / DECO ───────────────────────────────────────────────────────
        if (kw == "WALL" || kw == "DECO") {
            MapObject obj;
            obj.kind = (kw == "WALL") ? MapObject::Kind::Wall : MapObject::Kind::Deco;
            ss >> obj.center.x >> obj.center.y >> obj.center.z
               >> obj.half.x   >> obj.half.y   >> obj.half.z
               >> obj.color.r  >> obj.color.g  >> obj.color.b;
            if (ss.fail()) {
                std::fprintf(stderr, "  line %d: malformed %s\n", lineNum, kw.c_str());
                continue;
            }
            m_objects.push_back(obj);
            if (obj.kind == MapObject::Kind::Wall)
                m_collisionAABBs.push_back(AABB::fromCenter(obj.center, obj.half));

        // ── SPAWNER ───────────────────────────────────────────────────────────
        } else if (kw == "SPAWNER") {
            float x, z;
            ss >> x >> z;
            if (ss.fail()) {
                std::fprintf(stderr, "  line %d: malformed SPAWNER\n", lineNum);
                continue;
            }
            m_spawnerPositions.push_back({x, 0.f, z});

        // ── PICKUP ────────────────────────────────────────────────────────────
        } else if (kw == "PICKUP") {
            float x, z;
            std::string type;
            ss >> x >> z >> type;
            if (ss.fail()) {
                std::fprintf(stderr, "  line %d: malformed PICKUP\n", lineNum);
                continue;
            }
            MapObject obj;
            obj.kind       = MapObject::Kind::Pickup;
            obj.center     = {x, 0.f, z};
            obj.pickupType = (type == "HEAT") ? 1 : 0;
            m_objects.push_back(obj);

        // ── PLAYER_START ──────────────────────────────────────────────────────
        } else if (kw == "PLAYER_START") {
            int   idx;
            float x, y, z, yaw;
            ss >> idx >> x >> y >> z >> yaw;
            if (ss.fail() || idx < 0 || idx > 3) {
                std::fprintf(stderr, "  line %d: malformed PLAYER_START\n", lineNum);
                continue;
            }
            m_playerStartPos[idx] = {x, y, z};
            m_playerStartYaw[idx] = yaw;

        } else {
            std::fprintf(stderr, "  line %d: unknown keyword '%s'\n", lineNum, kw.c_str());
        }
    }

    // Count entity types for the diagnostic summary.
    int walls = 0, decos = 0, pickups = 0;
    for (const auto& o : m_objects) {
        if (o.kind == MapObject::Kind::Wall)   ++walls;
        if (o.kind == MapObject::Kind::Deco)   ++decos;
        if (o.kind == MapObject::Kind::Pickup) ++pickups;
    }
    std::printf("LevelManager: loaded '%s'  walls=%d  deco=%d  pickups=%d  "
                "spawners=%d  collision_aabbs=%d\n",
                path.c_str(), walls, decos, pickups,
                (int)m_spawnerPositions.size(), (int)m_collisionAABBs.size());
    return true;
}

// ── Entity spawning ───────────────────────────────────────────────────────────

void LevelManager::spawnEntities(entt::registry& reg) const {
    for (const auto& obj : m_objects) {
        auto e = reg.create();

        if (obj.kind == MapObject::Kind::Wall || obj.kind == MapObject::Kind::Deco) {
            reg.emplace<Transform>(e, obj.center, glm::vec3(0.f, 0.f, -1.f));
            reg.emplace<RenderMesh>(e, obj.half, obj.color);

        } else if (obj.kind == MapObject::Kind::Pickup) {
            reg.emplace<Transform>(e, obj.center, glm::vec3(0.f, 0.f, -1.f));
            Pickup pu;
            pu.type      = (obj.pickupType == 1) ? Pickup::Type::Heat : Pickup::Type::Health;
            pu.spinAngle = 0.f;
            pu.bobPhase  = 0.f;
            reg.emplace<Pickup>(e, pu);
        }
    }
}

// ── Accessors ─────────────────────────────────────────────────────────────────

glm::vec3 LevelManager::playerStartPos(int idx) const {
    if (idx < 0 || idx > 3) return {0.f, 0.f, 3.f};
    return m_playerStartPos[idx];
}

float LevelManager::playerStartYaw(int idx) const {
    if (idx < 0 || idx > 3) return -90.f;
    return m_playerStartYaw[idx];
}
