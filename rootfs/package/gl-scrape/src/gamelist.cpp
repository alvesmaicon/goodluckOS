#include "gamelist.h"

#include <cstdio>
#include <fstream>
#include <iterator>

static std::string unescape(const std::string& s) {
    static const std::pair<const char*, char> kEntities[] = {{"&amp;", '&'}, {"&lt;", '<'}, {"&gt;", '>'}, {"&quot;", '"'}, {"&apos;", '\''}};
    std::string out;
    for (size_t i = 0; i < s.size();) {
        bool done = false;
        if (s[i] == '&')
            for (const auto& [k, v] : kEntities) {
                const size_t n = std::char_traits<char>::length(k);
                if (s.compare(i, n, k) == 0) {
                    out += v;
                    i += n;
                    done = true;
                    break;
                }
            }
        if (!done) out += s[i++];
    }
    return out;
}

std::string xmlEscape(const std::string& s) {
    std::string out;
    for (char c : s) {
        switch (c) {
            case '&': out += "&amp;"; break;
            case '<': out += "&lt;"; break;
            case '>': out += "&gt;"; break;
            case '"': out += "&quot;"; break;
            case '\'': out += "&apos;"; break;
            default: out += c;
        }
    }
    return out;
}

static std::string trim(const std::string& s) {
    const size_t a = s.find_first_not_of(" \t\r\n");
    if (a == std::string::npos) return "";
    return s.substr(a, s.find_last_not_of(" \t\r\n") - a + 1);
}

// Where the text of <tag>...</tag> sits in a game block: [open, close)
static bool locate(const std::string& block, const std::string& tag, size_t& open, size_t& close) {
    const std::string o = "<" + tag + ">";
    const size_t a = block.find(o);
    if (a == std::string::npos) return false;
    const size_t b = block.find("</" + tag + ">", a + o.size());
    if (b == std::string::npos) return false;
    open = a + o.size();
    close = b;
    return true;
}

static std::string tagText(const std::string& block, const std::string& tag) {
    size_t a, b;
    return locate(block, tag, a, b) ? trim(unescape(block.substr(a, b - a))) : "";
}

static std::string romOf(const std::string& block) {
    std::string p = tagText(block, "path");
    if (p.compare(0, 2, "./") == 0) p.erase(0, 2);
    return p;
}

void Gamelist::load(const std::string& path) {
    parts.clear();
    changed = false;
    std::ifstream in(path, std::ios::binary);
    std::string xml((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    if (xml.find("<gameList") == std::string::npos) xml = "<?xml version=\"1.0\"?>\n<gameList>\n</gameList>\n";
    size_t pos = 0;
    for (size_t at = 0; (at = xml.find("<game", at)) != std::string::npos;) {
        // "<game>" or "<game id=...>", not "<gameList>"
        const char next = at + 5 < xml.size() ? xml[at + 5] : '\0';
        if (next != '>' && next != ' ' && next != '\t') {
            at += 5;
            continue;
        }
        const size_t end = xml.find("</game>", at);
        if (end == std::string::npos) break;
        parts.push_back({xml.substr(pos, at - pos), ""});
        const std::string block = xml.substr(at, end + 7 - at);
        parts.push_back({block, romOf(block)});
        pos = at = end + 7;
    }
    parts.push_back({xml.substr(pos), ""});
}

int Gamelist::find(const std::string& file) const {
    for (size_t i = 0; i < parts.size(); ++i)
        if (!parts[i].file.empty() && parts[i].file == file) return (int)i;
    return -1;
}

bool Gamelist::has(const std::string& file) const {
    return find(file) >= 0;
}

std::string Gamelist::get(const std::string& file, const std::string& tag) const {
    const int i = find(file);
    return i < 0 ? "" : tagText(parts[i].text, tag);
}

void Gamelist::set(const std::string& file, const Tags& tags, bool overwrite) {
    int i = find(file);
    if (i < 0) {
        // before </gameList>, in the text after the last game
        Part& last = parts.back();
        const size_t close = last.text.rfind("</gameList>");
        const size_t at = close == std::string::npos ? last.text.size() : close;
        Part after{last.text.substr(at), ""};
        last.text.erase(at);
        if (!last.text.empty() && last.text.back() != '\n') last.text += "\n";
        last.text += "\t";
        parts.push_back({"<game>\n\t\t<path>./" + xmlEscape(file) + "</path>\n\t</game>", file});
        after.text = "\n" + after.text;
        parts.push_back(after);
        i = (int)parts.size() - 2;
        changed = true;
    }
    std::string& block = parts[i].text;
    for (const auto& [tag, value] : tags) {
        if (value.empty()) continue;
        size_t a, b;
        if (locate(block, tag, a, b)) {
            const std::string now = trim(unescape(block.substr(a, b - a)));
            if (now == value || (!now.empty() && !overwrite)) continue;
            block.replace(a, b - a, xmlEscape(value));
        } else {
            block.insert(block.rfind("</game>"), "\t<" + tag + ">" + xmlEscape(value) + "</" + tag + ">\n\t");
        }
        changed = true;
    }
}

bool Gamelist::save(const std::string& path) {
    if (!changed) return true;
    const std::string tmp = path + ".tmp";
    FILE* f = fopen(tmp.c_str(), "wb");
    if (!f) return false;
    bool ok = true;
    for (const Part& p : parts) ok = ok && fwrite(p.text.data(), 1, p.text.size(), f) == p.text.size();
    ok = fclose(f) == 0 && ok;
    if (!ok || rename(tmp.c_str(), path.c_str()) != 0) {
        remove(tmp.c_str());
        return false;
    }
    changed = false;
    return true;
}
