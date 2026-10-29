#pragma once
// The feedback panel the Mesa HUD draws from /dev/shm/hud-osd (osd-notify.sh) for 1.5 s. The HUD
// only draws with a frame, so a panel written behind Puppy's back (the low battery warning, the USB
// network's) needs Puppy to draw one frame to show it and another to take it away.
#include <SDL2/SDL.h>

void watchOsd(Uint32 eventType);    // pushes an SDL event of this type each time the panel is written
