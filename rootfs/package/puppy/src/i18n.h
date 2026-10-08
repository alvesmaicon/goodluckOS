#pragma once
// Translations. Strings are looked up by their English text in <lang_dir>/<code>.lang
// (/usr/share/goodluck/lang), a UTF-8 file with one "English text = Translation" per line ("\n" for
// a line break, "#" comments). Its "language = <native name>" and "language_en = <English name>"
// lines name the language; System Settings shows tr(<English name>), so each language can name the
// others. English needs no file, and any missing translation falls back to the English text. The
// language is language=<code> in the settings file (see Prefs), or puppy.conf's language.
#include <string>
#include <vector>

namespace i18n {

struct Language {
    std::string code;       // file name without ".lang", e.g. "pt-BR"
    std::string name;       // native name, e.g. "Português (Brasil)"
    std::string english;    // English name, e.g. "Portuguese (Brazil)"; shown translated by display()

    std::string display() const;
};

std::vector<Language> available();      // English, then every language file found, by name
const std::string& current();
void load(const std::string& code);     // "" or "en": English
const char* tr(const char* english);    // the translation, or the English text itself
std::string tr(const std::string& english);

}  // namespace i18n
