#pragma once
// Screen layout, colours and timings of the launcher.
#include <SDL2/SDL.h>

#include <cstddef>

constexpr int kScreenW              = 640;
constexpr int kScreenH              = 480;

constexpr int kHeaderH              = 44;
constexpr int kTabsH                = 30;   // tab strip under the header
constexpr int kFooterH              = 30;
constexpr int kMargin               = 16;
constexpr int kBorder               = 3;

// Grid view: tiles in columns, the selected entry's name over a gradient at the bottom.
constexpr int kCellWidth            = 171;  // 4:3 like the 320x240 covers, so none is cut
constexpr int kCellHeight           = 128;
constexpr int kGridCols             = 3;
constexpr int kGridGap              = 16;
constexpr int kGridPitchY           = kCellHeight + kGridGap;
constexpr int kGridFullRows         = 2;    // rows kept fully visible above the title area

// List view: names on the left, a preview of the selected entry on the right.
constexpr int kListRowH             = 32;
constexpr int kListWidth            = 352;
constexpr int kPreviewX             = kMargin + kListWidth + kMargin;
constexpr int kPreviewW             = kScreenW - kPreviewX - kMargin;
constexpr int kPreviewH             = kPreviewW * 3 / 4;

// The Vitrine style's list (Shelf): a narrower list, the picture over the game's data, an A-Z rail.
constexpr int kShelfListW           = 312;
constexpr int kShelfCardX           = kScreenW - kMargin - 28 - kPreviewW;     // the rail's 28 px on its right

// The Vitrine style's grid (Streaming): the selected game's picture behind its data, one row of covers
// per tab under it, the next tab's row peeking out at the bottom. The top bar is see-through over the
// picture, so everything sits its height higher.
constexpr int kHeroW                = 400;
constexpr int kHeroH                = 300;
constexpr int kCardW                = 136;
constexpr int kCardH                = 102;
constexpr int kCardGap              = 10;
constexpr int kRowsTop              = 224;
constexpr Uint8 kBarShade           = 110;  // the see-through top bar's opacity at its bottom edge
constexpr int kRowLabelH            = 24;
constexpr int kRowPitch             = kRowLabelH + kCardH + 12;
constexpr int kRowSkip              = 10;   // covers L1/R1 jump along a row

constexpr int kMaxQueryLength       = 32;
constexpr int kMaxNameLength        = 96;   // renaming a game's file
constexpr Uint32 kNoticeMs          = 2500;

constexpr Uint32 kIdleCheckMs       = 60000;
constexpr Uint32 kSensorReadMs      = 5000;  // the top bar's battery and temperatures, at most this often
constexpr Uint32 kFollowMs          = 2200;  // after a hotkey, the levels are re-read while the Mesa HUD shows its bar
constexpr Uint8 kFnButton           = 10;    // BTN_MODE, which the SDL mapping leaves out
constexpr Uint32 kFollowReadMs      = 100;   // that often (the hotkey script runs async)
constexpr Uint32 kRepeatDelayMs     = 350;  // holding the d-pad repeats the move after this...
constexpr Uint32 kRepeatRateMs      = 60;   // ...and then this often
constexpr Uint32 kScrollDelayMs     = 250;  // right stick: description scroll repeat
constexpr Uint32 kScrollRateMs      = 110;
constexpr int    kStickOn           = 20000;    // analog stick deflection that counts as a press...
constexpr int    kStickOff          = 12000;    // ...and that releases it (hysteresis, so it doesn't flicker)
constexpr size_t kMaxCachedIcons    = 64;

// The tab strip can be hidden (System Settings -> Show Tabs); the content then moves up.
inline int bodyTop(bool showTabs)  { return kHeaderH + (showTabs ? kTabsH : 0); }
inline int gridTop(bool showTabs)  { return bodyTop(showTabs) + 8; }
inline int listTop(bool showTabs)  { return bodyTop(showTabs) + 6; }
inline int listRows(bool showTabs) { return (kScreenH - kFooterH - listTop(showTabs) - 4) / kListRowH; }

constexpr SDL_Color kYellow {255, 205, 60, 255};
constexpr SDL_Color kRed    {230, 60, 50, 255};
constexpr SDL_Color kGreen  {80, 200, 90, 255};
SDL_Color accent();         // the highlight colour chosen in System Settings (accents.h); kYellow by default

// The colours of the interface style (styles.h)
struct Theme {
    bool modern;
    bool vitrine;                       // the launcher in Vitrine's layouts: Shelf (list) and Streaming (grid)
    SDL_Color bg, bar, tile, rowSel;    // the screen, the top and bottom bars, tiles and tracks, a selected row
    SDL_Color text, muted, item, dim;   // titles and values, secondary text, a list's other entries, a row not usable now
    SDL_Color ink;                      // text on the accent colour
};
const Theme& theme();
