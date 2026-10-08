#include "launcher.h"

#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>

#include "config.h"
#include "system/device.h"
#include "layout.h"
#include "library.h"
#include "overlays.h"
#include "util.h"

LauncherScreen::LauncherScreen(App& app, Model model) : Screen(app), model(std::move(model)) {}

void LauncherScreen::onAction(Action a) {
    const bool grid = model.view == View::Grid;

    if (a == Action::GameMenu) {   // L2 + R2: rename or delete the selected game
        openGameMenu();
        return;
    }
    if (a == Action::Power) {
        // with the screen off, toggle-screen.sh turns it back on; don't open a menu in the dark
        if (screenOn()) openPowerMenu();
        return;
    }
    if (a == Action::Start) {
        if (model.hasSettings) {
            if (!launch(model, model.settings)) app.quit();
            return;
        }
        // no settings app (e.g. on other firmwares, where POWER may suspend): START opens the menu
        openPowerMenu();
        return;
    }

    switch (a) {
        case Action::PrevTab: model.switchTab(-1); break;
        case Action::NextTab: model.switchTab(1);  break;
        case Action::Up:    model.moveSel(grid ? -kGridCols : -1); break;
        case Action::Down:  model.moveSel(grid ? kGridCols : 1);   break;
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
                if (!launch(model, *e)) app.quit();
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
    } else if (a == Action::Power && screenOn() && !powerItems(model).empty()) {
        k.close(false);
        openPowerMenu();
    }
}

void LauncherScreen::openGameMenu() {
    const Entry* e = model.selected();
    if (!e || e->file.empty()) return;
    const Entry entry = *e;
    app.push(std::make_unique<DialogScreen>(app, "Game options", entry.name, std::vector<std::string>{"Rename", "Move to trash"},
                                            bodyTop(model.showTabs), [this, entry](int choice) {
        if (choice == 0) openRename(entry);
        else confirmTrash(entry);
    }));
}

void LauncherScreen::confirmTrash(const Entry& e) {
    app.push(std::make_unique<DialogScreen>(app, "Move this game to the trash?", e.name,
                                            std::vector<std::string>{"Cancel", "Move to trash"},
                                            bodyTop(model.showTabs), [this, e](int choice) {
        if (choice == 1) app.notice(deleteEntry(model, e));
    }));
}

bool LauncherScreen::openPowerMenu() {
    const std::vector<PowerItem> items = powerItems(model);
    if (items.empty()) return false;
    std::vector<std::string> labels;
    for (const PowerItem& item : items) labels.push_back(item.label);
    app.push(std::make_unique<DialogScreen>(app, "Power options", "", labels, bodyTop(model.showTabs),
                                            [this, items](int choice) { runPowerItem(items[choice]); }));
    return true;
}

void LauncherScreen::runPowerItem(const PowerItem& item) {
    if (item.quit) {
        app.quit();
        return;
    }
    if (item.command && !item.command->empty()) {
        if (item.status) app.push(std::make_unique<StatusScreen>(app, tr(item.status)));
        runDetached(*item.command);
        return;
    }
    if (item.confirmEntry) {
        auto confirm = std::find_if(model.systemEntries.begin(), model.systemEntries.end(),
                                    [&](const Entry& e) { return e.name == item.confirmEntry; });
        if (confirm != model.systemEntries.end()) {
            if (!launch(model, *confirm)) app.quit();
            return;
        }
    }
    if (item.status) app.push(std::make_unique<StatusScreen>(app, tr(item.status)));
    if (item.request) sendPowerRequest(item.request);
}

void LauncherScreen::render(Ui& ui) {
    if (model.cur().visible.empty()) renderEmpty(ui);
    else if (model.view == View::Grid) renderGrid(ui);
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
    return {tr(c.name), count, !model.query.empty()};
}

Hints LauncherScreen::hints() const {
    const Entry* sel = model.selected();
    Hints hints = {{"L1", tr("Prev")}, {"R1", tr("Next")}, {"A", tr("Launch")},
                   {"Y", tr(sel && model.isFavorite(*sel) ? "Remove" : "My List")}};
    // while searching, clearing the search is more useful than starting a new one
    if (model.query.empty()) hints.push_back({"X", tr("Search")});
    else hints.push_back({"B", tr("Clear")});
    hints.push_back({"SELECT", tr("Autolaunch")});
    if (model.hasSettings) hints.push_back({"START", tr("Settings")});
    return hints;
}

void LauncherScreen::renderEmpty(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    if (model.query.empty() && model.cur().name == kMyListName) {
        std::string s = tr("Your list is empty");
        std::string hint = tr("Press Y on any game to add it here");
        drawText(renderer, fonts.ui, s, (kScreenW - textWidth(fonts.ui, s)) / 2, kScreenH / 2 - 40, kGrey);
        drawText(renderer, fonts.small, hint, (kScreenW - textWidth(fonts.small, hint)) / 2, kScreenH / 2, kGrey);
        return;
    }
    std::string s = model.query.empty() ? tr("Nothing here") : tr("No matches for") + std::string(" \"") + model.query + "\"";
    int w = textWidth(fonts.ui, s);
    drawText(renderer, fonts.ui, s, std::max(kMargin, (kScreenW - w) / 2), kScreenH / 2 - 40, kGrey, kScreenW - 2 * kMargin);
    if (!model.query.empty()) {
        std::string hint = tr("L1/R1 to search other tabs");
        drawText(renderer, fonts.small, hint, (kScreenW - textWidth(fonts.small, hint)) / 2, kScreenH / 2, kGrey);
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
        if (k == c.sel) ui.frame(kYellow, cell, kBorder);
        const Entry& entry = c.entries[c.visible[k]];
        if (model.isAutoStart(entry)) ui.pill(tr("autolaunch"), cell.x, cell.y, kYellow, kBlack);
        if (model.isFavorite(entry)) {
            ui.fill(kBar, {cell.x + cell.w - 26, cell.y + 2, 24, 24});
            ui.star(cell.x + cell.w - 14, cell.y + 14, 9, kYellow);
        }
        if (c.mixed) {
            int w = textWidth(fonts.small, entry.tag) + 12;
            ui.pill(entry.tag, cell.x + cell.w - w, cell.y + cell.h - TTF_FontHeight(fonts.small) - 4, kBar, kGrey);
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
    ui.gradient({0, textTop - 70, kScreenW, 70}, kClear);
    ui.fill(kClear, {0, textTop, kScreenW, bottom - textTop});
    drawText(renderer, fonts.title, e->name, kMargin, textTop, kWhite, textW);
    drawText(renderer, fonts.desc, sub, kMargin, textTop + titleH, kGrey, textW);
}

void LauncherScreen::renderList(Ui& ui) {
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
        SDL_Rect r{kMargin, top + row * kListRowH, kListWidth, kListRowH - 2};
        if (k == c.sel) {
            ui.fill(kRowSel, r);
            ui.fill(kYellow, {r.x, r.y, 4, r.h});
        }
        const int tagY = r.y + (r.h - TTF_FontHeight(fonts.small) - 4) / 2;
        const int nameX = r.x + 12 + starW;
        int right = r.x + r.w - 4;      // the name ends before this
        if (c.mixed) {
            right -= tagColW;
            ui.pill(e.tag, right, tagY, kTile, kGrey);
            right -= 8;
        }
        if (model.isAutoStart(e)) {
            right -= ui.pillWidth(tr("auto"));
            ui.pill(tr("auto"), right, tagY, kYellow, kBlack);
            right -= 8;
        }
        if (model.isFavorite(e)) ui.star(r.x + 12 + starW / 2, r.y + r.h / 2, 7, kYellow);
        int scrollX = 0;
        if (k == c.sel) {
            const int overflow = textWidth(fonts.desc, e.name) - (right - nameX);
            if (overflow > 0) scrollX = ui.marqueeOffset(c.name + "\x1f" + e.category + "\x1f" + e.id, overflow);
        }
        drawText(renderer, fonts.desc, e.name, nameX, r.y + (r.h - fontH) / 2, k == c.sel ? kWhite : kGrey,
                 right - nameX, scrollX);
    }

    // Scrollbar, only when the tab doesn't fit on one screen
    int total = (int)c.visible.size();
    if (total > rows) {
        SDL_Rect track{kMargin + kListWidth + 4, top, 4, rows * kListRowH - 2};
        ui.fill(kTile, track);
        int thumbH = std::max(16, track.h * rows / total);
        int thumbY = track.y + (track.h - thumbH) * c.scroll / std::max(1, total - rows);
        ui.fill(kGrey, {track.x, thumbY, track.w, thumbH});
    }

    const Entry* e = model.selected();
    if (!e) return;
    SDL_Rect box{kPreviewX, top, kPreviewW, kPreviewH};
    ui.drawIcon(ui.previewIcons(), e->iconPath, box);
    int y = box.y + box.h + 10;
    y += ui.drawWrapped(fonts.ui, e->name, kPreviewX, y, kWhite, kPreviewW) + 4;
    if (!e->meta.empty()) {
        drawText(renderer, fonts.small, e->meta, kPreviewX, y, kYellow, kPreviewW);
        y += TTF_FontLineSkip(fonts.small) + 4;
    }
    const int textBottom = kScreenH - kFooterH - TTF_FontHeight(fonts.small) - 10;   // above the "n / total"
    descMax = ui.drawWrappedClipped(fonts.small, e->synopsis.empty() ? tr(e->description) : e->synopsis,
                                 kPreviewX, y, kGrey, kPreviewW - 16, textBottom - y, model.descScroll);

    std::string pos = std::to_string(c.sel + 1) + " / " + std::to_string(total);
    drawText(renderer, fonts.small, pos, kScreenW - kMargin - textWidth(fonts.small, pos),
             kScreenH - kFooterH - TTF_FontHeight(fonts.small) - 6, kGrey);
}

// Strip with the neighbouring tabs around the current one (L1/R1 are listed in the footer hints).
void LauncherScreen::renderTabs(Ui& ui) {
    SDL_Renderer* renderer = ui.sdl();
    const Fonts& fonts = ui.font();
    const int top = kHeaderH;
    ui.fill(kClear, {0, top, kScreenW, kTabsH});
    ui.fill(kTile, {0, top + kTabsH - 1, kScreenW, 1});
    const int pillH = TTF_FontHeight(fonts.small) + 4;
    const int pillY = top + (kTabsH - pillH) / 2;

    // Arrows at the ends: the tabs wrap around in both directions
    const int arrowW = 12;
    ui.sideTriangle(kMargin + 4, top + kTabsH / 2, 4, true, kGrey);
    ui.sideTriangle(kScreenW - kMargin - 4, top + kTabsH / 2, 4, false, kGrey);
    const int left = kMargin + arrowW + 6, right = kScreenW - kMargin - arrowW - 6;

    // The ring holds the tabs that aren't hidden (System Settings -> Launcher tabs)
    std::vector<int> order;
    for (int t = 0; t < (int)model.categories.size(); ++t)
        if (!model.categories[t].hidden || t == model.tab) order.push_back(t);
    const int n = (int)order.size();
    int pos = 0;
    for (int i = 0; i < n; ++i)
        if (order[i] == model.tab) pos = i;
    auto at = [&](int i) { return order[((pos + i) % n + n) % n]; };   // i tabs right of the current one
    const int gap = 18, pad = 8;
    auto width = [&](int t) { return textWidth(fonts.small, tr(model.categories[t].label)) + 2 * pad; };

    // Slide: start the new tab where it was drawn before the switch and ease it to the centre
    if (lastTab >= 0 && lastTab != model.tab && lastTab < (int)model.categories.size()) {
        int dir = at(-1) == lastTab ? 1 : (at(1) == lastTab ? -1 : 0);
        tabOffset += dir * (width(lastTab) / 2.0f + gap + width(model.tab) / 2.0f);
    }
    lastTab = model.tab;

    auto drawTab = [&](int t, int x) {
        int w = width(t);
        if (t == model.tab) {
            ui.fill(kRowSel, {x, pillY - 2, w, pillH + 4});
            ui.fill(kYellow, {x, pillY + pillH + 1, w, 2});
            drawText(renderer, fonts.small, tr(model.categories[t].label), x + pad, pillY + 2, kWhite);
        } else {
            drawText(renderer, fonts.small, tr(model.categories[t].label), x + pad, pillY + 2, kGrey);
        }
    };

    // A ring: the current tab in the middle, neighbours on both sides wrapping around, each tab
    // drawn once. Tabs cut by the edges are clipped.
    SDL_Rect clip{left, top, right - left, kTabsH};
    SDL_RenderSetClipRect(renderer, &clip);
    const int cx = (left + right) / 2 + (int)std::lround(tabOffset);
    drawTab(model.tab, cx - width(model.tab) / 2);
    int xr = cx + (width(model.tab) + 1) / 2 + gap;
    int xl = cx - width(model.tab) / 2 - gap;
    int used = 1;
    for (int i = 1; used < n; ++i) {
        bool placed = false;
        if (xr < right && used < n) {
            int t = at(i);
            drawTab(t, xr);
            xr += width(t) + gap;
            ++used;
            placed = true;
        }
        if (xl > left && used < n) {
            int t = at(-i);
            xl -= width(t);
            drawTab(t, xl);
            xl -= gap;
            ++used;
            placed = true;
        }
        if (!placed) break;
    }
    SDL_RenderSetClipRect(renderer, nullptr);

    tabOffset *= 0.6f;
    if (std::fabs(tabOffset) < 0.5f) tabOffset = 0.0f;
}
