#include <SDL2/SDL.h>

#include <cstdlib>
#include <iostream>
#include <memory>
#include <string>

#include <unistd.h>

#include "app.h"
#include "catalog.h"
#include "config.h"
#include "fonts.h"
#include "launcher.h"
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

    int rc;
    {
        App app(ui, pad);
        app.push(std::make_unique<LauncherScreen>(app, std::move(model)));
        rc = app.run();
    }
    if (pad) SDL_GameControllerClose(pad);
    return rc;
}
