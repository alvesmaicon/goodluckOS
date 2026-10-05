#include <SDL2/SDL.h>
#include "imgui.h"
#include "imgui_internal.h"
#include "fonts.h"
#include "i18n.h"
#include "imgui_impl_sdl2.h"
#include "imgui_impl_sdlrenderer2.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <ctime>
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

// Runs one of the root scripts doas.conf allows (each checks its own arguments), in the background
void run_as_root(const std::string& script_and_args) {
    std::string cmd = "doas /usr/local/bin/" + script_and_args + " >/dev/null 2>&1 &";
    if (system(cmd.c_str()) != 0) {}
}

// The in-game status bar's volume and output (Gallium HUD)
void update_hud_status() {
    if (system("/usr/local/bin/hud-status.sh >/dev/null 2>&1 &") != 0) {}
}

void request_volume_save() {
    run_as_root("persist-settings.sh save");
    update_hud_status();
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
    bool loading_text = false;  // appctl's screen while an app starts: "Loading..." instead of the ASCII-art dog
    std::vector<std::string> hidden_tabs;   // "hidden_tab=<name>" lines: tabs left out of the launcher's strip
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
        else if (line == "loading=text") s.loading_text = true;
        else if (line.compare(0, 11, "hidden_tab=") == 0 && line.size() > 11) s.hidden_tabs.push_back(line.substr(11));
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
                line.compare(0, 11, "hidden_tab=") != 0 && line.compare(0, 8, "loading=") != 0 &&
                !line.empty()) lines.push_back(line);
        }
    }
    lines.push_back(std::string("view=") + (s.list_view ? "list" : "grid"));
    lines.push_back(std::string("tabs=") + (s.show_tabs ? "on" : "off"));
    lines.push_back("language=" + s.language);
    if (!s.font.empty()) lines.push_back("font=" + s.font);
    if (s.loading_text) lines.push_back("loading=text");
    for (const auto& t : s.hidden_tabs) lines.push_back("hidden_tab=" + t);

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

// Gallium HUD options, read by /etc/profile.d/gallium_hud.sh before each launch
const char* HUD_CONFIG = "/home/player/.config/gallium_hud.conf";
const char* HUD_POSITIONS[] = {"top-left", "top-right", "bottom-left", "bottom-right"};
const char* HUD_POSITION_NAMES[] = {"Top left", "Top right", "Bottom left", "Bottom right"};

// Date formats: what the settings show, and the strftime format the clocks use
const char* DATE_FORMAT_NAMES[] = {"MM/DD", "DD/MM", "MM/DD/YYYY", "DD/MM/YYYY", "YYYY-MM-DD", "DD/MM/YY", "YY-MM-DD"};
const char* DATE_FORMATS[] = {"%m/%d", "%d/%m", "%m/%d/%Y", "%d/%m/%Y", "%Y-%m-%d", "%d/%m/%y", "%y-%m-%d"};
const int DATE_FORMAT_COUNT = sizeof(DATE_FORMATS) / sizeof(DATE_FORMATS[0]);

struct HudSettings {
    bool status_date = false;      // the in-game status bar's items
    bool status_time = false;
    bool status_battery = false;
    bool status_audio = false;
    int status_opacity = 50;
    bool visible = false;
    bool cpu = true;
    bool text = false;
    int position = 0;
    bool h24 = false;
    int date_format = 0;   // DATE_FORMATS
};

const char* HUD_DEFAULTS = "/usr/share/goodluck/defaults/gallium_hud.conf";

void read_hud_settings(const char* path, HudSettings& hud) {
    std::ifstream file(path);
    for (std::string line; std::getline(file, line);) {
        size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        std::string key = line.substr(0, eq), value = line.substr(eq + 1);
        if (key == "HUD_STATUS_DATE") hud.status_date = value == "true";
        else if (key == "HUD_STATUS_TIME") hud.status_time = value == "true";
        else if (key == "HUD_STATUS_BATTERY") hud.status_battery = value == "true";
        else if (key == "HUD_STATUS_AUDIO") hud.status_audio = value == "true";
        else if (key == "HUD_STATUS_OPACITY") hud.status_opacity = std::max(0, std::min(100, atoi(value.c_str())));
        else if (key == "HUD_24H") hud.h24 = value == "true";
        else if (key == "HUD_DATE_FORMAT") {
            for (int i = 0; i < DATE_FORMAT_COUNT; i++)
                if (value == DATE_FORMATS[i]) hud.date_format = i;
        }
        else if (key == "HUD_VISIBLE") hud.visible = value == "true";
        else if (key == "HUD_ITEMS") hud.cpu = value == "fps,cpu";
        else if (key == "HUD_STYLE") hud.text = value == "text";
        else if (key == "HUD_POSITION") {
            for (int i = 0; i < 4; i++)
                if (value == HUD_POSITIONS[i]) hud.position = i;
        }
    }
}

// The system's defaults, then the user's choices
HudSettings load_hud_settings() {
    HudSettings hud;
    read_hud_settings(HUD_DEFAULTS, hud);
    read_hud_settings(HUD_CONFIG, hud);
    return hud;
}

void save_hud_settings(const HudSettings& hud) {
    mkdir("/home/player/.config", 0755);
    std::string tmp = std::string(HUD_CONFIG) + ".tmp";
    {
        std::ofstream file(tmp.c_str());
        if (!file.is_open()) return;
        file << "HUD_STATUS_DATE=" << (hud.status_date ? "true" : "false") << "\n"
             << "HUD_STATUS_TIME=" << (hud.status_time ? "true" : "false") << "\n"
             << "HUD_STATUS_BATTERY=" << (hud.status_battery ? "true" : "false") << "\n"
             << "HUD_STATUS_AUDIO=" << (hud.status_audio ? "true" : "false") << "\n"
             << "HUD_STATUS_OPACITY=" << hud.status_opacity << "\n"
             << "HUD_VISIBLE=" << (hud.visible ? "true" : "false") << "\n"
             << "HUD_ITEMS=" << (hud.cpu ? "fps,cpu" : "fps") << "\n"
             << "HUD_STYLE=" << (hud.text ? "text" : "graph") << "\n"
             << "HUD_POSITION=" << HUD_POSITIONS[hud.position] << "\n"
             << "HUD_24H=" << (hud.h24 ? "true" : "false") << "\n"
             << "HUD_DATE_FORMAT=" << DATE_FORMATS[hud.date_format] << "\n";
    }
    rename(tmp.c_str(), HUD_CONFIG);
}

// Time zones as UTC offsets in minutes; ~/.config/timezone gets the POSIX TZ string
// (there is no zoneinfo), read by /etc/profile.d/timezone.sh when an app starts
const char* TIMEZONE_FILE = "/home/player/.config/timezone";
const int TIMEZONE_OFFSETS[] = {-720, -660, -600, -570, -540, -480, -420, -360, -300, -240, -210, -180,
                                -120, -60, 0, 60, 120, 180, 210, 240, 270, 300, 330, 345, 360, 390,
                                420, 480, 525, 540, 570, 600, 630, 660, 720, 765, 780, 840};
const int TIMEZONE_COUNT = sizeof(TIMEZONE_OFFSETS) / sizeof(TIMEZONE_OFFSETS[0]);

std::string timezone_label(int minutes) {
    char text[16];
    snprintf(text, sizeof(text), "UTC%c%02d:%02d", minutes < 0 ? '-' : '+', abs(minutes) / 60, abs(minutes) % 60);
    return text;
}

// "<-03>3" for UTC-3: POSIX counts west of Greenwich as positive
std::string timezone_posix(int minutes) {
    if (minutes == 0) return "UTC0";
    char text[24];
    int h = abs(minutes) / 60, m = abs(minutes) % 60;
    if (m) snprintf(text, sizeof(text), "<%c%02d%02d>%s%d:%02d", minutes < 0 ? '-' : '+', h, m, minutes < 0 ? "" : "-", h, m);
    else snprintf(text, sizeof(text), "<%c%02d>%s%d", minutes < 0 ? '-' : '+', h, minutes < 0 ? "" : "-", h);
    return text;
}

int load_timezone() {
    std::ifstream file(TIMEZONE_FILE);
    std::string line;
    std::getline(file, line);
    for (int i = 0; i < TIMEZONE_COUNT; i++)
        if (timezone_posix(TIMEZONE_OFFSETS[i]) == line) return i;
    for (int i = 0; i < TIMEZONE_COUNT; i++)
        if (TIMEZONE_OFFSETS[i] == 0) return i;
    return 0;
}

void save_timezone(int index) {
    const std::string tz = timezone_posix(TIMEZONE_OFFSETS[index]);
    mkdir("/home/player/.config", 0755);
    std::ofstream file(TIMEZONE_FILE);
    file << tz << "\n";
    setenv("TZ", tz.c_str(), 1);
    tzset();
}

// The launcher's tabs, written by Puppy as "name<TAB>label" lines.
struct LauncherTab {
    std::string name, label;
};

std::vector<LauncherTab> read_launcher_tabs() {
    std::vector<LauncherTab> tabs;
    std::ifstream file((std::string(LAUNCHER_SETTINGS_DIR) + "/tabs").c_str());
    for (std::string line; std::getline(file, line);) {
        size_t tab = line.find('\t');
        if (tab == std::string::npos || tab == 0) continue;
        LauncherTab t;
        t.name = line.substr(0, tab);
        t.label = line.substr(tab + 1);
        tabs.push_back(t);
    }
    return tabs;
}

// Games deleted in the launcher (L2 + R2 -> Move to trash) wait here until emptied.
const char* TRASH_DIR = "/home/player/.trash";

struct TrashStats {
    unsigned long long files = 0, bytes = 0;
};

// Counts the files under dir; with remove, deletes them and the folders too.
void trash_walk(const std::string& dir, TrashStats* stats, bool remove) {
    DIR* d = opendir(dir.c_str());
    if (!d) return;
    while (struct dirent* e = readdir(d)) {
        std::string name = e->d_name;
        if (name == "." || name == "..") continue;
        std::string path = dir + "/" + name;
        struct stat st;
        if (lstat(path.c_str(), &st) != 0) continue;
        if (S_ISDIR(st.st_mode)) {
            trash_walk(path, stats, remove);
            if (remove) rmdir(path.c_str());
        } else {
            stats->files++;
            stats->bytes += (unsigned long long)st.st_size;
            if (remove) unlink(path.c_str());
        }
    }
    closedir(d);
}

TrashStats trash_stats() {
    TrashStats stats;
    trash_walk(TRASH_DIR, &stats, false);
    return stats;
}

void empty_trash() {
    TrashStats stats;
    trash_walk(TRASH_DIR, &stats, true);
    sync();
}

const char* HOME_MOUNT = "/home/player";
const char* CARD_SYSFS = "/sys/class/block/mmcblk0";
const char* HOME_PART_SYSFS = "/sys/class/block/mmcblk0p2";
const char* CPUFREQ_SYSFS = "/sys/devices/system/cpu/cpu0/cpufreq";
// S01resize-home grows the partition and leaves less than this untouched
const unsigned long long RESIZE_MIN_FREE_KB = 8192;

// Power profiles, applied by power-profile.sh (run as root through doas)
const char* POWER_PROFILE_STATE = "/etc/player-flags/power-profile";
const char* POWER_DEFAULTS = "/usr/share/goodluck/defaults/power.conf";
const char* POWER_PROFILES[] = {"battery", "balanced", "performance"};
const char* POWER_PROFILE_NAMES[] = {"Battery saver", "Balanced", "Performance"};
const char* POWER_PROFILE_HINTS[] = {
    "Slower CPU and GPU: the battery lasts longer",
    "Speeds up only when a game needs it",
    "Always at full speed: uses more battery",
};
const int POWER_PROFILE_COUNT = 3;

int power_profile_index(const std::string& name) {
    for (int i = 0; i < POWER_PROFILE_COUNT; ++i)
        if (name == POWER_PROFILES[i]) return i;
    return -1;
}

int default_power_profile() {
    std::ifstream file(POWER_DEFAULTS);
    for (std::string line; std::getline(file, line);) {
        if (line.compare(0, 14, "POWER_PROFILE=") != 0) continue;
        int i = power_profile_index(line.substr(14));
        if (i >= 0) return i;
    }
    return 1;
}

int load_power_profile() {
    int i = power_profile_index(read_line(POWER_PROFILE_STATE));
    // before the profiles, only "Performance mode" was stored, as the governor
    if (i < 0 && read_line("/etc/player-flags/governor") == "performance") i = 2;
    return i >= 0 ? i : default_power_profile();
}

struct SystemInfo {
    std::string model, os, kernel;
    int cpu_mhz = -1, cpu_max_mhz = -1, temp_c = -1000;
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
        // 64 hardware levels: the nearest multiple of 5 is the level that was asked for
        if (max > min) vol = std::lround((vol - min) * 20.0 / (max - min)) * 5;
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
        long scaled_vol = min + std::lround(volume * (max - min) / 100.0);
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

// Off: sound on the headphones only (no jack detection)
bool get_speaker() {
    int on = 1;
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;
    if (snd_mixer_open(&handle, 0) < 0) return true;
    snd_mixer_attach(handle, ALSA_CARD);
    snd_mixer_selem_register(handle, NULL, NULL);
    snd_mixer_load(handle);
    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_name(sid, "Speaker");
    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    if (elem && snd_mixer_selem_has_playback_switch(elem))
        snd_mixer_selem_get_playback_switch(elem, SND_MIXER_SCHN_FRONT_LEFT, &on);
    snd_mixer_close(handle);
    return on != 0;
}

void set_speaker(bool on) {
    snd_mixer_t *handle;
    snd_mixer_selem_id_t *sid;
    if (snd_mixer_open(&handle, 0) < 0) return;
    snd_mixer_attach(handle, ALSA_CARD);
    snd_mixer_selem_register(handle, NULL, NULL);
    snd_mixer_load(handle);
    snd_mixer_selem_id_alloca(&sid);
    snd_mixer_selem_id_set_name(sid, "Speaker");
    snd_mixer_elem_t* elem = snd_mixer_find_selem(handle, sid);
    if (elem && snd_mixer_selem_has_playback_switch(elem))
        snd_mixer_selem_set_playback_switch_all(elem, on ? 1 : 0);
    // the speaker's high-pass filter, as audio-output.sh sets it
    snd_mixer_selem_id_set_name(sid, "DAC High-Pass Filter Cutoff");
    if (on && (elem = snd_mixer_find_selem(handle, sid)) && snd_mixer_selem_is_enumerated(elem))
        snd_mixer_selem_set_enum_item(elem, SND_MIXER_SCHN_FRONT_LEFT, 4);   // 500 Hz
    snd_mixer_selem_id_set_name(sid, "DAC High-Pass Filter");
    if ((elem = snd_mixer_find_selem(handle, sid)) && snd_mixer_selem_has_playback_switch(elem))
        snd_mixer_selem_set_playback_switch_all(elem, on ? 1 : 0);
    snd_mixer_close(handle);
    update_hud_status();
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
    {"FN + DOWN", "Speaker / headphones"},
    {"Launcher", nullptr},
    {"L1 / R1", "Previous / next tab"},
    {"D-pad / left stick", "Move"},
    {"LEFT / RIGHT (list)", "Previous / next page"},
    {"Right stick up/down", "Scroll the description"},
    {"A", "Launch"},
    {"Y", "Add to / remove from My List"},
    {"L2 + R2", "Game options: rename, move to trash"},
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
// A number changed with left / right while selected, wrapping around at the ends
bool number_stepper(const char* label, int* value, int min, int max, const char* format, bool hour12 = false) {
    char text[32];
    if (hour12) snprintf(text, sizeof(text), "%02d %s", *value % 12 ? *value % 12 : 12, *value < 12 ? "AM" : "PM");
    else snprintf(text, sizeof(text), format, *value);
    ImGui::Button((std::string("< ") + text + " >###" + label).c_str(), ImVec2(ImGui::GetFontSize() * 6.0f, 0));
    bool changed = false;
    if (ImGui::IsItemFocused()) {
        int dir = 0;
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadRight, true) || ImGui::IsKeyPressed(ImGuiKey_RightArrow, true)) dir = 1;
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadLeft, true) || ImGui::IsKeyPressed(ImGuiKey_LeftArrow, true)) dir = -1;
        if (dir) {
            *value += dir;
            if (*value > max) *value = min;
            if (*value < min) *value = max;
            changed = true;
        }
    }
    ImGui::SameLine();
    ImGui::Text("%s", label);
    return changed;
}

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
    // the next step on the min + n * step grid, so 46 goes to 50 or 40
    auto stepped = [&](int v, int dir) {
        int k = (v - min) / step;
        if (dir > 0) k++;
        else if ((v - min) % step == 0) k--;
        return std::max(min, std::min(max, min + k * step));
    };
    const int before = *value;
    bool changed = ImGui::SliderInt(label, value, min, max, "");
    ImGui::PopStyleColor(5);
    const bool active = ImGui::IsItemActive() || ImGui::IsItemFocused();
    // editing it after A moves it by 1: same step as when it is only focused
    if (ImGui::IsItemActive() && *value != before) *value = stepped(before, *value > before ? 1 : -1);
    if (ImGui::IsItemFocused() && !ImGui::IsItemActive()) {
        int dir = 0;
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadRight, true) || ImGui::IsKeyPressed(ImGuiKey_RightArrow, true)) dir = 1;
        if (ImGui::IsKeyPressed(ImGuiKey_GamepadDpadLeft, true) || ImGui::IsKeyPressed(ImGuiKey_LeftArrow, true)) dir = -1;
        int v = dir ? stepped(*value, dir) : *value;
        if (v != *value) { *value = v; changed = true; }
    }
    changed = changed && *value != before;

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
    bool speaker_on = get_speaker();

    // Changes are saved SAVE_DELAY_MS after the last edit, so holding the d-pad doesn't hammer the SD card
    bool brightness_dirty = false;
    bool volume_dirty = false;
    Uint32 last_change = 0;

    // The volume/brightness hotkeys change the levels behind our back (triggerhappy scripts): after
    // one is pressed, re-read the levels for a moment so the sliders follow
    const Uint32 HOTKEY_FOLLOW_MS = 2200, HOTKEY_POLL_MS = 100;   // until the HUD feedback is gone
    Uint32 follow_until = 0;

    // ImGui applies the default focus a couple of frames after the window appears, so render those
    // frames right away instead of waiting for the first input event
    int startup_frames = 3;

    // The main page is a menu of sections; each opens its own page
    enum Page { PAGE_NONE, PAGE_MAIN, PAGE_DISPLAY, PAGE_LAUNCHER, PAGE_INTERFACE, PAGE_STORAGE,
                PAGE_SYSTEM_MENU, PAGE_SYSTEM, PAGE_INPUT, PAGE_TESTER, PAGE_TABS, PAGE_OVERLAY, PAGE_DATETIME };
    Page page = PAGE_MAIN;
    // Where B / Back goes from each page (PAGE_NONE: leave the app)
    auto parent_of = [](Page p) {
        switch (p) {
            case PAGE_MAIN:   return PAGE_NONE;
            case PAGE_TABS:   return PAGE_LAUNCHER;
            case PAGE_SYSTEM: return PAGE_SYSTEM_MENU;
            case PAGE_TESTER: return PAGE_INPUT;
            default:          return PAGE_MAIN;
        }
    };
    // Coming back from a page puts the focus on the button that opened it
    Page focus_opener = PAGE_NONE;
    bool focus_first_tab = false;
    std::vector<LauncherTab> launcher_tabs = read_launcher_tabs();
    TrashStats trash = trash_stats();
    bool trash_confirm = false, focus_trash_cancel = false;   // "Empty trash" asks before deleting
    bool defaults_confirm = false, focus_defaults_cancel = false, defaults_restored = false;
    SDL_Joystick* joystick = controller ? SDL_GameControllerGetJoystick(controller) : nullptr;
    int last_button = -1;
    Uint32 b_hold_start = 0;
    SystemInfo info = gather_system_info();
    int power_profile = load_power_profile();
    LauncherSettings launcher = load_launcher_settings();
    HudSettings hud = load_hud_settings();
    int timezone = load_timezone();
    struct tm clock_edit = {};   // the date and time being set, taken from the clock when the page opens
    bool clock_set = false;
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
            // the current time ticks on the Date & Time page
            else if (page == PAGE_DATETIME) got_event = SDL_WaitEventTimeout(&event, 1000);
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
                // volume / brightness keys, and FN (FN + DOWN switches the audio output)
                if ((event.type == SDL_KEYDOWN &&
                     (event.key.keysym.sym == SDLK_VOLUMEUP || event.key.keysym.sym == SDLK_VOLUMEDOWN)) ||
                    (event.type == SDL_JOYBUTTONDOWN && event.jbutton.button == 10)) {
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
            speaker_on = get_speaker();
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
            if (page == PAGE_STORAGE && trash_confirm) trash_confirm = false;
            else if (page == PAGE_SYSTEM_MENU && defaults_confirm) defaults_confirm = false;
            else if (page != PAGE_TESTER) {     // the tester: B is a button being tested, it leaves only when held
                Page up = parent_of(page);
                if (up == PAGE_NONE) running = false;
                else next_page = up;
            }
        }

        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::SetNextWindowSize(io.DisplaySize);
        ImGuiWindowFlags window_flags = ImGuiWindowFlags_NoDecoration |
                                        ImGuiWindowFlags_NoMove |
                                        ImGuiWindowFlags_NoSavedSettings;

        // A page: the title, a part that scrolls following the d-pad selection (NavFlattened: the
        // d-pad moves between it and Back as if they were one), and Back fixed at the bottom under a line
        auto begin_page = [&](const char* id, const char* title) {
            ImGui::Begin(id, nullptr, window_flags);
            ImGui::Text("%s", tr(title));
            ImGui::Separator();
            ImGui::Spacing();
            const float back_h = ImGui::GetFrameHeightWithSpacing() + 2 * ImGui::GetStyle().ItemSpacing.y + 1.0f;   // + the line
            ImGui::BeginChild("page", ImVec2(0, ImGui::GetContentRegionAvail().y - back_h), ImGuiChildFlags_NavFlattened);
        };
        auto end_page = [&]() {
            ImGui::EndChild();
            ImGui::Separator();   // the scrolling part ends here; Back stays put
            ImGui::Spacing();
            if (ImGui::Button(tr("Back"))) {
                Page up = parent_of(page);
                if (up == PAGE_NONE) running = false;
                else next_page = up;
            }
            ImGui::End();
        };
        // A button that opens another page
        auto page_button = [&](const char* label, Page target) {
            if (focus_opener == target) {
                ImGui::SetKeyboardFocusHere();
                focus_opener = PAGE_NONE;
            }
            if (!ImGui::Button(label)) return false;
            next_page = target;
            return true;
        };

        if (page == PAGE_MAIN) {
            begin_page("Settings", "System Settings");
            page_button(tr("Display & Audio"), PAGE_DISPLAY);
            ImGui::SetItemDefaultFocus();
            page_button(tr("Launcher"), PAGE_LAUNCHER);
            page_button(tr("Interface"), PAGE_INTERFACE);
            page_button(tr("Overlay"), PAGE_OVERLAY);
            page_button(tr("Date & Time"), PAGE_DATETIME);
            page_button(tr("Storage"), PAGE_STORAGE);
            page_button(tr("System"), PAGE_SYSTEM_MENU);
            page_button(tr("Input Settings"), PAGE_INPUT);
            // TODO: Date/Time (the RTC has no backup battery, so the clock resets on every boot)
            end_page();
        } else if (page == PAGE_DISPLAY) {
            begin_page("Display", "Display & Audio");
            if (level_slider(tr("Brightness"), &display_brightness, 1, 10, 1)) {
                set_brightness(display_brightness);
                brightness_dirty = true;
                last_change = SDL_GetTicks();
            }
            ImGui::SetItemDefaultFocus();

            if (level_slider(tr("Master Volume"), &current_volume, 0, 100, 10)) {
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

            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Audio output:"));
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("Speaker"), speaker_on) && !speaker_on) {
                speaker_on = true;
                set_speaker(true);
                volume_dirty = true;
                last_change = SDL_GetTicks();
            }
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("Headphones"), !speaker_on) && speaker_on) {
                speaker_on = false;
                set_speaker(false);
                volume_dirty = true;
                last_change = SDL_GetTicks();
            }
            end_page();
        } else if (page == PAGE_LAUNCHER) {
            begin_page("Launcher", "Launcher");
            if (ImGui::Checkbox(tr("Show launcher tabs"), &launcher.show_tabs)) {
                save_launcher_settings(launcher);
            }
            ImGui::SetItemDefaultFocus();
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
            // Which tabs the launcher shows (the list comes from the launcher, see read_launcher_tabs)
            if (!launcher_tabs.empty() && page_button(tr("Launcher tabs"), PAGE_TABS)) focus_first_tab = true;
            end_page();
        } else if (page == PAGE_INTERFACE) {
            begin_page("Interface", "Interface");
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
            ImGui::SetItemDefaultFocus();

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

            bool show_puppy = !launcher.loading_text;
            if (ImGui::Checkbox(tr("Show Puppy on loading screens"), &show_puppy)) {
                launcher.loading_text = !show_puppy;
                save_launcher_settings(launcher);
            }
            end_page();
        } else if (page == PAGE_OVERLAY) {
            begin_page("Overlay", "Overlay");
            // The in-game status bar; the launcher has its own top bar. The clock's format and
            // 12/24 hours come from Date & Time
            ImGui::TextDisabled("%s", tr("In-game status bar"));
            bool hud_changed = ImGui::Checkbox(tr("Show date"), &hud.status_date);
            ImGui::SetItemDefaultFocus();
            hud_changed |= ImGui::Checkbox(tr("Show time"), &hud.status_time);
            hud_changed |= ImGui::Checkbox(tr("Show battery"), &hud.status_battery);
            hud_changed |= ImGui::Checkbox(tr("Show audio"), &hud.status_audio);
            hud_changed |= level_slider(tr("Opacity"), &hud.status_opacity, 0, 100, 10);
            ImGui::Spacing();
            ImGui::TextDisabled("%s", tr("Performance (FN + UP)"));
            hud_changed |= ImGui::Checkbox(tr("Show on game start"), &hud.visible);
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Content:"));
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("FPS"), !hud.cpu)) { hud.cpu = false; hud_changed = true; }
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("FPS + CPU"), hud.cpu)) { hud.cpu = true; hud_changed = true; }
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Style:"));
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("Graph"), !hud.text)) { hud.text = false; hud_changed = true; }
            ImGui::SameLine();
            if (ImGui::RadioButton(tr("Text"), hud.text)) { hud.text = true; hud.position &= 1; hud_changed = true; }
            // Mesa ignores the y offset in text mode, so it only goes at the top
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Position:"));
            ImGui::SameLine();
            ImGui::SetNextItemWidth(ImGui::GetFontSize() * 11.0f);
            if (ImGui::BeginCombo("##hud_position", tr(HUD_POSITION_NAMES[hud.position]))) {
                for (int i = 0; i < (hud.text ? 2 : 4); ++i) {
                    bool selected = i == hud.position;
                    if (ImGui::Selectable(tr(HUD_POSITION_NAMES[i]), selected) && !selected) {
                        hud.position = i;
                        hud_changed = true;
                    }
                    if (selected) ImGui::SetItemDefaultFocus();
                }
                ImGui::EndCombo();
            }
            if (hud_changed) save_hud_settings(hud);
            end_page();
        } else if (page == PAGE_DATETIME) {
            begin_page("DateTime", "Date & Time");
            {
                char now_text[48];
                time_t now = time(nullptr);
                struct tm tm;
                localtime_r(&now, &tm);
                std::string fmt = std::string(DATE_FORMATS[hud.date_format]) + (hud.h24 ? " %H:%M:%S" : " %I:%M:%S %p");
                strftime(now_text, sizeof(now_text), fmt.c_str(), &tm);
                ImGui::Text("%s %s", tr("Now:"), now_text);
            }
            bool shown_changed = ImGui::Checkbox(tr("24-hour clock"), &hud.h24);
            ImGui::SetItemDefaultFocus();
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Date format:"));
            ImGui::SameLine();
            ImGui::SetNextItemWidth(ImGui::GetFontSize() * 7.0f);
            if (ImGui::BeginCombo("##date_format", DATE_FORMAT_NAMES[hud.date_format])) {
                for (int i = 0; i < DATE_FORMAT_COUNT; ++i) {
                    bool selected = i == hud.date_format;
                    if (ImGui::Selectable(DATE_FORMAT_NAMES[i], selected) && !selected) {
                        hud.date_format = i;
                        shown_changed = true;
                    }
                    if (selected) ImGui::SetItemDefaultFocus();
                }
                ImGui::EndCombo();
            }
            if (shown_changed) save_hud_settings(hud);

            ImGui::Spacing();
            if (ImGui::IsWindowAppearing() || clock_edit.tm_year == 0) {
                time_t now = time(nullptr);
                localtime_r(&now, &clock_edit);
                clock_edit.tm_sec = 0;
                clock_set = false;
            }
            int year = clock_edit.tm_year + 1900, month = clock_edit.tm_mon + 1;
            bool edited = number_stepper(tr("Year"), &year, 2024, 2099, "%04d");
            edited |= number_stepper(tr("Month"), &month, 1, 12, "%02d");
            static const int kDays[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
            bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
            int days = kDays[month - 1] + (month == 2 && leap ? 1 : 0);
            clock_edit.tm_mday = std::min(clock_edit.tm_mday, days);
            edited |= number_stepper(tr("Day"), &clock_edit.tm_mday, 1, days, "%02d");
            edited |= number_stepper(tr("Hour"), &clock_edit.tm_hour, 0, 23, "%02d", !hud.h24);
            edited |= number_stepper(tr("Minute"), &clock_edit.tm_min, 0, 59, "%02d");
            clock_edit.tm_year = year - 1900;
            clock_edit.tm_mon = month - 1;
            if (edited) clock_set = false;
            if (ImGui::Button(tr("Set date and time"))) {
                struct tm t = clock_edit;
                t.tm_isdst = -1;
                time_t when = mktime(&t);
                if (when > 0) {
                    run_as_root("set-time.sh " + std::to_string((long long)when));
                    clock_set = true;
                }
            }
            if (clock_set) {
                ImGui::SameLine();
                ImGui::TextDisabled("%s", tr("Done"));
            }

            ImGui::Spacing();
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Time zone:"));
            ImGui::SameLine();
            ImGui::SetNextItemWidth(ImGui::GetFontSize() * 7.0f);
            if (ImGui::BeginCombo("##timezone", timezone_label(TIMEZONE_OFFSETS[timezone]).c_str())) {
                for (int i = 0; i < TIMEZONE_COUNT; ++i) {
                    bool selected = i == timezone;
                    if (ImGui::Selectable(timezone_label(TIMEZONE_OFFSETS[i]).c_str(), selected) && !selected) {
                        timezone = i;
                        save_timezone(i);
                        clock_edit.tm_year = 0;   // show the clock in the new zone
                    }
                    if (selected) ImGui::SetItemDefaultFocus();
                }
                ImGui::EndCombo();
            }
            end_page();
        } else if (page == PAGE_STORAGE) {
            begin_page("Storage", "Storage");
            char usage[96];
            snprintf(usage, sizeof(usage), tr("%s used of %s"), human_size_kb(info.home_used_kb).c_str(),
                     human_size_kb(info.home_total_kb).c_str());
            ImGui::Text("HOME: %s", usage);
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
            ImGui::SetItemDefaultFocus();
            if (can_grow && !fits) {
                ImGui::TextWrapped("%s", tr("Too much data in HOME to resize. Resize right after flashing, before copying games."));
            }

            // Games moved to the trash in the launcher, deleted for good only from here
            if (trash.files > 0) {
                if (!trash_confirm) {
                    char label[160];
                    snprintf(label, sizeof(label), tr("Empty trash (%llu files, %s)"), trash.files,
                             human_size_kb(trash.bytes / 1024).c_str());
                    if (ImGui::Button(label)) {
                        trash_confirm = true;
                        focus_trash_cancel = true;
                    }
                } else {
                    ImGui::TextWrapped("%s", tr("Delete the games in the trash for good?"));
                    if (focus_trash_cancel) {
                        ImGui::SetKeyboardFocusHere();
                        focus_trash_cancel = false;
                    }
                    if (ImGui::Button(tr("Cancel"))) trash_confirm = false;
                    if (ImGui::Button(tr("Empty"))) {
                        empty_trash();
                        trash = trash_stats();
                        info = gather_system_info();    // free space
                        trash_confirm = false;
                    }
                }
            }
            end_page();
        } else if (page == PAGE_SYSTEM_MENU) {
            begin_page("SystemMenu", "System");
            ImGui::AlignTextToFramePadding();
            ImGui::Text("%s", tr("Power mode:"));
            ImGui::SameLine();
            ImGui::SetNextItemWidth(ImGui::GetFontSize() * 11.0f);
            if (ImGui::BeginCombo("##power_profile", tr(POWER_PROFILE_NAMES[power_profile]))) {
                for (int i = 0; i < POWER_PROFILE_COUNT; ++i) {
                    bool selected = i == power_profile;
                    if (ImGui::Selectable(tr(POWER_PROFILE_NAMES[i]), selected) && !selected) {
                        power_profile = i;
                        run_as_root(std::string("power-profile.sh ") + POWER_PROFILES[i]);
                    }
                    if (selected) ImGui::SetItemDefaultFocus();
                }
                ImGui::EndCombo();
            }
            ImGui::SetItemDefaultFocus();
            ImGui::TextDisabled("%s", tr(POWER_PROFILE_HINTS[power_profile]));
            if (page_button(tr("System Info"), PAGE_SYSTEM)) info = gather_system_info();

            // Overlay, Date & Time, the launcher's view, tabs and font, and the power mode; the
            // language, the time zone and the clock stay
            ImGui::Spacing();
            if (!defaults_confirm) {
                if (ImGui::Button(tr("Restore default settings"))) {
                    defaults_confirm = true;
                    focus_defaults_cancel = true;
                    defaults_restored = false;
                }
                if (defaults_restored) {
                    ImGui::SameLine();
                    ImGui::TextDisabled("%s", tr("Done"));
                }
            } else {
                ImGui::TextWrapped("%s", tr("Restore the Overlay, Date & Time, launcher and power mode settings? The language and the time zone stay."));
                if (focus_defaults_cancel) {
                    ImGui::SetKeyboardFocusHere();
                    focus_defaults_cancel = false;
                }
                if (ImGui::Button(tr("Cancel"))) defaults_confirm = false;
                if (ImGui::Button(tr("Restore"))) {
                    unlink(HUD_CONFIG);
                    hud = load_hud_settings();
                    LauncherSettings fresh;
                    fresh.language = launcher.language;
                    launcher = fresh;
                    save_launcher_settings(launcher);
                    for (size_t i = 0; i < font_choices.size(); ++i)
                        if (&fonts::all()[font_choices[i]] == &fonts::find("")) pending_font = (int)i;
                    power_profile = default_power_profile();
                    run_as_root("power-profile.sh default");
                    defaults_confirm = false;
                    defaults_restored = true;
                }
            }
            end_page();
        } else if (page == PAGE_INPUT) {
            ImGui::Begin("Input", nullptr, window_flags);
            ImGui::Text("%s", tr("Input Settings"));
            ImGui::Separator();
            ImGui::Spacing();

            // The list scrolls with d-pad up/down and the right stick; the buttons sit side by side at
            // the bottom, so left/right picks one and up/down stay free for scrolling
            const float buttons_h = ImGui::GetFrameHeightWithSpacing() + 2 * ImGui::GetStyle().ItemSpacing.y + 1.0f;   // + the separator
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

            ImGui::Separator();   // the scrolling part ends here; the buttons below stay put
            ImGui::Spacing();
            if (page_button(tr("Button Tester"), PAGE_TESTER)) {
                last_button = -1;
                b_hold_start = 0;
            }
            ImGui::SetItemDefaultFocus();
            ImGui::SameLine();
            if (ImGui::Button(tr("Back"))) {
                next_page = PAGE_MAIN;
            }
            ImGui::End();
        } else if (page == PAGE_TABS) {
            ImGui::Begin("Tabs", nullptr, window_flags);
            ImGui::Text("%s", tr("Launcher tabs"));
            ImGui::Separator();
            ImGui::TextWrapped("%s", tr("Unticked tabs are hidden; their games still show in All Games and My List."));
            ImGui::Spacing();

            const float back_h = ImGui::GetFrameHeightWithSpacing() + 2 * ImGui::GetStyle().ItemSpacing.y + 1.0f;   // + the separator
            ImGui::BeginChild("tab_list", ImVec2(0, ImGui::GetContentRegionAvail().y - back_h), ImGuiChildFlags_NavFlattened);
            for (size_t i = 0; i < launcher_tabs.size(); ++i) {
                const LauncherTab& t = launcher_tabs[i];
                std::vector<std::string>& hidden = launcher.hidden_tabs;
                std::vector<std::string>::iterator it = std::find(hidden.begin(), hidden.end(), t.name);
                bool shown = it == hidden.end();
                std::string label = tr(t.label);
                if (t.label != t.name) label += std::string("  (") + tr(t.name) + ")";
                ImGui::PushID((int)i);
                if (i == 0 && focus_first_tab) {
                    ImGui::SetKeyboardFocusHere();
                    focus_first_tab = false;
                }
                if (ImGui::Checkbox(label.c_str(), &shown)) {
                    if (shown) hidden.erase(it);
                    else hidden.push_back(t.name);
                    save_launcher_settings(launcher);
                }
                ImGui::PopID();
            }
            ImGui::EndChild();

            ImGui::Separator();   // the scrolling part ends here; the buttons below stay put
            ImGui::Spacing();
            if (ImGui::Button(tr("Back"))) next_page = PAGE_LAUNCHER;
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
        } else if (page == PAGE_SYSTEM) {
            begin_page("System", "System Info");

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
            end_page();
        }

        if (next_page != page) {
            if (next_page == parent_of(page)) focus_opener = page;
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
