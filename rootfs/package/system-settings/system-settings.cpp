#include <SDL2/SDL.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "fonts.h"
#include "i18n.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/utsname.h>
#include <alsa/asoundlib.h>

using i18n::tr;

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

void send_power_request(const std::string& cmd) {
    int fd = open(POWER_REQUEST_FIFO, O_WRONLY | O_NONBLOCK);
    if (fd < 0) return;
    std::string line = cmd + "\n";
    ssize_t written = write(fd, line.c_str(), line.size());
    (void)written;
    close(fd);
}

void request_volume_save() {
    send_power_request("save-settings");
}

std::string read_line(const std::string& path) {
    std::ifstream file(path.c_str());
    std::string line;
    std::getline(file, line);
    // device-tree strings end with a NUL
    line.erase(std::remove(line.begin(), line.end(), '\0'), line.end());
    while (!line.empty() && (line.back() == ' ' || line.back() == '\n')) line.pop_back();
    return line;
}

long long read_number(const std::string& path, long long fallback = -1) {
    std::ifstream file(path.c_str());
    long long value;
    return (file >> value) ? value : fallback;
}

std::string human_size_kb(unsigned long long kb) {
    char buf[32];
    if (kb >= 1024ULL * 1024) snprintf(buf, sizeof(buf), "%.1f GB", kb / (1024.0 * 1024.0));
    else if (kb >= 1024) snprintf(buf, sizeof(buf), "%.0f MB", kb / 1024.0);
    else snprintf(buf, sizeof(buf), "%llu KB", kb);
    return buf;
}

// Options of the Puppy launcher, read by it every time it starts: "view=grid|list" and "tabs=on|off"
const char* LAUNCHER_SETTINGS_DIR = "/home/player/.config/puppy";
const char* LAUNCHER_SETTINGS_FILE = "/home/player/.config/puppy/settings";

struct LauncherSettings {
    bool show_tabs = true;
    bool list_view = false;
    std::string language = "en";
    std::string font;           // fonts.h key, "" = not chosen (Inter)
};

LauncherSettings load_launcher_settings() {
    LauncherSettings s;
    std::ifstream file(LAUNCHER_SETTINGS_FILE);
    for (std::string line; std::getline(file, line);) {
        if (line == "view=list") s.list_view = true;
        else if (line == "view=grid") s.list_view = false;
        else if (line == "tabs=off") s.show_tabs = false;
        else if (line == "tabs=on") s.show_tabs = true;
        else if (line.compare(0, 9, "language=") == 0 && line.size() > 9) s.language = line.substr(9);
        else if (line.compare(0, 5, "font=") == 0 && line.size() > 5) s.font = line.substr(5);
    }
    return s;
}

void save_launcher_settings(const LauncherSettings& s) {
    // keep any other options already in the file
    std::vector<std::string> lines;
    {
        std::ifstream file(LAUNCHER_SETTINGS_FILE);
        for (std::string line; std::getline(file, line);) {
            if (line.compare(0, 5, "view=") != 0 && line.compare(0, 5, "tabs=") != 0 &&
                line.compare(0, 9, "language=") != 0 && line.compare(0, 5, "font=") != 0 &&
                !line.empty()) lines.push_back(line);
        }
    }
    lines.push_back(std::string("view=") + (s.list_view ? "list" : "grid"));
    lines.push_back(std::string("tabs=") + (s.show_tabs ? "on" : "off"));
    lines.push_back("language=" + s.language);
    if (!s.font.empty()) lines.push_back("font=" + s.font);

    mkdir("/home/player/.config", 0755);
    mkdir(LAUNCHER_SETTINGS_DIR, 0755);
    std::string tmp = std::string(LAUNCHER_SETTINGS_FILE) + ".tmp";
    {
        std::ofstream file(tmp.c_str());
        if (!file.is_open()) return;
        for (const auto& line : lines) file << line << "\n";
    }
    rename(tmp.c_str(), LAUNCHER_SETTINGS_FILE);
}

const char* HOME_MOUNT = "/home/player";
const char* CARD_SYSFS = "/sys/class/block/mmcblk0";
const char* HOME_PART_SYSFS = "/sys/class/block/mmcblk0p2";
const char* CPUFREQ_SYSFS = "/sys/devices/system/cpu/cpu0/cpufreq";
const char* PERFORMANCE_GOVERNOR = "performance";
// S01resize-home grows the partition and leaves less than this untouched
const unsigned long long RESIZE_MIN_FREE_KB = 8192;

struct SystemInfo {
    std::string model, os, kernel;
    int cpu_mhz = -1, cpu_max_mhz = -1, temp_c = -1000;
    std::string governor, normal_governor;   // normal_governor: what "Performance mode" off means
    long long mem_total_kb = -1, mem_avail_kb = -1;
    int battery = -1;
    std::string battery_status;
    unsigned long long home_total_kb = 0, home_used_kb = 0;
    unsigned long long card_unused_kb = 0;
    unsigned long long tmp_free_kb = 0;
};

SystemInfo gather_system_info() {
    SystemInfo s;
    s.model = read_line("/proc/device-tree/model");

    std::ifstream os_release("/etc/os-release");
    for (std::string line; std::getline(os_release, line);) {
        if (line.compare(0, 12, "PRETTY_NAME=") != 0) continue;
        s.os = line.substr(12);
        s.os.erase(std::remove(s.os.begin(), s.os.end(), '"'), s.os.end());
    }

    struct utsname uts;
    if (uname(&uts) == 0) s.kernel = uts.release;

    std::string cpufreq = CPUFREQ_SYSFS;
    long long cur = read_number(cpufreq + "/scaling_cur_freq");
    long long max = read_number(cpufreq + "/cpuinfo_max_freq");
    if (cur > 0) s.cpu_mhz = (int)(cur / 1000);
    if (max > 0) s.cpu_max_mhz = (int)(max / 1000);
    long long temp = read_number("/sys/class/thermal/thermal_zone0/temp", -1000000);
    if (temp > -1000000) s.temp_c = (int)(temp / 1000);

    s.governor = read_line(cpufreq + "/scaling_governor");
    std::ifstream governors((cpufreq + "/scaling_available_governors").c_str());
    bool has_performance = false;
    for (std::string g; governors >> g;) {
        if (g == PERFORMANCE_GOVERNOR) has_performance = true;
        else if (s.normal_governor.empty() || g == "schedutil") s.normal_governor = g;
    }
    if (!has_performance) s.normal_governor.clear();

    std::ifstream meminfo("/proc/meminfo");
    for (std::string key; meminfo >> key;) {
        long long value;
        if (!(meminfo >> value)) break;
        if (key == "MemTotal:") s.mem_total_kb = value;
        else if (key == "MemAvailable:") s.mem_avail_kb = value;
        meminfo.ignore(64, '\n');
    }

    if (DIR* dir = opendir("/sys/class/power_supply")) {
        while (struct dirent* d = readdir(dir)) {
            std::string base = std::string("/sys/class/power_supply/") + d->d_name;
            if (d->d_name[0] == '.' || read_line(base + "/type") != "Battery") continue;
            s.battery = (int)read_number(base + "/capacity");
            s.battery_status = read_line(base + "/status");
            break;
        }
        closedir(dir);
    }

    struct statvfs vfs;
    if (statvfs(HOME_MOUNT, &vfs) == 0) {
        s.home_total_kb = (unsigned long long)vfs.f_blocks * vfs.f_frsize / 1024;
        s.home_used_kb = s.home_total_kb - (unsigned long long)vfs.f_bfree * vfs.f_frsize / 1024;
    }
    // resize-home backs HOME up to /tmp (a small RAM disk) while it reformats the partition
    if (statvfs("/tmp", &vfs) == 0) {
        s.tmp_free_kb = (unsigned long long)vfs.f_bavail * vfs.f_frsize / 1024;
    }

    long long disk = read_number(std::string(CARD_SYSFS) + "/size");
    long long start = read_number(std::string(HOME_PART_SYSFS) + "/start");
    long long size = read_number(std::string(HOME_PART_SYSFS) + "/size");
    if (disk > 0 && start > 0 && size > 0 && disk > start + size) {
        s.card_unused_kb = (unsigned long long)(disk - start - size) * 512 / 1024;
    }
    return s;
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



// Raw joystick button numbers of the GA36-MB gamepad, the same numbering used by SDL_GAMECONTROLLERCONFIG
// (/etc/profile.d/sdl_controller.sh) and RetroArch's autoconfig. FN is not mapped as a game controller
// button, so the tester reads the raw joystick.
const char* GAMEPAD_BUTTON_NAMES[] = {"B", "A", "X", "Y", "L1", "R1", "L2", "R2", "SELECT", "START",
                                      "FN", "L3", "R3", "UP", "DOWN", "LEFT", "RIGHT"};
const int GAMEPAD_BUTTON_COUNT = sizeof(GAMEPAD_BUTTON_NAMES) / sizeof(GAMEPAD_BUTTON_NAMES[0]);
const int GAMEPAD_BUTTON_B = 0;
const Uint32 TESTER_EXIT_HOLD_MS = 1000;

// Shortcuts, from /etc/triggerhappy/triggers.d, Puppy and the RetroArch config (hotkey = FN)
const char* const SHORTCUTS[][2] = {
    {"Any app", nullptr},
    {"VOL+ / VOL-", "Volume"},
    {"FN + VOL+ / VOL-", "Brightness"},
    {"POWER", "Screen off / on"},
    {"SELECT + START", "Close the app"},
    {"FN + SELECT + START", "Force close the app"},
    {"FN + UP", "FPS / CPU overlay"},
    {"Launcher", nullptr},
    {"L1 / R1", "Previous / next tab"},
    {"D-pad / left stick", "Move"},
    {"LEFT / RIGHT (list)", "Previous / next page"},
    {"Right stick up/down", "Scroll the description"},
    {"A", "Launch"},
    {"Y", "Add to / remove from My List"},
    {"X", "Search by name"},
    {"B", "Clear the search"},
    {"SELECT", "Autolaunch on boot"},
    {"START", "System Settings"},
    {"POWER", "Display off / restart / shut down"},
    {"RetroArch", nullptr},
    {"FN + X", "Menu"},
    {"FN + R1 / L1", "Save / load state"},
    {"FN + LEFT / RIGHT", "State slot"},
    {"FN + Y", "Pause"},
    {"FN + R2", "Fast forward"},
    {"FN + START", "Quit the game"},
};

// A button shape that lights up while pressed. Drawn by hand so it can't take the d-pad focus.
void input_chip(const char* label, bool pressed, float width) {
    ImVec2 size(width, ImGui::GetFrameHeight());
    ImVec2 p = ImGui::GetCursorScreenPos();
    ImDrawList* draw = ImGui::GetWindowDrawList();
    draw->AddRectFilled(p, ImVec2(p.x + size.x, p.y + size.y),
                        pressed ? IM_COL32(66, 150, 250, 255) : IM_COL32(50, 56, 66, 255), 4.0f);
    ImVec2 text = ImGui::CalcTextSize(label);
    draw->AddText(ImVec2(p.x + (size.x - text.x) * 0.5f, p.y + (size.y - text.y) * 0.5f),
                  IM_COL32_WHITE, label);
    ImGui::Dummy(size);
}

// A slider drawn as a level bar: filled from the left up to the value, with the percentage in the
// middle (value / max, so brightness 5 of 10 reads 50%). It's a regular ImGui slider underneath, with
// its frame and grab made transparent and the bar drawn behind it.
// Left/right change the value right away when the bar is selected (step per press), without having to
// press A first as plain ImGui sliders need.
bool level_slider(const char* label, int* value, int min, int max, int step) {
    ImDrawList* draw = ImGui::GetWindowDrawList();
    const ImVec2 pos = ImGui::GetCursorScreenPos();
    const float width = ImGui::CalcItemWidth();
    const float height = ImGui::GetFrameHeight();
    const float rounding = ImGui::GetStyle().FrameRounding;

    draw->ChannelsSplit(2);
    draw->ChannelsSetCurrent(1);
    const ImVec4 clear(0, 0, 0, 0);
    ImGui::PushStyleColor(ImGuiCol_FrameBg, clear);
    ImGui::PushStyleColor(ImGuiCol_FrameBgHovered, clear);
    ImGui::PushStyleColor(ImGuiCol_FrameBgActive, clear);
    ImGui::PushStyleColor(ImGuiCol_SliderGrab, clear);
    ImGui::PushStyleColor(ImGuiCol_SliderGrabActive, clear);
    bool changed = ImGui::SliderInt(label, value, min, max, "");
    ImGui::PopStyleColor(5);
    const bool active = ImGui::IsItemActive() || ImGui::IsItemFocused();
    if (ImGui::IsItemFocused() && !ImGui::IsItemActive()) {
        int delta = 0;
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadRight, true) || ImGui::IsKeyPressed(ImGuiKey_RightArrow, true)) delta = step;
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadLeft, true) || ImGui::IsKeyPressed(ImGuiKey_LeftArrow, true)) delta = -step;
        int v = std::max(min, std::min(max, *value + delta));
        if (v != *value) { *value = v; changed = true; }
    }

    char text[16];
    snprintf(text, sizeof(text), "%d%%", max > 0 ? *value * 100 / max : 0);
    const ImVec2 size = ImGui::CalcTextSize(text);
    draw->AddText(ImVec2(pos.x + (width - size.x) * 0.5f, pos.y + (height - size.y) * 0.5f),
                  ImGui::GetColorU32(ImGuiCol_Text), text);

    draw->ChannelsSetCurrent(0);   // behind the slider
    const ImVec2 end(pos.x + width, pos.y + height);
    draw->AddRectFilled(pos, end, ImGui::GetColorU32(active ? ImGuiCol_FrameBgHovered : ImGuiCol_FrameBg), rounding);
    const float fill = max > 0 ? std::max(0.0f, std::min(1.0f, (float)*value / max)) : 0.0f;
    if (fill > 0.0f)
        draw->AddRectFilled(pos, ImVec2(pos.x + width * fill, end.y), ImGui::GetColorU32(ImGuiCol_SliderGrabActive), rounding);
    draw->ChannelsMerge();
    return changed;
}

void section_headear(const char* english) {
    const char* text = tr(english);
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
    i18n::loadConfigured();
    // Interface fonts: every available one is loaded, so the Font option switches right away; the
    // chosen one is the default
    std::vector<int> font_choices;          // indexes in fonts::all() of the fonts that are there
    std::vector<ImFont*> loaded_fonts;
    for (size_t i = 0; i < fonts::all().size(); ++i) {
        const fonts::Font& f = fonts::forApp(fonts::all()[i], false);
        if (!fonts::available(f)) continue;
        ImFont* font = ImGui::GetIO().Fonts->AddFontFromFileTTF(fonts::path(f).c_str(), 13.0f * f.scale);
        if (!font) continue;
        font_choices.push_back((int)i);
        loaded_fonts.push_back(font);
    }
    int current_font = 0;   // in font_choices
    for (size_t i = 0; i < font_choices.size(); ++i)
        if (&fonts::all()[font_choices[i]] == &fonts::find(fonts::configuredKey())) current_font = (int)i;
    if (!loaded_fonts.empty()) ImGui::GetIO().FontDefault = loaded_fonts[current_font];
    int pending_font = -1;  // switched before the next frame
    ImGuiIO& io = ImGui::GetIO(); (void)io;

    io.ConfigFlags |= ImGuiConfigFlags_NavEnableGamepad | ImGuiConfigFlags_NavEnableKeyboard;
    // Show the focused item (the first slider) right away instead of only after the first d-pad press
    io.ConfigNavCursorVisibleAlways = true;
    // B leaves the app (see main loop) instead of just clearing the highlight
    io.ConfigNavEscapeClearFocusItem = false;

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

    // The volume/brightness hotkeys change the levels behind our back (triggerhappy scripts): after
    // one is pressed, re-read the levels for a moment so the sliders follow
    const Uint32 HOTKEY_FOLLOW_MS = 600, HOTKEY_POLL_MS = 100;
    Uint32 follow_until = 0;

    // ImGui applies the default focus a couple of frames after the window appears, so render those
    // frames right away instead of waiting for the first input event
    int startup_frames = 3;

    enum Page { PAGE_MAIN, PAGE_SYSTEM, PAGE_INPUT, PAGE_TESTER };
    Page page = PAGE_MAIN;
    // Coming back from a sub-page puts the focus on the button that opened it
    bool focus_system_button = false, focus_input_button = false, focus_tester_button = false;
    SDL_Joystick* joystick = controller ? SDL_GameControllerGetJoystick(controller) : nullptr;
    int last_button = -1;
    Uint32 b_hold_start = 0;
    SystemInfo info = gather_system_info();
    bool performance_mode = info.governor == PERFORMANCE_GOVERNOR;
    LauncherSettings launcher = load_launcher_settings();
    const std::vector<i18n::Language> languages = i18n::available();
    bool launch_resize_home = false;

    bool running = true;
    while (running) {
        SDL_Event event;

        bool pending = brightness_dirty || volume_dirty;
        bool following = (Sint32)(follow_until - SDL_GetTicks()) > 0;
        bool got_event;
        if (startup_frames > 0) {
            startup_frames--;
            got_event = SDL_PollEvent(&event);
        } else {
            // the tester redraws continuously to show the sticks and the hold-B progress
            if (page == PAGE_TESTER) got_event = SDL_WaitEventTimeout(&event, 33);
            // the shortcut list scrolls while the d-pad / right stick is held
            else if (page == PAGE_INPUT) got_event = SDL_WaitEventTimeout(&event, 50);
            else if (following) got_event = SDL_WaitEventTimeout(&event, HOTKEY_POLL_MS);
            // keep drawing while left/right is held, so holding it keeps changing a level bar
            else if (ImGui::IsKeyDown(ImGuiKey_GamepadDpadLeft) || ImGui::IsKeyDown(ImGuiKey_GamepadDpadRight) ||
                     ImGui::IsKeyDown(ImGuiKey_LeftArrow) || ImGui::IsKeyDown(ImGuiKey_RightArrow))
                got_event = SDL_WaitEventTimeout(&event, 50);
            else got_event = pending ? SDL_WaitEventTimeout(&event, 100) : SDL_WaitEvent(&event);
        }
        if (got_event) {
            do {
                ImGui_ImplSDL2_ProcessEvent(&event);
                if (event.type == SDL_QUIT) {
                    running = false;
                }
                if (event.type == SDL_KEYDOWN &&
                    (event.key.keysym.sym == SDLK_VOLUMEUP || event.key.keysym.sym == SDLK_VOLUMEDOWN)) {
                    follow_until = SDL_GetTicks() + HOTKEY_FOLLOW_MS;
                    following = true;
                }
            } while (SDL_PollEvent(&event));
        }

        // Don't overwrite a value the user is editing here or hasn't saved yet
        if (following && !pending && !ImGui::IsAnyItemActive()) {
            display_brightness = get_brightness();
            current_volume = get_alsa_volume();
            current_mute = get_alsa_mute();
        }

        if (pending && SDL_GetTicks() - last_change >= SAVE_DELAY_MS) {
            if (brightness_dirty) save_brightness(display_brightness);
            if (volume_dirty) request_volume_save();
            brightness_dirty = volume_dirty = false;
        }

        // B first cancels an active edit; only with nothing active does it leave the app
        bool editing = ImGui::IsAnyItemActive();

        if (pending_font >= 0) {
            ImGui::GetIO().FontDefault = loaded_fonts[pending_font];
            ImGui::GetStyle().FontSizeBase = loaded_fonts[pending_font]->LegacySize;
            current_font = pending_font;
            pending_font = -1;
        }

        ImGui_ImplSDLRenderer2_NewFrame();
        ImGui_ImplSDL2_NewFrame();
        ImGui::NewFrame();
        // Paint the focused item as selected from the first frame, not only after the first d-pad move
        ImGui::GetCurrentContext()->NavHighlightItemUnderNav = true;

        Page next_page = page;
        if (!editing && (ImGui::IsKeyPressed(ImGuiKey_GamepadFaceRight, false) ||
                         ImGui::IsKeyPressed(ImGuiKey_Escape, false))) {
            if (page == PAGE_SYSTEM || page == PAGE_INPUT) next_page = PAGE_MAIN;
            else if (page == PAGE_MAIN) running = false;
            // PAGE_TESTER: B is one of the buttons being tested, it leaves only when held
        }

        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::SetNextWindowSize(io.DisplaySize);
        ImGuiWindowFlags window_flags = ImGuiWindowFlags_NoDecoration |
                                        ImGuiWindowFlags_NoMove |
                                        ImGuiWindowFlags_NoSavedSettings;

        if (page == PAGE_MAIN) {
            ImGui::Begin("Settings", nullptr, window_flags);
            ImGui::Text("%s", tr("System Settings"));
            ImGui::Separator();
            ImGui::Spacing();

            // The options scroll (bigger fonts don't fit the 480px screen), following the d-pad
            // selection; Back stays at the bottom. NavFlattened: the d-pad moves between the list and
            // Back as if they were one.
            const float back_h = ImGui::GetFrameHeightWithSpacing() + ImGui::GetStyle().ItemSpacing.y;
            ImGui::BeginChild("main_list", ImVec2(0, ImGui::GetContentRegionAvail().y - back_h), ImGuiChildFlags_NavFlattened);

            section_headear("Display & Audio");
            if (level_slider(tr("Brightness"), &display_brightness, 1, 10, 1)) {
                set_brightness(display_brightness);
                brightness_dirty = true;
                last_change = SDL_GetTicks();
            }
            ImGui::SetItemDefaultFocus();

            if (level_slider(tr("Master Volume"), &current_volume, 0, 100, 5)) {
                set_alsa_volume(current_volume);

                if (current_mute && current_volume > 0) {
                    current_mute = false;
                    set_alsa_mute(current_mute);
                }
                volume_dirty = true;
                last_change = SDL_GetTicks();
            }

            if (ImGui::Checkbox(tr("Global Mute"), &current_mute)) {
                set_alsa_mute(current_mute);
                volume_dirty = true;
                last_change = SDL_GetTicks();
            }

            // CPU and launcher options share one section so the page still fits the 480px screen
            section_headear("Options");
            if (!info.normal_governor.empty()) {
                if (ImGui::Checkbox(tr("Performance mode (uses more battery)"), &performance_mode)) {
                    send_power_request(std::string("set-governor ") +
                                       (performance_mode ? PERFORMANCE_GOVERNOR : info.normal_governor));
                }
            }

            if (ImGui::Checkbox(tr("Show launcher tabs"), &launcher.show_tabs)) {
                save_launcher_settings(launcher);
            }
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Launcher view:"));
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("Grid"), !launcher.list_view)) {
                launcher.list_view = false;
                save_launcher_settings(launcher);
            }
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("List"), launcher.list_view)) {
                launcher.list_view = true;
                save_launcher_settings(launcher);
            }

            // Languages come from the files in /usr/share/goodluck/lang (see i18n.h)
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Language:"));
            ImGui::SameLine();
            int current_lang = 0;
            for (size_t i = 0; i < languages.size(); ++i)
                if (languages[i].code == i18n::current()) current_lang = (int)i;
            ImGui::SetNextItemWidth(ImGui::GetFontSize() * 11.0f);
            if (ImGui::BeginCombo("##language", languages[current_lang].display().c_str())) {
                for (size_t i = 0; i < languages.size(); ++i) {
                    bool selected = (int)i == current_lang;
                    if (ImGui::Selectable(languages[i].display().c_str(), selected) && !selected) {
                        launcher.language = languages[i].code;
                        save_launcher_settings(launcher);
                        i18n::load(launcher.language);
                    }
                    if (selected) ImGui::SetItemDefaultFocus();
                }
                ImGui::EndCombo();
            }

            // Interface font of every app (fonts.h); the launcher picks it up when it comes back
            if (loaded_fonts.size() > 1) {
                ImGui::AlignTextToFramePadding();
                ImGui::Text("%s", tr("Font:"));
                ImGui::SameLine();
                ImGui::SetNextItemWidth(ImGui::GetFontSize() * 11.0f);
                if (ImGui::BeginCombo("##font", tr(fonts::all()[font_choices[current_font]].name))) {
                    for (size_t i = 0; i < font_choices.size(); ++i) {
                        bool selected = (int)i == current_font;
                        // each name in its own font, as a preview
                        ImGui::PushFont(loaded_fonts[i], loaded_fonts[i]->LegacySize);
                        if (ImGui::Selectable(tr(fonts::all()[font_choices[i]].name), selected) && !selected) {
                            launcher.font = fonts::all()[font_choices[i]].key;
                            save_launcher_settings(launcher);
                            pending_font = (int)i;
                        }
                        ImGui::PopFont();
                        if (selected) ImGui::SetItemDefaultFocus();
                    }
                    ImGui::EndCombo();
                }
            }

            ImGui::Spacing();
            // Always offered here (the launcher hides it after the first run); resize-home shows the
            // details and asks before doing anything. It reformats HOME after backing it up to the RAM
            // disk, so it only works while HOME is still nearly empty (right after flashing).
            bool can_grow = info.card_unused_kb >= RESIZE_MIN_FREE_KB;
            bool fits = info.home_used_kb < info.tmp_free_kb;
            ImGui::BeginDisabled(can_grow && !fits);
            if (ImGui::Button(tr("Resize Home"))) {
                launch_resize_home = true;
                running = false;
            }
            ImGui::EndDisabled();
            if (can_grow && !fits) {
                ImGui::TextWrapped("%s", tr("Too much data in HOME to resize. Resize right after flashing, before copying games."));
            }

            if (focus_system_button) {
                ImGui::SetKeyboardFocusHere();
                focus_system_button = false;
            }
            if (ImGui::Button(tr("System Info"))) {
                info = gather_system_info();
                next_page = PAGE_SYSTEM;
            }
            if (focus_input_button) {
                ImGui::SetKeyboardFocusHere();
                focus_input_button = false;
            }
            if (ImGui::Button(tr("Input Settings"))) {
                next_page = PAGE_INPUT;
            }
            // TODO: Date/Time (the RTC has no backup battery, so the clock resets on every boot)
            ImGui::EndChild();

            ImGui::Spacing();
            if (ImGui::Button(tr("Back"))) {
                running = false;
            }
            ImGui::End();
        } else if (page == PAGE_INPUT) {
            ImGui::Begin("Input", nullptr, window_flags);
            ImGui::Text("%s", tr("Input Settings"));
            ImGui::Separator();
            ImGui::Spacing();

            // The list scrolls with d-pad up/down and the right stick; the buttons sit side by side at
            // the bottom, so left/right picks one and up/down stay free for scrolling
            const float buttons_h = ImGui::GetFrameHeightWithSpacing() + ImGui::GetStyle().ItemSpacing.y;
            ImGui::BeginChild("shortcut_list", ImVec2(0, ImGui::GetContentRegionAvail().y - buttons_h), ImGuiChildFlags_None,
                              ImGuiWindowFlags_NoNavInputs | ImGuiWindowFlags_NoNavFocus);
            const float step = ImGui::GetTextLineHeightWithSpacing() * 0.75f;
            if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadDown, true) || ImGui::IsKeyPressed(ImGuiKey_DownArrow, true) ||
                ImGui::IsKeyDown(ImGuiKey_GamepadRStickDown)) {
                ImGui::SetScrollY(ImGui::GetScrollY() + step);
            }
            if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadUp, true) || ImGui::IsKeyPressed(ImGuiKey_UpArrow, true) ||
                ImGui::IsKeyDown(ImGuiKey_GamepadRStickUp)) {
                ImGui::SetScrollY(ImGui::GetScrollY() - step);
            }
            ImGui::PushFont(nullptr, ImGui::GetStyle().FontSizeBase * 0.75f);
            if (ImGui::BeginTable("shortcuts", 2, ImGuiTableFlags_SizingStretchProp)) {
                for (const auto& row : SHORTCUTS) {
                    ImGui::TableNextRow();
                    ImGui::TableNextColumn();
                    if (!row[1]) {
                        ImGui::TextColored(ImVec4(0.45f, 0.70f, 1.0f, 1.0f), "%s", tr(row[0]));
                        continue;
                    }
                    ImGui::Text("  %s", tr(row[0]));
                    ImGui::TableNextColumn();
                    ImGui::TextUnformatted(tr(row[1]));
                }
                ImGui::EndTable();
            }
            ImGui::PopFont();
            ImGui::EndChild();

            ImGui::Spacing();
            if (focus_tester_button) {
                ImGui::SetKeyboardFocusHere();
                focus_tester_button = false;
            }
            if (ImGui::Button(tr("Button Tester"))) {
                last_button = -1;
                b_hold_start = 0;
                next_page = PAGE_TESTER;
            }
            ImGui::SetItemDefaultFocus();
            ImGui::SameLine();
            if (ImGui::Button(tr("Back"))) {
                next_page = PAGE_MAIN;
            }
            ImGui::End();
        } else if (page == PAGE_TESTER) {
            ImGui::Begin("Tester", nullptr, window_flags);
            ImGui::Text("%s", tr("Button Tester"));
            ImGui::Separator();
            ImGui::Spacing();

            auto pressed = [&](int button) {
                return joystick && button < SDL_JoystickNumButtons(joystick) && SDL_JoystickGetButton(joystick, button);
            };
            for (int b = 0; b < GAMEPAD_BUTTON_COUNT; ++b) {
                if (pressed(b)) last_button = b;
            }

            const float w = 92.0f, gap = ImGui::GetStyle().ItemSpacing.x;
            static const int rows[][5] = {
                {6, 4, -1, 5, 7},           // L2 L1   R1 R2
                {13, 14, 15, 16, -1},       // d-pad
                {2, 3, 1, 0, -1},           // X Y A B
                {8, 10, 9, 11, 12},         // SELECT FN START L3 R3
            };
            for (const auto& row : rows) {
                for (int i = 0; i < 5; ++i) {
                    if (i > 0) ImGui::SameLine(0.0f, gap);
                    if (row[i] < 0) ImGui::Dummy(ImVec2(w, ImGui::GetFrameHeight()));
                    else input_chip(GAMEPAD_BUTTON_NAMES[row[i]], pressed(row[i]), w);
                }
            }
            // Volume keys come from a separate keyboard-type input device
            const Uint8* keys = SDL_GetKeyboardState(nullptr);
            input_chip("VOL-", keys[SDL_SCANCODE_VOLUMEDOWN], w);
            ImGui::SameLine(0.0f, gap);
            input_chip("VOL+", keys[SDL_SCANCODE_VOLUMEUP], w);

            ImGui::Spacing();
            if (!joystick) {
                ImGui::Text("%s", tr("No gamepad found."));
            } else {
                if (SDL_JoystickNumAxes(joystick) >= 4) {
                    ImGui::Text(tr("Sticks:  L %+4d %+4d   R %+4d %+4d"),
                                SDL_JoystickGetAxis(joystick, 0) * 100 / 32767, SDL_JoystickGetAxis(joystick, 1) * 100 / 32767,
                                SDL_JoystickGetAxis(joystick, 2) * 100 / 32767, SDL_JoystickGetAxis(joystick, 3) * 100 / 32767);
                }
                if (last_button >= 0) ImGui::Text(tr("Last pressed: %s (button %d)"), GAMEPAD_BUTTON_NAMES[last_button], last_button);
                else ImGui::Text("%s", tr("Press any button"));
            }

            bool b_down = pressed(GAMEPAD_BUTTON_B) || keys[SDL_SCANCODE_ESCAPE];
            Uint32 now = SDL_GetTicks();
            if (!b_down) b_hold_start = 0;
            else if (b_hold_start == 0) b_hold_start = now;
            float hold = b_hold_start ? std::min(1.0f, (now - b_hold_start) / (float)TESTER_EXIT_HOLD_MS) : 0.0f;
            ImGui::Spacing();
            ImGui::ProgressBar(hold, ImVec2(-1.0f, 0.0f), tr("Hold B to go back"));
            if (hold >= 1.0f) next_page = PAGE_INPUT;
            ImGui::End();
        } else {
            ImGui::Begin("System", nullptr, window_flags);
            ImGui::Text("%s", tr("System Info"));
            ImGui::Separator();
            ImGui::Spacing();

            char value[160];
            auto row = [&](const char* label, const char* text) {
                ImGui::TableNextRow();
                ImGui::TableNextColumn();
                ImGui::TextUnformatted(tr(label));
                ImGui::TableNextColumn();
                ImGui::TextUnformatted(text);
            };
            if (ImGui::BeginTable("info", 2, ImGuiTableFlags_SizingFixedFit)) {
                row("Device", info.model.empty() ? tr("unknown") : info.model.c_str());
                row("System", info.os.c_str());
                snprintf(value, sizeof(value), "Linux %s", info.kernel.c_str());
                row("Kernel", value);
                if (info.cpu_mhz > 0) {
                    if (info.temp_c > -1000) snprintf(value, sizeof(value), "%d / %d MHz, %d C", info.cpu_mhz, info.cpu_max_mhz, info.temp_c);
                    else snprintf(value, sizeof(value), "%d / %d MHz", info.cpu_mhz, info.cpu_max_mhz);
                    row("CPU", value);
                }
                if (info.mem_total_kb > 0) {
                    snprintf(value, sizeof(value), tr("%s free of %s"), human_size_kb(info.mem_avail_kb).c_str(),
                             human_size_kb(info.mem_total_kb).c_str());
                    row("Memory", value);
                }
                if (info.battery >= 0) {
                    snprintf(value, sizeof(value), "%d%% (%s)", info.battery, tr(info.battery_status.c_str()));
                    row("Battery", value);
                }
                snprintf(value, sizeof(value), tr("%s used of %s"), human_size_kb(info.home_used_kb).c_str(),
                         human_size_kb(info.home_total_kb).c_str());
                row("Storage", value);
                if (info.card_unused_kb >= RESIZE_MIN_FREE_KB) {
                    snprintf(value, sizeof(value), tr("%s on the card (see Resize Home)"), human_size_kb(info.card_unused_kb).c_str());
                    row("Unused", value);
                }
                ImGui::EndTable();
            }

            ImGui::Spacing();
            if (ImGui::Button(tr("Back"))) {
                next_page = PAGE_MAIN;
            }
            ImGui::End();
        }

        if (next_page != page) {
            if (page == PAGE_SYSTEM) focus_system_button = true;
            if (page == PAGE_INPUT && next_page == PAGE_MAIN) focus_input_button = true;
            if (page == PAGE_TESTER) focus_tester_button = true;
            page = next_page;
            startup_frames = 3;
        }

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

    if (launch_resize_home) {
        // Replace this process so the launcher keeps waiting on the same PID and the display is free
        execl("/usr/bin/resize-home", "resize-home", (char*)nullptr);
        return 1;
    }

    return 0;
}
