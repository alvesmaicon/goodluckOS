#include "settings.h"

#include <algorithm>
#include <cstdlib>
#include <memory>

#include "config.h"
#include "layout.h"
#include "overlays.h"
#include "system/clock.h"
#include "system/device.h"
#include "util.h"

constexpr int kSectionsW  = 200;                    // the sections, on the left
constexpr int kPageX      = kSectionsW + 16;        // the page, on the right
constexpr int kPageRight  = kScreenW - kMargin;
constexpr int kTop        = kHeaderH + 8;
constexpr int kBottom     = kScreenH - kFooterH - 6;
constexpr int kRowH       = 32;
constexpr int kInfoRowH   = 26;
constexpr int kSectionRowH = 30;
constexpr int kValueW     = 168;                    // the value at the right of a row
constexpr int kHintLines  = 2;
constexpr Uint32 kSaveDelayMs = 800;                // holding the d-pad on a level saves once, after it
constexpr SDL_Color kDim  {100, 100, 104, 255};     // a row that can't be used now

int Row::height() const {
    switch (kind) {
        case Kind::Section: return kSectionRowH;
        case Kind::Info:    return kInfoRowH;
        default:            return kRowH;
    }
}

Row Row::section(const std::string& label) {
    Row r;
    r.kind = Kind::Section;
    r.label = label;
    return r;
}

Row Row::info(const std::string& label, const std::string& value) {
    Row r;
    r.kind = Kind::Info;
    r.label = label;
    r.value = value;
    return r;
}

Row Row::link(const std::string& label, std::function<void()> open, const std::string& value) {
    Row r;
    r.kind = Kind::Link;
    r.label = label;
    r.run = std::move(open);
    r.value = value;
    return r;
}

Row Row::toggle(const std::string& label, bool on, std::function<void(int)> set) {
    Row r;
    r.kind = Kind::Toggle;
    r.label = label;
    r.on = on;
    r.set = std::move(set);
    return r;
}

Row Row::choice(const std::string& label, std::vector<std::string> choices, int index, std::function<void(int)> set) {
    Row r;
    r.kind = Kind::Choice;
    r.label = label;
    r.choices = std::move(choices);
    r.index = std::clamp(index, 0, std::max(0, (int)r.choices.size() - 1));
    r.set = std::move(set);
    return r;
}

Row Row::level(const std::string& label, int value, int min, int max, int step, std::function<void(int)> set) {
    Row r;
    r.kind = Kind::Level;
    r.label = label;
    r.current = value;
    r.min = min;
    r.max = max;
    r.step = step;
    r.set = std::move(set);
    return r;
}

Row Row::number(const std::string& label, const std::string& shown, int value, int min, int max,
                std::function<void(int)> set) {
    Row r;
    r.kind = Kind::Number;
    r.label = label;
    r.value = shown;
    r.current = value;
    r.min = min;
    r.max = max;
    r.set = std::move(set);
    return r;
}

Row Row::action(const std::string& label, std::function<void()> run, const std::string& value) {
    Row r;
    r.kind = Kind::Action;
    r.label = label;
    r.run = std::move(run);
    r.value = value;
    return r;
}

static int firstFocusable(const std::vector<Row>& rows) {
    for (size_t i = 0; i < rows.size(); ++i)
        if (rows[i].focusable()) return (int)i;
    return -1;
}

SettingsScreen::SettingsScreen(App& app, Model& launcher, Hooks hooks)
    : Screen(app), launcher(launcher), hooks(std::move(hooks)), cursors(1) {
    startLanguage = i18n::current();
    reload();
}

void SettingsScreen::reload() {
    brightnessLevel = brightness();
    audio.read();
    prefs = Prefs::load();
    if (prefs.language.empty()) prefs.language = i18n::current();
    hud = HudSettings::load();
    profile = powerProfile();
    zone = timezoneIndex();
    home = homeUsage();
    card = externalCard();
    trash = trashStats();
    resize = Resize::read();
    info = SystemInfo::read();
}

SettingsScreen::Page SettingsScreen::page() const {
    return subpages.empty() ? sections()[section].first : subpages.back();
}

SettingsScreen::Cursor& SettingsScreen::cursor() {
    return cursors[subpages.size()];
}

void SettingsScreen::enterPage() {
    inPage = true;
    Cursor& c = cursor();
    if (c.sel < 0) c.sel = firstFocusable(rows(page()));
}

void SettingsScreen::open(Page p) {
    subpages.push_back(p);
    cursors.push_back(Cursor{firstFocusable(rows(p)), 0});
}

void SettingsScreen::back() {
    if (!subpages.empty()) {
        subpages.pop_back();
        cursors.pop_back();
    } else {
        inPage = false;
    }
}

void SettingsScreen::switchSection(int delta) {
    const int n = (int)sections().size();
    section = (section + delta + n) % n;
    subpages.clear();
    cursors.assign(1, Cursor{});
    clockEdit.tm_year = 0;      // the Date & Time page starts again from the clock
    clockSet = false;
    if (inPage) enterPage();
}

void SettingsScreen::close() {
    if (saveAt) {
        saveLevels();
        saveAt = 0;
    }
    const bool languageChanged = i18n::current() != startLanguage;
    const auto closed = hooks.closed;
    app.pop();
    if (closed) closed(languageChanged);
}

// To the next row that can be selected; on a page with none, the page scrolls.
void SettingsScreen::move(int delta) {
    Cursor& c = cursor();
    if (c.sel < 0) {
        c.scroll = std::max(0, c.scroll + delta);   // kept in range when drawn
        return;
    }
    const std::vector<Row> list = rows(page());
    for (int k = c.sel + delta; k >= 0 && k < (int)list.size(); k += delta) {
        if (list[k].focusable()) {
            c.sel = k;
            return;
        }
    }
}

void SettingsScreen::change(const Row& row, int dir) {
    if (!row.enabled || !row.set) return;
    switch (row.kind) {
        case Row::Kind::Toggle:
            if (row.on != (dir > 0)) row.set(dir > 0);
            break;
        case Row::Kind::Choice: {
            const int n = (int)row.choices.size();
            if (n > 1) row.set((row.index + dir + n) % n);
            break;
        }
        case Row::Kind::Level: {
            // the next step on the min + n * step grid, so 46 goes to 50 or 40
            int k = (row.current - row.min) / row.step;
            if (dir > 0) k++;
            else if ((row.current - row.min) % row.step == 0) k--;
            const int v = std::clamp(row.min + k * row.step, row.min, row.max);
            if (v != row.current) row.set(v);
            break;
        }
        case Row::Kind::Number: {
            int v = row.current + dir;
            if (v > row.max) v = row.min;
            if (v < row.min) v = row.max;
            row.set(v);
            break;
        }
        default: break;
    }
}

// The choices of a Choice row in a list, for the long ones (time zones).
void SettingsScreen::choose(const Row& row) {
    Dialog d;
    d.title = row.label;
    d.choices = row.choices;
    d.raw = row.rawChoices;
    d.selected = row.index;
    const auto set = row.set;
    app.push(std::make_unique<DialogScreen>(app, d, [set](int choice) { if (set) set(choice); }));
}

void SettingsScreen::levelChanged() {
    saveAt = SDL_GetTicks() + kSaveDelayMs;
}

void SettingsScreen::onAction(Action a) {
    if (a == Action::Power) {
        if (saveAt) {       // before a restart from the menu
            saveLevels();
            saveAt = 0;
        }
        if (hooks.powerMenu) hooks.powerMenu();
        return;
    }
    if (a == Action::Start) {
        close();
        return;
    }
    if (a == Action::PrevTab || a == Action::NextTab) {
        switchSection(a == Action::PrevTab ? -1 : 1);
        return;
    }
    if (!inPage) {
        switch (a) {
            case Action::Up:     switchSection(-1); break;
            case Action::Down:   switchSection(1);  break;
            case Action::Right:
            case Action::Launch: enterPage(); break;
            case Action::Back:   close(); break;
            default: break;
        }
        return;
    }

    const std::vector<Row> list = rows(page());
    const Cursor& c = cursor();
    const Row* row = c.sel >= 0 && c.sel < (int)list.size() ? &list[c.sel] : nullptr;
    const bool value = row && (row->kind == Row::Kind::Toggle || row->kind == Row::Kind::Choice ||
                               row->kind == Row::Kind::Level || row->kind == Row::Kind::Number);
    switch (a) {
        case Action::Up:   move(-1); break;
        case Action::Down: move(1);  break;
        case Action::Left:
            if (value) change(*row, -1);
            else back();
            break;
        case Action::Right:
            if (value) change(*row, 1);
            else if (row && row->kind == Row::Kind::Link && row->enabled && row->run) row->run();
            break;
        case Action::Launch:
            if (!row || !row->enabled) break;
            if (row->kind == Row::Kind::Toggle) row->set(!row->on);
            else if (row->kind == Row::Kind::Choice) choose(*row);
            else if (row->run) row->run();
            break;
        case Action::Back: back(); break;
        default: break;
    }
}

void SettingsScreen::tick(Uint32 now) {
    if (saveAt && (Sint32)(now - saveAt) >= 0) {
        saveLevels();
        saveAt = 0;
    }
    if (watchUntil) {
        if ((Sint32)(now - nextWatch) >= 0) {
            card = externalCard();
            home = homeUsage();
            nextWatch = now + 500;
        }
        if ((Sint32)(now - watchUntil) >= 0) watchUntil = 0;
    }
}

Uint32 SettingsScreen::wakeAt() const {
    Uint32 at = 0;
    auto earliest = [&](Uint32 t) {
        if (t && (!at || (Sint32)(t - at) < 0)) at = t;
    };
    earliest(saveAt);
    if (watchUntil) earliest(nextWatch);
    if (page() == Page::DateTime) earliest(clockDrawn + 1000);
    return at;
}

// A hotkey changed a level: follow it, unless it's being changed here
void SettingsScreen::levelsChanged() {
    if (saveAt) return;
    brightnessLevel = brightness();
    audio.read();
}

void SettingsScreen::applyFont() {
    std::string path;
    float scale;
    interfaceFont(prefs.font, path, scale);
    app.painter().setFont(path, scale);
    if (hooks.fontChanged) hooks.fontChanged();
}

Header SettingsScreen::header() const {
    return {tr("System Settings"), "", false};
}

Hints SettingsScreen::hints() const {
    if (!inPage) return {{"L1/R1", tr("Section")}, {"A", tr("Open")}, {"B", tr("Close")}};
    Hints hints = {{"L1/R1", tr("Section")}};
    switch (shownKind) {
        case Row::Kind::Toggle: hints.push_back({"A", tr("Change")}); break;
        case Row::Kind::Choice:
            hints.push_back({"LEFT/RIGHT", tr("Change")});
            hints.push_back({"A", tr("Select")});
            break;
        case Row::Kind::Level:
        case Row::Kind::Number: hints.push_back({"LEFT/RIGHT", tr("Change")}); break;
        case Row::Kind::Link:
        case Row::Kind::Action: hints.push_back({"A", tr("Select")}); break;
        default: hints.push_back({"UP/DOWN", tr("Scroll")}); break;
    }
    hints.push_back({"B", tr("Back")});
    return hints;
}

void SettingsScreen::render(Ui& ui) {
    renderSections(ui);
    renderPage(ui);
}

void SettingsScreen::renderSections(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const int fontH = TTF_FontHeight(fonts.desc);
    for (int i = 0; i < (int)sections().size(); ++i) {
        SDL_Rect r{kMargin / 2, kTop + i * kRowH, kSectionsW - kMargin / 2, kRowH - 2};
        const bool sel = i == section;
        if (sel) {
            ui.fill(kRowSel, r);
            if (!inPage) ui.fill(kYellow, {r.x, r.y, 4, r.h});
        }
        drawText(renderer, fonts.desc, tr(sections()[i].second), r.x + 14, r.y + (r.h - fontH) / 2,
                 sel ? kWhite : kGrey, r.w - 18);
    }
    ui.fill(kTile, {kSectionsW + 7, kTop, 1, kBottom - kTop});
}

static int rowsHeight(const std::vector<Row>& rows, int from, int to) {
    int h = 0;
    for (int k = from; k < to; ++k) h += rows[k].height();
    return h;
}

void SettingsScreen::renderPage(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const Page p = page();
    const std::vector<Row> list = rows(p);
    Cursor& c = cursor();
    const int width = kPageRight - kPageX;
    const int n = (int)list.size();
    if (p == Page::DateTime) clockDrawn = SDL_GetTicks();

    drawText(renderer, fonts.ui, title(p), kPageX, kTop, kWhite, width);
    const int top = kTop + TTF_FontHeight(fonts.ui) + 8;

    // the selected row's hint, else the page's, in the lines under the rows (on pages that have any)
    const std::string page = pageHint(p);
    const bool hints = !page.empty() || std::any_of(list.begin(), list.end(), [](const Row& r) { return !r.hint.empty(); });
    const int lineH = TTF_FontLineSkip(fonts.small);
    const int hintTop = kBottom - kHintLines * lineH;
    const Row* selected = inPage && c.sel >= 0 && c.sel < n ? &list[c.sel] : nullptr;
    shownKind = selected ? selected->kind : Row::Kind::Info;
    const std::string hint = selected && !selected->hint.empty() ? tr(selected->hint) : page;
    if (!hint.empty()) ui.drawWrappedClipped(fonts.small, hint, kPageX, hintTop, kGrey, width - 16, kHintLines * lineH);
    const int bottom = hints ? hintTop - 6 : kBottom;
    const int room = bottom - top;

    // scrolled so the selected row is in view, with the section above it when it's the first one
    if (c.sel >= 0 && c.sel < n) {
        if (c.sel < c.scroll) c.scroll = c.sel;
        if (c.scroll == c.sel && c.scroll > 0 && list[c.scroll - 1].kind == Row::Kind::Section) --c.scroll;
        while (c.scroll < c.sel && rowsHeight(list, c.scroll, c.sel + 1) > room) ++c.scroll;
    }
    int maxScroll = n;
    for (int h = 0; maxScroll > 0 && h + list[maxScroll - 1].height() <= room; --maxScroll) h += list[maxScroll - 1].height();
    c.scroll = std::clamp(c.scroll, 0, maxScroll);

    SDL_Rect clip{kPageX, top, width, room};
    SDL_RenderSetClipRect(renderer, &clip);
    int y = top;
    for (int k = c.scroll; k < n && y + list[k].height() <= bottom; ++k) {   // whole rows only
        const Row& row = list[k];
        const bool sel = inPage && k == c.sel;
        const int h = row.height();
        const std::string label = row.rawLabel ? row.label : tr(row.label);

        if (row.kind == Row::Kind::Section) {
            const int ty = y + h - TTF_FontHeight(fonts.small) - 4;
            const int lw = textWidth(fonts.small, label);
            drawText(renderer, fonts.small, label, kPageX + 4, ty, kGrey);
            ui.fill(kTile, {kPageX + 4 + lw + 8, ty + TTF_FontHeight(fonts.small) / 2, width - lw - 16, 1});
            y += h;
            continue;
        }
        if (row.kind == Row::Kind::Info) {
            const int ty = y + (h - TTF_FontHeight(fonts.small)) / 2;
            const int lw = std::min(textWidth(fonts.small, label), width / 2);
            drawText(renderer, fonts.small, label, kPageX + 16, ty, kGrey, width / 2);
            const int valueX = std::max(kPageX + 16 + lw + 16, kPageRight - 8 - textWidth(fonts.small, row.value));
            drawText(renderer, fonts.small, row.value, valueX, ty, kWhite, kPageRight - 8 - valueX);
            y += h;
            continue;
        }

        SDL_Rect r{kPageX, y, width, h - 2};
        if (sel) {
            ui.fill(kRowSel, r);
            ui.fill(kYellow, {r.x, r.y, 4, r.h});
        }
        const SDL_Color text = !row.enabled ? kDim : sel ? kWhite : kGrey;
        const int right = r.x + r.w - 8;
        const int mid = r.y + r.h / 2;
        const int fontH = TTF_FontHeight(fonts.desc);
        int valueW = 0;
        switch (row.kind) {
            case Row::Kind::Toggle: {
                valueW = 40;
                SDL_Rect track{right - 40, mid - 10, 40, 20};
                ui.fill(row.on ? (row.enabled ? kYellow : kDim) : kTile, track);
                ui.fill(row.on ? kBar : kGrey, {row.on ? track.x + track.w - 18 : track.x + 2, track.y + 2, 16, 16});
                break;
            }
            case Row::Kind::Choice:
            case Row::Kind::Number: {
                valueW = kValueW;
                const std::string v = row.kind == Row::Kind::Number ? row.value
                                    : row.choices.empty() ? std::string()
                                    : row.rawChoices ? row.choices[row.index] : tr(row.choices[row.index]);
                const int left = right - kValueW;
                const int vw = std::min(textWidth(fonts.desc, v), kValueW - 28);
                drawText(renderer, fonts.desc, v, left + (kValueW - vw) / 2, mid - fontH / 2, text, kValueW - 28);
                if (sel && row.enabled) {
                    ui.sideTriangle(left + 6, mid, 5, true, kYellow);
                    ui.sideTriangle(right - 6, mid, 5, false, kYellow);
                }
                break;
            }
            case Row::Kind::Level: {
                valueW = kValueW;
                const std::string pct = std::to_string(row.max > 0 ? row.current * 100 / row.max : 0) + "%";
                const int pctW = textWidth(fonts.small, "100%");
                SDL_Rect bar{right - kValueW, mid - 6, kValueW - pctW - 10, 12};
                ui.fill(kTile, bar);
                const int filled = row.max > 0 ? bar.w * std::clamp(row.current, 0, row.max) / row.max : 0;
                if (filled > 0) ui.fill(sel ? kYellow : kGrey, {bar.x, bar.y, filled, bar.h});
                drawText(renderer, fonts.small, pct, right - textWidth(fonts.small, pct), mid - TTF_FontHeight(fonts.small) / 2, text);
                break;
            }
            case Row::Kind::Link: {
                ui.sideTriangle(right - 4, mid, 5, false, row.enabled ? (sel ? kYellow : kGrey) : kDim);
                const int vw = textWidth(fonts.small, row.value);
                valueW = 16 + (vw ? vw + 8 : 0);
                drawText(renderer, fonts.small, row.value, right - valueW + 4, mid - TTF_FontHeight(fonts.small) / 2, kGrey);
                break;
            }
            case Row::Kind::Action: {
                const int vw = textWidth(fonts.small, row.value);
                valueW = vw;
                drawText(renderer, fonts.small, row.value, right - vw, mid - TTF_FontHeight(fonts.small) / 2, kGrey);
                break;
            }
            default: break;
        }
        // a selected label that doesn't fit scrolls, like the launcher's list
        const int labelX = r.x + 16;
        const int labelMax = right - (valueW ? valueW + 12 : 0) - labelX;
        int scrollX = 0;
        if (sel) {
            const int overflow = textWidth(fonts.desc, label) - labelMax;
            if (overflow > 0) scrollX = ui.marqueeOffset("settings\x1f" + label, overflow);
        }
        drawText(renderer, fonts.desc, label, labelX, mid - fontH / 2, text, labelMax, scrollX);
        y += h;
    }
    SDL_RenderSetClipRect(renderer, nullptr);

    // scrollbar, when the page doesn't fit
    const int total = rowsHeight(list, 0, n);
    if (total > room) {
        SDL_Rect track{kScreenW - 10, top, 3, room};
        ui.fill(kTile, track);
        const int thumbH = std::max(16, room * room / total);
        const int thumbY = track.y + (room - thumbH) * rowsHeight(list, 0, c.scroll) / std::max(1, total - room);
        ui.fill(kGrey, {track.x, std::min(thumbY, track.y + room - thumbH), track.w, thumbH});
    }
}
