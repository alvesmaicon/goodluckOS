#pragma once
// The console's mixer: the ALSA card of puppy.conf's alsa_card. On the GA36-MB, Headphone is the
// volume of both outputs and switching Speaker off leaves the sound on the headphones only (FN + DOWN,
// or the jack through triggerhappy: see system/jack.h). On the R36H the RK817's Master is the volume
// and its Playback Mux plays on one output at a time.
#include <alsa/asoundlib.h>

// The card, open and loaded for as long as the object lives.
class Mixer {
public:
    Mixer();
    ~Mixer();

    Mixer(const Mixer&) = delete;
    Mixer& operator=(const Mixer&) = delete;

    bool ok() const { return handle != nullptr; }
    snd_mixer_elem_t* find(const char* name) const;     // a simple control, or nullptr

private:
    snd_mixer_t* handle = nullptr;
};

struct Audio {
    int volume = -1;          // -1: no mixer
    bool muted = false;       // switched off, or at 0
    bool switchedOff = false; // Global Mute
    bool hasSwitch = true;    // the RK817 has none: no Global Mute
    bool headphones = false;

    bool operator!=(const Audio& o) const {
        return volume != o.volume || muted != o.muted || switchedOff != o.switchedOff || headphones != o.headphones;
    }

    void read();
};

void setVolume(int percent);
void setMuted(bool muted);
// Through audio-output.sh (as root), like FN + DOWN: it also sets the speaker's high-pass filter
// and shows the change in the HUD.
void setOutput(bool speaker);
