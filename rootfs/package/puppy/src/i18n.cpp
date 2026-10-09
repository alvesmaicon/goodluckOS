#include "i18n.h"

#include <dirent.h>

#include <algorithm>
#include <fstream>
#include <map>

#include "config.h"
#include "util.h"

namespace i18n {

static std::map<std::string, std::string>& table() {
    static std::map<std::string, std::string> t;
    return t;
}

static std::string& code() {
    static std::string c = "en";
    return c;
}

static std::string unescape(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size() && s[i + 1] == 'n') { out += '\n'; ++i; }
        else out += s[i];
    }
    return out;
}

// Calls f(key, value) for each "key = value" line of a language file.
template <typename F>
static void forEachEntry(const std::string& path, F f) {
    std::ifstream in(path);
    std::string line;
    while (std::getline(in, line)) {
        if (line.size() >= 3 && (unsigned char)line[0] == 0xEF) line.erase(0, 3);   // UTF-8 BOM
        if (trim(line).empty() || trim(line)[0] == '#') continue;
        size_t eq = line.find(" = ");
        if (eq == std::string::npos) continue;
        f(unescape(trim(line.substr(0, eq))), unescape(trim(line.substr(eq + 3))));
    }
}

std::vector<Language> available() {
    std::vector<Language> langs;
    if (DIR* dir = opendir(cfg.langDir.c_str())) {
        while (struct dirent* d = readdir(dir)) {
            std::string file = d->d_name;
            if (file.size() <= 5 || file.compare(file.size() - 5, 5, ".lang") != 0) continue;
            Language l;
            l.code = file.substr(0, file.size() - 5);
            l.name = l.code;
            forEachEntry(cfg.langDir + "/" + file, [&](const std::string& k, const std::string& v) {
                if (k == "language") l.name = v;
                else if (k == "language_en") l.english = v;
            });
            if (l.english.empty()) l.english = l.name;
            if (l.code != "en") langs.push_back(l);
        }
        closedir(dir);
    }
    std::sort(langs.begin(), langs.end(), [](const Language& a, const Language& b) { return a.name < b.name; });
    Language en;
    en.code = "en";
    en.name = "English";
    en.english = "English";
    langs.insert(langs.begin(), en);
    return langs;
}

const std::string& current() {
    return code();
}

void load(const std::string& c) {
    table().clear();
    code() = c.empty() ? "en" : c;
    if (code() == "en" || code().find('/') != std::string::npos) return;
    forEachEntry(cfg.langDir + "/" + code() + ".lang", [](const std::string& k, const std::string& v) {
        if (k != "language" && k != "language_en" && !v.empty()) table()[k] = v;
    });
}

const char* tr(const char* english) {
    auto it = table().find(english);
    return it == table().end() ? english : it->second.c_str();
}

std::string tr(const std::string& english) {
    auto it = table().find(english);
    return it == table().end() ? english : it->second;
}

std::string Language::display() const { return tr(english); }

}  // namespace i18n
