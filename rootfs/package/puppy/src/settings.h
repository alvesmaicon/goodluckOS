#pragma once
// System Settings, in the launcher: the sections on the left and the page of the selected one on the
// right. A page is a list of rows, rebuilt from the settings on every frame; a change applies and is
// saved right away. settings.cpp has the screen and the rows, settings_pages.cpp the pages.
#include <ctime>
#include <functional>
#include <string>
#include <vector>

#include "app.h"
#include "model.h"
#include "system/audio.h"
#include "system/hud.h"
#include "system/prefs.h"
#include "system/storage.h"
#include "system/sysinfo.h"

struct Row {
    enum class Kind { Section, Info, Link, Toggle, Choice, Level, Number, Action };
    Kind kind = Kind::Info;
    std::string label;          // English, translated when drawn, unless rawLabel
    bool rawLabel = false;
    std::string value;          // shown as it is: an Info's value, a Number's, a Link's or an Action's status
    std::string hint;           // English: under the page while the row is selected
    bool enabled = true;
    bool on = false;                            // Toggle
    std::vector<std::string> choices;           // Choice: English, or shown as they are with rawChoices
    bool rawChoices = false;
    std::vector<SDL_Color> swatches;            // Choice: a colour block for each, shown instead of its text
    int index = 0;                              // Choice: the current one
    int current = 0, min = 0, max = 0, step = 1;    // Level (shown as a percentage of max), Number (wraps around)
    std::function<void(int)> set;               // Toggle (0 or 1), Choice (index), Level and Number (value)
    std::function<void()> run;                  // Link, Action

    bool focusable() const { return kind != Kind::Section && kind != Kind::Info; }
    int height() const;

    static Row section(const std::string& label);
    static Row info(const std::string& label, const std::string& value);
    static Row link(const std::string& label, std::function<void()> open, const std::string& value = "");
    static Row toggle(const std::string& label, bool on, std::function<void(int)> set);
    static Row choice(const std::string& label, std::vector<std::string> choices, int index, std::function<void(int)> set);
    static Row level(const std::string& label, int value, int min, int max, int step, std::function<void(int)> set);
    static Row number(const std::string& label, const std::string& shown, int value, int min, int max,
                      std::function<void(int)> set);
    static Row action(const std::string& label, std::function<void()> run, const std::string& value = "");
};

class SettingsScreen : public Screen {
public:
    struct Hooks {
        std::function<void()> powerMenu;            // POWER, as in the launcher
        std::function<void()> fontChanged;          // what the launcher measured with the old font
        std::function<void(bool)> closed;           // back to the launcher; true: the language changed
    };
    SettingsScreen(App& app, Model& launcher, Hooks hooks);

    void onAction(Action a) override;
    void render(Ui& ui) override;
    Header header() const override;
    Hints hints() const override;
    Uint32 wakeAt() const override;
    void tick(Uint32 now) override;
    void levelsChanged() override;

private:
    enum class Page { Display, Launcher, Interface, Overlay, DateTime, Storage, System, Input,
                      Tabs, Shortcuts, Info, Resize };
    struct Cursor {
        int sel = -1;       // the selected row, -1 for none (a page with nothing to change scrolls)
        int scroll = 0;     // the first row on screen
    };

    Model& launcher;
    Hooks hooks;
    int section = 0;                // in sections()
    bool inPage = false;            // the d-pad is on the page, not on the sections
    std::vector<Page> subpages;     // opened from the section's page, e.g. Launcher tabs
    std::vector<Cursor> cursors;    // the section page's, then each subpage's

    // What the pages show
    int brightnessLevel = 5;
    Audio audio;
    Prefs prefs;
    HudSettings hud;
    int profile = 1, zone = 0;
    struct tm clockEdit = {};       // the date and time being set, from the clock when the page opens
    bool clockSet = false, defaultsRestored = false;
    Usage home, card;
    TrashStats trash;
    Resize resize;
    SystemInfo info;
    std::string startLanguage;
    Uint32 saveAt = 0;              // the brightness or volume changed: saved then (0: nothing to save)
    Uint32 watchUntil = 0, nextWatch = 0;   // a card is being detected or ejected: re-read it until then
    Uint32 clockDrawn = 0;          // the Date & Time page ticks every second
    Row::Kind shownKind = Row::Kind::Info;  // of the row selected in the last frame, for the hints

    static const std::vector<std::pair<Page, const char*>>& sections();
    Page page() const;
    Cursor& cursor();
    std::string title(Page p) const;
    std::string pageHint(Page p) const;
    std::vector<Row> rows(Page p);

    void reload();
    void enterPage();               // the d-pad goes to the page shown
    void open(Page p);              // a subpage
    void back();
    void close();
    void switchSection(int delta);
    void move(int delta);
    void change(const Row& row, int dir);
    void choose(const Row& row);
    void levelChanged();
    void applyFont();
    void restoreDefaults();
    void resizeHome();

    void renderSections(Ui& ui);
    void renderPage(Ui& ui);

    // the pages (settings_pages.cpp)
    std::vector<Row> displayPage();
    std::vector<Row> launcherPage();
    std::vector<Row> tabsPage();
    std::vector<Row> interfacePage();
    std::vector<Row> overlayPage();
    std::vector<Row> dateTimePage();
    std::vector<Row> storagePage();
    std::vector<Row> systemPage();
    std::vector<Row> infoPage();
    std::vector<Row> inputPage();
    std::vector<Row> shortcutsPage();
    std::vector<Row> resizePage();
};
