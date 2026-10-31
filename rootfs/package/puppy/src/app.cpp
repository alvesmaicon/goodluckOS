#include "app.h"

#include <algorithm>
#include <climits>
#include <ctime>

#include "layout.h"
#include "system/clock.h"
#include "system/jack.h"
#include "system/osd.h"

App::App(Ui& ui, SDL_GameController* pad) : ui(ui), pad(pad), input(pad) {
    osdEvent = SDL_RegisterEvents(1);
    watchOsd(osdEvent);
}

void App::push(std::unique_ptr<Screen> screen) {
    stack.push_back(std::move(screen));
    dirty = true;
}

void App::pop() {
    if (stack.empty()) return;
    closed.push_back(std::move(stack.back()));
    stack.pop_back();
    dirty = true;
}

void App::notice(const std::string& text) {
    noticeText = text;
    noticeUntil = SDL_GetTicks() + kNoticeMs;
}

void App::topBarChanged() {
    hud = HudSettings::load();
    clockFmt = hud.statusLauncher ? clockFormat(hud) : "";
    sensorsDue = SDL_GetTicks();
    dirty = true;
}

void App::audioChanged() {
    audio.read();
    dirty = true;
}

void App::follow() {
    following = true;
    followUntil = SDL_GetTicks() + kFollowMs;
    followNextRead = SDL_GetTicks() + 30;   // give the script a moment to write it
}

// The top bar's values. The battery and the temperatures are sysfs files the AXP answers over its
// bus: read only with sensors, else kept from the last frame (the marquee draws 30 a second).
TopBar App::readTopBar(bool sensors) const {
    TopBar b;
    if (!hud.statusLauncher) return b;
    b.clock = clockText(clockFmt);
    if (hud.statusAudio && audio.volume >= 0) b.audio = audio;
    if (!sensors) {
        b.cpuTemp = bar.cpuTemp;
        b.pmicTemp = bar.pmicTemp;
        b.battery = bar.battery;
        return b;
    }
    if (hud.statusCpuTemp) b.cpuTemp = cpuTemperature();
    if (hud.statusPmicTemp) b.pmicTemp = pmicTemperature();
    if (hud.statusBattery) b.battery = Battery::read();
    return b;
}

// The lowest screen of the overlays on top draws itself and the bars; the overlays go over them.
void App::render() {
    const Uint32 now = SDL_GetTicks();
    const bool sensors = (Sint32)(now - sensorsDue) >= 0;
    bar = readTopBar(sensors);
    if (sensors) sensorsDue = now + kSensorReadMs;
    size_t base = stack.size() - 1;
    while (base > 0 && stack[base]->overlay()) --base;

    ui.begin();
    // only the screen on top scrolls its selected text
    ui.setMarquee(base == stack.size() - 1);
    stack[base]->render(ui);
    // Bars are drawn last so long descriptions or scrolled tiles never spill over them
    ui.header(stack[base]->header(), bar);
    ui.footer(stack.back()->hints());
    for (size_t i = base + 1; i < stack.size(); ++i) {
        ui.setMarquee(i == stack.size() - 1);
        stack[i]->render(ui);
    }
    if (!noticeText.empty()) ui.notice(noticeText);
    ui.end();
}

int App::run() {
    audio.read();
    topBarChanged();
    jackEvent = jack::watch();
    lastActivity = SDL_GetTicks();

    while (running && !stack.empty()) {
        Uint32 now = SDL_GetTicks();
        // a screen may open or close others in its tick: closed ones stay alive until the loop's end
        std::vector<Screen*> live;
        for (const auto& s : stack) live.push_back(s.get());
        for (Screen* s : live) s->tick(now);
        if (stack.empty()) break;
        if (dirty) {
            render();
            dirty = false;
        }

        now = SDL_GetTicks();
        Uint32 elapsed = now - lastActivity;
        // the idle check only reads the top bar's battery, audio and temperatures again
        const bool liveItems = hud.statusLauncher && (hud.statusBattery || hud.statusAudio || hud.statusCpuTemp || hud.statusPmicTemp);
        int timeout = !liveItems ? INT_MAX : elapsed >= kIdleCheckMs ? 0 : (int)(kIdleCheckMs - elapsed);
        if (input.repeatIn(now) >= 0) timeout = std::min(timeout, input.repeatIn(now));
        if (following) {
            if ((Sint32)(now - followUntil) >= 0) {
                following = false;
                dirty = true;
                timeout = 0;
            } else {
                if ((Sint32)(now - followNextRead) >= 0) {
                    audio.read();
                    for (const auto& s : stack) s->levelsChanged();
                    followNextRead = now + kFollowReadMs;
                    dirty = true;
                }
                timeout = std::min(timeout, (int)kFollowReadMs);
            }
        }
        if (!clockFmt.empty())   // wake up when the minute changes
            timeout = std::min(timeout, (int)(60 - time(nullptr) % 60) * 1000);
        if (panelUntil) {
            if ((Sint32)(now - panelUntil) >= 0) {
                panelUntil = 0;
                dirty = true;
                timeout = 0;
            } else {
                timeout = std::min(timeout, (int)(panelUntil - now));
            }
        }
        if (!noticeText.empty()) {
            if ((Sint32)(now - noticeUntil) >= 0) {
                noticeText.clear();
                dirty = true;
                timeout = 0;
            } else {
                timeout = std::min(timeout, (int)(noticeUntil - now));
            }
        }
        // keep drawing until an animation is over (paced by vsync)
        if (std::any_of(stack.begin(), stack.end(), [](const std::unique_ptr<Screen>& s) { return s->animating(); })) {
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
        for (const auto& s : stack) {
            if (Uint32 at = s->wakeAt()) {
                if ((Sint32)(now - at) >= 0) {
                    dirty = true;
                    timeout = 0;
                } else {
                    timeout = std::min(timeout, (int)(at - now));
                }
            }
        }

        SDL_Event ev;
        if (!SDL_WaitEventTimeout(&ev, timeout)) {
            now = SDL_GetTicks();
            Action repeated = input.due(now);
            if (repeated != Action::None) {
                stack.back()->onAction(repeated);
                dirty = true;
                lastActivity = now;
            } else if (now - lastActivity >= kIdleCheckMs) {
                lastActivity = now;
                if (hud.statusAudio) audio.read();
                const TopBar fresh = readTopBar(true);
                if (fresh != bar) {
                    bar = fresh;
                    sensorsDue = now + kSensorReadMs;
                    dirty = true;
                }
            }
            if (clockText(clockFmt) != bar.clock) dirty = true;
            closed.clear();
            continue;
        }

        do {
            if (ev.type == osdEvent) {
                dirty = true;
                panelUntil = SDL_GetTicks() + kPanelMs;
                continue;
            }
            if (ev.type == SDL_QUIT) running = false;
            else if (ev.type == SDL_WINDOWEVENT && ev.window.event == SDL_WINDOWEVENT_EXPOSED) dirty = true;
            if (jackEvent && ev.type == jackEvent) {   // triggerhappy moves the sound: follow the mixer
                follow();
                continue;
            }

            if (stack.back()->raw()) {
                stack.back()->onEvent(ev);
                if (input.translate(ev, false).hotkey) follow();
                dirty = true;
                continue;
            }
            const Input::Result r = input.translate(ev, stack.back()->typing());
            if (r.hotkey) follow();
            if (!r.text.empty()) {
                stack.back()->onText(r.text);
                dirty = true;
            }
            if (r.action != Action::None) {
                stack.back()->onAction(r.action);
                input.started(r.action, SDL_GetTicks());
                dirty = true;
                lastActivity = SDL_GetTicks();
            }
        } while (running && !stack.empty() && SDL_PollEvent(&ev));
        closed.clear();
    }
    return 0;
}
