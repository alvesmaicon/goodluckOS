#pragma once
// The launcher: the tabs of games and apps in a grid or a list, the search, My List, autolaunch,
// the game options (L2 + R2) and the POWER menu.
#include <string>

#include "app.h"
#include "keyboard.h"
#include "model.h"

class KeyboardScreen;

class LauncherScreen : public Screen {
public:
    LauncherScreen(App& app, Model model);

    void onAction(Action a) override;
    void render(Ui& ui) override;
    Header header() const override;
    Hints hints() const override;
    bool animating() const override { return tabOffset != 0.0f; }

private:
    Model model;
    Keyboard kb;                // its cursor and case stay from one search to the next
    std::string renameText;     // the new name of a game, while it's typed
    int descMax = 0;            // lines the list preview's description can scroll, as last drawn
    int lastTab = -1;           // tab drawn in the previous frame, to animate the strip
    float tabOffset = 0.0f;     // remaining slide of the tab strip, in pixels

    void openSearch();
    void openRename(const Entry& e);
    void fromKeyboard(KeyboardScreen& k, Action a);
    void openGameMenu();
    void confirmTrash(const Entry& e);
    bool openPowerMenu(int bodyY);
    void runPowerItem(const PowerItem& item, int bodyY);
    void powerAction(const PowerItem& item);
    bool builtinSettings() const;
    void openSettings();
    void reloadGames();

    void renderEmpty(Ui& ui);
    void renderGrid(Ui& ui);
    void renderList(Ui& ui);
    void renderTabs(Ui& ui);
};
