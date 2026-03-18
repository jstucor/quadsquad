#include "ui/HUD.hpp"

#include "imgui.h"

#include <cfloat>
#include <cstdio>
#include <cmath>
#include <algorithm>

// ── Sci-Fi colour palette ─────────────────────────────────────────────────────

static constexpr ImU32 COL_CYAN       = IM_COL32( 80, 220, 255, 210);
static constexpr ImU32 COL_CYAN_DIM   = IM_COL32( 30, 140, 190, 160);
static constexpr ImU32 COL_CYAN_GLOW  = IM_COL32(140, 240, 255, 255);
static constexpr ImU32 COL_BAR_BG     = IM_COL32(  0,  18,  35, 210);
static constexpr ImU32 COL_BAR_FILL   = IM_COL32(  0, 190, 255, 210);
static constexpr ImU32 COL_BAR_BORDER = IM_COL32(  0, 200, 255, 160);
static constexpr ImU32 COL_DIVIDER    = IM_COL32(  0,  90, 140, 110);
static constexpr ImU32 COL_LABEL      = IM_COL32( 80, 220, 255, 230);
static constexpr ImU32 COL_SHADOW     = IM_COL32(  0,   0,   0, 180);

// ── Colour helpers ────────────────────────────────────────────────────────────

// Compute a heat-bar fill colour: green → yellow → red as fraction rises.
static ImU32 heatFillColor(float fraction, int alpha) {
    int r, g, b;
    if (fraction <= 0.6f) {
        const float t = fraction / 0.6f;
        r = static_cast<int>(t * 215);
        g = static_cast<int>(200 - t * 25);
        b = 20;
    } else {
        const float t = (fraction - 0.6f) / 0.4f;
        r = 215;
        g = static_cast<int>(175 - t * 155);
        b = static_cast<int>(20  - t * 20);
    }
    return IM_COL32(r, g, b, alpha);
}

// ── Per-viewport helpers ──────────────────────────────────────────────────────

// Crosshair with dynamic scope reticle for ADS zoom.
// zoomLevel 0 = standard 4-bar; 1 = sniper scope (long lines + ring).
// When overheated the reticle pulses red.
static void drawCrosshair(ImDrawList* dl, float cx, float cy,
                           float scale, float zoomLevel,
                           bool isOverheated, float lockoutTimer)
{
    // Scope blend factor: reaches full scope style halfway through zoom travel.
    const float scopeT = std::min(zoomLevel * 1.6f, 1.f);

    // ── Standard 4-bar reticle (fades out as scope fades in) ─────────────────
    if (scopeT < 0.98f) {
        const int   a   = static_cast<int>(210 * (1.f - scopeT));
        const ImU32 col = IM_COL32(80, 220, 255, a);
        const float GAP = 5.f  * scale;
        const float LEN = 12.f * scale;
        constexpr float TH = 1.5f;
        dl->AddLine({cx - GAP - LEN, cy}, {cx - GAP,       cy}, col, TH);
        dl->AddLine({cx + GAP,       cy}, {cx + GAP + LEN, cy}, col, TH);
        dl->AddLine({cx, cy - GAP - LEN}, {cx, cy - GAP      }, col, TH);
        dl->AddLine({cx, cy + GAP      }, {cx, cy + GAP + LEN}, col, TH);
        dl->AddCircleFilled({cx, cy}, 1.8f, COL_CYAN_DIM);
        dl->AddCircle({cx, cy}, 3.f * scale, col, 8, 0.8f);
    }

    // ── Scope reticle (fades in with zoom) ────────────────────────────────────
    if (scopeT > 0.02f) {
        const int   a   = static_cast<int>(200 * scopeT);
        const ImU32 col = IM_COL32(80, 220, 255, a);
        constexpr float SCOPE_GAP  = 18.f;
        constexpr float SCOPE_LEN  = 85.f;
        constexpr float SCOPE_RING = 40.f;
        dl->AddLine({cx - SCOPE_GAP - SCOPE_LEN, cy}, {cx - SCOPE_GAP, cy}, col, 1.f);
        dl->AddLine({cx + SCOPE_GAP, cy}, {cx + SCOPE_GAP + SCOPE_LEN, cy}, col, 1.f);
        dl->AddLine({cx, cy - SCOPE_GAP - SCOPE_LEN}, {cx, cy - SCOPE_GAP}, col, 1.f);
        dl->AddLine({cx, cy + SCOPE_GAP}, {cx, cy + SCOPE_GAP + SCOPE_LEN}, col, 1.f);
        dl->AddCircle({cx, cy}, SCOPE_RING, col, 64, 1.f);
        dl->AddCircleFilled({cx, cy}, 2.2f, col);
    }

    // ── Overheat warning (pulsing red text below crosshair) ───────────────────
    if (isOverheated) {
        const float pulse = (std::sin(static_cast<float>(ImGui::GetTime()) * 10.f) + 1.f) * 0.5f;
        const ImU32 warnCol = IM_COL32(255, 30, 30, static_cast<int>(pulse * 230 + 25));
        char buf[32];
        std::snprintf(buf, sizeof(buf), "OVERHEAT  %.1fs", lockoutTimer);
        // Shadow + label
        dl->AddText({cx - 42.f, cy + 22.f}, COL_SHADOW, buf);
        dl->AddText({cx - 43.f, cy + 21.f}, warnCol,    buf);
    }
}

// Sci-fi health bar with tick marks and an "HP" label.
static void drawHealthBar(ImDrawList* dl, float ox, float oy,
                          float /*vpW*/, float vpH, float health)
{
    constexpr float BAR_W  = 130.f;
    constexpr float BAR_H  = 9.f;
    constexpr float MARGIN = 10.f;
    constexpr int   TICKS  = 10;

    const float bx = ox + MARGIN;
    const float by = oy + vpH - MARGIN - BAR_H;

    // Background
    dl->AddRectFilled({bx, by}, {bx + BAR_W, by + BAR_H}, COL_BAR_BG);

    // Fill — clamp health to [0,1]
    const float fillW = (BAR_W - 2.f) * std::clamp(health, 0.f, 1.f);
    if (fillW > 0.f)
        dl->AddRectFilled({bx + 1.f, by + 1.f},
                          {bx + 1.f + fillW, by + BAR_H - 1.f},
                          COL_BAR_FILL);

    // Tick marks at equal intervals
    for (int t = 1; t < TICKS; ++t) {
        const float tx = bx + (BAR_W / TICKS) * t;
        dl->AddLine({tx, by + 2.f}, {tx, by + BAR_H - 2.f}, COL_BAR_BG, 1.f);
    }

    // Border
    dl->AddRect({bx, by}, {bx + BAR_W, by + BAR_H}, COL_BAR_BORDER, 0.f, 0, 1.0f);

    // "HP" label to the right
    dl->AddText({bx + BAR_W + 5.f, by}, COL_CYAN_DIM, "HP");
}

// Weapon heat bar — sits directly above the HP bar.
// Colour gradients green → yellow → red.  Blinks bright red during lockout.
static void drawHeatBar(ImDrawList* dl, float ox, float oy,
                         float /*vpW*/, float vpH,
                         float heat, bool isOverheated, float lockoutTimer)
{
    constexpr float BAR_W  = 130.f;
    constexpr float BAR_H  =   9.f;
    constexpr float MARGIN =  10.f;
    constexpr float HP_BAR =   9.f;   // height of the HP bar below
    constexpr float GAP    =   3.f;   // gap between HP bar and heat bar
    constexpr int   TICKS  =  10;

    const float bx = ox + MARGIN;
    const float by = oy + vpH - MARGIN - HP_BAR - GAP - BAR_H;

    // Background
    dl->AddRectFilled({bx, by}, {bx + BAR_W, by + BAR_H}, COL_BAR_BG);

    // Fill
    const float fraction = std::clamp(heat, 0.f, 1.f);
    const float fillW    = (BAR_W - 2.f) * fraction;
    if (fillW > 0.f) {
        // Blink the fill during overheat lockout
        int fillAlpha = 210;
        if (isOverheated) {
            const float pulse = (std::sin(static_cast<float>(ImGui::GetTime()) * 8.f) + 1.f) * 0.5f;
            fillAlpha = static_cast<int>(80 + pulse * 175);
        }
        dl->AddRectFilled({bx + 1.f, by + 1.f},
                          {bx + 1.f + fillW, by + BAR_H - 1.f},
                          heatFillColor(fraction, fillAlpha));
    }

    // Tick marks
    for (int t = 1; t < TICKS; ++t) {
        const float tx = bx + (BAR_W / TICKS) * t;
        dl->AddLine({tx, by + 2.f}, {tx, by + BAR_H - 2.f}, COL_BAR_BG, 1.f);
    }

    // Border — red tint when near max
    const ImU32 borderCol = (fraction >= 0.85f)
        ? IM_COL32(230, 60, 60, 180) : COL_BAR_BORDER;
    dl->AddRect({bx, by}, {bx + BAR_W, by + BAR_H}, borderCol, 0.f, 0, 1.f);

    // Label
    const char* label = isOverheated ? "!!" : "HT";
    dl->AddText({bx + BAR_W + 5.f, by}, COL_CYAN_DIM, label);

    (void)lockoutTimer; // timer shown in crosshair warning, not repeated here
}

// Small "P1" / "P2" label in the top-left corner of the viewport.
static void drawPlayerLabel(ImDrawList* dl, float ox, float oy, int playerNum) {
    char buf[4];
    std::snprintf(buf, sizeof(buf), "P%d", playerNum);

    const float lx = ox + 8.f;
    const float ly = oy + 6.f;
    dl->AddText({lx + 1.f, ly + 1.f}, COL_SHADOW, buf);  // drop-shadow
    dl->AddText({lx, ly}, COL_LABEL, buf);
}

// Thin line that separates two viewports at a given screen coordinate.
static void drawDivider(ImDrawList* dl, float x0, float y0, float x1, float y1) {
    dl->AddLine({x0, y0}, {x1, y1}, COL_DIVIDER, 1.f);
}

// ── Public API ────────────────────────────────────────────────────────────────

void HUD::applySciFiTheme() {
    ImGuiStyle& s = ImGui::GetStyle();
    s.WindowRounding  = 2.f;
    s.FrameRounding   = 2.f;
    s.WindowBorderSize = 1.f;
    s.FrameBorderSize  = 1.f;
    s.ScrollbarRounding = 2.f;

    ImVec4* c = s.Colors;
    c[ImGuiCol_WindowBg]        = {0.02f, 0.06f, 0.13f, 0.90f};
    c[ImGuiCol_TitleBg]         = {0.00f, 0.14f, 0.26f, 1.00f};
    c[ImGuiCol_TitleBgActive]   = {0.00f, 0.22f, 0.40f, 1.00f};
    c[ImGuiCol_Border]          = {0.08f, 0.50f, 0.78f, 0.60f};
    c[ImGuiCol_FrameBg]         = {0.00f, 0.10f, 0.20f, 0.80f};
    c[ImGuiCol_FrameBgHovered]  = {0.00f, 0.20f, 0.34f, 0.90f};
    c[ImGuiCol_Text]            = {0.60f, 0.90f, 1.00f, 1.00f};
    c[ImGuiCol_TextDisabled]    = {0.28f, 0.48f, 0.58f, 1.00f};
    c[ImGuiCol_Separator]       = {0.08f, 0.40f, 0.62f, 0.80f};
    c[ImGuiCol_Header]          = {0.00f, 0.26f, 0.44f, 0.80f};
    c[ImGuiCol_HeaderHovered]   = {0.00f, 0.36f, 0.56f, 0.90f};
    c[ImGuiCol_HeaderActive]    = {0.00f, 0.44f, 0.68f, 1.00f};
    c[ImGuiCol_PopupBg]         = {0.02f, 0.06f, 0.12f, 0.95f};
}

void HUD::drawRespawnOverlay(float vpX, float vpY, float vpW, float vpH,
                              float timerRemaining, int selectedClass)
{
    ImDrawList* dl  = ImGui::GetForegroundDrawList();
    ImFont*     fnt = ImGui::GetFont();
    const float t   = static_cast<float>(ImGui::GetTime());

    // ── Dark overlay scoped to the player's quadrant ─────────────────────────
    dl->AddRectFilled({vpX, vpY}, {vpX + vpW, vpY + vpH},
                      IM_COL32(0, 0, 0, 165));

    // ── Countdown bar (top edge, cyan → red in final 1.5 s) ──────────────────
    const float barH   = 6.f;
    const float frac   = std::clamp(timerRemaining / 5.f, 0.f, 1.f);
    const bool  urgent = timerRemaining <= 1.5f;
    const float pulse  = (std::sin(t * 8.f) + 1.f) * 0.5f;

    dl->AddRectFilled({vpX, vpY}, {vpX + vpW, vpY + barH},
                      IM_COL32(20, 20, 20, 220));
    dl->AddRectFilled({vpX, vpY}, {vpX + vpW * frac, vpY + barH},
                      urgent ? IM_COL32(220, int(30 + pulse * 30), 30, 255)
                             : IM_COL32(0, 190, 220, 255));

    // ── "ELIMINATED" ─────────────────────────────────────────────────────────
    const float  elimSz    = 26.f;
    const char*  ELIM      = "ELIMINATED";
    const float  elimPulse = (std::sin(t * 3.5f) + 1.f) * 0.5f;
    const ImVec2 elimDim   = fnt->CalcTextSizeA(elimSz, FLT_MAX, 0.f, ELIM);
    const float  elimX     = vpX + (vpW - elimDim.x) * 0.5f;
    const float  elimY     = vpY + barH + 8.f;

    dl->AddText(fnt, elimSz, {elimX + 1.f, elimY + 1.f},
                IM_COL32(0, 0, 0, 200), ELIM);
    dl->AddText(fnt, elimSz, {elimX, elimY},
                IM_COL32(255,
                         int(20  + elimPulse * 30),
                         int(10  + elimPulse * 15), 255),
                ELIM);

    // ── Timer readout ─────────────────────────────────────────────────────────
    const float  timerSz = 20.f;
    char         tmBuf[8];
    std::snprintf(tmBuf, sizeof(tmBuf), "%.1f",
                  timerRemaining > 0.f ? timerRemaining : 0.f);
    const ImVec2 tmDim = fnt->CalcTextSizeA(timerSz, FLT_MAX, 0.f, tmBuf);
    const float  tmX   = vpX + (vpW - tmDim.x) * 0.5f;
    const float  tmY   = elimY + elimSz + 2.f;
    dl->AddText(fnt, timerSz, {tmX, tmY},
                urgent ? IM_COL32(255, int(50 + pulse * 50), int(50 + pulse * 50), 255)
                       : IM_COL32(160, 200, 220, 220),
                tmBuf);

    // ── "CHOOSE YOUR CLASS" ───────────────────────────────────────────────────
    const float  subSz  = 11.f;
    const char*  SUB    = "CHOOSE YOUR CLASS";
    const ImVec2 subDim = fnt->CalcTextSizeA(subSz, FLT_MAX, 0.f, SUB);
    const float  subY   = tmY + timerSz + 4.f;
    dl->AddText(fnt, subSz,
                {vpX + (vpW - subDim.x) * 0.5f, subY},
                IM_COL32(80, 160, 200, 180), SUB);

    // ── Class cards ──────────────────────────────────────────────────────────
    struct ClassInfo {
        const char* name;
        const char* role;
        const char* hp;
        const char* speed;
        const char* heat;
        const char* blurb;
        ImU32       accent;
    };
    static const ClassInfo k_classes[3] = {
        {"SOLDIER", "All-Rounder", "100 HP", "Normal", "Medium",
         "Balanced blaster.\nSteady cooldown.",
         IM_COL32( 80, 190, 255, 255)},
        {"SNIPER",  "Precision",   "60 HP",  "Fast",   "Low",
         "High-damage rifle.\nRight-click 3.5x zoom.",
         IM_COL32( 80, 255, 120, 255)},
        {"HEAVY",   "Frontline",   "150 HP", "Slow",   "High",
         "Rapid-fire cannon.\nSlow but hard to kill.",
         IM_COL32(255, 140,  30, 255)},
    };

    const float margin   = 10.f;
    const float gap      = 8.f;
    const float hintH    = 18.f;
    const float cardsTop = subY + subSz + 8.f;
    const float cardW    = (vpW - margin * 2.f - gap * 2.f) / 3.f;
    const float cardH    = vpH - (cardsTop - vpY) - margin - hintH - 4.f;
    const float nameSz   = 13.f;
    const float roleSz   = 10.f;
    const float statSz   = 10.f;

    for (int i = 0; i < 3; ++i) {
        const ClassInfo& ci  = k_classes[i];
        const bool       sel = (selectedClass == i);
        const float      cx  = vpX + margin + static_cast<float>(i) * (cardW + gap);
        const float      cy  = cardsTop;

        // Background + border
        dl->AddRectFilled({cx, cy}, {cx + cardW, cy + cardH},
                          sel ? IM_COL32( 0, 40, 80, 220)
                              : IM_COL32(15, 15, 28, 200), 4.f);
        dl->AddRect({cx, cy}, {cx + cardW, cy + cardH},
                    sel ? ci.accent : IM_COL32(50, 50, 70, 180),
                    4.f, 0, sel ? 2.f : 1.f);

        float ly = cy + 8.f;

        // Class name (centred)
        const ImVec2 nameDim = fnt->CalcTextSizeA(nameSz, FLT_MAX, 0.f, ci.name);
        dl->AddText(fnt, nameSz,
                    {cx + (cardW - nameDim.x) * 0.5f, ly},
                    sel ? ci.accent : IM_COL32(140, 150, 165, 255),
                    ci.name);
        ly += nameSz + 2.f;

        // Role (centred, dimmed)
        const ImVec2 roleDim = fnt->CalcTextSizeA(roleSz, FLT_MAX, 0.f, ci.role);
        dl->AddText(fnt, roleSz,
                    {cx + (cardW - roleDim.x) * 0.5f, ly},
                    IM_COL32(80, 110, 140, 200), ci.role);
        ly += roleSz + 4.f;

        // Separator
        dl->AddLine({cx + 6.f, ly}, {cx + cardW - 6.f, ly},
                    IM_COL32(40, 80, 110, 150), 1.f);
        ly += 5.f;

        // Stat rows: label + value
        auto statRow = [&](const char* lbl, const char* val) {
            dl->AddText(fnt, statSz, {cx + 6.f, ly},
                        IM_COL32(80, 160, 220, 200), lbl);
            const float lw = fnt->CalcTextSizeA(statSz, FLT_MAX, 0.f, lbl).x;
            dl->AddText(fnt, statSz, {cx + 6.f + lw + 4.f, ly},
                        IM_COL32(200, 210, 220, 220), val);
            ly += statSz + 3.f;
        };
        statRow("HP",  ci.hp);
        statRow("SPD", ci.speed);
        statRow("HT",  ci.heat);

        ly += 2.f;
        dl->AddLine({cx + 6.f, ly}, {cx + cardW - 6.f, ly},
                    IM_COL32(40, 80, 110, 150), 1.f);
        ly += 5.f;

        // Blurb (auto-wrapped by AddText wrap_width)
        dl->AddText(fnt, statSz, {cx + 6.f, ly},
                    IM_COL32(120, 130, 145, 200),
                    ci.blurb, nullptr, cardW - 12.f);

        // "[ SELECTED ]" badge at card bottom
        if (sel) {
            const char*  SEL    = "[ SELECTED ]";
            const ImVec2 selDim = fnt->CalcTextSizeA(statSz, FLT_MAX, 0.f, SEL);
            dl->AddText(fnt, statSz,
                        {cx + (cardW - selDim.x) * 0.5f,
                         cy + cardH - statSz - 6.f},
                        ci.accent, SEL);
        }
    }

    // ── Input hint (bottom edge) ──────────────────────────────────────────────
    const char*  HINT    = "< >  Cycle Class        ENTER  Spawn Now";
    const ImVec2 hintDim = fnt->CalcTextSizeA(subSz, FLT_MAX, 0.f, HINT);
    dl->AddText(fnt, subSz,
                {vpX + (vpW - hintDim.x) * 0.5f,
                 vpY + vpH - hintH + 2.f},
                IM_COL32(70, 100, 130, 200), HINT);
}

void HUD::draw(const PlayerState players[4], float fps,
               int windowW, int windowH, int droidsAlive, int activePlayers)
{
    const float fw = static_cast<float>(windowW);
    const float fh = static_cast<float>(windowH);
    const float hw = fw * 0.5f;
    const float hh = fh * 0.5f;

    // Compute per-player ImGui-space viewport origins and dimensions.
    // ImGui uses top-left origin; layouts mirror the GL split:
    //   1p  — full screen
    //   2p  — P1 top half, P2 bottom half
    //   3-4p— 2×2 grid: P1 top-left, P2 top-right, P3 bot-left, P4 bot-right
    float vpW[4]{}, vpH_[4]{};
    float originX[4]{}, originY[4]{};

    if (activePlayers == 1) {
        vpW[0] = fw; vpH_[0] = fh;
        originX[0] = 0.f; originY[0] = 0.f;
    } else if (activePlayers == 2) {
        vpW[0] = fw; vpH_[0] = hh;  originX[0] = 0.f; originY[0] = 0.f;
        vpW[1] = fw; vpH_[1] = hh;  originX[1] = 0.f; originY[1] = hh;
    } else {
        for (int p = 0; p < 4; ++p) { vpW[p] = hw; vpH_[p] = hh; }
        originX[0] = 0.f; originY[0] = 0.f;
        originX[1] = hw;  originY[1] = 0.f;
        originX[2] = 0.f; originY[2] = hh;
        originX[3] = hw;  originY[3] = hh;
    }

    ImDrawList* dl = ImGui::GetForegroundDrawList();

    // ── Per-viewport HUD ──────────────────────────────────────────────────────
    for (int p = 0; p < activePlayers; ++p) {
        const float ox  = originX[p];
        const float oy  = originY[p];
        const float pvW = vpW[p];
        const float pvH = vpH_[p];

        drawCrosshair(dl, ox + pvW * 0.5f, oy + pvH * 0.5f,
                      players[p].crosshairScale,
                      players[p].zoomLevel,
                      players[p].isOverheated,
                      players[p].lockoutTimer);
        drawHealthBar(dl, ox, oy, pvW, pvH, players[p].health);
        drawHeatBar(dl, ox, oy, pvW, pvH,
                    players[p].heat,
                    players[p].isOverheated,
                    players[p].lockoutTimer);
        drawPlayerLabel(dl, ox, oy, p + 1);
    }

    // ── Viewport dividers ─────────────────────────────────────────────────────
    if (activePlayers == 2) {
        drawDivider(dl, 0.f, hh, fw, hh);           // horizontal only
    } else if (activePlayers >= 3) {
        drawDivider(dl, hw,  0.f, hw,  fh);         // vertical
        drawDivider(dl, 0.f, hh,  fw,  hh);         // horizontal
    }

    // ── Developer Menu ────────────────────────────────────────────────────────
    // Anchored to the top-right corner of the window (inside P2 viewport).
    constexpr ImGuiWindowFlags DEV_FLAGS =
        ImGuiWindowFlags_NoMove             |
        ImGuiWindowFlags_NoResize           |
        ImGuiWindowFlags_AlwaysAutoResize   |
        ImGuiWindowFlags_NoCollapse         |
        ImGuiWindowFlags_NoSavedSettings;

    ImGui::SetNextWindowPos(
        {static_cast<float>(windowW) - 8.f, 8.f},
        ImGuiCond_Always,
        {1.f, 0.f}  // pivot: top-right
    );
    ImGui::SetNextWindowBgAlpha(0.88f);

    if (ImGui::Begin("##dev", nullptr, DEV_FLAGS)) {
        ImGui::TextColored({0.40f, 0.90f, 1.00f, 1.f}, "DEV CONSOLE");
        ImGui::Separator();

        ImGui::Text("FPS  %6.1f", fps);

        ImGui::Separator();
        ImGui::TextColored({0.30f, 0.78f, 1.00f, 0.85f}, "CLASS");
        ImGui::Text("%s  [1/2/3]", players[0].className);

        ImGui::Separator();
        ImGui::TextColored({0.30f, 0.78f, 1.00f, 0.85f}, "WEAPON HEAT");
        const float heatPct = players[0].heat * 100.f;
        if (players[0].isOverheated) {
            ImGui::TextColored({1.f, 0.15f, 0.15f, 1.f},
                               "OVERHEATED  %.1fs", players[0].lockoutTimer);
        } else if (players[0].heat >= 0.85f) {
            ImGui::TextColored({1.f, 0.45f, 0.05f, 1.f}, "%.0f%%  WARNING", heatPct);
        } else {
            ImGui::Text("%.0f%%", heatPct);
        }

        ImGui::Separator();
        ImGui::TextColored({0.30f, 0.78f, 1.00f, 0.85f}, "P1 STATE");
        ImGui::Text("%s", players[0].stateLabel);

        ImGui::Separator();
        ImGui::TextColored({0.30f, 0.78f, 1.00f, 0.85f}, "P1 POSITION");
        ImGui::Text("X  %+.2f", players[0].pos.x);
        ImGui::Text("Y  %+.2f", players[0].pos.y);
        ImGui::Text("Z  %+.2f", players[0].pos.z);

        ImGui::Separator();
        ImGui::TextColored({0.30f, 0.78f, 1.00f, 0.85f}, "SCORE");
        ImGui::Text("%d", players[0].score);

        ImGui::Separator();
        ImGui::TextColored({0.90f, 0.70f, 0.02f, 0.90f}, "DROIDS");
        ImGui::Text("%d alive", droidsAlive);
    }
    ImGui::End();
}
