#include "launcher.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <memory>
#include <vector>

#include "config.h"
#include "system/clock.h"
#include "system/device.h"
#include "layout.h"
#include "library.h"
#include "overlays.h"
#include "settings.h"
#include "util.h"

LauncherScreen::LauncherScreen(App& app, Model model)
    : Screen(app), model(std::move(model)), dateFmt(dateFormat()), stillSince(SDL_GetTicks()) {}

void LauncherScreen::onAction(Action a) {
    // any button stops the trailer; the next one waits for the selection to stay still again
    trailer.stop();
    stillSince = SDL_GetTicks();
    played.clear();

    const bool grid = model.view == View::Grid;
    const bool streaming = grid && theme().showcase;    // a row per tab: up and down change the tab

    if (a == Action::GameMenu) {   // L2 + R2: rename or delete the selected game
        openGameMenu();
        return;
    }
    if (a == Action::Power) {
        // with the screen off, toggle-screen.sh turns it back on; don't open a menu in the dark
        if (screenOn()) openPowerMenu(bodyTop(model.showTabs));
        return;
    }
    if (a == Action::Start) {
        if (builtinSettings()) {
            openSettings();
            return;
        }
        if (model.hasSettings) {
            if (!launch(model, model.settings)) app.quit();
            return;
        }
        // no settings app (e.g. on other firmwares, where POWER may suspend): START opens the menu
        openPowerMenu(bodyTop(model.showTabs));
        return;
    }

    // Streaming's rows stop at the first and the last tab instead of wrapping around
    auto row = [this](int delta) {
        if ((model.neighbour(delta) - model.tab) * delta > 0) model.switchTab(delta);
    };
    switch (a) {
        case Action::PrevTab:
            if (streaming) model.moveSel(-kRowSkip);
            else model.switchTab(-1);
            break;
        case Action::NextTab:
            if (streaming) model.moveSel(kRowSkip);
            else model.switchTab(1);
            break;
        case Action::Up:
            if (streaming) row(-1);
            else model.moveSel(grid ? -kGridCols : -1);
            break;
        case Action::Down:
            if (streaming) row(1);
            else model.moveSel(grid ? kGridCols : 1);
            break;
        case Action::Left:  model.moveSel(grid ? -1 : -listRows(model.showTabs)); break;
        case Action::Right: model.moveSel(grid ? 1 : listRows(model.showTabs));   break;
        case Action::Search: openSearch(); break;
        case Action::Back:
            if (!model.query.empty()) { model.query.clear(); model.applyFilter(); }
            break;
        case Action::ToggleAutoStart: toggleAutoStart(model); break;
        case Action::ToggleFavorite:  toggleFavorite(model);  break;
        case Action::ScrollUp:   model.descScroll = std::max(0, model.descScroll - 1); break;
        case Action::ScrollDown: model.descScroll = std::min(descMax, model.descScroll + 1); break;
        case Action::Launch:
            if (const Entry* e = model.selected()) {
                const Entry entry = *e;   // addRecent rebuilds the Recent tab
                addRecent(model, entry);
                if (!launch(model, entry)) app.quit();
            }
            break;
        default: break;
    }
}

// The search filters every tab as it's typed; the keyboard keeps the query when it closes.
void LauncherScreen::openSearch() {
    KeyboardScreen::Hooks hooks;
    hooks.changed = [this] { model.applyFilter(); };
    hooks.forward = [this](KeyboardScreen& k, Action a) { fromKeyboard(k, a); };
    app.push(std::make_unique<KeyboardScreen>(app, kb, model.query, false, kMaxQueryLength, hooks));
}

// The keyboard starts from the name as shown; accepting renames the game's file.
void LauncherScreen::openRename(const Entry& e) {
    renameText = e.name;
    kb.caps = false;
    KeyboardScreen::Hooks hooks;
    hooks.done = [this, e](bool accepted) {
        const std::string name = trim(renameText);
        if (accepted && !name.empty() && name != e.name) app.notice(renameEntry(model, e, name));
    };
    hooks.forward = [this](KeyboardScreen& k, Action a) { fromKeyboard(k, a); };
    app.push(std::make_unique<KeyboardScreen>(app, kb, renameText, true, kMaxNameLength, hooks));
}

// What the keyboard leaves to the launcher: L1/R1 while searching switch tabs; POWER closes it and
// opens the power menu.
void LauncherScreen::fromKeyboard(KeyboardScreen& k, Action a) {
    if (a == Action::PrevTab || a == Action::NextTab) {
        model.switchTab(a == Action::PrevTab ? -1 : 1);
    } else if (a == Action::Power && screenOn() && !powerItems().empty()) {
        k.close(false);
        openPowerMenu(bodyTop(model.showTabs));
    }
}

void LauncherScreen::openGameMenu() {
    const Entry* e = model.selected();
    if (!e || e->file.empty()) return;
    const Entry entry = *e;
    Dialog d;
    d.title = "Game options";
    d.subtitle = entry.name;
    d.choices = {"Rename", "Move to trash"};
    d.bodyY = bodyTop(model.showTabs);
    app.push(std::make_unique<DialogScreen>(app, d, [this, entry](int choice) {
        if (choice == 0) openRename(entry);
        else confirmTrash(entry);
    }));
}

void LauncherScreen::confirmTrash(const Entry& e) {
    Dialog d;
    d.title = "Move this game to the trash?";
    d.subtitle = e.name;
    d.choices = {"Cancel", "Move to trash"};
    d.bodyY = bodyTop(model.showTabs);
    app.push(std::make_unique<DialogScreen>(app, d, [this, e](int choice) {
        if (choice == 1) app.notice(deleteEntry(model, e));
    }));
}

bool LauncherScreen::openPowerMenu(int bodyY) {
    const std::vector<PowerItem> items = powerItems();
    if (items.empty()) return false;
    Dialog d;
    d.title = "Power options";
    for (const PowerItem& item : items) d.choices.push_back(item.label);
    d.bodyY = bodyY;
    app.push(std::make_unique<DialogScreen>(app, d, [this, items, bodyY](int choice) { runPowerItem(items[choice], bodyY); }));
    return true;
}

void LauncherScreen::runPowerItem(const PowerItem& item, int bodyY) {
    if (item.quit) {
        app.quit();
        return;
    }
    if (!item.question) {
        powerAction(item);
        return;
    }
    Dialog d;
    d.title = item.label;
    d.message = item.question;
    d.choices = {"Cancel", item.label};
    d.bodyY = bodyY;
    app.push(std::make_unique<DialogScreen>(app, d, [this, item](int choice) {
        if (choice == 1) powerAction(item);
    }));
}

void LauncherScreen::powerAction(const PowerItem& item) {
    if (item.status) app.push(std::make_unique<StatusScreen>(app, tr(item.status)));
    if (item.command && !item.command->empty()) runDetached(*item.command);
    else if (item.request) sendPowerRequest(item.request);
}

// puppy.conf's settings_command, when set, wins over the System Settings in Puppy
bool LauncherScreen::builtinSettings() const {
    return cfg.builtinSettings && cfg.settingsCommand.empty();
}

void LauncherScreen::openSettings() {
    SettingsScreen::Hooks hooks;
    hooks.powerMenu = [this] {
        if (screenOn()) openPowerMenu(kHeaderH);
    };
    hooks.fontChanged = [this] {
        for (Category& c : model.categories) c.tagColumn = -1;
    };
    hooks.closed = [this](bool languageChanged) {
        if (languageChanged) reloadGames();
        dateFmt = dateFormat();
        if (model.cur().hidden) model.tab = 0;   // a tab just hidden: All Games
    };
    app.push(std::make_unique<SettingsScreen>(app, model, hooks));
}

// The games' names and descriptions come from the gamelists of the interface language, so a new
// language reads them again. The cursor stays on the same game.
void LauncherScreen::reloadGames() {
    const std::string tabName = model.cur().name;
    const Entry* sel = model.selected();
    const std::string category = sel ? sel->category : "", id = sel ? sel->id : "";
    Model fresh;
    if (!loadModel(fresh)) return;
    model = std::move(fresh);
    int t, e;
    if (!id.empty() && model.find(tabName, category, id, t, e)) {
        model.select(t, e);
    } else {
        for (size_t i = 0; i < model.categories.size(); ++i)
            if (model.categories[i].name == tabName) model.tab = (int)i;
    }
    lastTab = model.tab;
    tabOffset = 0.0f;
}

// "Played for 2 h 30 min · 10/21", or "" for a game never played
std::string LauncherScreen::playedText(const Entry& e, bool withDay) const {
    const PlayTime* p = model.played(e);
    if (!p) return "";
    const long long min = p->seconds / 60;
    std::string time = trf("%s min", std::to_string(min % 60));
    if (min >= 60) time = trf("%s h", std::to_string(min / 60)) + (min % 60 ? " " + time : "");
    else if (min < 1) time = tr("< 1 min");
    if (!withDay) return time;
    std::string text = trf("Played for %s", time);
    if (p->last > 0) text += " · " + dayText(dateFmt, (time_t)p->last);
    return text;
}

// The selected game's trailer, in the Showcase style: it starts once the launcher has been on top
// with no button pressed for kTrailerDelayMs, and plays once. Without the screen it waits for a button.
void LauncherScreen::tick(Uint32 now) {
    const Entry* e = theme().showcase ? model.selected() : nullptr;
    if (!app.onTop(this)) {
        stillSince = now;
        e = nullptr;
    }
    const std::string clip = e ? e->video : "";
    if (trailer.running() && trailer.path() != clip) {
        trailer.stop();
        app.redraw();
    }
    trailerAt = 0;
    if (clip.empty() || clip == played) return;
    if (!trailer.running()) {
        const Uint32 at = std::max<Uint32>(1, stillSince + kTrailerDelayMs);
        if ((Sint32)(now - at) < 0) {
            trailerAt = at;
            return;
        }
        const SDL_Rect box = trailerBox();
        std::error_code ec;
        if (screenOn() && fs::is_regular_file(clip, ec)) trailer.start(app.painter().sdl(), clip, box.w, box.h, model.trailerSound, e->excerpt);
        if (!trailer.running()) {   // no screen, no clip (a gamelist kept without its videos) or no ffmpeg
            played = clip;
            return;
        }
        frameDue = now;
    }
    if ((Sint32)(now - frameDue) < 0) return;
    frameDue = now + kTrailerFrameMs;
    const int got = trailer.update();
    if (got < 0) played = clip;     // to its end: the picture again
    if (got != 0) app.redraw();
}

// Where the trailer plays: over the Streaming picture, or the Shelf one
SDL_Rect LauncherScreen::trailerBox() const {
    if (model.view == View::Grid) return {kScreenW - kHeroW, kHeroY, kHeroW, kHeroH};
    return {kShelfCardX, listTop(model.showTabs), kPreviewW, kPreviewH};
}

void LauncherScreen::render(Ui& ui) {
    const bool grid = model.view == View::Grid;
    if (grid && theme().showcase) {
        renderStreaming(ui);    // its rows take the place of the tab strip
        return;
    }
    if (model.cur().visible.empty()) renderEmpty(ui);
    else if (grid) renderGrid(ui);
    else if (theme().showcase) renderShelf(ui);
    else renderList(ui);
    if (model.showTabs) renderTabs(ui);
}

Header LauncherScreen::header() const {
    const Category& c = model.cur();
    // "686 games", or "12 of 686 games" while searching
    std::string count = std::to_string(c.visible.size());
    if (!model.query.empty()) count += std::string(" ") + tr("of") + " " + std::to_string(c.entries.size());
    const bool one = c.entries.size() == 1;
    count += std::string(" ") + tr(c.media ? (one ? "item" : "items")
                                 : c.isArchive ? (one ? "game" : "games") : (one ? "app" : "apps"));
    if (!model.query.empty()) count += "  ·  \"" + model.query + "\"";
    return {tr(c.name), count, !model.query.empty(), model.view == View::Grid && theme().showcase};
}

Hints LauncherScreen::hints() const {
    const Entry* sel = model.selected();
    const bool fav = sel && model.isFavorite(*sel);
    const bool streaming = model.view == View::Grid && theme().showcase;
    Hints hints = {{"L1/R1", tr(streaming ? "Skip 10" : "Tab")}, {"A", tr("Launch")},
                   {"Y", tr(fav ? "Remove" : "My List"), tr(fav ? "My List" : "Remove")}};
    // while searching, clearing the search is more useful than starting a new one
    if (model.query.empty()) hints.push_back({"X", tr("Search"), tr("Clear")});
    else hints.push_back({"B", tr("Clear"), tr("Search")});
    hints.push_back({"SELECT", tr("Autolaunch")});
    if (model.hasSettings || builtinSettings()) hints.push_back({"START", tr("Settings")});
    return hints;
}

void LauncherScreen::renderEmpty(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    if (model.query.empty() && model.cur().name == kMyListName) {
        std::string s = tr("Your list is empty");
        std::string hint = tr("Press Y on any game to add it here");
        drawText(renderer, fonts.ui, s, (kScreenW - textWidth(fonts.ui, s)) / 2, kScreenH / 2 - 40, theme().muted);
        drawText(renderer, fonts.small, hint, (kScreenW - textWidth(fonts.small, hint)) / 2, kScreenH / 2, theme().muted);
        return;
    }
    std::string s = model.query.empty() ? tr("Nothing here") : tr("No matches for") + std::string(" \"") + model.query + "\"";
    int w = textWidth(fonts.ui, s);
    drawText(renderer, fonts.ui, s, std::max(kMargin, (kScreenW - w) / 2), kScreenH / 2 - 40, theme().muted, kScreenW - 2 * kMargin);
    if (!model.query.empty()) {
        std::string hint = tr("L1/R1 to search other tabs");
        drawText(renderer, fonts.small, hint, (kScreenW - textWidth(fonts.small, hint)) / 2, kScreenH / 2, theme().muted);
    }
}

void LauncherScreen::renderGrid(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const Category& c = model.cur();
    int selRow = c.sel / kGridCols;
    if (selRow < c.scroll) c.scroll = selRow;
    if (selRow >= c.scroll + kGridFullRows) c.scroll = selRow - kGridFullRows + 1;

    const int totalW = kGridCols * kCellWidth + (kGridCols - 1) * kGridGap;
    const int x0 = (kScreenW - totalW) / 2;
    for (int k = c.scroll * kGridCols; k < (int)c.visible.size(); ++k) {
        int row = k / kGridCols - c.scroll;
        if (row > kGridFullRows) break;    // one extra, partly hidden row hints that the list goes on
        int col = k % kGridCols;
        SDL_Rect cell{x0 + col * (kCellWidth + kGridGap), gridTop(model.showTabs) + row * kGridPitchY, kCellWidth, kCellHeight};
        ui.drawIcon(ui.gridIcons(), c.entries[c.visible[k]].iconPath, cell);
        if (k == c.sel) ui.frame(accent(), cell, kBorder);
        const Entry& entry = c.entries[c.visible[k]];
        int pillX = cell.x;    // the system tag top left, clear of the cover's title art at the bottom
        if (c.mixed) pillX += ui.pill(entry.tag, cell.x, cell.y, theme().bar, theme().muted);
        if (model.isAutoStart(entry)) ui.pill(tr("autolaunch"), pillX, cell.y, accent(), theme().ink);
        if (model.isFavorite(entry)) {    // a bigger dark star underneath outlines it on any cover
            ui.star(cell.x + cell.w - 16, cell.y + 16, 13, theme().ink);
            ui.star(cell.x + cell.w - 16, cell.y + 16, 9, accent());
        }
    }

    const Entry* e = model.selected();
    if (!e) return;
    const int bottom = kScreenH - kFooterH;
    const int textW = kScreenW - 2 * kMargin;
    const std::string sub = e->meta.empty() ? tr(e->description) : e->meta;
    int descH = sub.empty() ? 0 : TTF_FontHeight(fonts.desc);
    int titleH = TTF_FontHeight(fonts.title);
    int textTop = bottom - 8 - descH - titleH;
    ui.gradient({0, textTop - 70, kScreenW, 70}, theme().bg);
    ui.fill(theme().bg, {0, textTop, kScreenW, bottom - textTop});
    int titleW = textW;
    const std::string played = playedText(*e, false);
    if (!played.empty()) {
        const int w = textWidth(fonts.small, played);
        drawText(renderer, fonts.small, played, kScreenW - kMargin - w,
                 textTop + TTF_FontAscent(fonts.title) - TTF_FontAscent(fonts.small), theme().muted);
        titleW -= w + 12;
    }
    drawText(renderer, fonts.title, e->name, kMargin, textTop, theme().text, titleW);
    drawText(renderer, fonts.desc, sub, kMargin, textTop + titleH, theme().muted, textW);
}

void LauncherScreen::renderList(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const Category& c = model.cur();
    const int rows = listRows(model.showTabs), top = listTop(model.showTabs);
    renderRows(ui, kListWidth);

    // Scrollbar, only when the tab doesn't fit on one screen
    int total = (int)c.visible.size();
    if (total > rows) {
        SDL_Rect track{kMargin + kListWidth + 4, top, 4, rows * kListRowH - 2};
        ui.track(track, theme().tile);
        int thumbH = std::max(16, track.h * rows / total);
        int thumbY = track.y + (track.h - thumbH) * c.scroll / std::max(1, total - rows);
        ui.track({track.x, thumbY, track.w, thumbH}, theme().muted);
    }

    const Entry* e = model.selected();
    if (!e) return;
    SDL_Rect box{kPreviewX, top, kPreviewW, kPreviewH};
    ui.drawIcon(ui.previewIcons(), e->iconPath, box);
    int y = box.y + box.h + 10;
    y += ui.drawWrapped(fonts.ui, e->name, kPreviewX, y, theme().text, kPreviewW) + 4;
    if (!e->meta.empty()) {
        drawText(renderer, fonts.small, e->meta, kPreviewX, y, accent(), kPreviewW);
        y += TTF_FontLineSkip(fonts.small) + 4;
    }
    const std::string played = playedText(*e, true);
    if (!played.empty()) {
        drawText(renderer, fonts.small, played, kPreviewX, y, theme().text, kPreviewW);
        y += TTF_FontLineSkip(fonts.small) + 4;
    }
    const int textBottom = kScreenH - kFooterH - TTF_FontHeight(fonts.small) - 10;   // above the "n / total"
    descMax = ui.drawWrappedClipped(fonts.small, e->synopsis.empty() ? tr(e->description) : e->synopsis,
                                 kPreviewX, y, theme().muted, kPreviewW - 16, textBottom - y, model.descScroll);

    std::string pos = std::to_string(c.sel + 1) + " / " + std::to_string(total);
    drawText(renderer, fonts.small, pos, kScreenW - kMargin - textWidth(fonts.small, pos),
             kScreenH - kFooterH - TTF_FontHeight(fonts.small) - 6, theme().muted);
}

// The list's rows, width wide from the left margin
void LauncherScreen::renderRows(Ui& ui, int width) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const Category& c = model.cur();
    if (c.sel < c.scroll) c.scroll = c.sel;
    const int rows = listRows(model.showTabs), top = listTop(model.showTabs);
    if (c.sel >= c.scroll + rows) c.scroll = c.sel - rows + 1;

    // Rows are laid out in columns, like a table: [star] name ... [auto] [system]. The star has a
    // fixed slot before the name, and the system column is as wide as the widest tag in the tab,
    // with the tags at its left edge, so both line up from row to row.
    const int fontH = TTF_FontHeight(fonts.desc);
    const int starW = 20;
    if (c.mixed && c.tagColumn < 0) {
        c.tagColumn = 0;
        for (const Entry& e : c.entries) c.tagColumn = std::max(c.tagColumn, ui.pillWidth(e.tag));
    }
    const int tagColW = c.mixed ? c.tagColumn : 0;
    for (int row = 0; row < rows && c.scroll + row < (int)c.visible.size(); ++row) {
        int k = c.scroll + row;
        const Entry& e = c.entries[c.visible[k]];
        SDL_Rect r{kMargin, top + row * kListRowH, width, kListRowH - 2};
        const SDL_Color nameColor = k == c.sel ? ui.selection(r, true) : theme().item;
        const int tagY = r.y + (r.h - TTF_FontHeight(fonts.small) - 4) / 2;
        const int nameX = r.x + 12 + starW;
        int right = r.x + r.w - 4;      // the name ends before this
        if (c.mixed) {
            right -= tagColW;
            ui.pill(e.tag, right, tagY, theme().tile, theme().muted);
            right -= 8;
        }
        if (model.isAutoStart(e)) {
            right -= ui.pillWidth(tr("auto"));
            ui.pill(tr("auto"), right, tagY, ui.accentOn(k == c.sel), k == c.sel && theme().showcase ? accent() : theme().ink);
            right -= 8;
        }
        if (model.isFavorite(e)) ui.star(r.x + 12 + starW / 2, r.y + r.h / 2, 7, ui.accentOn(k == c.sel));
        int scrollX = 0;
        if (k == c.sel) {
            const int overflow = textWidth(fonts.desc, e.name) - (right - nameX);
            if (overflow > 0) scrollX = ui.marqueeOffset(c.name + "\x1f" + e.category + "\x1f" + e.id, overflow);
        }
        drawText(renderer, fonts.desc, e.name, nameX, r.y + (r.h - fontH) / 2, nameColor,
                 right - nameX, scrollX);
    }
}

// The Showcase style's list (Shelf): the rows, an A-Z rail on the right, and between them the picture
// over the game's name, system, data, play time and description.
void LauncherScreen::renderShelf(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const Category& c = model.cur();
    const int top = listTop(model.showTabs);
    renderRows(ui, kShelfListW);
    const Entry* e = model.selected();
    if (!e) return;

    // The rail lights the selected game's letter, in the tabs sorted by name
    if (c.name != kMyListName && c.name != kRecentName && c.name != kMostPlayedName) {
        const char* letters = "#ABCDEFGHIJKLMNOPQRSTUVWXYZ";
        char cur = e->name.empty() ? '#' : (char)std::toupper((unsigned char)e->name[0]);
        if (cur < 'A' || cur > 'Z') cur = '#';
        const int step = (kScreenH - kFooterH - 8 - top) / 27, cx = kScreenW - kMargin - 10;
        const int h = TTF_FontHeight(fonts.keyBold);
        for (int i = 0; i < 27; ++i) {
            const std::string l(1, letters[i]);
            const int cy = top + i * step + step / 2;
            if (letters[i] == cur) ui.roundRect({cx - 8, cy - 7, 16, 14}, 4, accent());
            drawText(renderer, fonts.keyBold, l, cx - textWidth(fonts.keyBold, l) / 2, cy - h / 2,
                     letters[i] == cur ? theme().ink : theme().dim);
        }
    }

    const int x = kShelfCardX, w = kPreviewW;
    const SDL_Rect box = trailerBox();
    ui.roundRect(box, 10, theme().tile);
    if (!ui.drawFrame(trailer.frame(), box)) ui.drawIcon(ui.previewIcons(), e->iconPath, box);
    ui.roundCorners(box, 10, theme().bg);
    int y = box.y + box.h + 10;
    y += ui.drawWrapped(fonts.uiBold, e->name, x, y, theme().text, w);
    drawText(renderer, fonts.small, c.mixed ? e->tag : tr(c.label), x, y, theme().muted, w);
    y += TTF_FontLineSkip(fonts.small) + 6;
    if (!e->meta.empty()) {
        drawText(renderer, fonts.small, e->meta, x, y, theme().text, w);
        y += TTF_FontLineSkip(fonts.small);
    }
    const std::string played = playedText(*e, true);
    if (!played.empty()) {
        drawText(renderer, fonts.small, played, x, y, theme().text, w);
        y += TTF_FontLineSkip(fonts.small);
    }
    const std::string pos = std::to_string(c.sel + 1) + " / " + std::to_string(c.visible.size());
    const int posY = kScreenH - kFooterH - TTF_FontHeight(fonts.small) - 6;
    descMax = ui.drawWrappedClipped(fonts.small, e->synopsis.empty() ? tr(e->description) : e->synopsis,
                                 x, y + 6, theme().muted, w - 16, posY - 4 - (y + 6), model.descScroll);
    drawText(renderer, fonts.small, pos, x + w - textWidth(fonts.small, pos), posY, theme().dim);
}

// The Showcase style's grid (Streaming): the selected game's picture fading into the screen behind its
// name and data, and under them the current tab's row of covers with the next tab's below it.
void LauncherScreen::renderStreaming(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const Entry* e = model.selected();
    if (e) {
        SDL_Rect clip{0, 0, kScreenW, kRowsTop + kRowLabelH};   // beside the row's name, down to its covers
        SDL_RenderSetClipRect(renderer, &clip);
        const SDL_Rect hero = trailerBox();
        if (ui.drawFrame(trailer.frame(), hero) || ui.drawCover(ui.heroIcons(), e->iconPath, hero)) {
            ui.shade({hero.x, kHeaderH, kHeroW, 24}, theme().bg, kBarShade, 0);   // the top bar's shade, so its edge doesn't show
            ui.sideGradient({hero.x, hero.y, kHeroFadeW, kHeroH}, theme().bg);
            ui.gradient({hero.x, hero.y + hero.h - kHeroFadeH, kHeroW, kHeroFadeH}, theme().bg);
        }
        SDL_RenderSetClipRect(renderer, nullptr);

        const int x = kMargin, w = 300;
        int y = kHeaderH + 2;
        y += ui.drawWrapped(fonts.titleBold ? fonts.titleBold : fonts.title, e->name, x, y, theme().text, w) + 2;
        if (!e->meta.empty()) {
            drawText(renderer, fonts.small, e->meta, x, y, theme().muted, w);
            y += TTF_FontLineSkip(fonts.small);
        }
        const std::string played = playedText(*e, true);
        if (!played.empty()) {
            drawText(renderer, fonts.small, played, x, y, theme().text, w);
            y += TTF_FontLineSkip(fonts.small);
        }
        descMax = ui.drawWrappedClipped(fonts.small, e->synopsis.empty() ? tr(e->description) : e->synopsis,
                                     x, y + 6, theme().muted, w - 16, kRowsTop - 8 - (y + 6), model.descScroll);
    } else {
        renderEmpty(ui);
    }
    renderRow(ui, model.tab, kRowsTop, true);
    const int next = model.neighbour(1);
    if (next > model.tab) renderRow(ui, next, kRowsTop + kRowPitch, false);
}

// A tab's name and its covers from the first one on screen, which keeps the tab's selection in view;
// the current tab's selection is framed.
void LauncherScreen::renderRow(Ui& ui, int tab, int y, bool current) {
    const Fonts& fonts = ui.font();
    const Category& c = model.categories[tab];
    drawText(ui.sdl(), fonts.smallBold ? fonts.smallBold : fonts.small, tr(c.label), kMargin, y,
             current ? theme().text : theme().muted, kScreenW - 2 * kMargin);
    const int pitch = kCardW + kCardGap, full = (kScreenW - kMargin) / pitch;
    if (c.sel < c.scroll) c.scroll = c.sel;
    if (c.sel >= c.scroll + full) c.scroll = c.sel - full + 1;
    if (c.visible.empty()) {    // the current tab says so above its row
        if (!current) drawText(ui.sdl(), fonts.small, tr("Nothing here"), kMargin, y + kRowLabelH + 4, theme().dim);
        return;
    }
    for (int k = c.scroll; k < (int)c.visible.size(); ++k) {
        SDL_Rect card{kMargin + (k - c.scroll) * pitch, y + kRowLabelH, kCardW, kCardH};
        if (card.x >= kScreenW) break;
        const bool sel = current && k == c.sel;
        if (sel) ui.roundRect({card.x - 3, card.y - 3, card.w + 6, card.h + 6}, 11, accent());
        ui.roundRect(card, 8, theme().tile);
        const Entry& entry = c.entries[c.visible[k]];
        ui.drawIcon(ui.cardIcons(), entry.iconPath, card);
        ui.roundCorners(card, 8, sel ? accent() : theme().bg);
        int pillX = card.x + 4;
        if (c.mixed) pillX += ui.pill(entry.tag, pillX, card.y + 4, theme().bar, theme().muted) + 4;
        if (model.isAutoStart(entry)) ui.pill(tr("autolaunch"), pillX, card.y + 4, accent(), theme().ink);
        if (model.isFavorite(entry)) {
            ui.star(card.x + card.w - 16, card.y + 16, 13, theme().ink);
            ui.star(card.x + card.w - 16, card.y + 16, 9, accent());
        }
    }
}

// Strip with the neighbouring tabs around the current one (L1/R1 are listed in the footer hints).
void LauncherScreen::renderTabs(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const int top = kHeaderH;
    ui.fill(theme().bg, {0, top, kScreenW, kTabsH});
    ui.fill(theme().tile, {0, top + kTabsH - 1, kScreenW, 1});
    const int pillH = TTF_FontHeight(fonts.small) + 4;
    const int pillY = top + (kTabsH - pillH) / 2;

    // Arrows at the ends, as the tabs wrap around in both directions; the Showcase style shows L1 and R1
    const bool showcase = theme().showcase;
    const int endW = showcase ? ui.keyWidth("L1") : 12;
    if (showcase) {
        ui.keyGlyph("L1", kMargin, top + kTabsH / 2, theme().bg);
        ui.keyGlyph("R1", kScreenW - kMargin - endW, top + kTabsH / 2, theme().bg);
    } else {
        ui.sideTriangle(kMargin + 4, top + kTabsH / 2, 4, true, theme().muted);
        ui.sideTriangle(kScreenW - kMargin - 4, top + kTabsH / 2, 4, false, theme().muted);
    }
    const int left = kMargin + endW + 6, right = kScreenW - kMargin - endW - 6;

    // The ring holds the tabs that aren't hidden (System Settings -> Launcher tabs)
    std::vector<int> order;
    for (int t = 0; t < (int)model.categories.size(); ++t)
        if (!model.categories[t].hidden || t == model.tab) order.push_back(t);
    const int n = (int)order.size();
    int pos = 0;
    for (int i = 0; i < n; ++i)
        if (order[i] == model.tab) pos = i;
    auto at = [&](int i) { return order[((pos + i) % n + n) % n]; };   // i tabs right of the current one

    // Slots of the same width: the current tab in the middle one, under a fixed highlight
    const int slots = 5, slotW = (right - left) / slots, pad = 8;
    const int cx = (left + right) / 2;
    ui.tabHighlight({cx - slotW / 2, pillY - 2, slotW, pillH + 4});

    // Slide: the strip moves one slot and eases back, so the new tab glides into the highlight
    if (lastTab >= 0 && lastTab != model.tab && lastTab < (int)model.categories.size()) {
        int dir = at(-1) == lastTab ? 1 : (at(1) == lastTab ? -1 : 0);
        tabOffset += dir * slotW;
    }
    lastTab = model.tab;

    // A ring: neighbours wrap around, so while sliding a tab can leave on one side and come back on
    // the other. With fewer tabs than slots each one is drawn once.
    SDL_Rect clip{left, top, right - left, kTabsH};
    SDL_RenderSetClipRect(renderer, &clip);
    const int reach = slots / 2 + 1 + (int)std::ceil(std::fabs(tabOffset) / slotW);
    for (int k = -reach; k <= reach; ++k) {
        if (n < slots && (k < -(n - 1) / 2 || k > n / 2)) continue;
        const int t = at(k);
        TTF_Font* f = showcase && k == 0 ? fonts.smallBold : fonts.small;
        const std::string label = elided(f, tr(model.categories[t].label), slotW - 2 * pad);
        const int x = cx + k * slotW + (int)std::lround(tabOffset) - textWidth(f, label) / 2;
        drawText(renderer, f, label, x, pillY + 2, k == 0 ? theme().text : theme().muted);
    }
    SDL_RenderSetClipRect(renderer, nullptr);

    tabOffset *= 0.6f;
    if (std::fabs(tabOffset) < 0.5f) tabOffset = 0.0f;
}
