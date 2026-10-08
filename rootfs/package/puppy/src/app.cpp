#include "app.h"

#include <algorithm>
#include <ctime>

#include "layout.h"

App::App(Ui& ui, SDL_GameController* pad) : ui(ui), input(pad) {}

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

void App::follow() {
    following = true;
    followUntil = SDL_GetTicks() + kFollowMs;
    followNextRead = SDL_GetTicks() + 30;   // give the script a moment to write it
}

// The lowest screen of the overlays on top draws itself and the bars; the overlays go over them.
void App::render() {
    battery = readBattery();
    clock = clockText(clockFmt);
    size_t base = stack.size() - 1;
    while (base > 0 && stack[base]->overlay()) --base;

    ui.begin();
    stack[base]->render(ui);
    // Bars are drawn last so long descriptions or scrolled tiles never spill over them
    ui.header(stack[base]->header(), battery, audio, clock);
    ui.footer(stack.back()->hints());
    for (size_t i = base + 1; i < stack.size(); ++i) stack[i]->render(ui);
    if (!noticeText.empty()) ui.notice(noticeText);
    ui.end();
}

int App::run() {
    audio.read();
    clockFmt = clockFormat();
    lastActivity = SDL_GetTicks();

    while (running && !stack.empty()) {
        if (dirty) {
            render();
            dirty = false;
        }

        Uint32 now = SDL_GetTicks();
        Uint32 elapsed = now - lastActivity;
        int timeout = elapsed >= kIdleCheckMs ? 0 : (int)(kIdleCheckMs - elapsed);
        if (input.repeatIn(now) >= 0) timeout = std::min(timeout, input.repeatIn(now));
        if (following) {
            if ((Sint32)(now - followUntil) >= 0) {
                following = false;
                dirty = true;
                timeout = 0;
            } else {
                if ((Sint32)(now - followNextRead) >= 0) {
                    audio.read();
                    followNextRead = now + kFollowReadMs;
                    dirty = true;
                }
                timeout = std::min(timeout, (int)kFollowReadMs);
            }
        }
        if (!clockFmt.empty())   // wake up when the minute changes
            timeout = std::min(timeout, (int)(60 - time(nullptr) % 60) * 1000);
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
                if (readBattery() != battery) dirty = true;
                Audio a;
                a.read();
                if (a != audio) { audio = a; dirty = true; }
            }
            if (clockText(clockFmt) != clock) dirty = true;
            closed.clear();
            continue;
        }

        do {
            if (ev.type == SDL_QUIT) running = false;
            else if (ev.type == SDL_WINDOWEVENT && ev.window.event == SDL_WINDOWEVENT_EXPOSED) dirty = true;

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
