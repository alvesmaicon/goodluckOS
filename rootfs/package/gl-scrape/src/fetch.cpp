#include "fetch.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>

#include <poll.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static const char* kUserAgent = "gl-scrape (goodluckOS)";

static std::string configQuote(const std::string& s) {
    std::string out;
    for (char c : s) {
        if (c == '"' || c == '\\') out += '\\';
        out += c;
    }
    return out;
}

static Fetched curl(const std::string& url, const std::string& out, int timeout) {
    Fetched r;
    int in[2], so[2], se[2];
    if (pipe(in) != 0) { r.error = "pipe"; return r; }
    if (pipe(so) != 0) { close(in[0]); close(in[1]); r.error = "pipe"; return r; }
    if (pipe(se) != 0) { close(in[0]); close(in[1]); close(so[0]); close(so[1]); r.error = "pipe"; return r; }
    const std::string seconds = std::to_string(timeout);
    const pid_t pid = fork();
    if (pid == 0) {
        dup2(in[0], 0);
        dup2(so[1], 1);
        dup2(se[1], 2);
        for (int fd : {in[0], in[1], so[0], so[1], se[0], se[1]}) close(fd);
        execlp("curl", "curl", "-s", "-S", "-L", "--compressed", "-K", "-", "-m", seconds.c_str(),
               "--connect-timeout", "15", "-A", kUserAgent, "-o", out.empty() ? "-" : out.c_str(),
               "-w", "\\n%{http_code}", (char*)nullptr);
        _exit(127);
    }
    close(in[0]);
    close(so[1]);
    close(se[1]);
    if (pid < 0) {
        close(in[1]); close(so[0]); close(se[0]);
        r.error = "fork";
        return r;
    }
    const std::string config = "url = \"" + configQuote(url) + "\"\n";
    for (size_t done = 0; done < config.size();) {
        const ssize_t n = write(in[1], config.data() + done, config.size() - done);
        if (n <= 0 && errno != EINTR) break;
        if (n > 0) done += n;
    }
    close(in[1]);

    std::string sout, serr;
    struct pollfd fds[2] = {{so[0], POLLIN, 0}, {se[0], POLLIN, 0}};
    int open = 2;
    char buf[65536];
    while (open > 0) {
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR) continue;
            break;
        }
        for (int k = 0; k < 2; ++k) {
            if (fds[k].fd < 0 || !(fds[k].revents & (POLLIN | POLLHUP | POLLERR))) continue;
            const ssize_t n = read(fds[k].fd, buf, sizeof(buf));
            if (n > 0) {
                (k ? serr : sout).append(buf, n);
            } else if (n == 0 || errno != EINTR) {
                close(fds[k].fd);
                fds[k].fd = -1;
                --open;
            }
        }
    }
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}

    // the last line is the status (-w)
    const size_t nl = sout.rfind('\n');
    if (nl != std::string::npos) {
        r.status = strtol(sout.c_str() + nl + 1, nullptr, 10);
        sout.erase(nl);
    }
    r.body = std::move(sout);
    if (r.status == 0) {
        r.error = serr.empty() ? "no answer" : serr.substr(0, serr.find('\n'));
        if (r.error.compare(0, 6, "curl: ") == 0) r.error.erase(0, 6);
    }
    return r;
}

Fetched fetch(const std::string& url, int timeoutSeconds) {
    return curl(url, "", timeoutSeconds);
}

Fetched download(const std::string& url, const std::string& path, int timeoutSeconds) {
    const std::string part = path + ".part";
    Fetched r = curl(url, part, timeoutSeconds);
    struct stat st;
    if (r.status == 200 && stat(part.c_str(), &st) == 0 && st.st_size > 0 && rename(part.c_str(), path.c_str()) == 0)
        return r;
    // a failed answer's body is the reason (ScreenScraper answers in text)
    if (FILE* f = fopen(part.c_str(), "rb")) {
        char b[200];
        const size_t n = fread(b, 1, sizeof(b), f);
        fclose(f);
        r.body.assign(b, n);
    }
    remove(part.c_str());
    if (r.status == 200) {
        r.status = 0;
        r.error = "empty file";
    }
    return r;
}

std::string urlEncode(const std::string& s) {
    static const char* hex = "0123456789ABCDEF";
    std::string out;
    for (unsigned char c : s) {
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~') {
            out += (char)c;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
    return out;
}
