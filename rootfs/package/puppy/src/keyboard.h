#pragma once
#include <cmath>
#include <string>
#include <vector>

// On-screen keyboard for the name search, driven by the d-pad. QWERTY like Android's: rows are
// staggered and some keys are wider, so positions and widths are in key units (10 per row).
struct Keyboard {
    struct Key {
        std::string label;
        float x, w;     // in key units
    };
    static constexpr int kRows = 5;
    static constexpr float kRowUnits = 10.0f;

    bool caps = false;      // the Aa key: letters typed in upper case
    int row = 1, col = 0;   // starts on Q

    static const std::vector<Key>& keys(int r) {
        static const std::vector<std::vector<Key>> kLayout = [] {
            auto evenRow = [](const char* chars, float x0) {
                std::vector<Key> keys;
                for (const char* c = chars; *c; ++c) keys.push_back({std::string(1, *c), x0++, 1.0f});
                return keys;
            };
            std::vector<std::vector<Key>> rows;
            rows.push_back(evenRow("1234567890", 0.0f));
            rows.push_back(evenRow("qwertyuiop", 0.0f));
            rows.push_back(evenRow("asdfghjkl", 0.5f));
            std::vector<Key> r3 = {{"-", 0.0f, 1.5f}};
            for (const Key& k : evenRow("zxcvbnm", 1.5f)) r3.push_back(k);
            r3.push_back({"del", 8.5f, 1.5f});
            rows.push_back(r3);
            // Aa switches the case; ( ) and . are common in game file names
            rows.push_back({{"shift", 0.0f, 1.5f}, {"'", 1.5f, 1.0f}, {"(", 2.5f, 1.0f}, {")", 3.5f, 1.0f},
                            {"space", 4.5f, 3.0f}, {".", 7.5f, 1.0f}, {"ok", 8.5f, 1.5f}});
            return rows;
        }();
        return kLayout[r];
    }

    const std::string& current() const { return keys(row)[col].label; }

    void move(int dx, int dy) {
        if (dx) {
            int n = (int)keys(row).size();
            col = (col + dx + n) % n;
        }
        if (dy) {
            // the rows are staggered: land on the key closest to the centre of the current one
            const Key& from = keys(row)[col];
            float centre = from.x + from.w / 2;
            row = (row + dy + kRows) % kRows;
            const auto& to = keys(row);
            col = 0;
            for (int i = 1; i < (int)to.size(); ++i) {
                if (std::fabs(to[i].x + to[i].w / 2 - centre) < std::fabs(to[col].x + to[col].w / 2 - centre)) col = i;
            }
        }
    }
};
