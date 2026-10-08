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
    // the fonts System Settings offers sit next to puppy.conf's font
    fonts::dirPath() = fs::path(cfg.font).parent_path().string();

    Model model;
    if (!loadModel(model)) return 1;
    restoreCursor(model);
    if (model.cur().hidden) model.tab = 0;   // All Games

    std::string font;
    float fontScale;
    interfaceFont(fonts::configuredKey(), font, fontScale);
    Ui ui(font, fontScale);
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
