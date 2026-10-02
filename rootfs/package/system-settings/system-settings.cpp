#include <SDL2/SDL.h>
#include "imgui.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#include <fstream>
#include <string>
#include <vector>
#include <fcntl.h>
#include <unistd.h>
#include <alsa/asoundlib.h>

const char* ALSA_MIXER_NAME = "Headphone";
const char* ALSA_CARD = "GA36mbAudio";

int get_brightness() {
    return 5;
}
void set_brightness(int brightness) {
    std::ofstream file("/sys/class/backlight/backlight/brightness");
    if (file.is_open()) {
        file << brightness;
    }
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
        vol = (vol * 100) / max;
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
        long scaled_vol = (volume * max) / 100;
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

const char* HUD_CONFIG = "/home/player/.config/gallium_hud.conf";
const char* HUD_POSITIONS[] = {"top-left", "top-right", "bottom-left", "bottom-right"};
const char* HUD_POSITION_NAMES[] = {"Top left", "Top right", "Bottom left", "Bottom right"};

struct HudSettings {
    bool visible = false;
    bool cpu = true;
    bool text = false;
    int position = 0;
};

HudSettings load_hud_settings() {
    HudSettings hud;
    std::ifstream file(HUD_CONFIG);
    std::string line;
    while (std::getline(file, line)) {
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string key = line.substr(0, eq), value = line.substr(eq + 1);
        if (key == "HUD_VISIBLE") hud.visible = value == "true";
        else if (key == "HUD_ITEMS") hud.cpu = value == "fps,cpu";
        else if (key == "HUD_STYLE") hud.text = value == "text";
        else if (key == "HUD_POSITION") {
            for (int i = 0; i < 4; i++) {
                if (value == HUD_POSITIONS[i]) hud.position = i;
            }
        }
    }
    return hud;
}

void save_hud_settings(const HudSettings& hud) {
    std::ofstream file(HUD_CONFIG);
    file << "HUD_VISIBLE=" << (hud.visible ? "true" : "false") << "\n"
         << "HUD_ITEMS=" << (hud.cpu ? "fps,cpu" : "fps") << "\n"
         << "HUD_STYLE=" << (hud.text ? "text" : "graph") << "\n"
         << "HUD_POSITION=" << HUD_POSITIONS[hud.position] << "\n";
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
    HudSettings hud = load_hud_settings();


    bool running = true;
    while (running) {
        SDL_Event event;

        if (SDL_WaitEvent(&event)) {
            do {
                ImGui_ImplSDL2_ProcessEvent(&event);
                if (event.type == SDL_QUIT) {
                    running = false;
                }
            } while (SDL_PollEvent(&event));
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
        }

        section_headear("Audio Settings");
        if (ImGui::SliderInt("Master Volume", &current_volume, 0, 100)) {
            set_alsa_volume(current_volume);

            if (current_mute && current_volume > 0) {
                current_mute = false;
                set_alsa_mute(current_mute);
            }
        }

        if (ImGui::Checkbox("Global Mute", &current_mute)) {
            set_alsa_mute(current_mute);
        }

        section_headear("Performance Overlay");
        bool hud_changed = ImGui::Checkbox("Show on game start", &hud.visible);
        ImGui::Text("Content:");
        ImGui::SameLine();
        if (ImGui::RadioButton("FPS", !hud.cpu)) { hud.cpu = false; hud_changed = true; }
        ImGui::SameLine();
        if (ImGui::RadioButton("FPS + CPU", hud.cpu)) { hud.cpu = true; hud_changed = true; }
        ImGui::Text("Style:");
        ImGui::SameLine();
        if (ImGui::RadioButton("Graph", !hud.text)) { hud.text = false; hud_changed = true; }
        ImGui::SameLine();
        if (ImGui::RadioButton("Text", hud.text)) { hud.text = true; hud.position &= 1; hud_changed = true; }
        hud_changed |= ImGui::Combo("Position", &hud.position, HUD_POSITION_NAMES, hud.text ? 2 : 4);
        ImGui::TextDisabled("FN + UP shows or hides it in game");
        if (hud_changed) {
            save_hud_settings(hud);
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

    if (controller) SDL_GameControllerClose(controller);

    ImGui_ImplSDLRenderer2_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();

    SDL_DestroyRenderer(renderer);
    SDL_DestroyWindow(window);
    SDL_Quit();

    return 0;
}
