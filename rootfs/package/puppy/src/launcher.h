#pragma once
// The launcher: the tabs of games and apps in a grid or a list, the search, My List, autolaunch,
// the game options (L2 + R2) and the POWER menu.
#include <string>

#include "app.h"
#include "keyboard.h"
#include "model.h"
#include "trailer.h"

class KeyboardScreen;

class LauncherScreen : public Screen {
public:
    LauncherScreen(App& app, Model model);

    void onAction(Action a) override;
    void render(Ui& ui) override;
    Header header() const override;
    Hints hints() const override;
    bool animating() const override { return tabOffset != 0.0f; }
    Uint32 wakeAt() const override { return trailer.running() ? frameDue : trailerAt; }
    void tick(Uint32 now) override;

private:
    Model model;
    Keyboard kb;                // its cursor and case stay from one search to the next
    std::string renameText;     // the new name of a game, while it's typed
    int descMax = 0;            // lines the list preview's description can scroll, as last drawn
    std::string dateFmt;        // the day a game was last played, as Date & Time shows it
    int lastTab = -1;           // tab drawn in the previous frame, to animate the strip
    float tabOffset = 0.0f;     // remaining slide of the tab strip, in pixels
    Trailer trailer;            // the selected game's clip, in the Vitrine style
    Uint32 stillSince = 0;      // the last button press (or the launcher back on top)
    Uint32 trailerAt = 0;       // when the selected game's trailer starts (0: none to start)
    Uint32 frameDue = 0;        // when the playing trailer's frames are read next
    std::string played;         // the clip that played to its end, not started again until a button

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
    std::string playedText(const Entry& e, bool withDay) const;
    SDL_Rect trailerBox() const;

    void renderEmpty(Ui& ui);
    void renderGrid(Ui& ui);
    void renderList(Ui& ui);
    void renderRows(Ui& ui, int width);
    void renderShelf(Ui& ui);
    void renderStreaming(Ui& ui);
    void renderRow(Ui& ui, int tab, int y, bool current);
    void renderTabs(Ui& ui);
};
