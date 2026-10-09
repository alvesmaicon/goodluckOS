#include "overlays.h"

#include <algorithm>

#include "layout.h"
#include "util.h"

// UTF-8 aware: the start of the letter before / after byte position pos
static size_t prevLetter(const std::string& t, size_t pos) {
    while (pos > 0 && ((unsigned char)t[--pos] & 0xC0) == 0x80) {}
    return pos;
}

static size_t nextLetter(const std::string& t, size_t pos) {
    if (pos < t.size()) ++pos;
    while (pos < t.size() && ((unsigned char)t[pos] & 0xC0) == 0x80) ++pos;
    return pos;
}

KeyboardScreen::KeyboardScreen(App& app, Keyboard& kb, std::string& text, bool rename, size_t maxLength, Hooks hooks)
    : Screen(app), kb(kb), text(text), rename(rename), cursor(text.size()), maxLength(maxLength), hooks(std::move(hooks)) {}

void KeyboardScreen::close(bool accept) {
    const auto done = hooks.done;
    app.pop();
    if (done) done(accept);
}

// Types at the cursor (the search's is always at its end)
void KeyboardScreen::type(const std::string& key) {
    size_t cursorAtEnd = text.size();
    size_t& at = rename ? cursor : cursorAtEnd;
    at = std::min(at, text.size());
    if (key == "ok") { close(true); return; }
    if (key == "shift") { kb.caps = !kb.caps; return; }
    if (key == "del") {
        const size_t start = prevLetter(text, at);
        text.erase(start, at - start);
        at = start;
    } else if (text.size() < maxLength) {
        std::string c = key == "space" ? " " : key;
        if (kb.caps && c.size() == 1) c = upper(c);
        text.insert(at, c);
        at += c.size();
    }
    if (hooks.changed) hooks.changed();
}

void KeyboardScreen::onAction(Action a) {
    switch (a) {
        case Action::Up:     kb.move(0, -1); break;
        case Action::Down:   kb.move(0, 1);  break;
        case Action::Left:   kb.move(-1, 0); break;
        case Action::Right:  kb.move(1, 0);  break;
        case Action::Launch: type(kb.current()); break;
        case Action::PrevTab:   // L1/R1 move the cursor in the name
            if (rename) cursor = prevLetter(text, std::min(cursor, text.size()));
            else if (hooks.forward) hooks.forward(*this, a);
            break;
        case Action::NextTab:
            if (rename) cursor = nextLetter(text, cursor);
            else if (hooks.forward) hooks.forward(*this, a);
            break;
        case Action::Back:
            if (text.empty()) close(false);
            else type("del");
            break;
        case Action::Start:
        case Action::Search: close(true); break;
        case Action::ToggleAutoStart: close(false); break;   // SELECT: cancel
        case Action::Power:
            if (hooks.forward) hooks.forward(*this, a);
            break;
        default: break;
    }
}

void KeyboardScreen::render(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const int pad = 12, gap = 4, unit = 58, keyH = 36;
    const int queryH = TTF_FontHeight(fonts.ui) + 12;
    const int panelW = (int)(Keyboard::kRowUnits * unit) - gap + 2 * pad;
    const int panelH = queryH + Keyboard::kRows * keyH + (Keyboard::kRows - 1) * gap + 2 * pad;
    SDL_Rect panel{(kScreenW - panelW) / 2, kScreenH - kFooterH - panelH - 6, panelW, panelH};
    ui.fill({12, 12, 14, 240}, panel);
    ui.frame(kTile, panel, 2);

    // What is typed: the search, or the new name of a game's file; a long name shows its end
    const std::string prompt = tr(rename ? "Rename:" : "Search:");
    drawText(renderer, fonts.ui, prompt, panel.x + pad, panel.y + pad, kGrey);
    const int textX = panel.x + pad + textWidth(fonts.ui, prompt) + 8;
    const int textMax = panel.x + panelW - pad - textX;
    if (rename) {
        // the name with a cursor bar, scrolled so the cursor stays in view
        const size_t at = std::min(cursor, text.size());
        const int caretX = textWidth(fonts.ui, text.substr(0, at));
        const int scroll = std::max(0, caretX + 4 - textMax);
        drawText(renderer, fonts.ui, text, textX, panel.y + pad, kWhite, textMax, scroll);
        ui.fill(accent(), {textX + caretX - scroll, panel.y + pad, 2, TTF_FontHeight(fonts.ui)});
    } else {
        const std::string shown = text + "_";
        drawText(renderer, fonts.ui, shown, textX, panel.y + pad, kWhite, textMax, std::max(0, textWidth(fonts.ui, shown) - textMax));
    }

    for (int r = 0; r < Keyboard::kRows; ++r) {
        const auto& keys = Keyboard::keys(r);
        for (int c = 0; c < (int)keys.size(); ++c) {
            const Keyboard::Key& key = keys[c];
            SDL_Rect k{panel.x + pad + (int)(key.x * unit), panel.y + pad + queryH + r * (keyH + gap),
                       (int)(key.w * unit) - gap, keyH};
            bool sel = r == kb.row && c == kb.col;
            ui.fill(sel ? accent() : kTile, k);
            if (key.label == "shift" && kb.caps) ui.frame(sel ? kBlack : accent(), k, 2);   // case switch on
            std::string label = key.label == "shift" ? (kb.caps ? "aA" : "Aa")
                              : key.label.size() > 1 ? tr(key.label) : key.label;   // space / del / ok
            TTF_Font* f = key.label.size() > 1 ? fonts.small : fonts.ui;
            if (key.label.size() == 1) label = kb.caps ? upper(label) : label;
            drawText(renderer, f, label, k.x + (k.w - textWidth(f, label)) / 2,
                     k.y + (k.h - TTF_FontHeight(f)) / 2, sel ? kBlack : kWhite);
        }
    }
}

Hints KeyboardScreen::hints() const {
    Hints hints = {{"A", tr("Type")}, {"B", tr("Delete")}, {"START", tr("Done")}};
    if (rename) {
        hints.insert(hints.begin(), {"L1/R1", tr("Cursor")});
        hints.push_back({"SELECT", tr("Cancel")});
    }
    return hints;
}

DialogScreen::DialogScreen(App& app, Dialog dialog, std::function<void(int)> onChoose)
    : Screen(app), d(std::move(dialog)), onChoose(std::move(onChoose)) {
    sel = std::clamp(d.selected, 0, std::max(0, (int)d.choices.size() - 1));
}

void DialogScreen::onAction(Action a) {
    const int n = (int)d.choices.size();
    if (n == 0) {
        if (a == Action::Back || a == Action::Power || a == Action::Launch) app.pop();
        return;
    }
    switch (a) {
        case Action::Up:   sel = (sel + n - 1) % n; break;
        case Action::Down: sel = (sel + 1) % n;     break;
        case Action::Launch: {
            const auto choose = onChoose;
            const int choice = sel;
            app.pop();
            if (choose) choose(choice);
            break;
        }
        case Action::Back:
        case Action::Power: app.pop(); break;
        default: break;
    }
}

void DialogScreen::render(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const int pad = 12, rowH = 40;
    const int titleH = TTF_FontHeight(fonts.ui) + 14;
    const int subH = d.subtitle.empty() ? 0 : TTF_FontLineSkip(fonts.small) + 6;
    const int panelW = d.subtitle.empty() && d.message.empty() ? 320 : 400;
    const int textW = panelW - 2 * pad - 4;
    const std::string message = tr(d.message);
    const int msgH = message.empty() ? 0 : ui.wrappedHeight(fonts.small, message, textW) + 10;
    const int count = (int)d.choices.size();
    const int fit = std::max(1, (kScreenH - kFooterH - d.bodyY - 16 - titleH - subH - msgH - 2 * pad) / rowH);
    const int shown = std::min(count, fit);
    if (sel < scroll) scroll = sel;
    if (sel >= scroll + shown) scroll = sel - shown + 1;
    const int panelH = titleH + subH + msgH + shown * rowH + 2 * pad;
    SDL_Rect panel{(kScreenW - panelW) / 2, d.bodyY + (kScreenH - kFooterH - d.bodyY - panelH) / 2, panelW, panelH};
    ui.fill({0, 0, 0, 150}, {0, kHeaderH, kScreenW, kScreenH - kFooterH - kHeaderH});   // dim the screen behind
    ui.fill(kBar, panel);
    ui.frame(kTile, panel, 2);
    drawText(renderer, fonts.ui, tr(d.title), panel.x + pad + 4, panel.y + pad, kWhite, textW);
    if (!d.subtitle.empty())
        drawText(renderer, fonts.small, d.subtitle, panel.x + pad + 4, panel.y + pad + titleH - 4, kGrey, textW);
    if (!message.empty())
        ui.drawWrapped(fonts.small, message, panel.x + pad + 4, panel.y + pad + titleH + subH - 4, kGrey, textW);

    const int fontH = TTF_FontHeight(fonts.desc);
    const int top = panel.y + pad + titleH + subH + msgH;
    for (int i = 0; i < shown; ++i) {
        const int k = scroll + i;
        SDL_Rect r{panel.x + pad, top + i * rowH, panelW - 2 * pad, rowH - 4};
        bool selected = k == sel;
        if (selected) {
            ui.fill(kRowSel, r);
            ui.fill(accent(), {r.x, r.y, 4, r.h});
        }
        int labelX = r.x + 16;
        if (k < (int)d.swatches.size()) {
            ui.fill(d.swatches[k], {labelX, r.y + (r.h - 16) / 2, 28, 16});
            labelX += 28 + 12;
        }
        const int labelW = r.x + r.w - 8 - labelX;
        const std::string label = d.raw ? d.choices[k] : tr(d.choices[k]);
        const int overflow = textWidth(fonts.desc, label) - labelW;
        const int scrollX = selected && overflow > 0 ? ui.marqueeOffset("dialog\x1f" + label, overflow) : 0;
        drawText(renderer, fonts.desc, label, labelX, r.y + (r.h - fontH) / 2, selected ? kWhite : kGrey, labelW,
                 scrollX);
    }
    // more choices above / below
    if (scroll > 0) ui.triangle(panel.x + panelW - pad - 10, top + 8, 5, true, accent());
    if (scroll + shown < count) ui.triangle(panel.x + panelW - pad - 10, top + shown * rowH - 12, 5, false, accent());
}

Hints DialogScreen::hints() const {
    return {{"A", tr("Select")}, {"B", tr("Close")}};
}
