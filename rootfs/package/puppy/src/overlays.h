#pragma once
// Screens that open over another one: the on-screen keyboard, a menu, and a full-screen message.
#include <functional>
#include <string>
#include <vector>

#include "app.h"
#include "keyboard.h"
#include "layout.h"

// Types into text with the d-pad. For a search the cursor stays at the end and L1/R1 are left to the
// screen below; for a rename L1/R1 move the cursor.
class KeyboardScreen : public Screen {
public:
    struct Hooks {
        std::function<void()> changed;                          // after each edit
        std::function<void(bool accepted)> done;                // closed with OK / START, or cancelled
        std::function<void(KeyboardScreen&, Action)> forward;   // actions the keyboard doesn't use
    };
    KeyboardScreen(App& app, Keyboard& kb, std::string& text, bool rename, size_t maxLength, Hooks hooks);

    void close(bool accept);

    void onAction(Action a) override;
    bool typing() const override { return true; }
    void onText(const std::string& text) override { type(text); }
    void render(Ui& ui) override;
    Hints hints() const override;
    bool overlay() const override { return true; }

private:
    Keyboard& kb;
    std::string& text;
    bool rename;
    size_t cursor;      // byte position in text, moved with L1/R1 when renaming
    size_t maxLength;
    Hooks hooks;

    void type(const std::string& key);
};

// A menu over the screen below. Texts are English and translated when drawn, except the subtitle
// (e.g. the game the menu acts on) and raw choices (time zones, language names).
struct Dialog {
    std::string title;
    std::string subtitle;
    std::string message;                // wrapped under the title, e.g. what a confirmation does
    std::vector<std::string> choices;
    std::vector<SDL_Color> swatches;    // a colour block before each choice
    bool raw = false;
    int selected = 0;
    int bodyY = kHeaderH;               // where the screen below starts (under its tab strip): the panel is centred there
};

// onChoose gets the picked choice once the menu has closed. A list too long for the screen scrolls.
class DialogScreen : public Screen {
public:
    DialogScreen(App& app, Dialog dialog, std::function<void(int)> onChoose);

    void onAction(Action a) override;
    void render(Ui& ui) override;
    Hints hints() const override;
    bool overlay() const override { return true; }

private:
    Dialog d;
    std::function<void(int)> onChoose;
    int sel = 0;
    int scroll = 0;     // first choice shown
};

// A message over the whole screen while something happens that takes Puppy down (restarting,
// shutting down). It takes no input. then runs once the message is on screen.
class StatusScreen : public Screen {
public:
    StatusScreen(App& app, std::string text, std::function<void()> then = nullptr)
        : Screen(app), text(std::move(text)), then(std::move(then)) {}

    void onAction(Action) override {}
    void render(Ui& ui) override {
        ui.status(text);
        shown = true;
    }
    bool overlay() const override { return true; }
    Uint32 wakeAt() const override { return then ? SDL_GetTicks() + 20 : 0; }
    void tick(Uint32) override {
        if (!shown || !then) return;
        const auto run = std::move(then);
        then = nullptr;
        run();
    }

private:
    std::string text;
    std::function<void()> then;
    bool shown = false;
};
