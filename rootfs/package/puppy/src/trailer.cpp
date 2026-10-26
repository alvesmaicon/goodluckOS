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

void Trailer::start(SDL_Renderer* r, const std::string& path, int width, int height, bool withSound, bool excerpt) {
    stop();
    clip = path;
    part = excerpt;
    if (!tex || w != width || h != height) {
        if (tex) SDL_DestroyTexture(tex);
        w = width;
        h = height;
        tex = SDL_CreateTexture(r, SDL_PIXELFORMAT_IYUV, SDL_TEXTUREACCESS_STREAMING, w, h);
        buf.assign((size_t)w * h * 3 / 2, 0);
    }
    if (tex) spawn(withSound);
}

// Starts a program with stdin and stdout on the given fds (-1: /dev/null) and, if extra >= 0, fd 3 on it
static pid_t run(const char* const* argv, int in, int out, int extra = -1) {
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    if (in >= 0) posix_spawn_file_actions_adddup2(&fa, in, STDIN_FILENO);
    else posix_spawn_file_actions_addopen(&fa, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (out >= 0) posix_spawn_file_actions_adddup2(&fa, out, STDOUT_FILENO);
    else posix_spawn_file_actions_addopen(&fa, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&fa, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    if (extra >= 0) posix_spawn_file_actions_adddup2(&fa, extra, 3);
    pid_t child = -1;
    const int err = posix_spawnp(&child, argv[0], &fa, nullptr, (char* const*)argv, environ);
    posix_spawn_file_actions_destroy(&fa);
    return err == 0 ? child : -1;
}

static void reap(pid_t& p) {
    if (p > 0) {
        kill(p, SIGKILL);
        waitpid(p, nullptr, 0);
    }
    p = -1;
}

void Trailer::spawn(bool withSound) {
    int fds[2], snd[2] = {-1, -1};
    if (pipe2(fds, O_CLOEXEC) != 0) return;
    if (withSound && pipe2(snd, O_CLOEXEC) != 0) withSound = false;
    fcntl(fds[0], F_SETPIPE_SZ, (int)buf.size() * 2);   // two whole frames, or the clip slows down
    if (withSound) fcntl(snd[1], F_SETPIPE_SZ, 4096);   // the least: ffmpeg runs only as far ahead as aplay plays
    const std::string vf = "scale=" + std::to_string(w) + ":" + std::to_string(h) +
                           ":force_original_aspect_ratio=increase:flags=bilinear,crop=" + std::to_string(w) + ":" + std::to_string(h);
    // -re makes up for its slow start with a burst, which the sound would keep as a lag: with sound,
    // aplay paces ffmpeg instead
    std::vector<const char*> argv = {"ffmpeg", "-nostdin", "-loglevel", "quiet", "-threads", "2"};
    if (!withSound) argv.push_back("-re");
    argv.insert(argv.end(), {"-i", clip.c_str(), "-map", "0:v:0", "-vf", vf.c_str(), "-pix_fmt", "yuv420p", "-f", "rawvideo", "-"});
    if (withSound) argv.insert(argv.end(), {"-map", "0:a:0?", "-ar", "48000", "-ac", "2", "-f", "s16le", "pipe:3"});
    if (part) {     // the duration from ffmpeg's header (there's no ffprobe), then 30 s from a fifth of it
        static const char* kExcerpt =
            "o=$(ffmpeg -nostdin -hide_banner -i \"$1\" 2>&1 | sed -n 's/.*Duration: \\([0-9:]*\\)\\..*/\\1/p' |"
            " awk -F: '{ print int(($1 * 3600 + $2 * 60 + $3) / 5); exit }'); shift; exec ffmpeg -ss \"${o:-0}\" -t 30 \"$@\"";
        argv[0] = clip.c_str();
        argv.insert(argv.begin(), {"sh", "-c", kExcerpt, "trailer"});
    }
    argv.push_back(nullptr);
    pid = run(argv.data(), -1, fds[1], snd[1]);
    close(fds[1]);
    if (withSound) {
        // ffmpeg's own ALSA output asks for the smallest period, and the codec stalls on it
        const char* play[] = {"aplay", "-q", "-D", "default", "-t", "raw", "-f", "S16_LE", "-r", "48000", "-c", "2",
                              "--buffer-time=80000", "--period-time=20000", nullptr};
        if (pid > 0) player = run(play, snd[0], -1);
        close(snd[0]);
        close(snd[1]);
    }
    if (pid < 0) {
        close(fds[0]);
        return;
    }
    fd = fds[0];
    sound = withSound;
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
}

void Trailer::stop() {
    reap(pid);
    reap(player);
    if (fd >= 0) close(fd);
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
        } else if (sound && !shown) {   // ffmpeg won't open a clip with no sound to play: again without
            stop();
            spawn(false);
            if (fd < 0) return -1;
        } else {    // the end of the clip, or ffmpeg failed
            stop();
            return -1;
        }
    }
}
