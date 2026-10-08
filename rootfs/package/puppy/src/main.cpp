#include <SDL2/SDL.h>

#include <algorithm>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <string>

#include <signal.h>
#include <unistd.h>

#include "catalog.h"
#include "config.h"
#include "device.h"
#include "fonts.h"
#include "input.h"
#include "keyboard.h"
#include "layout.h"
#include "library.h"
#include "model.h"
#include "ui.h"
#include "util.h"

int main(int argc, char** argv) {
    unsetenv("GALLIUM_HUD_STATUS");     // the top bar already shows it
    if (!loadConfig(argc, argv)) return 2;
    if (runAutoStart())
        for (;;) pause();           // appd stops the launcher once the app starts
    i18n::langDirPath() = cfg.langDir;
    i18n::settingsPath() = cfg.settingsFile();
    if (!cfg.language.empty()) i18n::load(cfg.language);
    else i18n::loadConfigured();
    // the font chosen in System Settings, from the folder of puppy.conf's font ("default": that one)
    fonts::dirPath() = fs::path(cfg.font).parent_path().string();
    if (fonts::find(fonts::configuredKey()).file) {
        const fonts::Font& f = fonts::find(fonts::configuredKey());
        if (fonts::available(f)) {
            cfg.font = fonts::path(f);
            cfg.fontScale = f.scale;
        }
    }

    Model model;
    model.categories = loadCatalog();
    if (model.categories.empty()) {
        std::cerr << "Nothing to show: no entries in the apps files and no games in the es_systems.cfg systems\n";
        return 1;
    }
    for (auto& c : model.categories)
        for (auto& e : c.entries) e.searchKey = lower(e.id == e.name ? e.name : e.name + " " + e.id);
    extractSystemMenu(model);
    applySettingsCommand(model);
    addAllGamesTab(model);   // first tab, and the one shown at boot
    loadFavorites(model);
    addMyListTab(model);
    addExternalTab(model);
    if (model.categories.empty()) {
        std::cerr << "Nothing to show\n";
        return 1;
    }

    loadSettings(model);
    writeTabsList(model);
    model.applyFilter();
    restoreCursor(model);
    if (model.cur().hidden) model.tab = 0;   // All Games
    {
        std::string cat, name;
        if (readAutoStartId(cat, name)) { model.autoCategory = cat; model.autoName = name; }
    }

    Ui ui;
    if (!ui.ok()) return 1;

    SDL_GameController* pad = nullptr;
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) { pad = SDL_GameControllerOpen(i); break; }
    }

    Keyboard kb;
    Osd osd;
    Audio audio;
    audio.read();
    bool fnHeld = false;        // FN + UP/DOWN are triggerhappy hotkeys, not navigation
    bool selectHeld = false, selectCombo = false;
    Action leftStick = Action::None, rightStick = Action::None;
    bool triggerL = false, triggerR = false;    // L2 / R2 held (they're axes); both: game options
    Uint32 osdUntil = 0, osdNextRead = 0;
    bool running = true;
    bool dirty = true;
    int shownBattery = -2;
    const std::string clock = clockFormat();
    Uint32 lastActivity = SDL_GetTicks();

    // d-pad auto-repeat
    Action held = Action::None;
    Uint32 nextRepeat = 0;

    auto showNotice = [&](const std::string& text) {
        model.notice = text;
        model.noticeUntil = SDL_GetTicks() + kNoticeMs;
    };

    // Closes the keyboard; when renaming, accept renames the game's file
    auto closeKeyboard = [&](bool accept) {
        kb.open = false;
        if (!model.renaming) return;
        model.renaming = false;
        const std::string name = trim(model.renameText);
        if (accept && !name.empty() && name != model.menuEntry.name) showNotice(renameEntry(model, model.menuEntry, name));
    };

    // UTF-8 aware: the start of the letter before / after byte position pos
    auto prevLetter = [](const std::string& t, size_t pos) {
        while (pos > 0 && ((unsigned char)t[--pos] & 0xC0) == 0x80) {}
        return pos;
    };
    auto nextLetter = [](const std::string& t, size_t pos) {
        if (pos < t.size()) ++pos;
        while (pos < t.size() && ((unsigned char)t[pos] & 0xC0) == 0x80) ++pos;
        return pos;
    };

    // Types at the cursor (the search's is always at its end)
    auto typeKey = [&](const std::string& key) {
        std::string& text = model.renaming ? model.renameText : model.query;
        size_t cursorAtEnd = text.size();
        size_t& cursor = model.renaming ? model.renameCursor : cursorAtEnd;
        cursor = std::min(cursor, text.size());
        const size_t maxLen = model.renaming ? kMaxNameLength : kMaxQueryLength;
        if (key == "ok") { closeKeyboard(true); return; }
        if (key == "shift") { kb.caps = !kb.caps; return; }
        if (key == "del") {
            const size_t start = prevLetter(text, cursor);
            text.erase(start, cursor - start);
            cursor = start;
        } else if (text.size() < maxLen) {
            std::string c = key == "space" ? " " : key;
            if (kb.caps && c.size() == 1) c = upper(c);
            text.insert(cursor, c);
            cursor += c.size();
        }
        if (!model.renaming) model.applyFilter();
    };

    auto apply = [&](Action a) {
        const bool grid = model.view == View::Grid;

        if (!model.status.empty()) return;   // restarting / shutting down

        if (model.menuOpen) {
            const int n = model.menuCount();
            switch (a) {
                case Action::Up:     model.menuSel = (model.menuSel + n - 1) % n; break;
                case Action::Down:   model.menuSel = (model.menuSel + 1) % n;     break;
                case Action::Launch: {
                    if (model.menuKind == Model::Menu::Game) {
                        model.menuOpen = false;
                        if (model.menuSel == 0) {   // Rename: the keyboard, with the name as shown
                            model.renaming = true;
                            model.renameText = model.menuEntry.name;
                            model.renameCursor = model.renameText.size();
                            kb.open = true;
                            kb.caps = false;
                        } else {                    // Move to trash: ask first
                            model.menuKind = Model::Menu::ConfirmDelete;
                            model.menuLabels = {"Cancel", "Move to trash"};
                            model.menuSel = 0;
                            model.menuOpen = true;
                        }
                        break;
                    }
                    if (model.menuKind == Model::Menu::ConfirmDelete) {
                        model.menuOpen = false;
                        if (model.menuSel == 1) showNotice(deleteEntry(model, model.menuEntry));
                        break;
                    }
                    const PowerItem item = model.menuItems[model.menuSel];
                    model.menuOpen = false;
                    if (item.quit) {
                        running = false;
                        break;
                    }
                    if (item.command && !item.command->empty()) {
                        if (item.status) model.status = tr(item.status);
                        runDetached(*item.command);
                        break;
                    }
                    if (item.confirmEntry) {
                        auto confirm = std::find_if(model.systemEntries.begin(), model.systemEntries.end(),
                                                    [&](const Entry& e) { return e.name == item.confirmEntry; });
                        if (confirm != model.systemEntries.end()) {
                            if (!launch(model, *confirm)) running = false;
                            break;
                        }
                    }
                    if (item.status) model.status = tr(item.status);
                    if (item.request) sendPowerRequest(item.request);
                    break;
                }
                case Action::Back:
                case Action::Power:  model.menuOpen = false; break;
                default: break;
            }
            return;
        }
        auto openMenu = [&]() {
            model.menuItems = powerItems(model);
            if (model.menuItems.empty()) return;
            model.menuKind = Model::Menu::Power;
            closeKeyboard(false);
            model.menuOpen = true;
            model.menuSel = 0;
        };
        if (a == Action::GameMenu) {   // L2 + R2: rename or delete the selected game
            const Entry* e = model.selected();
            if (e && !e->file.empty() && !kb.open) {
                model.menuEntry = *e;
                model.menuKind = Model::Menu::Game;
                model.menuLabels = {"Rename", "Move to trash"};
                model.menuSel = 0;
                model.menuOpen = true;
            }
            return;
        }
        if (a == Action::Power) {
            // with the screen off, toggle-screen.sh turns it back on; don't open a menu in the dark
            if (screenOn()) openMenu();
            return;
        }
        if (a == Action::Start && !kb.open) {
            if (model.hasSettings) {
                if (!launch(model, model.settings)) running = false;
                return;
            }
            // no settings app (e.g. on other firmwares, where POWER may suspend): START opens the menu
            openMenu();
            if (model.menuOpen) return;
        }

        if (!model.renaming) {
            switch (a) {
                case Action::PrevTab:    model.switchTab(-1); return;
                case Action::NextTab:    model.switchTab(1);  return;
                default: break;
            }
        }

        if (kb.open) {
            switch (a) {
                case Action::Up:     kb.move(0, -1); break;
                case Action::Down:   kb.move(0, 1);  break;
                case Action::Left:   kb.move(-1, 0); break;
                case Action::Right:  kb.move(1, 0);  break;
                case Action::Launch: typeKey(kb.current()); break;
                case Action::PrevTab:   // L1/R1 move the cursor in the name
                    if (model.renaming) model.renameCursor = prevLetter(model.renameText, std::min(model.renameCursor, model.renameText.size()));
                    break;
                case Action::NextTab:
                    if (model.renaming) model.renameCursor = nextLetter(model.renameText, model.renameCursor);
                    break;
                case Action::Back:
                    if ((model.renaming ? model.renameText : model.query).empty()) closeKeyboard(false);
                    else typeKey("del");
                    break;
                case Action::Start:
                case Action::Search: closeKeyboard(true); break;
                case Action::ToggleAutoStart: closeKeyboard(false); break;   // SELECT: cancel
                default: break;
            }
            return;
        }

        switch (a) {
            case Action::Up:    model.moveSel(grid ? -kGridCols : -1); break;
            case Action::Down:  model.moveSel(grid ? kGridCols : 1);   break;
            case Action::Left:  model.moveSel(grid ? -1 : -listRows(model.showTabs)); break;
            case Action::Right: model.moveSel(grid ? 1 : listRows(model.showTabs));   break;
            case Action::Search: kb.open = true; break;
            case Action::Back:
                if (!model.query.empty()) { model.query.clear(); model.applyFilter(); }
                break;
            case Action::ToggleAutoStart: toggleAutoStart(model); break;
            case Action::ToggleFavorite:  toggleFavorite(model);  break;
            case Action::ScrollUp:   model.descScroll = std::max(0, model.descScroll - 1); break;
            case Action::ScrollDown: model.descScroll = std::min(ui.descMaxScroll(), model.descScroll + 1); break;
            case Action::Launch:
                if (const Entry* e = model.selected()) {
                    if (!launch(model, *e)) running = false;
                }
                break;
            default: break;
        }
    };

    while (running) {
        if (dirty) {
            shownBattery = readBattery();
            model.clock = clockText(clock);
            ui.render(model, kb, osd, shownBattery, audio);
            dirty = false;
        }

        Uint32 now = SDL_GetTicks();
        Uint32 elapsed = now - lastActivity;
        int timeout = elapsed >= kIdleCheckMs ? 0 : (int)(kIdleCheckMs - elapsed);
        if (held != Action::None) timeout = std::min(timeout, (int)std::max<Sint32>(0, (Sint32)(nextRepeat - now)));
        if (osd.visible) {
            if ((Sint32)(now - osdUntil) >= 0) {
                osd.visible = false;
                dirty = true;
                timeout = 0;
            } else {
                if ((Sint32)(now - osdNextRead) >= 0) {
                    osd.read();
                    audio.read();
                    osdNextRead = now + kOsdRefreshMs;
                    dirty = true;
                }
                timeout = std::min(timeout, (int)kOsdRefreshMs);
            }
        }
        if (!clock.empty())   // wake up when the minute changes
            timeout = std::min(timeout, (int)(60 - time(nullptr) % 60) * 1000);
        if (!model.notice.empty()) {
            if ((Sint32)(now - model.noticeUntil) >= 0) {
                model.notice.clear();
                dirty = true;
                timeout = 0;
            } else {
                timeout = std::min(timeout, (int)(model.noticeUntil - now));
            }
        }
        if (ui.animating()) {   // keep drawing until the tab strip has slid into place (paced by vsync)
            dirty = true;
            timeout = 0;
        }
        if (Uint32 due = ui.marqueeDue()) {   // a long selected name is scrolling
            if ((Sint32)(now - due) >= 0) {
                dirty = true;
                timeout = 0;
            } else {
                timeout = std::min(timeout, (int)(due - now));
            }
        }

        SDL_Event ev;
        if (!SDL_WaitEventTimeout(&ev, timeout)) {
            now = SDL_GetTicks();
            if (held != Action::None && (Sint32)(now - nextRepeat) >= 0) {
                apply(held);
                nextRepeat = now + (isScroll(held) ? kScrollRateMs : kRepeatRateMs);
                dirty = true;
                lastActivity = now;
            } else if (now - lastActivity >= kIdleCheckMs) {
                lastActivity = now;
                if (readBattery() != shownBattery) dirty = true;
                Audio a;
                a.read();
                if (a != audio) { audio = a; dirty = true; }
            }
            if (clockText(clock) != model.clock) dirty = true;
            continue;
        }

        do {
            Action action = Action::None;
            switch (ev.type) {
                case SDL_QUIT:
                    running = false;
                    break;
                case SDL_WINDOWEVENT:
                    if (ev.window.event == SDL_WINDOWEVENT_EXPOSED) dirty = true;
                    break;
                case SDL_KEYDOWN: {
                    SDL_Keycode k = ev.key.keysym.sym;
                    // volume keys (and FN + volume for brightness) are handled by triggerhappy scripts;
                    // just show the resulting level
                    if (k == SDLK_VOLUMEUP || k == SDLK_VOLUMEDOWN) {
                        osd.visible = true;
                        osdUntil = SDL_GetTicks() + kOsdShowMs;
                        osdNextRead = SDL_GetTicks() + 30;   // give the script a moment to write it
                        break;
                    }
                    if (kb.open && ((k >= SDLK_a && k <= SDLK_z) || (k >= SDLK_0 && k <= SDLK_9))) {
                        typeKey(std::string(1, (char)k));
                        dirty = true;
                    } else if (!ev.key.repeat) {
                        action = actionFromKey(k);
                    }
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
                        if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_DOWN) {
                            osd.visible = true;
                            osdUntil = SDL_GetTicks() + kOsdShowMs;
                            osdNextRead = SDL_GetTicks() + 30;
                        }
                        break;
                    }
                    action = actionFromButton(ev.cbutton.button);
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
                            action = dir;
                        }
                    } else if (axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT || axis == SDL_CONTROLLER_AXIS_TRIGGERRIGHT) {
                        bool& on = axis == SDL_CONTROLLER_AXIS_TRIGGERLEFT ? triggerL : triggerR;
                        const bool wasBoth = triggerL && triggerR;
                        if (ev.caxis.value > kStickOn) on = true;
                        else if (ev.caxis.value < kStickOff) on = false;
                        if (!wasBoth && triggerL && triggerR) action = Action::GameMenu;
                    } else if (axis == SDL_CONTROLLER_AXIS_RIGHTY) {
                        const int v = ev.caxis.value;
                        Action dir = v < -kStickOn ? Action::ScrollUp : v > kStickOn ? Action::ScrollDown
                                   : std::abs(v) < kStickOff ? Action::None : rightStick;
                        if (dir != rightStick) {
                            if (held == rightStick) held = Action::None;
                            rightStick = dir;
                            action = dir;
                        }
                    }
                    break;
                }
                case SDL_CONTROLLERBUTTONUP:
                    if (ev.cbutton.button == SDL_CONTROLLER_BUTTON_BACK) {
                        if (selectHeld && !selectCombo) action = Action::ToggleAutoStart;
                        selectHeld = false;
                        break;
                    }
                    if (actionFromButton(ev.cbutton.button) == held) held = Action::None;
                    break;
            }

            if (action != Action::None) {
                apply(action);
                if (isRepeatable(action)) {
                    held = action;
                    nextRepeat = SDL_GetTicks() + (isScroll(action) ? kScrollDelayMs : kRepeatDelayMs);
                }
                dirty = true;
                lastActivity = SDL_GetTicks();
            }
        } while (running && SDL_PollEvent(&ev));
    }

    if (pad) SDL_GameControllerClose(pad);
    return 0;
}
