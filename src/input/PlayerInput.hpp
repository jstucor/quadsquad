#pragma once

struct PlayerInput {
    // ── In-game movement / look ───────────────────────────────────────────────
    float moveX      = 0.f;  // -1 (left) .. +1 (right)
    float moveY      = 0.f;  // -1 (back) .. +1 (forward)
    float lookX      = 0.f;  // horizontal look axis
    float lookY      = 0.f;  // vertical look axis
    bool  isJumping   = false;
    bool  isFiring    = false;
    bool  isSprinting = false;  // Left Shift (suppressed while crouching)
    bool  isCrouching = false;  // Left Ctrl
    bool  isZooming   = false;  // Right Mouse (Sniper ADS — hold)

    // ── Menu / respawn navigation (rising-edge, one true frame per press) ─────
    // When a player is dead these redirect W/S/D-pad-up/down → class cycling
    // and Space/A-button → class confirm.  Game logic decides when to use them.
    bool  menuPrev    = false;  // W  or D-pad Up   — previous option
    bool  menuNext    = false;  // S  or D-pad Down — next option
    bool  menuConfirm = false;  // Space or A-button — confirm selection
};
