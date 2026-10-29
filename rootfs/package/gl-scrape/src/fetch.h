#pragma once
// HTTP through the curl program. The URL reaches curl on its standard input (-K -), so the
// credentials in it never show in the process list.
#include <string>

struct Fetched {
    long status = 0;        // the HTTP status; 0 when no answer came
    std::string body;       // fetch()'s answer
    std::string error;      // curl's message when no answer came
};

Fetched fetch(const std::string& url, int timeoutSeconds);
// The answer goes to path only when the status is 200 (through path.part)
Fetched download(const std::string& url, const std::string& path, int timeoutSeconds);
std::string urlEncode(const std::string& s);
