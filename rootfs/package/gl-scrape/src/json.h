#pragma once
// A small JSON reader and writer, for ScreenScraper's answers and the cache.
#include <string>
#include <utility>
#include <vector>

struct Json {
    enum class Type { Null, Bool, Number, String, Array, Object };
    Type type = Type::Null;
    std::string text;                                   // a string's value; a number or a bool as written
    std::vector<Json> items;                            // an array's
    std::vector<std::pair<std::string, Json>> fields;   // an object's, in order

    const Json& operator[](const std::string& key) const;   // null when missing
    const Json& operator[](size_t i) const;
    bool isNull() const { return type == Type::Null; }
    Json& set(const std::string& key, Json value);       // an object's field, replaced or added
    Json& push(Json value);                              // an array's next item

    static Json str(const std::string& s);
    static Json array();
    static Json object();
    static bool parse(const std::string& in, Json& out);
    std::string dump() const;
};
