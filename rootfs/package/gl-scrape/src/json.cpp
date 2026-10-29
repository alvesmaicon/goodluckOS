#include "json.h"

#include <cstdio>
#include <cstring>

static const Json kNull;

const Json& Json::operator[](const std::string& key) const {
    if (type == Type::Object)
        for (const auto& f : fields)
            if (f.first == key) return f.second;
    return kNull;
}

const Json& Json::operator[](size_t i) const {
    return type == Type::Array && i < items.size() ? items[i] : kNull;
}

Json& Json::set(const std::string& key, Json value) {
    type = Type::Object;
    for (auto& f : fields)
        if (f.first == key) return f.second = std::move(value);
    fields.emplace_back(key, std::move(value));
    return fields.back().second;
}

Json& Json::push(Json value) {
    type = Type::Array;
    items.push_back(std::move(value));
    return items.back();
}

Json Json::str(const std::string& s) {
    Json j;
    j.type = Type::String;
    j.text = s;
    return j;
}

Json Json::array() {
    Json j;
    j.type = Type::Array;
    return j;
}

Json Json::object() {
    Json j;
    j.type = Type::Object;
    return j;
}

static void appendUtf8(std::string& out, unsigned long cp) {
    if (cp < 0x80) out += (char)cp;
    else if (cp < 0x800) { out += (char)(0xC0 | (cp >> 6)); out += (char)(0x80 | (cp & 0x3F)); }
    else if (cp < 0x10000) { out += (char)(0xE0 | (cp >> 12)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
    else { out += (char)(0xF0 | (cp >> 18)); out += (char)(0x80 | ((cp >> 12) & 0x3F)); out += (char)(0x80 | ((cp >> 6) & 0x3F)); out += (char)(0x80 | (cp & 0x3F)); }
}

namespace {

struct Parser {
    const std::string& s;
    size_t i = 0;

    void space() {
        while (i < s.size() && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) ++i;
    }

    bool word(const char* w) {
        const size_t n = strlen(w);
        if (s.compare(i, n, w) != 0) return false;
        i += n;
        return true;
    }

    bool hex4(unsigned long& v) {
        if (i + 4 > s.size()) return false;
        v = 0;
        for (int k = 0; k < 4; ++k) {
            const char c = s[i++];
            v <<= 4;
            if (c >= '0' && c <= '9') v |= c - '0';
            else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
            else return false;
        }
        return true;
    }

    bool string(std::string& out) {
        if (i >= s.size() || s[i] != '"') return false;
        ++i;
        while (i < s.size()) {
            char c = s[i++];
            if (c == '"') return true;
            if (c != '\\') {
                out += c;
                continue;
            }
            if (i >= s.size()) return false;
            c = s[i++];
            switch (c) {
                case '"': case '\\': case '/': out += c; break;
                case 'b': out += '\b'; break;
                case 'f': out += '\f'; break;
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case 'u': {
                    unsigned long cp;
                    if (!hex4(cp)) return false;
                    if (cp >= 0xD800 && cp < 0xDC00 && i + 1 < s.size() && s[i] == '\\' && s[i + 1] == 'u') {
                        i += 2;
                        unsigned long low;
                        if (!hex4(low)) return false;
                        cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                    }
                    appendUtf8(out, cp);
                    break;
                }
                default: return false;
            }
        }
        return false;
    }

    bool value(Json& v, int depth) {
        if (depth > 64) return false;
        space();
        if (i >= s.size()) return false;
        const char c = s[i];
        if (c == '{' || c == '[') {
            const bool object = c == '{';
            v.type = object ? Json::Type::Object : Json::Type::Array;
            ++i;
            space();
            if (i < s.size() && s[i] == (object ? '}' : ']')) {
                ++i;
                return true;
            }
            for (;;) {
                Json item;
                if (object) {
                    space();
                    std::string key;
                    if (!string(key)) return false;
                    space();
                    if (i >= s.size() || s[i] != ':') return false;
                    ++i;
                    if (!value(item, depth + 1)) return false;
                    v.fields.emplace_back(std::move(key), std::move(item));
                } else {
                    if (!value(item, depth + 1)) return false;
                    v.items.push_back(std::move(item));
                }
                space();
                if (i >= s.size()) return false;
                if (s[i] == ',') { ++i; continue; }
                if (s[i] == (object ? '}' : ']')) { ++i; return true; }
                return false;
            }
        }
        if (c == '"') {
            v.type = Json::Type::String;
            return string(v.text);
        }
        for (const char* b : {"true", "false"}) {
            if (!word(b)) continue;
            v.type = Json::Type::Bool;
            v.text = b;
            return true;
        }
        if (word("null")) return true;
        const size_t start = i;
        while (i < s.size() && ((s[i] >= '0' && s[i] <= '9') || s[i] == '-' || s[i] == '+' || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) ++i;
        if (i == start) return false;
        v.type = Json::Type::Number;
        v.text = s.substr(start, i - start);
        return true;
    }
};

void quote(std::string& out, const std::string& s) {
    out += '"';
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char b[8];
                    snprintf(b, sizeof(b), "\\u%04x", c);
                    out += b;
                } else {
                    out += (char)c;
                }
        }
    }
    out += '"';
}

void write(const Json& j, std::string& out) {
    switch (j.type) {
        case Json::Type::Null: out += "null"; break;
        case Json::Type::Bool:
        case Json::Type::Number: out += j.text; break;
        case Json::Type::String: quote(out, j.text); break;
        case Json::Type::Array:
            out += '[';
            for (size_t k = 0; k < j.items.size(); ++k) {
                if (k) out += ',';
                write(j.items[k], out);
            }
            out += ']';
            break;
        case Json::Type::Object:
            out += '{';
            for (size_t k = 0; k < j.fields.size(); ++k) {
                if (k) out += ',';
                quote(out, j.fields[k].first);
                out += ':';
                write(j.fields[k].second, out);
            }
            out += '}';
            break;
    }
}

}  // namespace

bool Json::parse(const std::string& in, Json& out) {
    Parser p{in};
    out = Json();
    if (!p.value(out, 0)) return false;
    p.space();
    return p.i == in.size();
}

std::string Json::dump() const {
    std::string out;
    write(*this, out);
    return out;
}
