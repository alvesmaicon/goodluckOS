#include "util.h"

#include <cctype>
#include <cstdio>
#include <cstdlib>

// String helper functions
std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && std::isspace((unsigned char)s[a])) ++a;
    while (b > a && std::isspace((unsigned char)s[b - 1])) --b;
    return s.substr(a, b - a);
}

std::string upper(std::string s) {
    for (auto& c : s) c = (char)std::toupper((unsigned char)c);
    return s;
}

std::string lower(std::string s) {
    for (auto& c : s) c = (char)std::tolower((unsigned char)c);
    return s;
}

// Converts semicolon-separated-list to an vector:
// "a;b;c;" -> {"a","b","c"}
std::vector<std::string> splitList(const std::string& s) {
    std::vector<std::string> out;
    size_t start = 0;
    while (start <= s.size()) {
        size_t end = s.find(';', start);
        if (end == std::string::npos) end = s.size();
        std::string item = trim(s.substr(start, end - start));
        if (!item.empty()) out.push_back(item);
        start = end + 1;
    }
    return out;
}

// Single-quote a string for safe use in a shell command line.
std::string shellQuote(const std::string& s) {
    std::string out = "'";
    for (char c : s) {
        if (c == '\'') out += "'\\''";
        else out += c;
    }
    out += "'";
    return out;
}

std::string homeDir() {
    const char* home = getenv("HOME");
    return home && *home ? home : "/root";
}

// "~/x" -> "$HOME/x"
std::string expandHome(const std::string& path) {
    if (path == "~" || path.compare(0, 2, "~/") == 0) return homeDir() + path.substr(1);
    return path;
}

void replaceAll(std::string& s, const std::string& from, const std::string& to) {
    if (from.empty()) return;
    for (size_t pos = 0; (pos = s.find(from, pos)) != std::string::npos; pos += to.size()) s.replace(pos, from.size(), to);
}

std::string humanSize(unsigned long long kb) {
    char buf[32];
    if (kb >= 1024ULL * 1024) snprintf(buf, sizeof(buf), "%.1f GB", kb / (1024.0 * 1024.0));
    else if (kb >= 1024) snprintf(buf, sizeof(buf), "%.0f MB", kb / 1024.0);
    else snprintf(buf, sizeof(buf), "%llu KB", kb);
    return buf;
}

std::string trf(const char* english, const std::string& value) {
    std::string text = tr(english);
    size_t pos = text.find("%s");
    if (pos != std::string::npos) text.replace(pos, 2, value);
    return text;
}
