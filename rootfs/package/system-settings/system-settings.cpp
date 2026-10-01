#include <SDL2/SDL.h>
#include "imgui.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <alsa/asoundlib.h>

const char* ALSA_MIXER_NAME = "Headphone";
const char* ALSA_CARD = "hw:GA36mbAudio";

// Restored on boot by S91settings / persist-settings.sh
const char* BRIGHTNESS_STATE_FILE = "/etc/player-flags/brightness";
// Handled by the root power-manager, which stores the ALSA state
const char* POWER_REQUEST_FIFO = "/run/power-request";
const Uint32 SAVE_DELAY_MS = 800;

int get_brightness() {
    std::ifstream file("/sys/class/backlight/backlight/brightness");
    int brightness = 5;
    if (file.is_open()) {
        file >> brightness;
    }
    return std::max(1, std::min(brightness, 10));
}
void set_brightness(int brightness) {
    std::ofstream file("/sys/class/backlight/backlight/brightness");
    if (file.is_open()) {
        file << brightness;
    }
}

void save_brightness(int brightness) {
    std::string tmp = std::string(BRIGHTNESS_STATE_FILE) + ".tmp";
    {
        std::ofstream file(tmp);
        if (!file.is_open()) return;
        file << brightness << "\n";
    }
    rename(tmp.c_str(), BRIGHTNESS_STATE_FILE);
}

void request_volume_save() {
    int fd = open(POWER_REQUEST_FIFO, O_WRONLY | O_NONBLOCK);
    if (fd < 0) return;
    const char cmd[] = "save-settings\n";
    ssize_t written = write(fd, cmd, sizeof(cmd) - 1);
    (void)written;
    close(fd);
}

long get_alsa_volume() {
    long min, max, vol = 0;
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;

    snd_mixer_open(&handle, 0);
    snd_mixer_attach(handle, ALSA_CARD);
    snd_mixer_selem_register(handle, NULL, NULL);
    snd_mixer_load(handle);

    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_index(sid, 0);
    snd_mixer_selem_id_set_name(sid, ALSA_MIXER_NAME);

    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    if (elem) {
        snd_mixer_selem_get_playback_volume_range(elem, &min, &max);
        snd_mixer_selem_get_playback_volume(elem, SND_MIXER_SCHN_FRONT_LEFT, &vol);
        if (max > min) vol = ((vol - min) * 100) / (max - min);
    }
    snd_mixer_close(handle);
    return vol;
}
void set_alsa_volume(long volume) {
    long min, max;
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;

    snd_mixer_open(&handle, 0);
    snd_mixer_attach(handle, ALSA_CARD);
    snd_mixer_selem_register(handle, NULL, NULL);
    snd_mixer_load(handle);

    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_index(sid, 0);
    snd_mixer_selem_id_set_name(sid, ALSA_MIXER_NAME);

    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    if (elem) {
        snd_mixer_selem_get_playback_volume_range(elem, &min, &max);
        long scaled_vol = min + (volume * (max - min)) / 100;
        snd_mixer_selem_set_playback_volume_all(elem, scaled_vol);
    }
    snd_mixer_close(handle);
}
bool get_alsa_mute() {
    int switch_state = 1;
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;

    snd_mixer_open(&handle, 0);
    snd_mixer_attach(handle, ALSA_CARD);
    snd_mixer_selem_register(handle, NULL, NULL);
    snd_mixer_load(handle);

    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_index(sid, 0);
    snd_mixer_selem_id_set_name(sid, ALSA_MIXER_NAME);

    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    if (elem && snd_mixer_selem_has_playback_switch(elem)) {
        snd_mixer_selem_get_playback_switch(elem, SND_MIXER_SCHN_FRONT_LEFT, &switch_state);
    }
    snd_mixer_close(handle);

    return (switch_state == 0); // 0 = muted, 1 = unmuted
}

void set_alsa_mute(bool mute) {
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;

    snd_mixer_open(&handle, 0);
    snd_mixer_attach(handle, ALSA_CARD);
    snd_mixer_selem_register(handle, NULL, NULL);
    snd_mixer_load(handle);

    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_index(sid, 0);
    snd_mixer_selem_id_set_name(sid, ALSA_MIXER_NAME);

    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    if (elem && snd_mixer_selem_has_playback_switch(elem)) {
        snd_mixer_selem_set_playback_switch_all(elem, mute ? 0 : 1);
    }
    snd_mixer_close(handle);
}



void section_headear(const char* text) {
    float windowWidth = ImGui::GetWindowSize().x;
    float textWidth = ImGui::CalcTextSize(text).x;

    ImGui::SetCursorPosX((windowWidth - textWidth) * 0.5f);
    ImGui::Text("%s", text);
    ImGui::Separator();
    ImGui::Spacing();
}

int main(int argc, char* argv[]) {
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER) != 0) {
        return -1;
    }

    SDL_Window* window = SDL_CreateWindow("System Settings",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        640, 480, SDL_WINDOW_SHOWN | SDL_WINDOW_ALLOW_HIGHDPI);

    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1,
        SDL_RENDERER_PRESENTVSYNC | SDL_RENDERER_ACCELERATED);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;

    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad;

    ImGui_ImplSDL2_InitForSDLRenderer(window, renderer);
    ImGui_ImplSDLRenderer2_Init(renderer);

    ImGui::GetStyle().FontScaleMain = 1.65;

    SDL_GameController* controller = nullptr;
    for (int i = 0; i < SDL_NumJoysticks(); ++i) {
        if (SDL_IsGameController(i)) {
            controller = SDL_GameControllerOpen(i);
            if (controller) break;
        }
    }

    // Settings Values
    int display_brightness = get_brightness();
    int current_volume = get_alsa_volume();
    bool current_mute = get_alsa_mute();

    // Changes are saved SAVE_DELAY_MS after the last edit, so holding the d-pad doesn't hammer the SD card
    bool brightness_dirty = false;
    bool volume_dirty = false;
    Uint32 last_change = 0;

    bool running = true;
    while (running) {
        SDL_Event event;

        bool pending = brightness_dirty || volume_dirty;
        if (pending ? SDL_WaitEventTimeout(&event, 100) : SDL_WaitEvent(&event)) {
            do {
                ImGui_ImplSDL2_ProcessEvent(&event);
                if (event.type == SDL_QUIT) {
                    running = false;
                }
            } while (SDL_PollEvent(&event));
        }

        if (pending && SDL_GetTicks() - last_change >= SAVE_DELAY_MS) {
            if (brightness_dirty) save_brightness(display_brightness);
            if (volume_dirty) request_volume_save();
            brightness_dirty = volume_dirty = false;
        }

        ImGui_ImplSDLRenderer2_NewFrame();
        ImGui_ImplSDL2_NewFrame();
        ImGui::NewFrame();

        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::SetNextWindowSize(io.DisplaySize);
        ImGuiWindowFlags window_flags = ImGuiWindowFlags_NoDecoration |
                                        ImGuiWindowFlags_NoMove |
                                        ImGuiWindowFlags_NoSavedSettings;

        ImGui::Begin("Settings", nullptr, window_flags);
        ImGui::Text("System Settings");
        ImGui::Separator();
        ImGui::Spacing();

        section_headear("Display");
        if (ImGui::SliderInt("Brightness", &display_brightness, 1, 10)) {
            set_brightness(display_brightness);
            brightness_dirty = true;
            last_change = SDL_GetTicks();
        }

        section_headear("Audio Settings");
        if (ImGui::SliderInt("Master Volume", &current_volume, 0, 100)) {
            set_alsa_volume(current_volume);

            if (current_mute && current_volume > 0) {
                current_mute = false;
                set_alsa_mute(current_mute);
            }
            volume_dirty = true;
            last_change = SDL_GetTicks();
        }

        if (ImGui::Checkbox("Global Mute", &current_mute)) {
            set_alsa_mute(current_mute);
            volume_dirty = true;
            last_change = SDL_GetTicks();
        }

        if (ImGui::Button("System Settings")) {
            // CPU Governer [select box]
            // CPU info [label]
            // Ram info [label]
            // Show free space on SD card
            // Maybe move this to a dedicated System Info app?
        }
        if (ImGui::Button("Input Settings")) {
            // Swap A/B [toggle]
            // Input Tester (maybe this should be it's own app?)
        }
        if (ImGui::Button("Date/Time")) {
            // Set date
            // Set Time
        }

        ImGui::Spacing();
        if (ImGui::Button("Exit Application")) {
            running = false;
        }

        ImGui::End();

        ImGui::Render();
        SDL_SetRenderDrawColor(renderer, 45, 45, 45, 255);
        SDL_RenderClear(renderer);
        ImGui_ImplSDLRenderer2_RenderDrawData(ImGui::GetDrawData(), renderer);
        SDL_RenderPresent(renderer);
    }

    if (brightness_dirty) save_brightness(display_brightness);
    if (volume_dirty) request_volume_save();

    if (controller) SDL_GameControllerClose(controller);

    ImGui_ImplSDLRenderer2_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
