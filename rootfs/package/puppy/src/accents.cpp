#include "accents.h"

#include <cstdio>

#include "layout.h"

namespace accents {

const std::vector<Accent>& all() {
    static const std::vector<Accent> list = {
        {"yellow", "Yellow", {255, 205, 60, 255}},
        {"orange", "Orange", {255, 150, 60, 255}},
        {"red", "Red", {245, 95, 85, 255}},
        {"pink", "Pink", {245, 120, 180, 255}},
        {"purple", "Purple", {175, 135, 255, 255}},
        {"blue", "Blue", {90, 165, 255, 255}},
        {"cyan", "Cyan", {70, 210, 220, 255}},
        {"green", "Green", {100, 210, 110, 255}},
    };
    return list;
}

int find(const std::string& key) {
    for (size_t i = 0; i < all().size(); ++i)
        if (key == all()[i].key) return (int)i;
    return 0;
}

static SDL_Color& current() {
    static SDL_Color c = all()[0].color;
    return c;
}

void choose(const std::string& key) {
    current() = all()[find(key)].color;
}

std::string hex(SDL_Color c) {
    char s[8];
    snprintf(s, sizeof(s), "%02x%02x%02x", c.r, c.g, c.b);
    return s;
}

}  // namespace accents

SDL_Color accent() {
    return accents::current();
}
