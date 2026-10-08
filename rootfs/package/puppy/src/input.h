#pragma once
#include <SDL2/SDL.h>

enum class Action { None, Up, Down, Left, Right, Launch, Back, ToggleAutoStart, ToggleFavorite, Search, PrevTab, NextTab, Start, Power,
                    ScrollUp, ScrollDown, GameMenu };

bool isRepeatable(Action a);
bool isScroll(Action a);
Action stickDirection(int x, int y, Action current);
Action actionFromKey(SDL_Keycode k);
Action actionFromButton(Uint8 b);
