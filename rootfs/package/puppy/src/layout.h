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
constexpr int kCellWidth            = 192;
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

constexpr int kMaxQueryLength       = 32;
constexpr int kMaxNameLength        = 96;   // renaming a game's file
constexpr Uint32 kNoticeMs          = 2500;

constexpr Uint32 kIdleCheckMs       = 60000;
constexpr Uint32 kOsdShowMs         = 2200;  // keeps redrawing while the Mesa HUD shows the bar (1.5 s after the script writes it)
constexpr Uint8 kFnButton           = 10;    // BTN_MODE, which the SDL mapping leaves out
constexpr Uint32 kOsdRefreshMs      = 100;   // re-read the level while it's up (the hotkey script runs async)
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

constexpr SDL_Color kWhite  {255, 255, 255, 255};
constexpr SDL_Color kGrey   {170, 170, 170, 255};
constexpr SDL_Color kBlack  {0, 0, 0, 255};
constexpr SDL_Color kYellow {255, 205, 60, 255};
constexpr SDL_Color kRed    {230, 60, 50, 255};
constexpr SDL_Color kGreen  {80, 200, 90, 255};
constexpr SDL_Color kTile   {40, 40, 44, 255};
constexpr SDL_Color kRowSel {56, 56, 64, 255};
constexpr SDL_Color kBar    {12, 12, 14, 255};
constexpr SDL_Color kClear  {24, 24, 28, 255};
