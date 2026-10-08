#include "input.h"

#include <algorithm>
#include <cstdlib>

#include "layout.h"

bool isRepeatable(Action a) {
    return a == Action::Up || a == Action::Down || a == Action::Left || a == Action::Right ||
           a == Action::ScrollUp || a == Action::ScrollDown;
}

bool isScroll(Action a) { return a == Action::ScrollUp || a == Action::ScrollDown; }

// Left stick as a d-pad: the dominant axis past kStickOn picks the direction, which holds until the
// stick comes back under kStickOff.
Action stickDirection(int x, int y, Action current) {
    auto magnitude = [&](Action a) {
        switch (a) {
            case Action::Left:  return -x;
            case Action::Right: return x;
            case Action::Up:    return -y;
            case Action::Down:  return y;
            default:            return 0;
        }
    };
    if (current != Action::None && magnitude(current) > kStickOff) return current;
    if (std::max(std::abs(x), std::abs(y)) < kStickOn) return Action::None;
    if (std::abs(x) > std::abs(y)) return x < 0 ? Action::Left : Action::Right;
    return y < 0 ? Action::Up : Action::Down;
}

// Keyboard bindings, mostly for running the launcher on a PC: F1/F2 = L1/R1, Space = Y, F3 = Select,
// F4 = X, F5 = Start,
// F6 = POWER (the real power key arrives as SDLK_POWER), PageUp/PageDown = right stick.
Action actionFromKey(SDL_Keycode k) {
    switch (k) {
        case SDLK_UP:        return Action::Up;
        case SDLK_DOWN:      return Action::Down;
        case SDLK_LEFT:      return Action::Left;
        case SDLK_RIGHT:     return Action::Right;
        case SDLK_RETURN:    return Action::Launch;
        case SDLK_ESCAPE:
        case SDLK_BACKSPACE: return Action::Back;
        case SDLK_SPACE:     return Action::ToggleFavorite;
        case SDLK_F3:        return Action::ToggleAutoStart;
        case SDLK_F1:        return Action::PrevTab;
        case SDLK_F2:        return Action::NextTab;
        case SDLK_F4:        return Action::Search;
        case SDLK_F5:        return Action::Start;
        case SDLK_POWER:
        case SDLK_F6:        return Action::Power;
        case SDLK_F7:        return Action::GameMenu;   // L2 + R2
        case SDLK_PAGEUP:    return Action::ScrollUp;
        case SDLK_PAGEDOWN:  return Action::ScrollDown;
        default:             return Action::None;
    }
}

Action actionFromButton(Uint8 b) {
    switch (b) {
        case SDL_CONTROLLER_BUTTON_DPAD_UP:       return Action::Up;
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:     return Action::Down;
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:     return Action::Left;
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:    return Action::Right;
        case SDL_CONTROLLER_BUTTON_A:             return Action::Launch;
        case SDL_CONTROLLER_BUTTON_B:             return Action::Back;
        case SDL_CONTROLLER_BUTTON_X:             return Action::Search;
        case SDL_CONTROLLER_BUTTON_Y:             return Action::ToggleFavorite;
        case SDL_CONTROLLER_BUTTON_START:         return Action::Start;
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:  return Action::PrevTab;
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: return Action::NextTab;
        default:                                  return Action::None;
    }
}
