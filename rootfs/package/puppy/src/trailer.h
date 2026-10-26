#pragma once
// A game's trailer, the clip a scraper puts in its gamelist.xml (<video>), or for a video 30 s of itself
// from a fifth of the way in. ffmpeg decodes it at its own pace (-re), scaled and cropped to the box,
// into a pipe; each whole frame goes to a texture. Its sound, when asked for, goes through a second
// pipe to aplay. Stopping, or the clip ending, kills both. What Puppy starts dies with it when a game starts (appd), so nothing is left behind.
#include <SDL2/SDL.h>
#include <sys/types.h>

#include <string>
#include <vector>

class Trailer {
public:
    Trailer() = default;
    ~Trailer();

    Trailer(const Trailer&) = delete;
    Trailer& operator=(const Trailer&) = delete;

    void start(SDL_Renderer* r, const std::string& path, int w, int h, bool sound, bool excerpt);
    void stop();
    int update();                           // reads what ffmpeg wrote: 1 a new frame, 0 none, -1 the clip ended
    bool running() const { return pid > 0; }
    SDL_Texture* frame() const { return running() && shown ? tex : nullptr; }   // the last whole frame
    const std::string& path() const { return clip; }

private:
    void spawn(bool withSound);

    pid_t pid = -1;
    pid_t player = -1;          // aplay, with the sound
    int fd = -1;
    SDL_Texture* tex = nullptr;
    int w = 0, h = 0;
    std::vector<Uint8> buf;     // one frame, as it comes in
    size_t have = 0;
    bool shown = false;
    bool sound = false;         // this run plays the clip's sound
    bool part = false;          // only a part of the video plays
    std::string clip;
};
