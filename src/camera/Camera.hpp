#pragma once

#include "input/PlayerInput.hpp"
#include "physics/AABB.hpp"

#include <glm/glm.hpp>

// Combined player physics + first-person camera.
// physicsPos is the feet contact point (y=0 when standing on the floor).
//
// Frame order:  camera.update(input, dt)  →  CollisionSystem::resolve()  →  viewMatrix()
class Camera {
public:
    enum class MoveState { Standing, Crouching, Sprinting };

    glm::vec3 physicsPos{0.f, 0.f,  3.f};
    glm::vec3 velocity  {0.f, 0.f,  0.f};
    bool      isOnGround = false;

    MoveState moveState = MoveState::Standing;

    float yaw   = -90.f;   // degrees; -90 = looking toward -Z
    float pitch =   0.f;   // degrees; clamped to [-89, 89]

    // ── Class-driven overrides (set externally by WeaponComponent::applyClass) ─
    float classSpeedMult = 1.f;    // applied on top of sprint/crouch multipliers
    bool  canZoom        = false;  // Sniper ADS — right mouse activates zoom

    // ── Tuning constants ──────────────────────────────────────────────────────
    static constexpr float MOVE_SPEED        =  6.f;   // m/s base walk
    static constexpr float SPRINT_MULTIPLIER =  1.6f;
    static constexpr float CROUCH_MULTIPLIER =  0.5f;
    static constexpr float GRAVITY           = -22.f;  // m/s²
    static constexpr float JUMP_SPEED        =  8.f;   // m/s upward impulse
    static constexpr float EYE_STAND         =  1.7f;  // eye height standing
    static constexpr float EYE_CROUCH        =  0.6f;  // eye height crouching
    static constexpr float ZOOM_FOV_NORMAL   = 70.f;   // degrees unzoomed
    static constexpr float ZOOM_FOV_MAX      = 20.f;   // degrees fully zoomed (Sniper ADS)

    // Integrate look, movement state, gravity, jump, bob, and crouch lerp.
    // Resets isOnGround; CollisionSystem::resolve() restores it.
    void update(const PlayerInput& input, float dt);

    glm::vec3 eyePosition() const;  // includes bob offset and crouch lerp
    glm::vec3 getFront()    const;  // full 3-D forward vector (respects pitch)
    glm::mat4 viewMatrix()  const;
    AABB      getAABB()     const;  // AABB that shrinks smoothly during crouch

    // Current vertical FOV in degrees — varies smoothly with ADS zoom lerp.
    float zoomFOV()   const;
    // Current zoom level 0-1 — used by HUD to draw scope overlay.
    float zoomLevel() const { return m_zoomLerp; }

private:
    bool  m_prevJump     = false;
    float m_crouchLerp   = 0.f;    // 0 = standing, 1 = crouching (smoothly interpolated)
    float m_bobPhase     = 0.f;    // oscillation phase (radians), advances with distance walked
    float m_bobAmplitude = 0.f;    // current bob amplitude (smoothly lerped to avoid pop)
    float m_zoomLerp     = 0.f;    // 0 = not zoomed, 1 = fully zoomed (ADS)
};
