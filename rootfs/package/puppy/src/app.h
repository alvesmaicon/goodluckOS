#pragma once
// The screens Puppy shows and the loop that runs them. Screens sit on a stack: the launcher at the
// bottom, then whatever opens over it (a menu, the keyboard, a status message). Input goes to the
// top one.
#include <SDL2/SDL.h>

#include <memory>
#include <string>
#include <vector>

#include "device.h"
#include "input.h"
#include "ui.h"

class App;

class Screen {
public:
    explicit Screen(App& app) : app(app) {}
    virtual ~Screen() = default;

    virtual void onAction(Action a) = 0;
    virtual bool typing() const { return false; }               // takes letters typed on a keyboard
    virtual void onText(const std::string&) {}
    virtual void render(Ui& ui) = 0;
    virtual Header header() const { return {}; }
    virtual Hints hints() const { return {}; }
    virtual bool overlay() const { return false; }   // drawn over the screen below, which keeps the top bar
    virtual bool animating() const { return false; } // wants the next frame right away

protected:
    App& app;
};

class App {
public:
    App(Ui& ui, SDL_GameController* pad);

    void push(std::unique_ptr<Screen> screen);
    void pop();                                 // the top screen, destroyed once the event is handled
    void notice(const std::string& text);       // a short message over the footer
    void quit() { running = false; }
    int run();

private:
    Ui& ui;
    Input input;
    std::vector<std::unique_ptr<Screen>> stack, closed;
    bool running = true;
    bool dirty = true;
    Audio audio;
    int battery = -2;
    std::string clockFmt, clock;    // strftime format of the top bar's clock, and what it shows
    bool following = false;     // after a volume, brightness or output hotkey, which change the levels behind our back
    Uint32 followUntil = 0, followNextRead = 0;
    std::string noticeText;
    Uint32 noticeUntil = 0;
    Uint32 lastActivity = 0;

    void render();
    void follow();
};
