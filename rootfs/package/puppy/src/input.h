#pragma once
#include <SDL2/SDL.h>

#include <string>

enum class Action { None, Up, Down, Left, Right, Launch, Back, ToggleAutoStart, ToggleFavorite, Search, PrevTab, NextTab, Start, Power,
                    ScrollUp, ScrollDown, GameMenu };

bool isRepeatable(Action a);
bool isScroll(Action a);
Action stickDirection(int x, int y, Action current);
Action actionFromKey(SDL_Keycode k);
Action actionFromButton(Uint8 b);

// Turns SDL events into actions: buttons and keys, the left stick as a d-pad and the right one for
// scrolling, L2 + R2 together, SELECT released on its own (SELECT + START is the close-app shortcut),
// and the repeat of a held direction. FN + UP/DOWN are left to the hotkey daemon.
class Input {
public:
    explicit Input(SDL_GameController* pad) : pad(pad) {}

    struct Result {
        Action action = Action::None;
        bool hotkey = false;    // the volume, brightness or audio output hotkey was pressed
        std::string text;       // a letter or digit typed on a keyboard, when typing
    };
    Result translate(const SDL_Event& ev, bool typing);
    void started(Action a, Uint32 now);   // a held direction repeats from now on
    Action due(Uint32 now);               // the held action, when its repeat is due
    int repeatIn(Uint32 now) const;       // ms until then, -1 with nothing held

private:
    SDL_GameController* pad;
    bool fnHeld = false;        // FN + UP/DOWN are triggerhappy hotkeys, not navigation
    bool selectHeld = false, selectCombo = false;
    Action leftStick = Action::None, rightStick = Action::None;
    bool triggerL = false, triggerR = false;    // L2 / R2 held (they're axes); both: game options
    Action held = Action::None;                 // d-pad auto-repeat
    Uint32 nextRepeat = 0;
};
