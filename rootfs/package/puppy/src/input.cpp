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

Input::Result Input::translate(const SDL_Event& ev, bool typing) {
    Result r;
    switch (ev.type) {
        case SDL_KEYDOWN: {
            SDL_Keycode k = ev.key.keysym.sym;
            // volume keys (and FN + volume for brightness) are handled by triggerhappy scripts;
            // just show the resulting level
            if (k == SDLK_VOLUMEUP || k == SDLK_VOLUMEDOWN) {
                r.hotkey = true;
                break;
            }
            if (typing && ((k >= SDLK_a && k <= SDLK_z) || (k >= SDLK_0 && k <= SDLK_9))) r.text = std::string(1, (char)k);
            else if (!ev.key.repeat) r.action = actionFromKey(k);
            break;
        }
        case SDL_KEYUP:
            if (actionFromKey(ev.key.keysym.sym) == held) held = Action::None;
            break;
        case SDL_JOYBUTTONDOWN:
        case SDL_JOYBUTTONUP:
            if (ev.jbutton.button == kFnButton) fnHeld = ev.type == SDL_JOYBUTTONDOWN;
            break;
        case SDL_CONTROLLERBUTTONDOWN:
            // SELECT toggles autolaunch when released on its own: SELECT + START is the
            // close-app shortcut, which must neither set autolaunch nor open the settings
            if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK) {
                selectHeld = true;
                selectCombo = false;
                break;
            }
            if (selectHeld) {
                selectCombo = true;
                break;
            }
            if (fnHeld && (ev.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_UP ||
                           ev.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_DOWN)) {
                if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_DOWN) r.hotkey = true;
                break;
            }
            r.action = actionFromButton(ev.cbutton.button);
            break;
        case SDL_CONTROLLERAXISMOTION: {
            // Left stick navigates like the d-pad; right stick up/down scrolls the description
            const Uint8 axis = ev.caxis.axis;
            if (axis == SDL_CONTROLLER_AXIS_LEFTX || axis == SDL_CONTROLLER_AXIS_LEFTY) {
                Action dir = stickDirection(SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTX),
                                            SDL_GameControllerGetAxis(pad, SDL_CONTROLLER_AXIS_LEFTY), leftStick);
                if (dir != leftStick) {
                    if (held == leftStick) held = Action::None;
                    leftStick = dir;
                    r.action = dir;
                }
            } else if (axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT || axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT) {
                bool& on = axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT ? triggerL : triggerR;
                const bool wasBoth = triggerL && triggerR;
                if (ev.caxis.value > kStickOn) on = true;
                else if (ev.caxis.value < kStickOff) on = false;
                if (!wasBoth && triggerL && triggerR) r.action = Action::GameMenu;
            } else if (axis == SDL_CONTROLLER_AXIS_RIGHTY) {
                const int v = ev.caxis.value;
                Action dir = v < -kStickOn ? Action::ScrollUp : v > kStickOn ? Action::ScrollDown
                           : std::abs(v) < kStickOff ? Action::None : rightStick;
                if (dir != rightStick) {
                    if (held == rightStick) held = Action::None;
                    rightStick = dir;
                    r.action = dir;
                }
            }
            break;
        }
        case SDL_CONTROLLERBUTTONUP:
            if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK) {
                if (selectHeld && !selectCombo) r.action = Action::ToggleAutoStart;
                selectHeld = false;
                break;
            }
            if (actionFromButton(ev.cbutton.button) == held) held = Action::None;
            break;
    }
    return r;
}

void Input::started(Action a, Uint32 now) {
    if (!isRepeatable(a)) return;
    held = a;
    nextRepeat = now + (isScroll(a) ? kScrollDelayMs : kRepeatDelayMs);
}

Action Input::due(Uint32 now) {
    if (held == Action::None || (Sint32)(now - nextRepeat) < 0) return Action::None;
    nextRepeat = now + (isScroll(held) ? kScrollRateMs : kRepeatRateMs);
    return held;
}

int Input::repeatIn(Uint32 now) const {
    if (held == Action::None) return -1;
    return (int)std::max<Sint32>(0, (Sint32)(nextRepeat - now));
}
