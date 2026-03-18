#include "camera/Camera.hpp"

#include <glm/gtc/matrix_transform.hpp>
#include <algorithm>
#include <cmath>

// ── Bob tuning ────────────────────────────────────────────────────────────────
// BOB_FREQ: phase radians advanced per metre walked.
// At walk speed (6 m/s): 6 * 1.55 = 9.3 rad/s  → ~1.5 Hz — one step every 0.66 s
// At sprint  (9.6 m/s): 9.6 * 1.55 = 14.9 rad/s → ~2.4 Hz — appropriately quicker
static constexpr float BOB_FREQ     = 1.55f;
static constexpr float BOB_AMP_BASE = 0.022f;  // metres of peak vertical displacement

// ── State machine helpers ─────────────────────────────────────────────────────
static float speedMultiplier(Camera::MoveState s) {
    switch (s) {
        case Camera::MoveState::Sprinting: return Camera::SPRINT_MULTIPLIER;
        case Camera::MoveState::Crouching: return Camera::CROUCH_MULTIPLIER;
        default:                           return 1.f;
    }
}

// ─────────────────────────────────────────────────────────────────────────────

void Camera::update(const PlayerInput& input, float dt) {
    constexpr float LOOK_SENS     = 0.12f;
    constexpr float CROUCH_SPEED  = 9.f;   // lerp rate for crouch transition (units/s)
    constexpr float BOB_FADE_RATE = 7.f;   // lerp rate for bob amplitude fade
    constexpr float ZOOM_RATE     = 8.f;   // lerp rate for ADS zoom

    // -- ADS: all classes can zoom; adsZoomFOV controls target depth --
    const float zoomTarget = input.isZooming ? 1.f : 0.f;
    m_zoomLerp += (zoomTarget - m_zoomLerp) * std::min(ZOOM_RATE * dt, 1.f);

    // -- Recoil recovery --
    // bounce: elastic kick, springs to 0 in ~0.2 s
    // drift:  accumulated half-kick, decays over ~1 s (manual mouse correction)
    // yaw:    horizontal shake, fully recovers in ~0.1 s
    constexpr float BOUNCE_RATE = 12.f;
    constexpr float DRIFT_RATE  =  3.5f;
    constexpr float YAW_RATE    = 20.f;
    m_recoil.bounce *= std::max(0.f, 1.f - BOUNCE_RATE * dt);
    m_recoil.drift  *= std::max(0.f, 1.f - DRIFT_RATE  * dt);
    m_recoil.yaw    *= std::max(0.f, 1.f - YAW_RATE    * dt);

    // -- Look (sensitivity scales to 25% at full zoom for precision aiming) --
    const float effectiveSens = LOOK_SENS * (1.f - 0.75f * m_zoomLerp);
    yaw   += input.lookX * effectiveSens;
    pitch -= input.lookY * effectiveSens;
    pitch  = std::clamp(pitch, -89.f, 89.f);

    // -- Movement state --
    if      (input.isCrouching) moveState = MoveState::Crouching;
    else if (input.isSprinting) moveState = MoveState::Sprinting;
    else                        moveState = MoveState::Standing;

    const float spdMult = speedMultiplier(moveState);

    // -- Smooth crouch lerp --
    const float crouchTarget = (moveState == MoveState::Crouching) ? 1.f : 0.f;
    m_crouchLerp += (crouchTarget - m_crouchLerp) * std::min(CROUCH_SPEED * dt, 1.f);

    // -- Horizontal movement --
    const float     yr      = glm::radians(yaw);
    const glm::vec3 frontXZ = glm::normalize(glm::vec3(std::cos(yr), 0.f, std::sin(yr)));
    const glm::vec3 rightXZ = glm::normalize(glm::cross(frontXZ, glm::vec3(0.f, 1.f, 0.f)));
    // classSpeedMult applies the Heavy/Sniper speed penalty.
    // zoomMoveMult halves movement speed at full ADS zoom.
    const float zoomMoveMult = 1.f - 0.4f * m_zoomLerp;  // 40% speed penalty at full ADS
    const glm::vec3 hMove   = (frontXZ * input.moveY + rightXZ * input.moveX)
                             * MOVE_SPEED * spdMult * classSpeedMult * zoomMoveMult;
    const float     hSpeed  = glm::length(glm::vec2(hMove.x, hMove.z));

    // -- Camera bob --
    // Target amplitude: non-zero only when grounded and moving.
    // isOnGround here still holds last frame's value (reset happens below).
    // Suppress bob when zoomed — magnified shake would be nauseating.
    const float targetAmp = (isOnGround && hSpeed > 0.05f)
        ? BOB_AMP_BASE * spdMult * (1.f - m_zoomLerp)
        : 0.f;
    m_bobAmplitude += (targetAmp - m_bobAmplitude) * std::min(BOB_FADE_RATE * dt, 1.f);
    if (m_bobAmplitude > 0.001f)
        m_bobPhase += hSpeed * BOB_FREQ * dt;

    // -- Gravity --
    velocity.y += GRAVITY * dt;

    // -- Jump (reads isOnGround from previous frame, before the reset below) --
    if (input.isJumping && !m_prevJump && isOnGround)
        velocity.y = JUMP_SPEED;
    m_prevJump = input.isJumping;

    // -- Reset ground flag; CollisionSystem will restore it this frame --
    isOnGround = false;

    // -- Integrate --
    physicsPos   += hMove      * dt;
    physicsPos.y += velocity.y * dt;
}

glm::vec3 Camera::eyePosition() const {
    // Eye height slides smoothly between stand and crouch values.
    const float eyeH = EYE_STAND + (EYE_CROUCH - EYE_STAND) * m_crouchLerp;

    // Vertical bob: full sine wave.
    // Side bob: half-frequency gives a subtle left-right sway (Battlefront feel).
    const float bobY = std::sin(m_bobPhase)        * m_bobAmplitude;
    const float bobX = std::sin(m_bobPhase * 0.5f) * m_bobAmplitude * 0.25f;

    return physicsPos + glm::vec3(bobX, eyeH + bobY, 0.f);
}

void Camera::applyRecoil(float pitchDeg, float yawDeg) {
    // Split the kick: half springs back automatically (bounce),
    // half accumulates as drift the player must correct.
    m_recoil.bounce += pitchDeg * 0.5f;
    m_recoil.drift  += pitchDeg * 0.5f;
    m_recoil.yaw    += yawDeg;
}

glm::vec3 Camera::getFront() const {
    // Recoil offsets the view direction without touching stored pitch/yaw,
    // so mouse movement always feels consistent regardless of recoil state.
    const float effectivePitch = std::clamp(
        pitch + m_recoil.bounce + m_recoil.drift, -89.f, 89.f);
    const float effectiveYaw = yaw + m_recoil.yaw;
    const float pr = glm::radians(effectivePitch);
    const float yr = glm::radians(effectiveYaw);
    return glm::normalize(glm::vec3(
        std::cos(pr) * std::cos(yr),
        std::sin(pr),
        std::cos(pr) * std::sin(yr)
    ));
}

glm::mat4 Camera::viewMatrix() const {
    const glm::vec3 front = getFront();
    const glm::vec3 eye   = eyePosition();
    return glm::lookAt(eye, eye + front, glm::vec3(0.f, 1.f, 0.f));
}

float Camera::zoomFOV() const {
    return ZOOM_FOV_NORMAL - (ZOOM_FOV_NORMAL - adsZoomFOV) * m_zoomLerp;
}

AABB Camera::getAABB() const {
    // Height transitions smoothly: standing=1.0m, crouching=0.5m.
    // Half-height and centre-Y both scale with the lerp so the bottom stays at physicsPos.y.
    const float halfH   = 0.5f - 0.25f * m_crouchLerp;   // 0.5 → 0.25
    return AABB::fromCenter(
        physicsPos + glm::vec3(0.f, halfH, 0.f),
        glm::vec3(0.5f, halfH, 0.5f)
    );
}
