#pragma once
// The device as the launcher sees it: power requests, the screen, battery, clock and mixer.
#include <SDL2/SDL.h>
#include <alsa/asoundlib.h>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <string>

#include "config.h"

void runDetached(const std::string& command);
void sendPowerRequest(const char* request);
bool screenOn();
extern bool batteryCharging, batteryFull;
std::string clockFormat();
std::string clockText(const std::string& fmt);
int readBattery();

// headphones: the speaker is switched off (no jack detection on the GA36-MB)
struct Audio {
    int volume = -1;          // -1: no mixer
    bool muted = false;
    bool headphones = false;

    bool operator!=(const Audio& o) const {
        return volume != o.volume || muted != o.muted || headphones != o.headphones;
    }

    void read() {
        volume = -1;
        snd_mixer_t* mixer = nullptr;
        if (snd_mixer_open(&mixer, 0) < 0) return;
        if (snd_mixer_attach(mixer, cfg.alsaCard.c_str()) < 0 || snd_mixer_selem_register(mixer, nullptr, nullptr) < 0 ||
            snd_mixer_load(mixer) < 0) {
            snd_mixer_close(mixer);
            return;
        }
        snd_mixer_selem_id_t* sid;
        snd_mixer_selem_id_alloca(&sid);
        snd_mixer_selem_id_set_name(sid, "Headphone");
        if (snd_mixer_elem_t* e = snd_mixer_find_selem(mixer, sid)) {
            long min = 0, max = 0, v = 0;
            int on = 1;
            snd_mixer_selem_get_playback_volume_range(e, &min, &max);
            snd_mixer_selem_get_playback_volume(e, SND_MIXER_SCHN_FRONT_LEFT, &v);
            if (snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_get_playback_switch(e, SND_MIXER_SCHN_FRONT_LEFT, &on);
            // 64 hardware levels: the nearest multiple of 5 is the level that was asked for
            volume = max > min ? (int)std::lround((v - min) * 20.0 / (max - min)) * 5 : 0;
            muted = !on || volume == 0;
        }
        snd_mixer_selem_id_set_name(sid, "Speaker");
        headphones = false;
        if (snd_mixer_elem_t* e = snd_mixer_find_selem(mixer, sid)) {
            int on = 1;
            if (snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_get_playback_switch(e, SND_MIXER_SCHN_FRONT_LEFT, &on);
            headphones = !on;
        }
        snd_mixer_close(mixer);
    }
};

