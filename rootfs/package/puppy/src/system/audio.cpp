#include "system/audio.h"

#include <cmath>
#include <cstring>

#include "config.h"
#include "system/device.h"
#include "system/jack.h"

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

// The GA36-MB's Headphone (63 steps of 1 dB), or the R36H's RK817 Master: its 95 dB would leave half
// the scale silent, so its percent follows amixer -M's curve (10^(dB/60)), as in volstep.sh.
static snd_mixer_elem_t* volumeControl(const Mixer& mixer, bool& mapped) {
    mapped = false;
    if (snd_mixer_elem_t* e = mixer.find("Headphone")) return e;
    mapped = true;
    return mixer.find("Master");
}

static int readPercent(snd_mixer_elem_t* e, bool mapped) {
    long min = 0, max = 0, v = 0;
    if (mapped && snd_mixer_selem_get_playback_dB_range(e, &min, &max) == 0 && max > min &&
        snd_mixer_selem_get_playback_dB(e, SND_MIXER_SCHN_FRONT_LEFT, &v) == 0) {
        double n = std::pow(10.0, (v - max) / 6000.0);
        if (min != SND_CTL_TLV_DB_GAIN_MUTE) {
            const double floor = std::pow(10.0, (min - max) / 6000.0);
            n = (n - floor) / (1 - floor);
        }
        return (int)std::lround(n * 20) * 5;
    }
    snd_mixer_selem_get_playback_volume_range(e, &min, &max);
    snd_mixer_selem_get_playback_volume(e, SND_MIXER_SCHN_FRONT_LEFT, &v);
    // 64 hardware levels: the nearest multiple of 5 is the level that was asked for
    return max > min ? (int)std::lround((v - min) * 20.0 / (max - min)) * 5 : 0;
}

static void writePercent(snd_mixer_elem_t* e, bool mapped, int percent) {
    long min = 0, max = 0;
    if (mapped && snd_mixer_selem_get_playback_dB_range(e, &min, &max) == 0 && max > min) {
        double n = percent / 100.0;
        if (min != SND_CTL_TLV_DB_GAIN_MUTE) {
            const double floor = std::pow(10.0, (min - max) / 6000.0);
            n = n * (1 - floor) + floor;
        }
        snd_mixer_selem_set_playback_dB_all(e, n > 0 ? std::lround(6000.0 * std::log10(n)) + max : min, 0);
        return;
    }
    snd_mixer_selem_get_playback_volume_range(e, &min, &max);
    snd_mixer_selem_set_playback_volume_all(e, min + std::lround(percent * (max - min) / 100.0));
}

void Audio::read() {
    volume = -1;
    Mixer mixer;
    if (!mixer.ok()) return;
    bool mapped = false;
    if (snd_mixer_elem_t* e = volumeControl(mixer, mapped)) {
        int on = 1;
        hasSwitch = snd_mixer_selem_has_playback_switch(e);
        if (hasSwitch) snd_mixer_selem_get_playback_switch(e, SND_MIXER_SCHN_FRONT_LEFT, &on);
        volume = readPercent(e, mapped);
        muted = !on || volume == 0;
        switchedOff = !on;
    }
    headphones = false;
    if (snd_mixer_elem_t* e = mixer.find("Speaker")) {
        int on = 1;
        if (snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_get_playback_switch(e, SND_MIXER_SCHN_FRONT_LEFT, &on);
        headphones = !on;
    } else if (mixer.find("Playback Mux")) {
        headphones = jack::plugged();   // the RK817's speakers hang on its headphone output: the jack decides
    }
}

void setVolume(int percent) {
    Mixer mixer;
    bool mapped = false;
    if (snd_mixer_elem_t* e = volumeControl(mixer, mapped)) writePercent(e, mapped, percent);
}

void setMuted(bool muted) {
    Mixer mixer;
    bool mapped = false;
    snd_mixer_elem_t* e = volumeControl(mixer, mapped);
    if (e && snd_mixer_selem_has_playback_switch(e)) snd_mixer_selem_set_playback_switch_all(e, muted ? 0 : 1);
}

void setOutput(bool speaker) {
    runScript(std::string("audio-output.sh ") + (speaker ? "speaker" : "headphones"), true);
}
