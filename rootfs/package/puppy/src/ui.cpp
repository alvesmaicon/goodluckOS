#include "ui.h"

#include <SDL2/SDL_image.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <iostream>

#include "config.h"
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

IconCache::IconCache(SDL_Renderer* r, const std::string& fallbackPath, int boxW, int boxH, bool fit)
    : renderer(r), boxW(boxW), boxH(boxH), fit(fit) {
    fallback = load(fallbackPath);
    if (!fallback.tex) std::cerr << "Warning: missing fallback icon: " << fallbackPath << "\n";
}

IconCache::~IconCache() {
    for (auto& [path, slot] : slots) if (slot.icon.tex) SDL_DestroyTexture(slot.icon.tex);
    if (fallback.tex) SDL_DestroyTexture(fallback.tex);
}

IconCache::Icon IconCache::get(const std::string& path) {
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

Ui::Ui() {
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
    fonts.ui    = TTF_OpenFont(font, size(22));
    fonts.title = TTF_OpenFont(font, size(30));
    fonts.desc  = TTF_OpenFont(font, size(20));
    fonts.small = TTF_OpenFont(font, size(15));
    if (!fonts.ui || !fonts.title || !fonts.desc || !fonts.small)
        std::cerr << "Warning: could not load font " << cfg.font << "\n";

    gridCache    = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kCellWidth, kCellHeight, false);
    previewCache = std::make_unique<IconCache>(renderer, cfg.fallbackIcon, kPreviewW, kPreviewH, true);
    ok_ = true;
}

Ui::~Ui() {
    gridCache.reset();
    previewCache.reset();
    if (clipTex) SDL_DestroyTexture(clipTex);
    for (TTF_Font* f : {fonts.ui, fonts.title, fonts.desc, fonts.small}) if (f) TTF_CloseFont(f);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    if (sdlUp) { TTF_Quit(); IMG_Quit(); SDL_Quit(); }
}

void Ui::begin() {
    marqueeNext = 0;    // set again while the selected name is still scrolling
    setColor(kClear);
    SDL_RenderClear(renderer);
}

void Ui::end() {
    if (!marqueeNext) marqueeKey.clear();   // coming back to the same name starts it over
    SDL_RenderPresent(renderer);
}

void Ui::header(const Header& h, const Battery& battery, const Audio& audio, const std::string& clock) {
    fill(kBar, {0, 0, kScreenW, kHeaderH});
    const int nameY = (kHeaderH - TTF_FontHeight(fonts.ui)) / 2;

    const int statusY = (kHeaderH - TTF_FontHeight(fonts.small)) / 2;
    std::string bat = battery.percent >= 0 ? std::to_string(battery.percent) + "%" : "??";
    int statusX = kScreenW - kMargin - textWidth(fonts.small, bat);
    drawText(renderer, fonts.small, bat, statusX, statusY, kGrey);
    statusX -= 28;
    batteryIcon(statusX, (kHeaderH - 12) / 2, battery.percent, battery.charging, battery.full);

    if (audio.volume >= 0) {
        std::string vol = audio.muted ? tr("muted") : std::to_string(audio.volume) + "%";
        statusX -= 14 + textWidth(fonts.small, vol);
        drawText(renderer, fonts.small, vol, statusX, statusY, kGrey);
        statusX -= 22;
        if (audio.headphones) headphonesIcon(statusX, (kHeaderH - 16) / 2, kGrey);
        else speakerIcon(statusX, (kHeaderH - 16) / 2, kGrey, audio.muted);
    }
    if (!clock.empty()) {
        statusX -= 14 + textWidth(fonts.small, clock);
        drawText(renderer, fonts.small, clock, statusX, statusY, kGrey);
    }

    int countW = textWidth(fonts.small, h.count);
    int maxNameW = statusX - 24 - countW - 10 - kMargin;
    int nameW = std::min(textWidth(fonts.ui, h.title), maxNameW);
    drawText(renderer, fonts.ui, h.title, kMargin, nameY, kWhite, maxNameW);
    drawText(renderer, fonts.small, h.count, kMargin + nameW + 10,
             nameY + TTF_FontAscent(fonts.ui) - TTF_FontAscent(fonts.small), h.highlight ? kYellow : kGrey);
}

// Button in the highlight colour, followed by what it does. The gap between hints shrinks when they
// wouldn't fit on one line (e.g. "Y Remove" is wider than "Y My List").
void Ui::footer(const Hints& hints) {
    const int top = kScreenH - kFooterH;
    fill(kBar, {0, top, kScreenW, kFooterH});

    const int y = top + (kFooterH - TTF_FontHeight(fonts.small)) / 2;
    const int keyGap = 6;
    int textW = 0;
    for (const auto& h : hints) textW += textWidth(fonts.small, h.first) + keyGap + textWidth(fonts.small, h.second);
    const int slots = std::max(1, (int)hints.size() - 1);
    const int gap = std::clamp((kScreenW - 2 * kMargin - textW) / slots, 4, 16);
    int x = kScreenW - kMargin;
    for (auto it = hints.rbegin(); it != hints.rend(); ++it) {
        x -= textWidth(fonts.small, it->second);
        drawText(renderer, fonts.small, it->second, x, y, kGrey);
        int keyW = textWidth(fonts.small, it->first);
        x -= keyGap + keyW;
        drawText(renderer, fonts.small, it->first, x, y, kYellow);
        x -= gap;
    }
}

// A short message over the footer, e.g. after renaming a game.
void Ui::notice(const std::string& text) {
    const int padX = 14, h = TTF_FontHeight(fonts.desc) + 14;
    const int w = std::min(kScreenW - 2 * kMargin, textWidth(fonts.desc, text) + 2 * padX);
    SDL_Rect r{(kScreenW - w) / 2, kScreenH - kFooterH - h - 10, w, h};
    fill({12, 12, 14, 240}, r);
    frame(kYellow, r, 2);
    drawText(renderer, fonts.desc, text, r.x + padX, r.y + 7, kWhite, w - 2 * padX);
}

void Ui::status(const std::string& text) {
    fill(kClear, {0, 0, kScreenW, kScreenH});
    drawText(renderer, fonts.title, text, (kScreenW - textWidth(fonts.title, text)) / 2,
             (kScreenH - TTF_FontHeight(fonts.title)) / 2, kWhite);
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
    fill(bg, r);
    drawText(renderer, fonts.small, text, x + padX, y + padY, fg);
    return r.w;
}

void Ui::drawIcon(IconCache& cache, const std::string& path, const SDL_Rect& box) {
    IconCache::Icon icon = cache.get(path);
    if (!icon.tex) return;
    SDL_Rect dst{box.x + (box.w - icon.w) / 2, box.y + (box.h - icon.h) / 2, icon.w, icon.h};
    SDL_RenderCopy(renderer, icon.tex, nullptr, &dst);
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
    if (scroll > 0) triangle(ax, y + 5, 5, true, kYellow);
    if (scroll < maxScroll) triangle(ax, y + h - 5, 5, false, kYellow);
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
int Ui::pillWidth(const std::string& text) {
    auto it = pillWidths.find(text);
    if (it != pillWidths.end()) return it->second;
    return pillWidths[text] = textWidth(fonts.small, text) + 12;
}

int Ui::marqueeOffset(const std::string& key, int overflow) {
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
    frame(kGrey, {x, y, 22, 12}, 1);
    fill(kGrey, {x + 22, y + 3, 2, 6});
    const SDL_Color c = full || (charging && percent >= 100) ? kGreen
                      : charging ? kYellow : percent <= 10 ? kRed : kGrey;
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
