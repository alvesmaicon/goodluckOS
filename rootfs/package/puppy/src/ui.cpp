#include "ui.h"

#include <SDL2/SDL_image.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <iostream>

#include "config.h"
#include "input.h"
#include "layout.h"
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

void drawText(SDL_Renderer* r, TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int maxW,
              int scrollX) {
    if (!font || text.empty()) return;
    SDL_Surface* s = TTF_RenderUTF8_Blended(font, text.c_str(), color);
    if (!s) return;
    drawSurface(r, s, x, y, maxW, scrollX);
    SDL_FreeSurface(s);
}

int textWidth(TTF_Font* font, const std::string& text) {
    int w = 0, h = 0;
    if (font && !text.empty()) TTF_SizeUTF8(font, text.c_str(), &w, &h);
    return w;
}

std::string elided(TTF_Font* font, const std::string& text, int maxW) {
    if (textWidth(font, text) <= maxW) return text;
    std::string s = text;
    while (!s.empty()) {
        while (!s.empty() && ((unsigned char)s.back() & 0xC0) == 0x80) s.pop_back();   // a whole UTF-8 character
        if (!s.empty()) s.pop_back();
        while (!s.empty() && s.back() == ' ') s.pop_back();
        if (textWidth(font, s + "...") <= maxW) return s + "...";
    }
    return "";
}

IconCache::IconCache(SDL_Renderer* r, const std::string& fallbackPath, int boxW, int boxH, bool fit, size_t maxIcons)
    : renderer(r), boxW(boxW), boxH(boxH), maxIcons(maxIcons), fit(fit) {
    fallback = load(fallbackPath);
    if (!fallback.tex) std::cerr << "Warning: missing fallback icon: " << fallbackPath << "\n";
}

IconCache::~IconCache() {
    for (auto& [path, slot] : slots) if (slot.icon.tex) SDL_DestroyTexture(slot.icon.tex);
    if (fallback.tex) SDL_DestroyTexture(fallback.tex);
}

IconCache::Icon IconCache::get(const std::string& path, bool orFallback) {
    const Icon none = orFallback ? fallback : Icon{};
    if (path.empty()) return none;

    auto it = slots.find(path);
    if (it != slots.end()) {
        it->second.lastUsed = ++clock;
        return it->second.icon.tex ? it->second.icon : none;
    }

    if (slots.size() >= maxIcons) evictOldest();

    Slot slot;
    slot.icon = load(path);
    slot.lastUsed = ++clock;
    slots[path] = slot;
    return slot.icon.tex ? slot.icon : none;
}

// Name of the scaled copy of an image for this cache's box; changes when the image does.
std::string IconCache::thumbPath(const std::string& path) const {
    std::error_code ec;
    auto size = fs::file_size(path, ec);
    auto time = fs::last_write_time(path, ec).time_since_epoch().count();
    std::string key = path + "|" + std::to_string(size) + "|" + std::to_string(time) + "|" +
                      std::to_string(boxW) + "x" + std::to_string(boxH) + (fit ? "f" : "c");
    char name[32];
    snprintf(name, sizeof(name), "%016zx.png", std::hash<std::string>{}(key));
    return cfg.thumbDir() + "/" + name;
}

IconCache::Icon IconCache::load(const std::string& path) {
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

void IconCache::evictOldest() {
    auto oldest = slots.begin();
    for (auto it = slots.begin(); it != slots.end(); ++it)
        if (it->second.lastUsed < oldest->second.lastUsed) oldest = it;
    if (oldest->second.icon.tex) SDL_DestroyTexture(oldest->second.icon.tex);
    slots.erase(oldest);
}

Ui::Ui(const std::string& font, const std::string& bold, float scale) {
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

    setFont(font, bold, scale);

    gridCache    = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kCellWidth, kCellHeight, false, kMaxCachedIcons);
    previewCache = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kPreviewW, kPreviewH, true, kMaxCachedIcons);
    cardCache    = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kCardW, kCardH, false, kMaxCachedIcons);
    heroCache    = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kHeroW, kHeroH, true, 4);   // 300 KB each
    ok_ = true;
}

Ui::~Ui() {
    gridCache.reset();
    previewCache.reset();
    cardCache.reset();
    heroCache.reset();
    if (clipTex) SDL_DestroyTexture(clipTex);
    if (circle) SDL_DestroyTexture(circle);
    if (corner) SDL_DestroyTexture(corner);
    if (button) SDL_DestroyTexture(button);
    for (TTF_Font* f : {fonts.ui, fonts.title, fonts.desc, fonts.small, fonts.uiBold, fonts.titleBold, fonts.smallBold, fonts.keyBold}) if (f) TTF_CloseFont(f);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    if (sdlUp) { TTF_Quit(); IMG_Quit(); SDL_Quit(); }
}

// The four sizes of the interface font, and four of the bold one. What was measured or drawn with the
// old ones is dropped.
void Ui::setFont(const std::string& path, const std::string& bold, float scale) {
    for (TTF_Font* f : {fonts.ui, fonts.title, fonts.desc, fonts.small, fonts.uiBold, fonts.titleBold, fonts.smallBold, fonts.keyBold}) if (f) TTF_CloseFont(f);
    auto size = [&](int pt) { return (int)std::lround(pt * scale); };
    fonts.ui    = TTF_OpenFont(path.c_str(), size(22));
    fonts.title = TTF_OpenFont(path.c_str(), size(30));
    fonts.desc  = TTF_OpenFont(path.c_str(), size(20));
    fonts.small = TTF_OpenFont(path.c_str(), size(15));
    fonts.uiBold    = bold.empty() ? nullptr : TTF_OpenFont(bold.c_str(), size(22));
    fonts.titleBold = bold.empty() ? nullptr : TTF_OpenFont(bold.c_str(), size(30));
    fonts.smallBold = bold.empty() ? nullptr : TTF_OpenFont(bold.c_str(), size(15));
    fonts.keyBold   = bold.empty() ? nullptr : TTF_OpenFont(bold.c_str(), size(11));
    if (!fonts.ui || !fonts.title || !fonts.desc || !fonts.small)
        std::cerr << "Warning: could not load font " << path << "\n";
    pillWidths.clear();
    if (clipTex) SDL_DestroyTexture(clipTex);
    clipTex = nullptr;
    clipText.clear();
}

void Ui::begin() {
    marqueeNext = 0;    // set again while the selected name is still scrolling
    setColor(theme().bg);
    SDL_RenderClear(renderer);
}

void Ui::end() {
    if (!marqueeNext) marqueeKey.clear();   // coming back to the same name starts it over
    SDL_RenderPresent(renderer);
}

void Ui::header(const Header& h, const TopBar& bar) {
    if (h.clear) shade({0, 0, kScreenW, kHeaderH}, theme().bg, 230, kBarShade);
    else fill(theme().modern ? theme().bg : theme().bar, {0, 0, kScreenW, kHeaderH});
    const int nameY = (kHeaderH - TTF_FontHeight(fonts.ui)) / 2;

    // Right to left, 14 px apart: each item's text, then its icon (returns where the icon goes)
    const int statusY = (kHeaderH - TTF_FontHeight(fonts.small)) / 2;
    int statusX = kScreenW - kMargin + 14;
    auto item = [&](const std::string& text, int iconW, SDL_Color c) {
        statusX -= 14 + textWidth(fonts.small, text);
        drawText(renderer, fonts.small, text, statusX, statusY, c);
        statusX -= iconW;
        return statusX;
    };
    if (bar.battery) {
        const Battery& b = *bar.battery;
        const int x = item(b.percent >= 0 ? std::to_string(b.percent) + "%" : "??", 28, theme().muted);
        batteryIcon(x, (kHeaderH - 12) / 2, b.percent, b.charging, b.full);
    }
    if (bar.audio) {
        const Audio& a = *bar.audio;
        const int x = item(a.muted ? tr("muted") : std::to_string(a.volume) + "%", 22, theme().muted);
        if (a.headphones) headphonesIcon(x, (kHeaderH - 16) / 2, theme().muted);
        else speakerIcon(x, (kHeaderH - 16) / 2, theme().muted, a.muted);
    }
    if (!bar.clock.empty()) item(bar.clock, 0, theme().muted);
    // the A33 slows down from 75 C; 90 C is "hot"
    auto temp = [&](int t, void (Ui::*icon)(int, int, SDL_Color)) {
        const SDL_Color c = t >= 90 ? kRed : t >= 75 ? kYellow : theme().muted;
        (this->*icon)(item(t >= 0 ? std::to_string(t) + "\u00b0" : "??", 20, c), (kHeaderH - 16) / 2, c);
    };
    if (bar.pmicTemp) temp(*bar.pmicTemp, &Ui::boltIcon);
    if (bar.cpuTemp) temp(*bar.cpuTemp, &Ui::chipIcon);

    TTF_Font* titleFont = theme().modern ? fonts.uiBold : fonts.ui;
    int countW = textWidth(fonts.small, h.count);
    int maxNameW = statusX - 24 - countW - 10 - kMargin;
    const std::string title = elided(titleFont, h.title, maxNameW);
    int nameW = textWidth(titleFont, title);
    drawText(renderer, titleFont, title, kMargin, nameY, theme().text);
    drawText(renderer, fonts.small, h.count, kMargin + nameW + 10,
             nameY + TTF_FontAscent(fonts.ui) - TTF_FontAscent(fonts.small), h.highlight ? accent() : theme().muted);
}

// Button in the highlight colour, followed by what it does. The gap between hints shrinks when they
// wouldn't fit on one line (e.g. "Y Remove" is wider than "Y My List").
void Ui::footer(const Hints& hints) {
    const int top = kScreenH - kFooterH;
    fill(theme().bar, {0, top, kScreenW, kFooterH});

    const int y = top + (kFooterH - TTF_FontHeight(fonts.small)) / 2;
    const int keyGap = 6;
    auto labelW = [&](const Hint& h) { return std::max(textWidth(fonts.small, h.label), textWidth(fonts.small, h.room)); };
    int textW = 0;
    for (const auto& h : hints) textW += textWidth(fonts.small, buttonLabel(h.key)) + keyGap + labelW(h);
    const int slots = std::max(1, (int)hints.size() - 1);
    if (theme().modern) {   // Vitrine's: left to right, each button drawn, then what it does
        const int cy = top + kFooterH / 2;
        int w = 0;
        for (const auto& h : hints) w += keyWidth(buttonLabel(h.key)) + keyGap + labelW(h);
        const int gap = std::clamp((kScreenW - 2 * kMargin - w) / slots, 6, 18);
        int x = kMargin;
        for (const auto& h : hints) {
            x += keyGlyph(buttonLabel(h.key), x, cy, theme().bar) + keyGap;
            drawText(renderer, fonts.small, h.label, x, cy - TTF_FontHeight(fonts.small) / 2, theme().muted);
            x += labelW(h) + gap;
        }
        return;
    }
    const int gap = std::clamp((kScreenW - 2 * kMargin - textW) / slots, 4, 16);
    int x = kScreenW - kMargin;
    for (auto it = hints.rbegin(); it != hints.rend(); ++it) {
        x -= labelW(*it);
        drawText(renderer, fonts.small, it->label, x, y, theme().muted);
        const std::string key = buttonLabel(it->key);
        x -= keyGap + textWidth(fonts.small, key);
        drawText(renderer, fonts.small, key, x, y, accent());
        x -= gap;
    }
}

// A short message over the footer, e.g. after renaming a game.
void Ui::notice(const std::string& text) {
    const int padX = 14, h = TTF_FontHeight(fonts.desc) + 14;
    const int w = std::min(kScreenW - 2 * kMargin, textWidth(fonts.desc, text) + 2 * padX);
    SDL_Rect r{(kScreenW - w) / 2, kScreenH - kFooterH - h - 10, w, h};
    panel(r, {12, 12, 14, 240}, accent());
    drawText(renderer, fonts.desc, text, r.x + padX, r.y + 7, theme().text, w - 2 * padX);
}

void Ui::status(const std::string& text) {
    fill(theme().bg, {0, 0, kScreenW, kScreenH});
    drawText(renderer, fonts.title, text, (kScreenW - textWidth(fonts.title, text)) / 2,
             (kScreenH - TTF_FontHeight(fonts.title)) / 2, theme().text);
}

// Retro: a band with the accent at its left edge. Modern: a pill, in the accent when the d-pad is on it.
SDL_Color Ui::selection(const SDL_Rect& r, bool focused) {
    if (theme().modern) {
        roundRect(r, r.h / 2, focused ? accent() : theme().rowSel);
        return focused ? theme().ink : theme().text;
    }
    fill(theme().rowSel, r);
    if (focused) fill(accent(), {r.x, r.y, 4, r.h});
    return theme().text;
}

SDL_Color Ui::accentOn(bool selected) const {
    return theme().modern && selected ? theme().ink : accent();
}

void Ui::panel(const SDL_Rect& r, SDL_Color inside, SDL_Color border) {
    if (theme().modern) {   // a card: the border shows when it isn't the card's own colour (a notice's accent)
        roundRect(r, 16, border);
        roundRect({r.x + 2, r.y + 2, r.w - 4, r.h - 4}, 14, theme().tile);
        return;
    }
    fill(inside, r);
    frame(border, r, 2);
}

void Ui::key(const SDL_Rect& r, bool lit) {
    if (theme().modern) roundRect(r, 8, lit ? accent() : theme().rowSel);
    else fill(lit ? accent() : theme().tile, r);
}

void Ui::tabHighlight(const SDL_Rect& r) {
    if (theme().modern) {
        roundRect({r.x + 16, r.y + r.h - 1, r.w - 32, 3}, 1, accent());
        return;
    }
    fill(theme().rowSel, r);
    fill(accent(), {r.x, r.y + r.h - 1, r.w, 2});
}

void Ui::toggle(const SDL_Rect& r, bool on, bool enabled, bool selected) {
    if (theme().modern) {
        const SDL_Color lit = enabled ? accentOn(selected) : theme().dim;
        roundRect(r, r.h / 2, on ? lit : theme().tile);
        roundRect({on ? r.x + r.w - 18 : r.x + 2, r.y + 2, 16, 16}, 8,
                  on ? (selected ? accent() : theme().ink) : theme().muted);
        return;
    }
    fill(on ? (enabled ? accent() : theme().dim) : theme().tile, r);
    fill(on ? theme().bar : theme().muted, {on ? r.x + r.w - 18 : r.x + 2, r.y + 2, 16, 16});
}

void Ui::track(const SDL_Rect& r, SDL_Color c) {
    if (theme().modern) roundRect(r, r.h / 2, c);
    else fill(c, r);
}

// Modern: rounded, and ringed on a selected row, whose pill may be the same colour
void Ui::swatch(const SDL_Rect& r, SDL_Color c, bool selected) {
    if (!theme().modern) {
        fill(c, r);
        return;
    }
    if (selected) roundRect({r.x - 2, r.y - 2, r.w + 4, r.h + 4}, 6, theme().ink);
    roundRect(r, 4, c);
}

// Corners from a white disc tinted to the colour (Vitrine's Painter), straight sides from rectangles
void Ui::roundRect(const SDL_Rect& r, int radius, SDL_Color c) {
    radius = std::min({radius, r.w / 2, r.h / 2});
    if (!circle) {
        const int size = 64;
        SDL_Surface* s = SDL_CreateRGBSurfaceWithFormat(0, size, size, 32, SDL_PIXELFORMAT_RGBA32);
        if (s) {
            Uint32* px = (Uint32*)s->pixels;
            const float rad = size / 2.0f;
            for (int y = 0; y < size; ++y)
                for (int x = 0; x < size; ++x) {
                    const float dx = x + 0.5f - rad, dy = y + 0.5f - rad;
                    const float a = std::clamp(rad - std::sqrt(dx * dx + dy * dy) + 0.5f, 0.0f, 1.0f);
                    px[y * (s->pitch / 4) + x] = SDL_MapRGBA(s->format, 255, 255, 255, (Uint8)(a * 255));
                }
            circle = SDL_CreateTextureFromSurface(renderer, s);
            SDL_FreeSurface(s);
            if (circle) SDL_SetTextureBlendMode(circle, SDL_BLENDMODE_BLEND);
        }
    }
    if (radius <= 0 || !circle) {
        fill(c, r);
        return;
    }
    SDL_SetTextureColorMod(circle, c.r, c.g, c.b);
    SDL_SetTextureAlphaMod(circle, c.a);
    const int half = 32;
    const SDL_Rect src[4] = {{0, 0, half, half}, {half, 0, half, half}, {0, half, half, half}, {half, half, half, half}};
    const SDL_Rect dst[4] = {{r.x, r.y, radius, radius}, {r.x + r.w - radius, r.y, radius, radius},
                             {r.x, r.y + r.h - radius, radius, radius}, {r.x + r.w - radius, r.y + r.h - radius, radius, radius}};
    for (int i = 0; i < 4; ++i) SDL_RenderCopy(renderer, circle, &src[i], &dst[i]);
    fill(c, {r.x + radius, r.y, r.w - 2 * radius, r.h});
    fill(c, {r.x, r.y + radius, radius, r.h - 2 * radius});
    fill(c, {r.x + r.w - radius, r.y + radius, radius, r.h - 2 * radius});
}

// The face buttons in their colours, as printed on the pad
static SDL_Color buttonColor(char letter) {
    switch (letter) {
        case 'A': return {229, 72, 77, 255};
        case 'B': return {245, 197, 66, 255};
        case 'X': return {62, 142, 247, 255};
        default:  return {70, 167, 88, 255};
    }
}

static bool faceButton(const std::string& key) {
    return key.size() == 1 && std::string("ABXY").find(key[0]) != std::string::npos;
}

int Ui::keyWidth(const std::string& key) {
    return faceButton(key) ? 22 : textWidth(fonts.keyBold, key) + 10;
}

// A face button: a grey disc, a little concave like the pad's (lit from above, its dish is darker at
// the top and its rim lighter)
static SDL_Texture* makeButton(SDL_Renderer* renderer) {
    const int size = 64;
    SDL_Surface* s = SDL_CreateRGBSurfaceWithFormat(0, size, size, 32, SDL_PIXELFORMAT_RGBA32);
    if (!s) return nullptr;
    Uint32* px = (Uint32*)s->pixels;
    const float rad = size / 2.0f;
    for (int y = 0; y < size; ++y)
        for (int x = 0; x < size; ++x) {
            const float dx = (x + 0.5f - rad) / rad, dy = (y + 0.5f - rad) / rad, d = std::sqrt(dx * dx + dy * dy);
            const float a = std::clamp((1.0f - d) * rad + 0.5f, 0.0f, 1.0f);
            const float slope = dy + 0.35f * dx;
            const float shade = d > 0.86f ? 1.0f - 0.22f * slope : 1.0f + 0.12f * slope;
            const auto ch = [&](float base) { return (Uint8)std::clamp(base * shade, 0.0f, 255.0f); };
            px[y * (s->pitch / 4) + x] = SDL_MapRGBA(s->format, ch(66), ch(70), ch(80), (Uint8)(a * 255));
        }
    SDL_Texture* t = SDL_CreateTextureFromSurface(renderer, s);
    SDL_FreeSurface(s);
    if (t) SDL_SetTextureBlendMode(t, SDL_BLENDMODE_BLEND);
    return t;
}

// A face button is its letter in its colour on a grey button; the others, their name in an outline
int Ui::keyGlyph(const std::string& key, int x, int cy, SDL_Color inside) {
    const int w = keyWidth(key);
    if (faceButton(key)) {
        if (!button) button = makeButton(renderer);
        const SDL_Rect r{x, cy - w / 2, w, w};
        if (button) SDL_RenderCopy(renderer, button, nullptr, &r);
        drawText(renderer, fonts.smallBold, key, x + (w - textWidth(fonts.smallBold, key)) / 2,
                 cy - TTF_FontHeight(fonts.smallBold) / 2, buttonColor(key[0]));
        return w;
    }
    const int h = TTF_FontHeight(fonts.keyBold) + 2;
    const SDL_Rect r{x, cy - h / 2, w, h};
    roundRect(r, 4, theme().muted);
    roundRect({r.x + 1, r.y + 1, r.w - 2, r.h - 2}, 3, inside);
    drawText(renderer, fonts.keyBold, key, x + (w - textWidth(fonts.keyBold, key)) / 2,
             cy - TTF_FontHeight(fonts.keyBold) / 2, theme().muted);
    return w;
}

void Ui::setColor(SDL_Color c) { SDL_SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a); }

void Ui::fill(SDL_Color c, const SDL_Rect& r) {
    setColor(c);
    SDL_RenderFillRect(renderer, &r);
}

void Ui::frame(SDL_Color c, const SDL_Rect& r, int t) {
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
void Ui::gradient(const SDL_Rect& r, SDL_Color c) {
    shade(r, c, 0, 255);
}

// The colour with one opacity at the top and another at the bottom.
void Ui::shade(const SDL_Rect& r, SDL_Color c, Uint8 top, Uint8 bottom) {
    SDL_Vertex v[4];
    const float xs[2] = {(float)r.x, (float)(r.x + r.w)};
    const float ys[2] = {(float)r.y, (float)(r.y + r.h)};
    for (int i = 0; i < 4; ++i) {
        v[i].position = {xs[i % 2], ys[i / 2]};
        v[i].color = {c.r, c.g, c.b, i < 2 ? top : bottom};
        v[i].tex_coord = {0, 0};
    }
    const int idx[6] = {0, 1, 2, 1, 3, 2};
    SDL_RenderGeometry(renderer, nullptr, v, 4, idx, 6);
}

// A frame made elsewhere (a trailer's), stretched to the box; false when there is none.
bool Ui::drawFrame(SDL_Texture* frame, const SDL_Rect& box) {
    if (!frame) return false;
    SDL_RenderCopy(renderer, frame, nullptr, &box);
    return true;
}

// Horizontal fade from the colour (left) to transparent (right).
void Ui::sideGradient(const SDL_Rect& r, SDL_Color c) {
    SDL_Vertex v[4];
    const float xs[2] = {(float)r.x, (float)(r.x + r.w)};
    const float ys[2] = {(float)r.y, (float)(r.y + r.h)};
    for (int i = 0; i < 4; ++i) {
        v[i].position = {xs[i % 2], ys[i / 2]};
        v[i].color = {c.r, c.g, c.b, (Uint8)(i % 2 ? 0 : 255)};
        v[i].tex_coord = {0, 0};
    }
    const int idx[6] = {0, 1, 2, 1, 3, 2};
    SDL_RenderGeometry(renderer, nullptr, v, 4, idx, 6);
}

// Paints what lies outside rounded corners, so a picture under it looks rounded (Vitrine's way).
void Ui::roundCorners(const SDL_Rect& r, int radius, SDL_Color outside) {
    if (!corner) {
        const int size = 64;
        SDL_Surface* s = SDL_CreateRGBSurfaceWithFormat(0, size, size, 32, SDL_PIXELFORMAT_RGBA32);
        if (!s) return;
        Uint32* px = (Uint32*)s->pixels;
        for (int y = 0; y < size; ++y)
            for (int x = 0; x < size; ++x) {   // the top left quarter: opaque outside the circle
                const float dx = size - (x + 0.5f), dy = size - (y + 0.5f);
                const float a = std::clamp(std::sqrt(dx * dx + dy * dy) - (size - 0.5f), 0.0f, 1.0f);
                px[y * (s->pitch / 4) + x] = SDL_MapRGBA(s->format, 255, 255, 255, (Uint8)(a * 255));
            }
        corner = SDL_CreateTextureFromSurface(renderer, s);
        SDL_FreeSurface(s);
        if (!corner) return;
        SDL_SetTextureBlendMode(corner, SDL_BLENDMODE_BLEND);
    }
    SDL_SetTextureColorMod(corner, outside.r, outside.g, outside.b);
    const SDL_Rect dst[4] = {{r.x, r.y, radius, radius}, {r.x + r.w - radius, r.y, radius, radius},
                             {r.x, r.y + r.h - radius, radius, radius}, {r.x + r.w - radius, r.y + r.h - radius, radius, radius}};
    const SDL_RendererFlip flip[4] = {SDL_FLIP_NONE, SDL_FLIP_HORIZONTAL, SDL_FLIP_VERTICAL,
                                      (SDL_RendererFlip)(SDL_FLIP_HORIZONTAL | SDL_FLIP_VERTICAL)};
    for (int i = 0; i < 4; ++i) SDL_RenderCopyEx(renderer, corner, nullptr, &dst[i], 0, nullptr, flip[i]);
}

// Filled five-pointed star centred on (cx, cy), the My List badge.
void Ui::star(int cx, int cy, int r, SDL_Color c) {
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
int Ui::pill(const std::string& text, int x, int y, SDL_Color bg, SDL_Color fg) {
    const int padX = 6, padY = 2;
    SDL_Rect r{x, y, textWidth(fonts.small, text) + padX * 2, TTF_FontHeight(fonts.small) + padY * 2};
    if (theme().modern) roundRect(r, 5, bg);
    else fill(bg, r);
    drawText(renderer, fonts.small, text, x + padX, y + padY, fg);
    return r.w;
}

void Ui::drawIcon(IconCache& cache, const std::string& path, const SDL_Rect& box) {
    IconCache::Icon icon = cache.get(path);
    if (!icon.tex) return;
    SDL_Rect dst{box.x + (box.w - icon.w) / 2, box.y + (box.h - icon.h) / 2, icon.w, icon.h};
    SDL_RenderCopy(renderer, icon.tex, nullptr, &dst);
}

// The image scaled to cover the box, its edges cropped; false when there is no image.
bool Ui::drawCover(IconCache& cache, const std::string& path, const SDL_Rect& box) {
    IconCache::Icon icon = cache.get(path, false);
    if (!icon.tex) return false;
    const float scale = std::max((float)box.w / icon.w, (float)box.h / icon.h);
    SDL_Rect src;
    src.w = std::min(icon.w, (int)std::lround(box.w / scale));
    src.h = std::min(icon.h, (int)std::lround(box.h / scale));
    src.x = (icon.w - src.w) / 2;
    src.y = (icon.h - src.h) / 2;
    SDL_RenderCopy(renderer, icon.tex, &src, &box);
    return true;
}

// Draws wrapped text and returns its height.
int Ui::drawWrapped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width) {
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
int Ui::drawWrappedClipped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width, int maxH,
                           int scrollLines) {
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
    if (scroll > 0) triangle(ax, y + 5, 5, true, accent());
    if (scroll < maxScroll) triangle(ax, y + h - 5, 5, false, accent());
    return maxScroll;
}

void Ui::triangle(int cx, int cy, int r, bool up, SDL_Color c) {
    SDL_Vertex v[3];
    const float d = up ? -1.0f : 1.0f;
    v[0].position = {(float)cx, cy + d * r};
    v[1].position = {(float)(cx - r), cy - d * r};
    v[2].position = {(float)(cx + r), cy - d * r};
    for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
    SDL_RenderGeometry(renderer, nullptr, v, 3, nullptr, 0);
}

// Pointing left or right; drawn rather than a text arrow, which not every font has.
void Ui::sideTriangle(int cx, int cy, int r, bool left, SDL_Color c) {
    SDL_Vertex v[3];
    const float d = left ? -1.0f : 1.0f;
    v[0].position = {cx + d * r, (float)cy};
    v[1].position = {cx - d * r, (float)(cy - r)};
    v[2].position = {cx - d * r, (float)(cy + r)};
    for (auto& vert : v) { vert.color = c; vert.tex_coord = {0, 0}; }
    SDL_RenderGeometry(renderer, nullptr, v, 3, nullptr, 0);
}

// Width of a pill() with this text; the system tags are measured once.
int Ui::wrappedHeight(TTF_Font* font, const std::string& text, int width) {
    if (!font || text.empty()) return 0;
    SDL_Surface* s = TTF_RenderUTF8_Blended_Wrapped(font, text.c_str(), theme().text, width);
    if (!s) return 0;
    int h = s->h;
    SDL_FreeSurface(s);
    return h;
}

int Ui::pillWidth(const std::string& text) {
    auto it = pillWidths.find(text);
    if (it != pillWidths.end()) return it->second;
    return pillWidths[text] = textWidth(fonts.small, text) + 12;
}

int Ui::marqueeOffset(const std::string& key, int overflow) {
    if (!marqueeOn) return 0;
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

// 16x16
void Ui::speakerIcon(int x, int y, SDL_Color c, bool muted) {
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
void Ui::batteryIcon(int x, int y, int percent, bool charging, bool full) {
    frame(theme().muted, {x, y, 22, 12}, 1);
    fill(theme().muted, {x + 22, y + 3, 2, 6});
    const SDL_Color c = full || (charging && percent >= 100) ? kGreen
                      : charging ? kYellow : percent <= 10 ? kRed : theme().muted;
    if (percent > 0) fill(c, {x + 2, y + 2, std::max(3, 18 * std::min(percent, 100) / 100), 8});
}

void Ui::headphonesIcon(int x, int y, SDL_Color c) {
    fill(c, {x + 4, y, 8, 2});
    fill(c, {x + 2, y + 1, 2, 2});
    fill(c, {x + 12, y + 1, 2, 2});
    fill(c, {x, y + 3, 2, 7});
    fill(c, {x + 14, y + 3, 2, 7});
    fill(c, {x, y + 9, 4, 7});
    fill(c, {x + 12, y + 9, 4, 7});
}

// 16x16, like the in-game status bar's: the CPU temperature...
void Ui::chipIcon(int x, int y, SDL_Color c) {
    fill(c, {x + 3, y + 3, 10, 1});
    fill(c, {x + 3, y + 12, 10, 1});
    fill(c, {x + 3, y + 3, 1, 10});
    fill(c, {x + 12, y + 3, 1, 10});
    fill(c, {x + 6, y + 6, 4, 4});
    for (int i = 5; i <= 11; i += 3) {
        fill(c, {x + i, y + 1, 1, 2});
        fill(c, {x + i, y + 13, 1, 2});
        fill(c, {x + 1, y + i, 2, 1});
        fill(c, {x + 13, y + i, 2, 1});
    }
}

// ...and the power chip's
void Ui::boltIcon(int x, int y, SDL_Color c) {
    static const int rows[][3] = {
        {9, 1, 3}, {8, 2, 3}, {7, 3, 3}, {6, 4, 3}, {5, 5, 3}, {4, 6, 8}, {4, 7, 8},
        {8, 8, 3}, {7, 9, 3}, {6, 10, 3}, {5, 11, 3}, {4, 12, 2}, {4, 13, 1},
    };
    for (const auto& r : rows) fill(c, {x + r[0], y + r[1], r[2], 1});
}
