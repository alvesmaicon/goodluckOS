#pragma once
// Screens that open over another one: the on-screen keyboard, a menu, and a full-screen message.
#include <functional>
#include <string>
#include <vector>

#include "app.h"
#include "keyboard.h"

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

// A menu with a title, an optional subtitle (e.g. the game it acts on) and its choices, in English
// (translated when drawn). onChoose gets the picked choice once the menu has closed.
class DialogScreen : public Screen {
public:
    DialogScreen(App& app, std::string title, std::string subtitle, std::vector<std::string> choices, int bodyY,
                 std::function<void(int)> onChoose);

    void onAction(Action a) override;
    void render(Ui& ui) override;
    Hints hints() const override;
    bool overlay() const override { return true; }

private:
    std::string title, subtitle;
    std::vector<std::string> choices;
    int bodyY;          // where the screen below starts, under its tab strip: the panel is centred there
    std::function<void(int)> onChoose;
    int sel = 0;
};

// A message over the whole screen while something happens that takes Puppy down (restarting,
// shutting down). It takes no input.
class StatusScreen : public Screen {
public:
    StatusScreen(App& app, std::string text) : Screen(app), text(std::move(text)) {}

    void onAction(Action) override {}
    void render(Ui& ui) override { ui.status(text); }
    bool overlay() const override { return true; }

private:
    std::string text;
};
