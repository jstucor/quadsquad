#include "systems/EnemySystem.hpp"

#include "components/DroidAI.hpp"
#include "components/Transform.hpp"
#include "components/Projectile.hpp"
#include "components/Lifetime.hpp"
#include "physics/AABB.hpp"
#include "physics/CollisionSystem.hpp"
#include "particle/ParticleSystem.hpp"
#include "renderer/Shader.hpp"
#include "renderer/CubeMesh.hpp"
#include "systems/ProjectileSystem.hpp"

#include <glm/gtc/matrix_transform.hpp>

#include <algorithm>
#include <random>
#include <vector>

// ── Module RNG ────────────────────────────────────────────────────────────────

static std::mt19937 s_rng{42u};

// Pick a random point inside the arena floor (keeps droids away from the
// player's starting position near z = +3).
static glm::vec3 randomArenaPoint() {
    static std::uniform_real_distribution<float> dX(-14.f, 14.f);
    static std::uniform_real_distribution<float> dZ(-18.f,  2.f);
    return {dX(s_rng), 0.f, dZ(s_rng)};
}

static float randIdleSecs() {
    static std::uniform_real_distribution<float> d(1.f, 3.f);
    return d(s_rng);
}

// ── Public API ────────────────────────────────────────────────────────────────

void EnemySystem::spawn(entt::registry& reg, int count,
                         const std::vector<AABB>& statics)
{
    std::uniform_real_distribution<float> dX(-14.f, 14.f);
    std::uniform_real_distribution<float> dZ(-14.f, 14.f);
    const glm::vec3 halfExt{DroidAI::HALF_W, DroidAI::HALF_H, DroidAI::HALF_W};

    for (int i = 0; i < count; ++i) {
        // Retry random positions until one lands outside every wall AABB.
        glm::vec3 pos;
        for (int attempt = 0; attempt < 30; ++attempt) {
            const glm::vec3 candidate{dX(s_rng), 0.f, dZ(s_rng)};
            const glm::vec3 resolved =
                CollisionSystem::resolveBox(candidate, halfExt, statics);
            // Accept if the position required no significant push
            if (glm::length(resolved - candidate) < 0.05f) {
                pos = candidate;
                break;
            }
            pos = resolved;   // fallback: use the pushed-out position
        }

        auto e = reg.create();
        reg.emplace<Transform>(e, pos, glm::vec3(0.f, 0.f, -1.f));
        auto& ai          = reg.emplace<DroidAI>(e);
        ai.stateTimer     = randIdleSecs();
        ai.attackCooldown = 0.5f + static_cast<float>(i) * 0.3f;
    }
}

void EnemySystem::spawn(entt::registry& reg,
                         const std::vector<glm::vec3>& positions,
                         const std::vector<AABB>& statics)
{
    const glm::vec3 halfExt{DroidAI::HALF_W, DroidAI::HALF_H, DroidAI::HALF_W};

    for (int i = 0; i < static_cast<int>(positions.size()); ++i) {
        // Push the spawn point out of any overlapping wall
        const glm::vec3 safePos =
            CollisionSystem::resolveBox(positions[i], halfExt, statics);

        auto e = reg.create();
        reg.emplace<Transform>(e, safePos, glm::vec3(0.f, 0.f, -1.f));
        auto& ai          = reg.emplace<DroidAI>(e);
        ai.stateTimer     = randIdleSecs();
        // Stagger so all droids don't open fire simultaneously.
        ai.attackCooldown = 0.5f + static_cast<float>(i) * 0.3f;
    }
}

void EnemySystem::update(entt::registry& reg,
                         const glm::vec3& playerPos,
                         const glm::vec3& playerEye,
                         const std::vector<AABB>& obstacles,
                         float dt)
{
    auto view = reg.view<Transform, DroidAI>();

    for (auto [entity, xform, ai] : view.each()) {
        ai.attackCooldown -= dt;

        const glm::vec3 toPlayer3D = playerPos - xform.position;
        const float dist2D = glm::length(glm::vec2(toPlayer3D.x, toPlayer3D.z));

        switch (ai.state) {

        // ── Idle ──────────────────────────────────────────────────────────────
        case DroidAI::State::Idle:
            ai.stateTimer -= dt;
            if (dist2D < DroidAI::DETECT_RANGE) {
                ai.state = DroidAI::State::Attack;
            } else if (ai.stateTimer <= 0.f) {
                ai.patrolTarget = randomArenaPoint();
                ai.state        = DroidAI::State::Patrol;
            }
            break;

        // ── Patrol ────────────────────────────────────────────────────────────
        case DroidAI::State::Patrol: {
            if (dist2D < DroidAI::DETECT_RANGE) {
                ai.state = DroidAI::State::Attack;
                break;
            }

            const glm::vec3 toTarget   = ai.patrolTarget - xform.position;
            const float     targetDist = glm::length(glm::vec2(toTarget.x, toTarget.z));

            if (targetDist < 0.8f) {
                // Reached waypoint — rest briefly then pick another.
                ai.state      = DroidAI::State::Idle;
                ai.stateTimer = randIdleSecs();
                break;
            }

            const glm::vec3 dir    = glm::normalize(glm::vec3(toTarget.x, 0.f, toTarget.z));
            const glm::vec3 newPos = xform.position + dir * DroidAI::PATROL_SPEED * dt;
            const glm::vec3 resolved = CollisionSystem::resolveBox(
                newPos,
                glm::vec3(DroidAI::HALF_W, DroidAI::HALF_H, DroidAI::HALF_W),
                obstacles);

            xform.forward  = dir;
            xform.position = resolved;

            // If the wall pushed us back significantly, choose a new waypoint
            // rather than oscillating against the obstacle forever.
            if (glm::length(resolved - newPos) > 0.05f)
                ai.patrolTarget = randomArenaPoint();

            break;
        }

        // ── Attack ────────────────────────────────────────────────────────────
        case DroidAI::State::Attack: {
            if (dist2D > DroidAI::DISENGAGE_RANGE) {
                ai.patrolTarget = randomArenaPoint();
                ai.state        = DroidAI::State::Patrol;
                break;
            }

            // Face the player on the horizontal plane only.
            if (dist2D > 0.1f)
                xform.forward = glm::normalize(glm::vec3(toPlayer3D.x, 0.f, toPlayer3D.z));

            // Fire only when cooldown has elapsed AND line-of-sight is clear.
            if (ai.attackCooldown <= 0.f) {
                const glm::vec3 muzzle = xform.position + glm::vec3(0.f, 0.8f, 0.f);

                // Cast a segment from muzzle to playerEye; if any wall AABB
                // intersects it, the shot is blocked — don't fire this tick.
                bool hasLOS = true;
                for (const auto& wall : obstacles) {
                    if (wall.intersectsSegment(muzzle, playerEye)) {
                        hasLOS = false;
                        break;
                    }
                }

                if (hasLOS) {
                    const glm::vec3 aimDir = glm::normalize(playerEye - muzzle);
                    ProjectileSystem::spawn(reg, muzzle, aimDir, /*ownerID=*/1);
                    ai.attackCooldown = DroidAI::FIRE_INTERVAL;
                }
                // If no LOS: leave cooldown ≤ 0 so the droid fires the moment
                // the player steps into view — no extra delay on acquisition.
            }
            break;
        }
        } // switch

        xform.position.y = 0.f;   // keep droids grounded
    }
}

void EnemySystem::checkHits(entt::registry& reg, float dt, int* scores,
                             ParticleSystem& particles)
{
    std::vector<entt::entity> deadDroids;
    std::vector<entt::entity> deadBolts;

    // Store droid positions before any destruction so explosion positions are valid
    std::vector<glm::vec3> explosionPositions;

    auto boltView  = reg.view<Transform, Projectile, Lifetime>();
    auto droidView = reg.view<Transform, DroidAI>();

    for (auto [droid, dxform, dai] : droidView.each()) {
        // Droid hit-box: 1 m cube centred at mid-body.
        const AABB box = AABB::fromCenter(
            dxform.position + glm::vec3(0.f, 0.5f, 0.f),
            glm::vec3(0.5f));

        for (auto [bolt, bxform, bproj, blt] : boltView.each()) {
            // A bolt consumed earlier this frame must not be retested.
            if (std::find(deadBolts.begin(), deadBolts.end(), bolt) != deadBolts.end())
                continue;
            if (bproj.ownerID != 0)   // only player bolts damage droids
                continue;

            // Reconstruct the segment the bolt swept through this frame.
            // This prevents fast bolts from tunnelling through thin targets.
            const glm::vec3 p1 = bxform.position;
            const glm::vec3 p0 = p1 - bproj.velocity * dt;

            if (box.intersectsSegment(p0, p1)) {
                scores[bproj.ownerID] += 100;
                explosionPositions.push_back(
                    dxform.position + glm::vec3(0.f, 0.5f, 0.f));  // mid-body
                deadDroids.push_back(droid);
                deadBolts.push_back(bolt);
                break;   // bolt is spent — no double-hits on the same frame
            }
        }
    }

    for (auto e : deadDroids) if (reg.valid(e)) reg.destroy(e);
    for (auto e : deadBolts)  if (reg.valid(e)) reg.destroy(e);

    // Spawn explosions after entity destruction so registry is clean
    for (const auto& pos : explosionPositions)
        particles.spawnExplosion(pos);
}

void EnemySystem::render(const entt::registry& reg,
                         Shader& shader, CubeMesh& mesh, const glm::mat4& vp)
{
    shader.use();
    auto view = reg.view<const Transform, const DroidAI>();

    for (auto [entity, xform, ai] : view.each()) {
        // Colour telegraphs AI state:
        //   Idle   → gold        (non-threatening)
        //   Patrol → amber       (on the move)
        //   Attack → orange-red  (hostile)
        glm::vec3 color;
        switch (ai.state) {
            case DroidAI::State::Idle:   color = {0.90f, 0.70f, 0.02f}; break;
            case DroidAI::State::Patrol: color = {0.80f, 0.55f, 0.02f}; break;
            case DroidAI::State::Attack: color = {0.95f, 0.28f, 0.02f}; break;
        }

        const glm::mat4 model = glm::translate(
            glm::mat4{1.f}, xform.position + glm::vec3(0.f, 0.5f, 0.f));
        shader.setMat4("uMVP",   vp * model);
        shader.setVec3("uColor", color);
        mesh.draw();
    }
}

int EnemySystem::count(const entt::registry& reg) {
    return static_cast<int>(reg.view<const DroidAI>().size());
}
