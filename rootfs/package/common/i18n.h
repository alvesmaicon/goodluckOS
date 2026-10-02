// Minimal translations for the goodluckOS apps (Puppy, System Settings, are-you-sure).
//
// Strings are looked up by their English text in /usr/share/goodluck/lang/<code>.lang, a UTF-8
// file with one "English text = Translation" per line ("\n" for a line break, "#" comments).
// Its "language = <native name>" and "language_en = <English name>" lines name the language; the
// settings show tr(<English name>), so each language can name the others. English needs no file, and any
// missing translation falls back to the English text. The language comes from
// ~/.config/puppy/settings ("language=<code>"), shared with the launcher options.
//
// Header-only and C++11, so every app can include it.
#pragma once

#include <dirent.h>

#include <algorithm>
#include <fstream>
#include <map>
#include <string>
#include <vector>

namespace i18n {

// The paths can be changed before loading (Puppy takes them from its puppy.conf).
inline std::string& langDirPath() { static std::string p = "/usr/share/goodluck/lang"; return p; }
inline std::string& settingsPath() { static std::string p = "/home/player/.config/puppy/settings"; return p; }
inline const char* langDir() { return langDirPath().c_str(); }
inline const char* settingsFile() { return settingsPath().c_str(); }

struct Language {
    std::string code;       // file name without ".lang", e.g. "pt-BR"
    std::string name;       // native name, e.g. "Português (Brasil)"
    std::string english;    // English name, e.g. "Portuguese (Brazil)"; shown translated by display()

    std::string display() const;
};

inline std::map<std::string, std::string>& table() {
    static std::map<std::string, std::string> t;
    return t;
}

inline std::string trimmed(const std::string& s) {
    size_t a = s.find_first_not_of(" \t\r");
    if (a == std::string::npos) return std::string();
    size_t b = s.find_last_not_of(" \t\r");
    return s.substr(a, b - a + 1);
}

inline std::string unescape(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size() && s[i + 1] == 'n') { out += '\n'; ++i; }
        else out += s[i];
    }
    return out;
}

// Calls f(key, value) for each "key = value" line of a language file.
template <typename F>
inline void forEachEntry(const std::string& path, F f) {
    std::ifstream in(path.c_str());
    std::string line;
    while (std::getline(in, line)) {
        if (line.size() >= 3 && (unsigned char)line[0] == 0xEF) line.erase(0, 3);   // UTF-8 BOM
        if (trimmed(line).empty() || trimmed(line)[0] == '#') continue;
        size_t eq = line.find(" = ");
        if (eq == std::string::npos) continue;
        f(unescape(trimmed(line.substr(0, eq))), unescape(trimmed(line.substr(eq + 3))));
    }
}

// English plus every language file found, by name.
inline std::vector<Language> available() {
    std::vector<Language> langs;
    if (DIR* dir = opendir(langDir())) {
        while (struct dirent* d = readdir(dir)) {
            std::string file = d->d_name;
            if (file.size() <= 5 || file.compare(file.size() - 5, 5, ".lang") != 0) continue;
            Language l;
            l.code = file.substr(0, file.size() - 5);
            l.name = l.code;
            forEachEntry(std::string(langDir()) + "/" + file, [&](const std::string& k, const std::string& v) {
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

// The value of "key=value" in the settings file (the last one wins), or "".
inline std::string settingValue(const std::string& key) {
    std::ifstream in(settingsFile());
    const std::string prefix = key + "=";
    std::string line, value;
    while (std::getline(in, line)) {
        line = trimmed(line);
        if (line.compare(0, prefix.size(), prefix) == 0 && line.size() > prefix.size()) value = line.substr(prefix.size());
    }
    return value;
}

inline std::string configuredLanguage() {
    const std::string code = settingValue("language");
    return code.empty() ? "en" : code;
}

inline std::string& current() {
    static std::string code = "en";
    return code;
}

inline void load(const std::string& code) {
    table().clear();
    current() = code;
    if (code == "en" || code.empty() || code.find('/') != std::string::npos) return;
    forEachEntry(std::string(langDir()) + "/" + code + ".lang", [](const std::string& k, const std::string& v) {
        if (k != "language" && k != "language_en" && !v.empty()) table()[k] = v;
    });
}

inline void loadConfigured() { load(configuredLanguage()); }

// The translation of an English string, or the string itself.
inline const char* tr(const char* english) {
    std::map<std::string, std::string>::const_iterator it = table().find(english);
    return it == table().end() ? english : it->second.c_str();
}

inline std::string tr(const std::string& english) {
    std::map<std::string, std::string>::const_iterator it = table().find(english);
    return it == table().end() ? english : it->second;
}

// The language's name in the current language ("Portuguese (Brazil)" while in English).
inline std::string Language::display() const { return tr(english); }

}  // namespace i18n
