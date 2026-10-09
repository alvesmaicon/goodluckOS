#pragma once
// The button tester (System Settings -> Input Settings): every button lights up while pressed, the
// sticks show their position, and holding B for a second goes back.
#include <SDL2/SDL.h>

#include "app.h"

class TesterScreen : public Screen {
public:
    explicit TesterScreen(App& app);

    void onAction(Action) override {}
    bool raw() const override { return true; }
    void render(Ui& ui) override;
    Header header() const override;
    Uint32 wakeAt() const override { return nextFrame; }   // the sticks and the hold of B move
    void tick(Uint32 now) override;

private:
    SDL_Joystick* joystick = nullptr;
    int lastButton = -1;
    Uint32 holdStart = 0;       // B held since then (0: not held)
    Uint32 nextFrame = 0;       // when the next frame is due

    bool pressed(int button) const;
    bool backHeld() const;
};
