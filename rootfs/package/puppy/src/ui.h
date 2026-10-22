#pragma once
// Drawing for every screen: the window, fonts, shapes, text and covers, and the bars they share
// (the top bar with the clock, volume, battery and temperatures, and the footer with the button hints).
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>

#include <cstdint>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "system/audio.h"
#include "system/device.h"

void drawText(SDL_Renderer* r, TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int maxW = 0,
              int scrollX = 0);
int textWidth(TTF_Font* font, const std::string& text);
std::string elided(TTF_Font* font, const std::string& text, int maxW);   // cut with "..." to fit maxW

class IconCache {
public:
    struct Icon {
        SDL_Texture* tex = nullptr;
        int w = 0, h = 0;
    };

    // Images larger than boxW x boxH are scaled down: cropped to cover the box, or with 'fit' shrunk
    // to fit inside it. Smaller images are kept at their size. Scaled images are saved in
    // cfg.thumbDir(), so big covers (e.g. 800x600 scraper images) are only decoded and scaled once.
    IconCache(SDL_Renderer* r, const std::string& fallbackPath, int boxW, int boxH, bool fit);
    ~IconCache();

    IconCache(const IconCache&) = delete;
    IconCache& operator=(const IconCache&) = delete;

    Icon get(const std::string& path);

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

    std::string thumbPath(const std::string& path) const;
    Icon load(const std::string& path);
    void evictOldest();
};

// The top bar's title and what follows it ("NES", "686 games"); highlight: the count in yellow.
struct Header {
    std::string title, count;
    bool highlight = false;
};

// The top bar's items right of the title, the ones System Settings -> Overlay turns on for the launcher.
struct TopBar {
    std::optional<int> cpuTemp, pmicTemp;   // degrees C, -1 when unreadable
    std::string clock;                      // "": off
    std::optional<Audio> audio;
    std::optional<Battery> battery;

    bool operator!=(const TopBar& o) const {
        return cpuTemp != o.cpuTemp || pmicTemp != o.pmicTemp || clock != o.clock || audio != o.audio || battery != o.battery;
    }
};

// The footer: each button with what it does.
using Hints = std::vector<std::pair<std::string, std::string>>;

struct Fonts {
    TTF_Font* ui = nullptr;
    TTF_Font* title = nullptr;
    TTF_Font* desc = nullptr;
    TTF_Font* small = nullptr;
    TTF_Font* uiBold = nullptr;      // the modern style's titles and button names (retro: none)
    TTF_Font* smallBold = nullptr;
};

class Ui {
public:
    Ui(const std::string& font, const std::string& bold, float scale);
    ~Ui();

    Ui(const Ui&) = delete;
    Ui& operator=(const Ui&) = delete;

    bool ok() const { return ok_; }
    SDL_Renderer* sdl() const { return renderer; }
    const Fonts& font() const { return fonts; }
    IconCache& gridIcons() { return *gridCache; }
    IconCache& previewIcons() { return *previewCache; }
    void setFont(const std::string& path, const std::string& bold, float scale);   // bold: "" for none

    void begin();   // a new frame, cleared to the background colour
    void end();     // shows it
    Uint32 marqueeDue() const { return marqueeNext; }   // when the scrolling name needs a frame (0: never)

    // The bars and messages over everything
    void header(const Header& h, const TopBar& bar);
    void footer(const Hints& hints);
    void notice(const std::string& text);
    void status(const std::string& text);

    // The pieces each style draws its own way
    SDL_Color selection(const SDL_Rect& r, bool focused);    // a selected row; returns its text's colour
    void panel(const SDL_Rect& r, SDL_Color inside, SDL_Color border);  // a menu or the keyboard over the screen
    void key(const SDL_Rect& r, bool lit);                   // a key of the keyboard or the button tester
    void tabHighlight(const SDL_Rect& r);                    // the current tab's slot
    void toggle(const SDL_Rect& r, bool on, bool enabled, bool selected);   // a switch, 40x20
    void track(const SDL_Rect& r, SDL_Color c);              // a bar: a level, a scrollbar
    void swatch(const SDL_Rect& r, SDL_Color c, bool selected);   // a colour to choose
    SDL_Color accentOn(bool selected) const;                 // the accent, or what shows over a selected row
    int keyWidth(const std::string& key);                    // a footer button as keyGlyph draws it
    int keyGlyph(const std::string& key, int x, int cy, SDL_Color inside);   // modern: a button in an outline
    void roundRect(const SDL_Rect& r, int radius, SDL_Color c);

    void setColor(SDL_Color c);
    void fill(SDL_Color c, const SDL_Rect& r);
    void frame(SDL_Color c, const SDL_Rect& r, int t);
    void gradient(const SDL_Rect& r, SDL_Color c);
    void star(int cx, int cy, int r, SDL_Color c);
    void triangle(int cx, int cy, int r, bool up, SDL_Color c);
    void sideTriangle(int cx, int cy, int r, bool left, SDL_Color c);
    int pill(const std::string& text, int x, int y, SDL_Color bg, SDL_Color fg);
    int pillWidth(const std::string& text);
    void drawIcon(IconCache& cache, const std::string& path, const SDL_Rect& box);
    int drawWrapped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width);
    int wrappedHeight(TTF_Font* font, const std::string& text, int width);
    int drawWrappedClipped(TTF_Font* font, const std::string& text, int x, int y, SDL_Color color, int width, int maxH,
                           int scrollLines = 0);
    int marqueeOffset(const std::string& key, int overflow);
    void setMarquee(bool on) { marqueeOn = on; }   // off: marqueeOffset() is 0 (a screen under another)
    void speakerIcon(int x, int y, SDL_Color c, bool muted);
    void batteryIcon(int x, int y, int percent, bool charging, bool full);
    void headphonesIcon(int x, int y, SDL_Color c);
    void chipIcon(int x, int y, SDL_Color c);
    void boltIcon(int x, int y, SDL_Color c);

private:
    bool sdlUp = false, ok_ = false;
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    Fonts fonts;
    std::unique_ptr<IconCache> gridCache, previewCache;
    SDL_Texture* clipTex = nullptr;     // drawWrappedClipped's last text
    std::string clipText;
    int clipWidth = 0, clipW = 0, clipH = 0;
    std::map<std::string, int> pillWidths;
    SDL_Texture* circle = nullptr;      // the rounded corners' quarters, made the first time they're drawn
    SDL_Texture* button = nullptr;      // a face button, the same way

    // The selected list row's name, when it doesn't fit, scrolls left to show the rest: it waits a
    // moment, scrolls to the end, waits again and starts over.
    static constexpr Uint32 kMarqueeHoldMs = 1200;
    static constexpr int kMarqueeSpeed = 40;            // pixels per second
    static constexpr Uint32 kMarqueeFrameMs = 33;
    std::string marqueeKey;
    Uint32 marqueeStart = 0, marqueeNext = 0;
    bool marqueeOn = true;
};
