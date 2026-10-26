#include "trailer.h"

#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>

extern char** environ;

Trailer::~Trailer() {
    stop();
    if (tex) SDL_DestroyTexture(tex);
}

void Trailer::start(SDL_Renderer* r, const std::string& path, int width, int height) {
    stop();
    clip = path;
    if (!tex || w != width || h != height) {
        if (tex) SDL_DestroyTexture(tex);
        w = width;
        h = height;
        tex = SDL_CreateTexture(r, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, w, h);
        buf.assign((size_t)w * h * 3 / 2, 0);
    }
    if (!tex) return;

    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) return;
    const std::string vf = "scale=" + std::to_string(w) + ":" + std::to_string(h) +
                           ":force_original_aspect_ratio=increase:flags=bilinear,crop=" + std::to_string(w) + ":" + std::to_string(h);
    const char* argv[] = {"ffmpeg", "-nostdin", "-loglevel", "quiet", "-threads", "2", "-re", "-i", path.c_str(),
                          "-an", "-vf", vf.c_str(), "-pix_fmt", "yuv420p", "-f", "rawvideo", "-", nullptr};
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, fds[1], STDOUT_FILENO);
    posix_spawn_file_actions_addopen(&fa, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    pid_t child = -1;
    const int err = posix_spawnp(&child, "ffmpeg", &fa, nullptr, (char* const*)argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    close(fds[1]);
    if (err != 0) {
        close(fds[0]);
        return;
    }
    pid = child;
    fd = fds[0];
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

void Trailer::stop() {
    if (pid > 0) {
        kill(pid, SIGKILL);
        waitpid(pid, nullptr, 0);
    }
    if (fd >= 0) close(fd);
    pid = -1;
    fd = -1;
    have = 0;
    shown = false;
}

int Trailer::update() {
    if (fd < 0) return -1;
    int got = 0;
    for (;;) {
        const ssize_t n = read(fd, buf.data() + have, buf.size() - have);
        if (n > 0) {
            have += (size_t)n;
            if (have == buf.size()) {
                SDL_UpdateTexture(tex, nullptr, buf.data(), w);
                have = 0;
                shown = true;
                got = 1;
            }
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            return got;
        } else {    // the end of the clip, or ffmpeg failed
            stop();
            return -1;
        }
    }
}
