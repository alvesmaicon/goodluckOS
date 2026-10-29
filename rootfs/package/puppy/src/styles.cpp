#include "styles.h"

namespace styles {

const std::vector<Style>& all() {
    static const std::vector<Style> list = {
        {"retro", "Retro", {false, {24, 24, 28, 255}, {12, 12, 14, 255}, {40, 40, 44, 255}, {56, 56, 64, 255},
                            {255, 255, 255, 255}, {170, 170, 170, 255}, {170, 170, 170, 255}, {100, 100, 104, 255},
                            {0, 0, 0, 255}}},
        {"showcase", "Showcase", {true, {11, 13, 18, 255}, {7, 8, 12, 255}, {30, 34, 43, 255}, {44, 50, 63, 255},
                                  {255, 255, 255, 255}, {184, 188, 198, 255}, {226, 229, 236, 255}, {92, 98, 112, 255},
                                  {11, 13, 18, 255}}},
    };
    return list;
}

int find(const std::string& key) {
    for (size_t i = 0; i < all().size(); ++i)
        if (key == all()[i].key) return (int)i;
    return 0;
}

static const Theme* current = &all()[0].theme;

void choose(const std::string& key) {
    current = &all()[find(key)].theme;
}

}  // namespace styles

const Theme& theme() {
    return *styles::current;
}
