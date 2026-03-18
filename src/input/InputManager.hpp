#pragma once

#include "PlayerInput.hpp"
#include <array>

// InputManager owns one PlayerInput per player (indices 0-3).
// Call update() once per frame after SDL_PollEvent drains the queue.
// Game logic reads state via getInput(); it never touches SDL directly.
class InputManager {
public:
    static constexpr int MAX_PLAYERS = 4;

    InputManager();

    // Snapshot the current input state for all players.
    void update();

    const PlayerInput& getInput(int playerIndex) const;

private:
    std::array<PlayerInput, MAX_PLAYERS> m_inputs{};

    void pollKeyboard();

    // Rising-edge state — previous-frame key states for edge detection.
    bool m_prevFire        = false;  // left mouse button
    bool m_prevMenuPrev    = false;  // W key
    bool m_prevMenuNext    = false;  // S key
    bool m_prevMenuConfirm = false;  // Space key
};
