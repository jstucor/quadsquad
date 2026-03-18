#pragma once

#include <algorithm>

enum class PlayerClass { Soldier, Sniper, Heavy };

// Per-player weapon state and class stats.
// Lives as a plain struct in main (not an ECS entity) while only P1 is active.
struct WeaponComponent {

    PlayerClass playerClass    = PlayerClass::Soldier;

    // ── Heat system ───────────────────────────────────────────────────────────
    float currentHeat          = 0.f;
    float maxHeat              = 100.f;
    float heatPerShot          = 20.f;   // heat added per bolt
    float cooldownRate         = 15.f;   // heat/sec passively removed
    bool  overheatLockout      = false;  // true = cannot fire until lockout clears
    float lockoutTimer         = 0.f;    // seconds remaining in lockout

    // ── Class stats ───────────────────────────────────────────────────────────
    float damage               = 10.f;
    float classSpeedMult       = 1.f;    // multiplier on Camera::MOVE_SPEED
    bool  canZoom              = false;  // Sniper ADS (right mouse)
    float maxHp                = 100.f;
    float currentHp            = 100.f;

    static constexpr float LOCKOUT_DURATION = 3.f;

    // ── Presets ───────────────────────────────────────────────────────────────
    //   Soldier  — balanced blaster,  100 HP, medium heat capacity
    //   Sniper   — 1 shot = 50% heat, 75 HP, 25 dmg, ADS zoom, fast cooldown
    //   Heavy    — rapid fire,         150 HP, 200 heat capacity, slow movement
    void applyClass(PlayerClass cls) {
        playerClass     = cls;
        currentHeat     = 0.f;
        overheatLockout = false;
        lockoutTimer    = 0.f;

        switch (cls) {
            case PlayerClass::Soldier:
                maxHeat        = 100.f;  heatPerShot    = 20.f;
                cooldownRate   = 15.f;   damage         = 10.f;
                classSpeedMult = 1.00f;  canZoom        = false;
                maxHp          = 100.f;  break;

            case PlayerClass::Sniper:
                maxHeat        = 100.f;  heatPerShot    = 50.f; // 1 shot = 50%
                cooldownRate   = 20.f;   damage         = 25.f;
                classSpeedMult = 1.00f;  canZoom        = true;
                maxHp          =  75.f;  break;

            case PlayerClass::Heavy:
                maxHeat        = 200.f;  heatPerShot    = 10.f;
                cooldownRate   = 10.f;   damage         = 10.f;
                classSpeedMult = 0.65f;  canZoom        = false;
                maxHp          = 150.f;  break;
        }
        currentHp = maxHp;
    }

    // ── Per-frame update ──────────────────────────────────────────────────────
    void tick(float dt) {
        if (overheatLockout) {
            lockoutTimer -= dt;
            if (lockoutTimer <= 0.f) {
                overheatLockout = false;
                lockoutTimer    = 0.f;
                currentHeat     = 0.f;   // fully cooled after lockout penalty
            }
        } else {
            currentHeat = std::max(0.f, currentHeat - cooldownRate * dt);
        }
    }

    // Attempt to fire one bolt.  Returns true if the shot should be spawned.
    // Mutates heat state on success.
    bool tryFire() {
        if (overheatLockout) return false;
        currentHeat += heatPerShot;
        if (currentHeat >= maxHeat) {
            currentHeat     = maxHeat;
            overheatLockout = true;
            lockoutTimer    = LOCKOUT_DURATION;
        }
        return true;
    }
};
