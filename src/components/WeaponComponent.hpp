#pragma once

#include <algorithm>
#include <glm/glm.hpp>

enum class PlayerClass { Soldier, Sniper, Heavy };

// Per-player weapon state and class stats.
// Acts as the ClassComponent — all per-class firing attributes live here and
// are set by applyClass().  Lives as a plain struct in main while only P1 is active.
struct WeaponComponent {

    PlayerClass playerClass    = PlayerClass::Soldier;

    // ── Heat system ───────────────────────────────────────────────────────────
    float currentHeat          = 0.f;
    float maxHeat              = 100.f;
    float heatPerShot          = 20.f;
    float cooldownRate         = 15.f;
    bool  overheatLockout      = false;
    float lockoutTimer         = 0.f;

    // ── Survivability ─────────────────────────────────────────────────────────
    float damage               = 10.f;
    float classSpeedMult       = 1.f;
    bool  canZoom              = false;
    float maxHp                = 100.f;
    float currentHp            = 100.f;

    // ── Class-specific firing attributes (set by applyClass) ──────────────────
    float     fireRate         = 0.2f;    // minimum seconds between shots
    float     fireCooldown     = 0.f;     // remaining cooldown this frame
    float     boltSpeed        = 150.f;   // m/s
    float     spread           = 0.f;     // max angular spread in degrees
    float     recoilAmount     = 0.f;     // upward pitch kick per shot (degrees)
    glm::vec3 boltColor        {1.f, 0.15f, 0.05f};  // red default

    // Heavy spin-up: barrels must spin up before first shot.
    float     adsZoomFOV       = 60.f;    // target FOV at full ADS (degrees)
    float     spinUpDelay      = 0.f;     // total seconds needed to reach full spin
    float     spinUpTimer      = 0.f;     // accumulated spin-up time

    static constexpr float LOCKOUT_DURATION   = 3.f;
    static constexpr float SPINDOWN_RATE      = 0.5f; // spin-down multiplier vs spin-up

    // ── Presets ───────────────────────────────────────────────────────────────
    //   Soldier — red bolts,   0.2s rate,  2° spread, standard 150 m/s
    //   Sniper  — green bolts, 1.5s rate,  0° spread, 300 m/s, 5° recoil per shot
    //   Heavy   — blue bolts,  0.05s rate, 1.5° spread, 0.5s spin-up before first bolt
    void applyClass(PlayerClass cls) {
        playerClass     = cls;
        currentHeat     = 0.f;
        overheatLockout = false;
        lockoutTimer    = 0.f;
        fireCooldown    = 0.f;
        spinUpTimer     = 0.f;

        switch (cls) {
            case PlayerClass::Soldier:
                maxHeat        = 100.f;   heatPerShot    = 20.f;
                cooldownRate   = 15.f;    damage         = 10.f;
                classSpeedMult = 1.00f;   canZoom        = false;
                maxHp          = 100.f;
                fireRate       = 0.20f;   boltSpeed      = 150.f;
                spread         = 2.0f;    recoilAmount   = 0.f;
                spinUpDelay    = 0.f;
                boltColor      = {1.0f, 0.15f, 0.05f};   // red
                adsZoomFOV     = 60.f;
                break;

            case PlayerClass::Sniper:
                maxHeat        = 100.f;   heatPerShot    = 50.f;
                cooldownRate   = 20.f;    damage         = 25.f;
                classSpeedMult = 1.00f;   canZoom        = true;
                maxHp          =  60.f;
                fireRate       = 1.50f;   boltSpeed      = 300.f;
                spread         = 0.0f;    recoilAmount   = 5.f;
                spinUpDelay    = 0.f;
                boltColor      = {0.1f, 1.0f, 0.25f};    // green
                adsZoomFOV     = 20.f;   // deep scope zoom
                break;

            case PlayerClass::Heavy:
                maxHeat        = 200.f;   heatPerShot    = 10.f;
                cooldownRate   = 10.f;    damage         = 10.f;
                classSpeedMult = 0.65f;   canZoom        = false;
                maxHp          = 150.f;
                fireRate       = 0.05f;   boltSpeed      = 120.f;
                spread         = 1.5f;    recoilAmount   = 0.f;
                spinUpDelay    = 0.5f;
                boltColor      = {0.15f, 0.4f, 1.0f};    // blue
                adsZoomFOV     = 60.f;
                break;
        }
        currentHp = maxHp;
    }

    // ── Per-frame update ──────────────────────────────────────────────────────
    // Pass isFiring so spin-up can advance/decay while the trigger is held.
    void tick(float dt, bool isFiring) {
        // Heat
        if (overheatLockout) {
            lockoutTimer -= dt;
            if (lockoutTimer <= 0.f) {
                overheatLockout = false;
                lockoutTimer    = 0.f;
                currentHeat     = 0.f;
            }
        } else {
            currentHeat = std::max(0.f, currentHeat - cooldownRate * dt);
        }

        // Fire-rate cooldown
        fireCooldown = std::max(0.f, fireCooldown - dt);

        // Heavy spin-up: advance when trigger held, decay when released
        if (spinUpDelay > 0.f) {
            if (isFiring) {
                spinUpTimer = std::min(spinUpTimer + dt, spinUpDelay);
            } else {
                spinUpTimer = std::max(0.f, spinUpTimer - dt * SPINDOWN_RATE);
            }
        }
    }

    // Attempt to fire one bolt.  Returns true when a bolt should be spawned.
    // Checks: overheat, fire-rate cooldown, spin-up.  Mutates state on success.
    bool tryFire() {
        if (overheatLockout)        return false;
        if (fireCooldown > 0.f)     return false;
        if (spinUpDelay > 0.f && spinUpTimer < spinUpDelay) return false;

        fireCooldown = fireRate;
        currentHeat += heatPerShot;
        if (currentHeat >= maxHeat) {
            currentHeat     = maxHeat;
            overheatLockout = true;
            lockoutTimer    = LOCKOUT_DURATION;
        }
        return true;
    }
};
