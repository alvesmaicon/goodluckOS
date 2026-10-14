#pragma once
// The confirm button in RetroArch's Nintendo cores (GB/GBC, GBA, NES, SNES). Their games confirm with A,
// so with B (bottom) confirming, their core remaps (config/remaps/<core>/<core>.rmp) swap A and B.

void addRetroArchSwap();        // in the cores whose remap leaves A and B alone
void removeRetroArchSwap();     // where the remap swaps them as addRetroArchSwap() does
