#pragma once

#include <glm/glm.hpp>

// State-machine component for enemy Droid entities.
// Each droid runs: Idle ⇄ Patrol ⇄ Attack
struct DroidAI {
    enum class State { Idle, Patrol, Attack };

    State     state          = State::Idle;
    float     stateTimer     = 0.f;          // seconds remaining in Idle
    glm::vec3 patrolTarget   {0.f};          // world-space destination (Patrol)
    float     attackCooldown = 0.f;          // seconds until next bolt fires

    // Tuning constants
    static constexpr float DETECT_RANGE    = 30.f;  // player range that triggers Attack
    static constexpr float DISENGAGE_RANGE = 35.f;  // hysteresis — leave Attack
    static constexpr float PATROL_SPEED    = 2.5f;  // m/s
    static constexpr float FIRE_INTERVAL   = 2.f;   // seconds between shots
    static constexpr float HALF_W          = 0.4f;  // AABB half-extent on X/Z (movement)
    static constexpr float HALF_H          = 0.5f;  // AABB half-extent on Y  (movement)
};
