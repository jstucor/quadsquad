#include "InputManager.hpp"

#include <SDL2/SDL.h>
#include <cassert>

InputManager::InputManager()
{
    // m_inputs is zero-initialised by the aggregate default member initialisers
    // in PlayerInput, so players 1-3 are already inert.
}

void InputManager::update()
{
    // Reset all inputs each frame so released keys/buttons clear automatically.
    m_inputs.fill(PlayerInput{});

    pollKeyboard();
    // TODO: pollControllers() — iterate SDL_GameController handles for players 1-3
}

const PlayerInput& InputManager::getInput(int playerIndex) const
{
    assert(playerIndex >= 0 && playerIndex < MAX_PLAYERS);
    return m_inputs[static_cast<std::size_t>(playerIndex)];
}

// ── Private ───────────────────────────────────────────────────────────────────

void InputManager::pollKeyboard()
{
    // SDL_GetKeyboardState returns a pointer to a static array — no allocation.
    const Uint8* keys = SDL_GetKeyboardState(nullptr);

    PlayerInput& p0 = m_inputs[0];

    // Movement: WASD → normalised -1 / +1 axis values
    if (keys[SDL_SCANCODE_D]) p0.moveX += 1.f;
    if (keys[SDL_SCANCODE_A]) p0.moveX -= 1.f;
    if (keys[SDL_SCANCODE_W]) p0.moveY += 1.f;
    if (keys[SDL_SCANCODE_S]) p0.moveY -= 1.f;

    // Actions
    p0.isJumping  = keys[SDL_SCANCODE_SPACE]  != 0;
    p0.isCrouching = keys[SDL_SCANCODE_LCTRL] != 0;
    // Sprint is suppressed while crouching so the states are mutually exclusive.
    p0.isSprinting = keys[SDL_SCANCODE_LSHIFT] != 0 && !p0.isCrouching;

    // Mouse look — must be called after SDL_PollEvent drains the queue so that
    // relative deltas are correctly accumulated for this frame only.
    int mx = 0, my = 0;
    const Uint32 buttons = SDL_GetRelativeMouseState(&mx, &my);
    p0.lookX = static_cast<float>(mx);
    p0.lookY = static_cast<float>(my);

    // Fire: rising-edge on left mouse button (true for exactly one frame on click).
    const bool fireNow = (buttons & SDL_BUTTON(SDL_BUTTON_LEFT)) != 0;
    p0.isFiring = fireNow && !m_prevFire;
    m_prevFire  = fireNow;

    // Zoom: held right mouse button (continuous, no edge detection needed).
    p0.isZooming = (buttons & SDL_BUTTON(SDL_BUTTON_RIGHT)) != 0;

    // ── Menu / respawn navigation (rising-edge) ───────────────────────────────
    // W and S are also bound to moveY above; the game picks which field to read
    // based on whether the player is currently dead (class-selection mode).
    const bool menuPrevNow    = keys[SDL_SCANCODE_W]     != 0;
    const bool menuNextNow    = keys[SDL_SCANCODE_S]     != 0;
    const bool menuConfirmNow = keys[SDL_SCANCODE_SPACE] != 0;

    p0.menuPrev    = menuPrevNow    && !m_prevMenuPrev;
    p0.menuNext    = menuNextNow    && !m_prevMenuNext;
    p0.menuConfirm = menuConfirmNow && !m_prevMenuConfirm;

    m_prevMenuPrev    = menuPrevNow;
    m_prevMenuNext    = menuNextNow;
    m_prevMenuConfirm = menuConfirmNow;
}
