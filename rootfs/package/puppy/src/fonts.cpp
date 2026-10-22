#include "fonts.h"

#include <fstream>

#include "config.h"
#include "util.h"

namespace fonts {

const std::vector<Font>& all() {
    static const std::vector<Font> list = {
        {"default", "Default", nullptr, 1.0f},
        {"vt323", "VT323", "VT323-Regular.ttf", 1.2f},
        {"pixelify", "Pixelify Sans", "PixelifySans-VF.ttf", 1.05f},
        {"proggy", "ProggyClean", "ProggyClean.ttf", 1.25f},
    };
    return list;
}

int find(const std::string& key) {
    for (size_t i = 0; i < all().size(); ++i)
        if (key == all()[i].key) return (int)i;
    return 0;
}

std::string path(const Font& f) {
    if (!f.file) return cfg.font;
    return (fs::path(cfg.font).parent_path() / f.file).string();
}

bool available(const Font& f) {
    std::ifstream in(path(f));
    return in.good();
}

// The modern style's default, after Vitrine's (SIL Open Font License, next to them)
static const char* kModernFont = "AtkinsonHyperlegible-Regular.ttf";
static const char* kModernBold = "AtkinsonHyperlegible-Bold.ttf";

void choose(const std::string& key, bool modern, std::string& file, std::string& bold, float& scale) {
    const Font& f = all()[find(key)];
    const fs::path dir = fs::path(cfg.font).parent_path();
    bold.clear();
    if (modern && !f.file && std::ifstream(dir / kModernFont).good()) {
        file = (dir / kModernFont).string();
        bold = std::ifstream(dir / kModernBold).good() ? (dir / kModernBold).string() : file;
        scale = 1.0f;
        return;
    }
    const bool there = available(f);
    file = there ? path(f) : cfg.font;
    scale = there ? f.scale : 1.0f;
    if (modern) bold = file;
}

}  // namespace fonts
