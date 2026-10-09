#include "tester.h"

#include <algorithm>
#include <cstdio>

#include "layout.h"
#include "util.h"

// Raw joystick button numbers of the GA36-MB gamepad, the same numbering used by SDL_GAMECONTROLLERCONFIG
// (/etc/profile.d/sdl_controller.sh) and RetroArch's autoconfig. FN is not mapped as a game controller
// button, so the tester reads the raw joystick.
static const char* kButtons[] = {"B", "A", "X", "Y", "L1", "R1", "L2", "R2", "SELECT", "START",
                                 "FN", "L3", "R3", "UP", "DOWN", "LEFT", "RIGHT"};
constexpr int kButtonCount = sizeof(kButtons) / sizeof(kButtons[0]);
constexpr int kButtonB = 0;
constexpr Uint32 kExitHoldMs = 1000;
constexpr Uint32 kFrameMs = 33;

TesterScreen::TesterScreen(App& app) : Screen(app) {
    if (app.gamepad()) joystick = SDL_GameControllerGetJoystick(app.gamepad());
}

bool TesterScreen::pressed(int button) const {
    return joystick && button < SDL_JoystickNumButtons(joystick) && SDL_JoystickGetButton(joystick, button);
}

bool TesterScreen::backHeld() const {
    return pressed(kButtonB) || SDL_GetKeyboardState(nullptr)[SDL_SCANCODE_ESCAPE];
}

void TesterScreen::tick(Uint32 now) {
    for (int b = 0; b < kButtonCount; ++b)
        if (pressed(b)) lastButton = b;
    if (!backHeld()) holdStart = 0;
    else if (!holdStart) holdStart = now;
    else if (now - holdStart >= kExitHoldMs) app.pop();
}

Header TesterScreen::header() const {
    return {tr("Button Tester"), "", false};
}

// A button shape that lights up while it's pressed
static void chip(Ui& ui, const char* label, bool on, const SDL_Rect& r) {
    const Fonts& fonts = ui.font();
    ui.fill(on ? accent() : kTile, r);
    drawText(ui.sdl(), fonts.small, label, r.x + (r.w - textWidth(fonts.small, label)) / 2,
             r.y + (r.h - TTF_FontHeight(fonts.small)) / 2, on ? kBlack : kWhite);
}

void TesterScreen::render(Ui& ui) {
    nextFrame = SDL_GetTicks() + kFrameMs;
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const int w = 100, h = 34, gap = 10;
    const int x0 = (kScreenW - 5 * w - 4 * gap) / 2;
    int y = kHeaderH + 14;
    static const int rows[][5] = {
        {6, 4, -1, 5, 7},           // L2 L1   R1 R2
        {13, 14, 15, 16, -1},       // d-pad
        {2, 3, 1, 0, -1},           // X Y A B
        {8, 10, 9, 11, 12},         // SELECT FN START L3 R3
    };
    for (const auto& row : rows) {
        for (int i = 0; i < 5; ++i)
            if (row[i] >= 0) chip(ui, kButtons[row[i]], pressed(row[i]), {x0 + i * (w + gap), y, w, h});
        y += h + gap;
    }
    // Volume keys come from a separate keyboard-type input device
    const Uint8* keys = SDL_GetKeyboardState(nullptr);
    chip(ui, "VOL-", keys[SDL_SCANCODE_VOLUMEDOWN], {x0, y, w, h});
    chip(ui, "VOL+", keys[SDL_SCANCODE_VOLUMEUP], {x0 + w + gap, y, w, h});
    y += h + 2 * gap;

    char text[96];
    const int lineH = TTF_FontLineSkip(fonts.desc);
    if (!joystick) {
        drawText(renderer, fonts.desc, tr("No gamepad found."), x0, y, kGrey);
    } else {
        if (SDL_JoystickNumAxes(joystick) >= 4) {
            snprintf(text, sizeof(text), tr("Sticks:  L %+4d %+4d   R %+4d %+4d"),
                     SDL_JoystickGetAxis(joystick, 0) * 100 / 32767, SDL_JoystickGetAxis(joystick, 1) * 100 / 32767,
                     SDL_JoystickGetAxis(joystick, 2) * 100 / 32767, SDL_JoystickGetAxis(joystick, 3) * 100 / 32767);
            drawText(renderer, fonts.desc, text, x0, y, kGrey);
        }
        y += lineH;
        if (lastButton >= 0) snprintf(text, sizeof(text), tr("Last pressed: %s (button %d)"), kButtons[lastButton], lastButton);
        else snprintf(text, sizeof(text), "%s", tr("Press any button"));
        drawText(renderer, fonts.desc, text, x0, y, kGrey);
    }

    // holding B fills the bar; full, it goes back
    const Uint32 held = holdStart ? std::min<Uint32>(SDL_GetTicks() - holdStart, kExitHoldMs) : 0;
    SDL_Rect bar{x0, kScreenH - kFooterH - 14 - h, 5 * w + 4 * gap, h};
    ui.fill(kTile, bar);
    const char* label = tr("Hold B to go back");
    const int labelX = bar.x + (bar.w - textWidth(fonts.small, label)) / 2;
    const int labelY = bar.y + (bar.h - TTF_FontHeight(fonts.small)) / 2;
    drawText(renderer, fonts.small, label, labelX, labelY, kWhite);
    if (held) {     // black where the bar is full
        SDL_Rect full{bar.x, bar.y, (int)(bar.w * held / kExitHoldMs), bar.h};
        ui.fill(accent(), full);
        SDL_RenderSetClipRect(renderer, &full);
        drawText(renderer, fonts.small, label, labelX, labelY, kBlack);
        SDL_RenderSetClipRect(renderer, nullptr);
    }
}
