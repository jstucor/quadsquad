#pragma once

#include <glm/glm.hpp>

namespace HUD {

    struct PlayerState {
        float       health          = 1.f;      // 0 – 1
        glm::vec3   pos             {0.f};
        float       crosshairScale  = 1.f;      // 1=normal, <1=accurate, >1=spread
        const char* stateLabel      = "WALK";   // "WALK" | "SPRINT" | "CROUCH"
        int         score           = 0;        // cumulative kill score
        float       heat            = 0.f;      // weapon heat, normalised 0 – 1
        bool        isOverheated    = false;    // in lockout cooldown
        float       lockoutTimer    = 0.f;      // seconds remaining in lockout
        const char* className       = "SOLDIER";// "SOLDIER" | "SNIPER" | "HEAVY"
        float       zoomLevel       = 0.f;      // 0=normal, 1=fully zoomed (ADS)
    };

    // Apply once after ImGui::CreateContext() to set the sci-fi colour theme.
    void applySciFiTheme();

    // Call between ImGui::NewFrame() and ImGui::Render().
    // Draws per-viewport HUD elements (crosshair, health bar, player label)
    // and the floating Developer Menu window.
    // activePlayers (1–4) controls the viewport split layout.
    void draw(const PlayerState players[4], float fps,
              int windowW, int windowH, int droidsAlive, int activePlayers);

    // Respawn class-selection overlay for one player's viewport quadrant.
    // Renders entirely via the foreground draw-list — no ImGui windows or input.
    // vpX/vpY/vpW/vpH: rect in ImGui (top-left origin) screen coordinates.
    // timerRemaining: seconds left on the 5-second countdown (0 – 5).
    // selectedClass: currently highlighted class (0=Soldier, 1=Sniper, 2=Heavy).
    void drawRespawnOverlay(float vpX, float vpY, float vpW, float vpH,
                            float timerRemaining, int selectedClass);

} // namespace HUD
