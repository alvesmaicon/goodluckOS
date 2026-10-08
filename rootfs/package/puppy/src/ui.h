#pragma once
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include <SDL2/SDL_ttf.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <iostream>
#include <map>
#include <memory>
#include <string>

#include "config.h"
#include "device.h"
#include "keyboard.h"
#include "layout.h"
#include "model.h"
#include "util.h"

// srcX skips that many pixels of the surface's left side (scrolling text).
static void drawSurface(SDL_Renderer* r, SDL_Surface* s, int x, int y, int maxW = 0, int srcX = 0) {
    SDL_Texture* t = SDL_CreateTextureFromSurface(r, s);
    if (!t) return;
    SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    srcX = std::clamp(srcX, 0, s->w);
    int w = (maxW > 0) ? std::min(s->w - srcX, maxW) : s->w - srcX;   // clip, don't squash
    SDL_Rect src{srcX, 0, w, s->h};
    SDL_Rect dst{x, y, w, s->h};
    SDL_RenderCopy(r, t, &src, &dst);
    SDL_DestroyTexture(t);
}

static void drawText(SDL_Renderer* r, TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int maxW = 0,
                     int scrollX = 0) {
    if (!font || text.empty()) return;
    SDL_Surface* s = TTF_RenderUTF8_Blended(font, text.c_str(), color);
    if (!s) return;
    drawSurface(r, s, x, y, maxW, scrollX);
    SDL_FreeSurface(s);
}

static int textWidth(TTF_Font* font, const std::string& text) {
    int w = 0, h = 0;
    if (font && !text.empty()) TTF_SizeUTF8(font, text.c_str(), &w, &h);
    return w;
}

class IconCache {
public:
    struct Icon {
        SDL_Texture* tex = nullptr;
        int w = 0, h = 0;
    };

    // Images larger than boxW x boxH are scaled down: cropped to cover the box, or with 'fit' shrunk
    // to fit inside it. Smaller images are kept at their size. Scaled images are saved in
    // cfg.thumbDir(), so big covers (e.g. 800x600 scraper images) are only decoded and scaled once.
    IconCache(SDL_Renderer* r, const std::string& fallbackPath, int boxW, int boxH, bool fit)
        : renderer(r), boxW(boxW), boxH(boxH), fit(fit) {
        fallback = load(fallbackPath);
        if (!fallback.tex) std::cerr << "Warning: missing fallback icon: " << fallbackPath << "\n";
    }

    ~IconCache() {
        for (auto& [path, slot] : slots) if (slot.icon.tex) SDL_DestroyTexture(slot.icon.tex);
        if (fallback.tex) SDL_DestroyTexture(fallback.tex);
    }

    IconCache(const IconCache&) = delete;
    IconCache& operator=(const IconCache&) = delete;

    Icon get(const std::string& path) {
        if (path.empty()) return fallback;

        auto it = slots.find(path);
        if (it != slots.end()) {
            it->second.lastUsed = ++clock;
            return it->second.icon.tex ? it->second.icon : fallback;
        }

        if (slots.size() >= kMaxCachedIcons) evictOldest();

        Slot slot;
        slot.icon = load(path);
        slot.lastUsed = ++clock;
        slots[path] = slot;
        return slot.icon.tex ? slot.icon : fallback;
    }

private:
    struct Slot {
        Icon icon;
        uint64_t lastUsed = 0;
    };

    SDL_Renderer* renderer;
    int boxW, boxH;
    bool fit;
    Icon fallback;
    std::map<std::string, Slot> slots;
    uint64_t clock = 0;

    // Name of the scaled copy of an image for this cache's box; changes when the image does.
    std::string thumbPath(const std::string& path) const {
        std::error_code ec;
        auto size = fs::file_size(path, ec);
        auto time = fs::last_write_time(path, ec).time_since_epoch().count();
        std::string key = path + "|" + std::to_string(size) + "|" + std::to_string(time) + "|" +
                          std::to_string(boxW) + "x" + std::to_string(boxH) + (fit ? "f" : "c");
        char name[32];
        snprintf(name, sizeof(name), "%016zx.png", std::hash<std::string>{}(key));
        return cfg.thumbDir() + "/" + name;
    }

    Icon load(const std::string& path) {
        Icon icon;
        const std::string thumb = thumbPath(path);
        bool fromThumb = true;
        SDL_Surface* loaded = IMG_Load(thumb.c_str());
        if (!loaded) {
            fromThumb = false;
            loaded = IMG_Load(path.c_str());
        }
        if (!loaded) return icon;
        SDL_Surface* src = SDL_ConvertSurfaceFormat(loaded, SDL_PIXELFORMAT_RGBA32, 0);
        SDL_FreeSurface(loaded);
        if (!src) return icon;

        SDL_Surface* result = src;

        if (src->w > boxW || src->h > boxH) {
            SDL_Rect crop{0, 0, src->w, src->h};
            int outW = boxW, outH = boxH;
            if (fit) {
                float scale = std::min((float)boxW / src->w, (float)boxH / src->h);
                outW = std::max(1, (int)std::lround(src->w * scale));
                outH = std::max(1, (int)std::lround(src->h * scale));
            } else {
                // Scale and crop so icons cover the cell if they're too large.
                float scale = std::max((float)boxW / src->w, (float)boxH / src->h);
                crop.w = std::min(src->w, (int)std::lround(boxW / scale));
                crop.h = std::min(src->h, (int)std::lround(boxH / scale));
                crop.x = (src->w - crop.w) / 2;
                crop.y = (src->h - crop.h) / 2;
            }

            SDL_Surface* out = SDL_CreateRGBSurfaceWithFormat(0, outW, outH, 32, SDL_PIXELFORMAT_RGBA32);
            if (!out) { SDL_FreeSurface(src); return icon; }

            SDL_SetSurfaceBlendMode(src, SDL_BLENDMODE_NONE);
            SDL_SoftStretchLinear(src, &crop, out, nullptr);
            SDL_FreeSurface(src);
            result = out;
            if (!fromThumb) {
                std::error_code ec;
                fs::create_directories(cfg.thumbDir(), ec);
                IMG_SavePNG(result, thumb.c_str());
            }
        }

        icon.w = result->w;
        icon.h = result->h;
        icon.tex = SDL_CreateTextureFromSurface(renderer, result);
        SDL_FreeSurface(result);
        if (icon.tex) SDL_SetTextureBlendMode(icon.tex, SDL_BLENDMODE_BLEND);
        return icon;
    }

    void evictOldest() {
        auto oldest = slots.begin();
        for (auto it = slots.begin(); it != slots.end(); ++it)
            if (it->second.lastUsed < oldest->second.lastUsed) oldest = it;
        if (oldest->second.icon.tex) SDL_DestroyTexture(oldest->second.icon.tex);
        slots.erase(oldest);
    }
};

class Ui {
public:
    Ui() {
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "linear");

        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
            std::cerr << "SDL_Init failed: " << SDL_GetError() << "\n";
            return;
        }
        sdlUp = true;
        IMG_Init(IMG_INIT_PNG | IMG_INIT_JPG);
        TTF_Init();

        window = SDL_CreateWindow("Puppy Launcher", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, kScreenW, kScreenH, 0);
        if (!window) { std::cerr << "SDL_CreateWindow failed: " << SDL_GetError() << "\n"; return; }

        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
        if (!renderer) { std::cerr << "SDL_CreateRenderer failed: " << SDL_GetError() << "\n"; return; }

        SDL_RenderSetLogicalSize(renderer, kScreenW, kScreenH);
        SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

        const char* font = cfg.font.c_str();
        auto size = [](int pt) { return (int)std::lround(pt * cfg.fontScale); };
        uiFont    = TTF_OpenFont(font, size(22));
        titleFont = TTF_OpenFont(font, size(30));
        descFont  = TTF_OpenFont(font, size(20));
        smallFont = TTF_OpenFont(font, size(15));
        if (!uiFont || !titleFont || !descFont || !smallFont)
            std::cerr << "Warning: could not load font " << cfg.font << "\n";

        gridIcons    = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kCellWidth, kCellHeight, false);
        previewIcons = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kPreviewW, kPreviewH, true);
        ok_ = true;
    }

    ~Ui() {
        gridIcons.reset();
        previewIcons.reset();
        if (clipTex) SDL_DestroyTexture(clipTex);
        for (TTF_Font* f : {uiFont, titleFont, descFont, smallFont}) if (f) TTF_CloseFont(f);
        if (renderer) SDL_DestroyRenderer(renderer);
        if (window) SDL_DestroyWindow(window);
        if (sdlUp) { TTF_Quit(); IMG_Quit(); SDL_Quit(); }
    }

    Ui(const Ui&) = delete;
    Ui& operator=(const Ui&) = delete;

    bool ok() const { return ok_; }
    bool animating() const { return tabOffset != 0.0f; }
    Uint32 marqueeDue() const { return marqueeNext; }   // when the scrolling name needs a frame (0: never)
    int descMaxScroll() const { return descMax; }   // of the description drawn in the last frame

    void render(const Model& m, const Keyboard& kb, int battery, const Audio& audio) {
        marqueeNext = 0;    // set again below if the selected name is still scrolling
        setColor(kClear);
        SDL_RenderClear(renderer);

        if (m.cur().visible.empty()) renderEmpty(m);
        else if (m.view == View::Grid) renderGrid(m);
        else renderList(m);

        // Bars are drawn last so long descriptions or scrolled tiles never spill over them
        renderHeader(m, battery, audio);
        renderFooter(m, kb);
        if (kb.open) renderKeyboard(m, kb);
        if (m.menuOpen) renderMenu(m);
        if (!m.status.empty()) renderStatus(m.status);
        if (!m.notice.empty()) renderNotice(m.notice);
        if (!marqueeNext) marqueeKey.clear();   // coming back to the same name starts it over

        SDL_RenderPresent(renderer);
    }

private:
    bool sdlUp = false, ok_ = false;
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    TTF_Font *uiFont = nullptr, *titleFont = nullptr, *descFont = nullptr, *smallFont = nullptr;
    std::unique_ptr<IconCache> gridIcons, previewIcons;
    SDL_Texture* clipTex = nullptr;     // drawWrappedClipped's last text
    std::string clipText;
    int clipWidth = 0, clipW = 0, clipH = 0;
    int descMax = 0;
    int lastTab = -1;           // tab drawn in the previous frame, to animate the strip
    float tabOffset = 0.0f;     // remaining slide of the tab strip, in pixels

    void setColor(SDL_Color c) { SDL_SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a); }

    void fill(SDL_Color c, const SDL_Rect& r) {
        setColor(c);
        SDL_RenderFillRect(renderer, &r);
    }

    void frame(SDL_Color c, const SDL_Rect& r, int t) {
        setColor(c);
        SDL_Rect strips[4] = {
            {r.x, r.y, r.w, t},                 // top
            {r.x, r.y + r.h - t, r.w, t},       // bottom
            {r.x, r.y, t, r.h},                 // left
            {r.x + r.w - t, r.y, t, r.h},       // right
        };
        SDL_RenderFillRects(renderer, strips, 4);
    }

    // Vertical fade from transparent (top) to the colour (bottom).
    void gradient(const SDL_Rect& r, SDL_Color c) {
        SDL_Vertex v[4];
        const float xs[2] = {(float)r.x, (float)(r.x + r.w)};
        const float ys[2] = {(float)r.y, (float)(r.y + r.h)};
        for (int i = 0; i < 4; ++i) {
            v[i].position = {xs[i % 2], ys[i / 2]};
            v[i].color = {c.r, c.g, c.b, (Uint8)(i < 2 ? 0 : 255)};
            v[i].tex_coord = {0, 0};
        }
        const int idx[6] = {0, 1, 2, 1, 3, 2};
        SDL_RenderGeometry(renderer, nullptr, v, 4, idx, 6);
    }

    // Filled five-pointed star centred on (cx, cy), the My List badge.
    void star(int cx, int cy, int r, SDL_Color c) {
        SDL_Vertex v[11];
        v[0].position = {(float)cx, (float)cy};
        for (int i = 0; i < 10; ++i) {
            float a = (float)M_PI * (-0.5f + i * 0.2f);
            float rad = (i % 2 == 0) ? r : r * 0.45f;
            v[i + 1].position = {cx + rad * std::cos(a), cy + rad * std::sin(a)};
        }
        int idx[30];
        for (int i = 0; i < 10; ++i) {
            idx[i * 3] = 0;
            idx[i * 3 + 1] = i + 1;
            idx[i * 3 + 2] = (i + 1) % 10 + 1;
        }
        for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
        SDL_RenderGeometry(renderer, nullptr, v, 11, idx, 30);
    }

    // Text on a rounded-looking label; returns its width.
    int pill(const std::string& text, int x, int y, SDL_Color bg, SDL_Color fg) {
        const int padX = 6, padY = 2;
        SDL_Rect r{x, y, textWidth(smallFont, text) + padX * 2, TTF_FontHeight(smallFont) + padY * 2};
        fill(bg, r);
        drawText(renderer, smallFont, text, x + padX, y + padY, fg);
        return r.w;
    }

    void drawIcon(IconCache& cache, const std::string& path, const SDL_Rect& box) {
        IconCache::Icon icon = cache.get(path);
        if (!icon.tex) return;
        SDL_Rect dst{box.x + (box.w - icon.w) / 2, box.y + (box.h - icon.h) / 2, icon.w, icon.h};
        SDL_RenderCopy(renderer, icon.tex, nullptr, &dst);
    }

    // Draws wrapped text and returns its height.
    int drawWrapped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width) {
        if (!font || text.empty()) return 0;
        SDL_Surface* s = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), color, width);
        if (!s) return 0;
        int h = s->h;
        drawSurface(renderer, s, x, y);
        SDL_FreeSurface(s);
        return h;
    }

    // Wrapped text cut to the whole lines that fit in maxH. The last texture is kept, since a long
    // synopsis is expensive to lay out again on every frame.
    // Returns how many lines it can scroll; scrollLines starts the text that many lines down.
    int drawWrappedClipped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width, int maxH,
                           int scrollLines = 0) {
        if (!font || text.empty() || maxH <= 0) return 0;
        if (text != clipText || width != clipWidth || !clipTex) {
            if (clipTex) SDL_DestroyTexture(clipTex);
            clipTex = nullptr;
            clipText = text;
            clipWidth = width;
            SDL_Surface* surf = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), color, width);
            if (!surf) return 0;
            clipTex = SDL_CreateTextureFromSurface(renderer, surf);
            clipW = surf->w;
            clipH = surf->h;
            SDL_FreeSurface(surf);
            if (!clipTex) return 0;
        }
        const int line = std::max(1, TTF_FontLineSkip(font));
        const int h = std::min(clipH, maxH / line * line);
        if (h <= 0) return 0;
        const int maxScroll = std::max(0, (clipH - h + line - 1) / line);
        const int scroll = std::clamp(scrollLines, 0, maxScroll);
        const int srcY = std::min(scroll * line, clipH - h);
        SDL_Rect src{0, srcY, clipW, h}, dst{x, y, clipW, h};
        SDL_RenderCopy(renderer, clipTex, &src, &dst);

        // Arrows just right of the text when there's more above / below (callers leave room for them)
        const int ax = x + width + 8;
        if (scroll > 0) triangle(ax, y + 5, 5, true, kYellow);
        if (scroll < maxScroll) triangle(ax, y + h - 5, 5, false, kYellow);
        return maxScroll;
    }

    void triangle(int cx, int cy, int r, bool up, SDL_Color c) {
        SDL_Vertex v[3];
        const float d = up ? -1.0f : 1.0f;
        v[0].position = {(float)cx, cy + d * r};
        v[1].position = {(float)(cx - r), cy - d * r};
        v[2].position = {(float)(cx + r), cy - d * r};
        for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
        SDL_RenderGeometry(renderer, nullptr, v, 3, nullptr, 0);
    }

    // Pointing left or right; drawn rather than a text arrow, which not every font has.
    void sideTriangle(int cx, int cy, int r, bool left, SDL_Color c) {
        SDL_Vertex v[3];
        const float d = left ? -1.0f : 1.0f;
        v[0].position = {cx + d * r, (float)cy};
        v[1].position = {cx - d * r, (float)(cy - r)};
        v[2].position = {cx - d * r, (float)(cy + r)};
        for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
        SDL_RenderGeometry(renderer, nullptr, v, 3, nullptr, 0);
    }

    int wrappedHeight(TTF_Font* font, const std::string& text, int width) {
        if (!font || text.empty()) return 0;
        SDL_Surface* s = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), kWhite, width);
        if (!s) return 0;
        int h = s->h;
        SDL_FreeSurface(s);
        return h;
    }

    // 16x16
    void speakerIcon(int x, int y, SDL_Color c, bool muted) {
        fill(c, {x, y + 5, 4, 6});
        for (int i = 0; i < 6; ++i) fill(c, {x + 4 + i, y + 5 - i, 1, 6 + 2 * i});
        if (muted) {
            setColor(c);
            for (int d = 0; d < 2; ++d) {
                SDL_RenderDrawLine(renderer, x + 11 + d, y + 4, x + 16 + d, y + 11);
                SDL_RenderDrawLine(renderer, x + 11 + d, y + 11, x + 16 + d, y + 4);
            }
        } else {
            fill(c, {x + 12, y + 5, 1, 6});
            fill(c, {x + 14, y + 3, 1, 10});
        }
    }

    // 24x12: green when full, yellow while charging, red at 10% or less
    void batteryIcon(int x, int y, int percent, bool charging, bool full) {
        frame(kGrey, {x, y, 22, 12}, 1);
        fill(kGrey, {x + 22, y + 3, 2, 6});
        const SDL_Color c = full || (charging && percent >= 100) ? kGreen
                          : charging ? kYellow : percent <= 10 ? kRed : kGrey;
        if (percent > 0) fill(c, {x + 2, y + 2, std::max(3, 18 * std::min(percent, 100) / 100), 8});
    }

    void headphonesIcon(int x, int y, SDL_Color c) {
        fill(c, {x + 4, y, 8, 2});
        fill(c, {x + 2, y + 1, 2, 2});
        fill(c, {x + 12, y + 1, 2, 2});
        fill(c, {x, y + 3, 2, 7});
        fill(c, {x + 14, y + 3, 2, 7});
        fill(c, {x, y + 9, 4, 7});
        fill(c, {x + 12, y + 9, 4, 7});
    }

    void renderHeader(const Model& m, int battery, const Audio& audio) {
        fill(kBar, {0, 0, kScreenW, kHeaderH});
        const Category& c = m.cur();
        const int nameY = (kHeaderH - TTF_FontHeight(uiFont)) / 2;

        const int statusY = (kHeaderH - TTF_FontHeight(smallFont)) / 2;
        std::string bat = battery >= 0 ? std::to_string(battery) + "%" : "??";
        int statusX = kScreenW - kMargin - textWidth(smallFont, bat);
        drawText(renderer, smallFont, bat, statusX, statusY, kGrey);
        statusX -= 28;
        batteryIcon(statusX, (kHeaderH - 12) / 2, battery, batteryCharging, batteryFull);

        if (audio.volume >= 0) {
            std::string vol = audio.muted ? tr("muted") : std::to_string(audio.volume) + "%";
            statusX -= 14 + textWidth(smallFont, vol);
            drawText(renderer, smallFont, vol, statusX, statusY, kGrey);
            statusX -= 22;
            if (audio.headphones) headphonesIcon(statusX, (kHeaderH - 16) / 2, kGrey);
            else speakerIcon(statusX, (kHeaderH - 16) / 2, kGrey, audio.muted);
        }
        if (!m.clock.empty()) {
            statusX -= 14 + textWidth(smallFont, m.clock);
            drawText(renderer, smallFont, m.clock, statusX, statusY, kGrey);
        }

        // "686 games", or "12 of 686 games" while searching
        std::string count = std::to_string(c.visible.size());
        if (!m.query.empty()) count += std::string(" ") + tr("of") + " " + std::to_string(c.entries.size());
        const bool one = c.entries.size() == 1;
        count += std::string(" ") + tr(c.media ? (one ? "item" : "items")
                                     : c.isArchive ? (one ? "game" : "games") : (one ? "app" : "apps"));
        if (!m.query.empty()) count += "  \u00b7  \"" + m.query + "\"";
        int countW = textWidth(smallFont, count);

        int maxNameW = statusX - 24 - countW - 10 - kMargin;
        const std::string title = tr(c.name);
        int nameW = std::min(textWidth(uiFont, title), maxNameW);
        drawText(renderer, uiFont, title, kMargin, nameY, kWhite, maxNameW);
        drawText(renderer, smallFont, count, kMargin + nameW + 10,
                 nameY + TTF_FontAscent(uiFont) - TTF_FontAscent(smallFont), m.query.empty() ? kGrey : kYellow);

        if (m.showTabs) renderTabs(m);
    }

    // Strip with the neighbouring tabs around the current one (L1/R1 are listed in the footer hints).
    void renderTabs(const Model& m) {
        const int top = kHeaderH;
        fill(kClear, {0, top, kScreenW, kTabsH});
        fill(kTile, {0, top + kTabsH - 1, kScreenW, 1});
        const int pillH = TTF_FontHeight(smallFont) + 4;
        const int pillY = top + (kTabsH - pillH) / 2;

        // Arrows at the ends: the tabs wrap around in both directions
        const int arrowW = 12;
        sideTriangle(kMargin + 4, top + kTabsH / 2, 4, true, kGrey);
        sideTriangle(kScreenW - kMargin - 4, top + kTabsH / 2, 4, false, kGrey);
        const int left = kMargin + arrowW + 6, right = kScreenW - kMargin - arrowW - 6;

        // The ring holds the tabs that aren't hidden (System Settings -> Launcher tabs)
        std::vector<int> order;
        for (int t = 0; t < (int)m.categories.size(); ++t)
            if (!m.categories[t].hidden || t == m.tab) order.push_back(t);
        const int n = (int)order.size();
        int pos = 0;
        for (int i = 0; i < n; ++i)
            if (order[i] == m.tab) pos = i;
        auto at = [&](int i) { return order[((pos + i) % n + n) % n]; };   // i tabs right of the current one
        const int gap = 18, pad = 8;
        auto width = [&](int t) { return textWidth(smallFont, tr(m.categories[t].label)) + 2 * pad; };

        // Slide: start the new tab where it was drawn before the switch and ease it to the centre
        if (lastTab >= 0 && lastTab != m.tab && lastTab < (int)m.categories.size()) {
            int dir = at(-1) == lastTab ? 1 : (at(1) == lastTab ? -1 : 0);
            tabOffset += dir * (width(lastTab) / 2.0f + gap + width(m.tab) / 2.0f);
        }
        lastTab = m.tab;

        auto drawTab = [&](int t, int x) {
            int w = width(t);
            if (t == m.tab) {
                fill(kRowSel, {x, pillY - 2, w, pillH + 4});
                fill(kYellow, {x, pillY + pillH + 1, w, 2});
                drawText(renderer, smallFont, tr(m.categories[t].label), x + pad, pillY + 2, kWhite);
            } else {
                drawText(renderer, smallFont, tr(m.categories[t].label), x + pad, pillY + 2, kGrey);
            }
        };

        // A ring: the current tab in the middle, neighbours on both sides wrapping around, each tab
        // drawn once. Tabs cut by the edges are clipped.
        SDL_Rect clip{left, top, right - left, kTabsH};
        SDL_RenderSetClipRect(renderer, &clip);
        const int cx = (left + right) / 2 + (int)std::lround(tabOffset);
        drawTab(m.tab, cx - width(m.tab) / 2);
        int xr = cx + (width(m.tab) + 1) / 2 + gap;
        int xl = cx - width(m.tab) / 2 - gap;
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

    void renderFooter(const Model& m, const Keyboard& kb) {
        const int top = kScreenH - kFooterH;
        fill(kBar, {0, top, kScreenW, kFooterH});

        std::vector<std::pair<std::string, std::string>> hints;
        if (m.menuOpen) {
            hints = {{"A", tr("Select")}, {"B", tr("Close")}};
        } else if (kb.open) {
            hints = {{"A", tr("Type")}, {"B", tr("Delete")}, {"START", tr("Done")}};
            if (m.renaming) {
                hints.insert(hints.begin(), {"L1/R1", tr("Cursor")});
                hints.push_back({"SELECT", tr("Cancel")});
            }
        } else {
            const Entry* sel = m.selected();
            hints = {{"L1", tr("Prev")}, {"R1", tr("Next")}, {"A", tr("Launch")},
                     {"Y", tr(sel && m.isFavorite(*sel) ? "Remove" : "My List")}};
            // while searching, clearing the search is more useful than starting a new one
            if (m.query.empty()) hints.push_back({"X", tr("Search")});
            else hints.push_back({"B", tr("Clear")});
            hints.push_back({"SELECT", tr("Autolaunch")});
            if (m.hasSettings) hints.push_back({"START", tr("Settings")});
        }

        // Button in the highlight colour, followed by what it does. The gap between hints shrinks
        // when they wouldn't fit on one line (e.g. "Y Remove" is wider than "Y My List").
        const int y = top + (kFooterH - TTF_FontHeight(smallFont)) / 2;
        const int keyGap = 6;
        int textW = 0;
        for (const auto& h : hints) textW += textWidth(smallFont, h.first) + keyGap + textWidth(smallFont, h.second);
        const int slots = std::max(1, (int)hints.size() - 1);
        const int gap = std::clamp((kScreenW - 2 * kMargin - textW) / slots, 4, 16);
        int x = kScreenW - kMargin;
        for (auto it = hints.rbegin(); it != hints.rend(); ++it) {
            x -= textWidth(smallFont, it->second);
            drawText(renderer, smallFont, it->second, x, y, kGrey);
            int keyW = textWidth(smallFont, it->first);
            x -= keyGap + keyW;
            drawText(renderer, smallFont, it->first, x, y, kYellow);
            x -= gap;
        }
    }

    void renderEmpty(const Model& m) {
        if (m.query.empty() && m.cur().name == kMyListName) {
            std::string s = tr("Your list is empty");
            std::string hint = tr("Press Y on any game to add it here");
            drawText(renderer, uiFont, s, (kScreenW - textWidth(uiFont, s)) / 2, kScreenH / 2 - 40, kGrey);
            drawText(renderer, smallFont, hint, (kScreenW - textWidth(smallFont, hint)) / 2, kScreenH / 2, kGrey);
            return;
        }
        std::string s = m.query.empty() ? tr("Nothing here") : tr("No matches for") + std::string(" \"") + m.query + "\"";
        int w = textWidth(uiFont, s);
        drawText(renderer, uiFont, s, std::max(kMargin, (kScreenW - w) / 2), kScreenH / 2 - 40, kGrey, kScreenW - 2 * kMargin);
        if (!m.query.empty()) {
            std::string hint = tr("L1/R1 to search other tabs");
            drawText(renderer, smallFont, hint, (kScreenW - textWidth(smallFont, hint)) / 2, kScreenH / 2, kGrey);
        }
    }

    void renderGrid(const Model& m) {
        const Category& c = m.cur();
        int selRow = c.sel / kGridCols;
        if (selRow < c.scroll) c.scroll = selRow;
        if (selRow >= c.scroll + kGridFullRows) c.scroll = selRow - kGridFullRows + 1;

        const int totalW = kGridCols * kCellWidth + (kGridCols - 1) * kGridGap;
        const int x0 = (kScreenW - totalW) / 2;
        for (int k = c.scroll * kGridCols; k < (int)c.visible.size(); ++k) {
            int row = k / kGridCols - c.scroll;
            if (row > kGridFullRows) break;    // one extra, partly hidden row hints that the list goes on
            int col = k % kGridCols;
            SDL_Rect cell{x0 + col * (kCellWidth + kGridGap), gridTop(m.showTabs) + row * kGridPitchY, kCellWidth, kCellHeight};
            drawIcon(*gridIcons, c.entries[c.visible[k]].iconPath, cell);
            if (k == c.sel) frame(kYellow, cell, kBorder);
            const Entry& entry = c.entries[c.visible[k]];
            if (m.isAutoStart(entry)) pill(tr("autolaunch"), cell.x, cell.y, kYellow, kBlack);
            if (m.isFavorite(entry)) {
                fill(kBar, {cell.x + cell.w - 26, cell.y + 2, 24, 24});
                star(cell.x + cell.w - 14, cell.y + 14, 9, kYellow);
            }
            if (c.mixed) {
                int w = textWidth(smallFont, entry.tag) + 12;
                pill(entry.tag, cell.x + cell.w - w, cell.y + cell.h - TTF_FontHeight(smallFont) - 4, kBar, kGrey);
            }
        }

        const Entry* e = m.selected();
        if (!e) return;
        const int bottom = kScreenH - kFooterH;
        const int textW = kScreenW - 2 * kMargin;
        const std::string sub = e->meta.empty() ? tr(e->description) : e->meta;
        int descH = sub.empty() ? 0 : TTF_FontHeight(descFont);
        int titleH = TTF_FontHeight(titleFont);
        int textTop = bottom - 8 - descH - titleH;
        gradient({0, textTop - 70, kScreenW, 70}, kClear);
        fill(kClear, {0, textTop, kScreenW, bottom - textTop});
        drawText(renderer, titleFont, e->name, kMargin, textTop, kWhite, textW);
        drawText(renderer, descFont, sub, kMargin, textTop + titleH, kGrey, textW);
    }

    // Width of a pill() with this text; the system tags are measured once.
    int pillWidth(const std::string& text) {
        auto it = pillWidths.find(text);
        if (it != pillWidths.end()) return it->second;
        return pillWidths[text] = textWidth(smallFont, text) + 12;
    }
    std::map<std::string, int> pillWidths;

    // The selected list row's name, when it doesn't fit, scrolls left to show the rest: it waits a
    // moment, scrolls to the end, waits again and starts over.
    static constexpr Uint32 kMarqueeHoldMs = 1200;
    static constexpr int kMarqueeSpeed = 40;            // pixels per second
    static constexpr Uint32 kMarqueeFrameMs = 33;
    std::string marqueeKey;
    Uint32 marqueeStart = 0, marqueeNext = 0;

    int marqueeOffset(const std::string& key, int overflow) {
        const Uint32 now = SDL_GetTicks();
        if (key != marqueeKey) { marqueeKey = key; marqueeStart = now; }
        const Uint32 scrollMs = (Uint32)overflow * 1000 / kMarqueeSpeed;
        Uint32 t = now - marqueeStart;
        if (t >= 2 * kMarqueeHoldMs + scrollMs) { marqueeStart = now; t = 0; }
        if (t < kMarqueeHoldMs) {
            marqueeNext = marqueeStart + kMarqueeHoldMs;
            return 0;
        }
        if (t < kMarqueeHoldMs + scrollMs) {
            marqueeNext = now + kMarqueeFrameMs;
            return (int)((t - kMarqueeHoldMs) * kMarqueeSpeed / 1000);
        }
        marqueeNext = marqueeStart + 2 * kMarqueeHoldMs + scrollMs;
        return overflow;
    }

    void renderList(const Model& m) {
        const Category& c = m.cur();
        if (c.sel < c.scroll) c.scroll = c.sel;
        const int rows = listRows(m.showTabs), top = listTop(m.showTabs);
        if (c.sel >= c.scroll + rows) c.scroll = c.sel - rows + 1;

        // Rows are laid out in columns, like a table: [star] name ... [auto] [system]. The star has a
        // fixed slot before the name, and the system column is as wide as the widest tag in the tab,
        // with the tags at its left edge, so both line up from row to row.
        const int fontH = TTF_FontHeight(descFont);
        const int starW = 20;
        if (c.mixed && c.tagColumn < 0) {
            c.tagColumn = 0;
            for (const Entry& e : c.entries) c.tagColumn = std::max(c.tagColumn, pillWidth(e.tag));
        }
        const int tagColW = c.mixed ? c.tagColumn : 0;
        for (int row = 0; row < rows && c.scroll + row < (int)c.visible.size(); ++row) {
            int k = c.scroll + row;
            const Entry& e = c.entries[c.visible[k]];
            SDL_Rect r{kMargin, top + row * kListRowH, kListWidth, kListRowH - 2};
            if (k == c.sel) {
                fill(kRowSel, r);
                fill(kYellow, {r.x, r.y, 4, r.h});
            }
            const int tagY = r.y + (r.h - TTF_FontHeight(smallFont) - 4) / 2;
            const int nameX = r.x + 12 + starW;
            int right = r.x + r.w - 4;      // the name ends before this
            if (c.mixed) {
                right -= tagColW;
                pill(e.tag, right, tagY, kTile, kGrey);
                right -= 8;
            }
            if (m.isAutoStart(e)) {
                right -= pillWidth(tr("auto"));
                pill(tr("auto"), right, tagY, kYellow, kBlack);
                right -= 8;
            }
            if (m.isFavorite(e)) star(r.x + 12 + starW / 2, r.y + r.h / 2, 7, kYellow);
            int scrollX = 0;
            if (k == c.sel) {
                const int overflow = textWidth(descFont, e.name) - (right - nameX);
                if (overflow > 0) scrollX = marqueeOffset(c.name + "\x1f" + e.category + "\x1f" + e.id, overflow);
            }
            drawText(renderer, descFont, e.name, nameX, r.y + (r.h - fontH) / 2, k == c.sel ? kWhite : kGrey,
                     right - nameX, scrollX);
        }

        // Scrollbar, only when the tab doesn't fit on one screen
        int total = (int)c.visible.size();
        if (total > rows) {
            SDL_Rect track{kMargin + kListWidth + 4, top, 4, rows * kListRowH - 2};
            fill(kTile, track);
            int thumbH = std::max(16, track.h * rows / total);
            int thumbY = track.y + (track.h - thumbH) * c.scroll / std::max(1, total - rows);
            fill(kGrey, {track.x, thumbY, track.w, thumbH});
        }

        const Entry* e = m.selected();
        if (!e) return;
        SDL_Rect box{kPreviewX, top, kPreviewW, kPreviewH};
        drawIcon(*previewIcons, e->iconPath, box);
        int y = box.y + box.h + 10;
        y += drawWrapped(uiFont, e->name, kPreviewX, y, kWhite, kPreviewW) + 4;
        if (!e->meta.empty()) {
            drawText(renderer, smallFont, e->meta, kPreviewX, y, kYellow, kPreviewW);
            y += TTF_FontLineSkip(smallFont) + 4;
        }
        const int textBottom = kScreenH - kFooterH - TTF_FontHeight(smallFont) - 10;   // above the "n / total"
        descMax = drawWrappedClipped(smallFont, e->synopsis.empty() ? tr(e->description) : e->synopsis,
                                     kPreviewX, y, kGrey, kPreviewW - 16, textBottom - y, m.descScroll);

        std::string pos = std::to_string(c.sel + 1) + " / " + std::to_string(total);
        drawText(renderer, smallFont, pos, kScreenW - kMargin - textWidth(smallFont, pos),
                 kScreenH - kFooterH - TTF_FontHeight(smallFont) - 6, kGrey);
    }

    // A short message over the footer, e.g. after renaming a game.
    void renderNotice(const std::string& text) {
        const int padX = 14, h = TTF_FontHeight(descFont) + 14;
        const int w = std::min(kScreenW - 2 * kMargin, textWidth(descFont, text) + 2 * padX);
        SDL_Rect r{(kScreenW - w) / 2, kScreenH - kFooterH - h - 10, w, h};
        fill({12, 12, 14, 240}, r);
        frame(kYellow, r, 2);
        drawText(renderer, descFont, text, r.x + padX, r.y + 7, kWhite, w - 2 * padX);
    }

    void renderStatus(const std::string& text) {
        fill(kClear, {0, 0, kScreenW, kScreenH});
        drawText(renderer, titleFont, text, (kScreenW - textWidth(titleFont, text)) / 2,
                 (kScreenH - TTF_FontHeight(titleFont)) / 2, kWhite);
    }

    // The POWER menu, or the game options menu (L2 + R2) and its delete confirmation, which show the
    // game's name under the title.
    void renderMenu(const Model& m) {
        std::string title, subtitle;
        std::vector<std::string> labels;
        if (m.menuKind == Model::Menu::Power) {
            title = tr("Power options");
            for (const auto& item : m.menuItems) labels.push_back(tr(item.label));
        } else {
            title = tr(m.menuKind == Model::Menu::Game ? "Game options" : "Move this game to the trash?");
            subtitle = m.menuEntry.name;
            for (const auto& l : m.menuLabels) labels.push_back(tr(l));
        }
        const int pad = 12, rowH = 40;
        const int titleH = TTF_FontHeight(uiFont) + 14;
        const int subH = subtitle.empty() ? 0 : TTF_FontLineSkip(smallFont) + 6;
        const int panelW = subtitle.empty() ? 320 : 400;
        const int count = (int)labels.size();
        const int panelH = titleH + subH + count * rowH + 2 * pad;
        const int bodyY = bodyTop(m.showTabs);
        SDL_Rect panel{(kScreenW - panelW) / 2, bodyY + (kScreenH - kFooterH - bodyY - panelH) / 2, panelW, panelH};
        fill({0, 0, 0, 150}, {0, kHeaderH, kScreenW, kScreenH - kFooterH - kHeaderH});   // dim the tab behind
        fill(kBar, panel);
        frame(kTile, panel, 2);
        drawText(renderer, uiFont, title, panel.x + pad + 4, panel.y + pad, kWhite, panelW - 2 * pad - 4);
        if (!subtitle.empty())
            drawText(renderer, smallFont, subtitle, panel.x + pad + 4, panel.y + pad + titleH - 4, kGrey, panelW - 2 * pad - 4);

        const int fontH = TTF_FontHeight(descFont);
        for (int i = 0; i < count; ++i) {
            SDL_Rect r{panel.x + pad, panel.y + pad + titleH + subH + i * rowH, panelW - 2 * pad, rowH - 4};
            bool sel = i == m.menuSel;
            if (sel) {
                fill(kRowSel, r);
                fill(kYellow, {r.x, r.y, 4, r.h});
            }
            drawText(renderer, descFont, labels[i], r.x + 16, r.y + (r.h - fontH) / 2, sel ? kWhite : kGrey, r.w - 24);
        }
    }

    void renderKeyboard(const Model& m, const Keyboard& kb) {
        const int pad = 12, gap = 4, unit = 58, keyH = 36;
        const int queryH = TTF_FontHeight(uiFont) + 12;
        const int panelW = (int)(Keyboard::kRowUnits * unit) - gap + 2 * pad;
        const int panelH = queryH + Keyboard::kRows * keyH + (Keyboard::kRows - 1) * gap + 2 * pad;
        SDL_Rect panel{(kScreenW - panelW) / 2, kScreenH - kFooterH - panelH - 6, panelW, panelH};
        fill({12, 12, 14, 240}, panel);
        frame(kTile, panel, 2);

        // What is typed: the search, or the new name of a game's file; a long name shows its end
        const std::string prompt = tr(m.renaming ? "Rename:" : "Search:");
        drawText(renderer, uiFont, prompt, panel.x + pad, panel.y + pad, kGrey);
        const int textX = panel.x + pad + textWidth(uiFont, prompt) + 8;
        const int textMax = panel.x + panelW - pad - textX;
        if (m.renaming) {
            // the name with a cursor bar, scrolled so the cursor stays in view
            const size_t cursor = std::min(m.renameCursor, m.renameText.size());
            const int caretX = textWidth(uiFont, m.renameText.substr(0, cursor));
            const int scroll = std::max(0, caretX + 4 - textMax);
            drawText(renderer, uiFont, m.renameText, textX, panel.y + pad, kWhite, textMax, scroll);
            fill(kYellow, {textX + caretX - scroll, panel.y + pad, 2, TTF_FontHeight(uiFont)});
        } else {
            const std::string text = m.query + "_";
            drawText(renderer, uiFont, text, textX, panel.y + pad, kWhite, textMax, std::max(0, textWidth(uiFont, text) - textMax));
        }

        for (int r = 0; r < Keyboard::kRows; ++r) {
            const auto& keys = Keyboard::keys(r);
            for (int c = 0; c < (int)keys.size(); ++c) {
                const Keyboard::Key& key = keys[c];
                SDL_Rect k{panel.x + pad + (int)(key.x * unit), panel.y + pad + queryH + r * (keyH + gap),
                           (int)(key.w * unit) - gap, keyH};
                bool sel = r == kb.row && c == kb.col;
                fill(sel ? kYellow : kTile, k);
                if (key.label == "shift" && kb.caps) frame(sel ? kBlack : kYellow, k, 2);   // case switch on
                std::string label = key.label == "shift" ? (kb.caps ? "aA" : "Aa")
                                  : key.label.size() > 1 ? tr(key.label) : key.label;   // space / del / ok
                TTF_Font* f = key.label.size() > 1 ? smallFont : uiFont;
                if (key.label.size() == 1) label = kb.caps ? upper(label) : label;
                drawText(renderer, f, label, k.x + (k.w - textWidth(f, label)) / 2,
                         k.y + (k.h - TTF_FontHeight(f)) / 2, sel ? kBlack : kWhite);
            }
        }
    }
};
