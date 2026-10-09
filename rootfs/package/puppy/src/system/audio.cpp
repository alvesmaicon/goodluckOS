#include "system/audio.h"

#include <cmath>

#include "config.h"
#include "system/device.h"

Mixer::Mixer() {
    if (snd_mixer_open(&handle, 0) < 0) {
        handle = nullptr;
        return;
    }
    if (snd_mixer_attach(handle, cfg.alsaCard.c_str()) < 0 || snd_mixer_selem_register(handle, nullptr, nullptr) < 0 ||
        snd_mixer_load(handle) < 0) {
        snd_mixer_close(handle);
        handle = nullptr;
    }
}

Mixer::~Mixer() {
    if (handle) snd_mixer_close(handle);
}

snd_mixer_elem_t* Mixer::find(const char* name) const {
    if (!handle) return nullptr;
    snd_mixer_selem_id_t* sid;
    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_name(sid, name);
    return snd_mixer_find_selem(handle, sid);
}

void Audio::read() {
    volume = -1;
    Mixer mixer;
    if (!mixer.ok()) return;
    if (snd_mixer_elem_t* e = mixer.find("Headphone")) {
        long min = 0, max = 0, v = 0;
        int on = 1;
        snd_mixer_selem_get_playback_volume_range(e, &min, &max);
        snd_mixer_selem_get_playback_volume(e, SND_MIXER_SCHN_FRONT_LEFT, &v);
        if (snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_get_playback_switch(e, SND_MIXER_SCHN_FRONT_LEFT, &on);
        // 64 hardware levels: the nearest multiple of 5 is the level that was asked for
        volume = max > min ? (int)std::lround((v - min) * 20.0 / (max - min)) * 5 : 0;
        muted = !on || volume == 0;
        switchedOff = !on;
    }
    headphones = false;
    if (snd_mixer_elem_t* e = mixer.find("Speaker")) {
        int on = 1;
        if (snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_get_playback_switch(e, SND_MIXER_SCHN_FRONT_LEFT, &on);
        headphones = !on;
    }
}

void setVolume(int percent) {
    Mixer mixer;
    if (snd_mixer_elem_t* e = mixer.find("Headphone")) {
        long min = 0, max = 0;
        snd_mixer_selem_get_playback_volume_range(e, &min, &max);
        snd_mixer_selem_set_playback_volume_all(e, min + std::lround(percent * (max - min) / 100.0));
    }
}

void setMuted(bool muted) {
    Mixer mixer;
    snd_mixer_elem_t* e = mixer.find("Headphone");
    if (e && snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_set_playback_switch_all(e, muted ? 0 : 1);
}

void setOutput(bool speaker) {
    runScript(std::string("audio-output.sh ") + (speaker ? "speaker" : "headphones"), true);
}
