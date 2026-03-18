#pragma once

// Collectible power-up entity.  Animation state lives here so PickupSystem
// can update and render without touching Transform.
struct Pickup {
    enum class Type { Health, Heat };

    Type  type      = Type::Health;
    float spinAngle = 0.f;    // accumulated Y-axis spin (radians)
    float bobPhase  = 0.f;    // accumulated bob phase (radians)

    // Tuning
    static constexpr float RADIUS        = 1.4f;   // collection sphere radius
    static constexpr float SPIN_SPEED    = 1.8f;   // rad/sec
    static constexpr float BOB_SPEED     = 2.2f;   // rad/sec
    static constexpr float BOB_AMPLITUDE = 0.12f;  // metres, peak displacement
    static constexpr float HOVER_HEIGHT  = 0.9f;   // base height off the floor
};
