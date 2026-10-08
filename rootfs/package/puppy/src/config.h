#pragma once
#include <string>
#include <vector>

// Files and commands, from puppy.conf (see loadConfig). The defaults are goodluckOS's own layout, so
// goodluckOS needs no config file; on other firmwares a puppy.conf points Puppy at their files.
struct Config {
    std::string font          = "/usr/share/fonts/Inter_24pt-Medium.ttf";   // the other fonts (fonts.h) are next to it
    std::string fallbackIcon  = "/usr/share/puppy/assets/fallback.png";
    std::vector<std::string> apps     = {"/usr/share/puppy/apps.puppy", "/home/player/apps.puppy"};
    std::vector<std::string> appsDirs = {"/home/player/.local/share/applications"};   // *.puppy files
    std::vector<std::string> esSystems;     // EmulationStation es_systems.cfg files to take systems from
    // goodluckOS's appd runs the picked app and closes Puppy meanwhile; with launch_command empty
    // (puppy.conf), Puppy writes the command to launch_file and quits, for a script that runs it
    std::string launchCommand = "doas appctl launch-application";
    std::string launchFile    = "/dev/shm/launch";
    std::string autoStartMark = "/dev/shm/puppy-autolaunched";   // the autolaunch runs once per boot
    std::string stateFile     = "/dev/shm/launcher_state";
    std::string autoStartFile = "/home/player/autolaunch";
    std::string configDir     = "/home/player/.config/puppy";   // settings, favorites
    std::string cacheDir      = "/home/player/.cache/puppy";    // downscaled covers
    std::string langDir       = "/usr/share/goodluck/lang";
    std::string language;                   // overrides the one in the settings file
    std::string view, tabs;                 // defaults for the settings file's view= and tabs=
    std::string powerFifo;                  // a root daemon reading requests, e.g. "screen-off" (puppy.conf)
    std::string backlight     = "/sys/class/backlight/backlight/brightness";
    std::string alsaCard      = "hw:GA36mbAudio";   // volume and audio output shown in the header
    std::string trashDir      = "/home/player/.trash";   // deleted games, until System Settings empties it
    // RetroArch saves and states, renamed along with a game (sort_savefiles: one folder per core)
    std::vector<std::string> saveDirs = {"/home/player/.config/retroarch/saves", "/home/player/.config/retroarch/states"};
    std::string settingsCommand;            // START runs it instead of opening System Settings
    // The POWER menu's restart and shut down (goodluckOS: power-action.sh); when empty, the power_fifo
    // requests
    std::string restartCommand = "doas /usr/local/bin/power-action.sh reboot";
    std::string shutdownCommand = "doas /usr/local/bin/power-action.sh poweroff";
    std::string screenOffCommand = "doas /usr/local/bin/toggle-screen.sh off";
    bool quit = false;      // a "Quit Puppy" power option, for when Puppy is started from another frontend
    bool builtinSettings = false;   // START opens System Settings in Puppy (goodluckOS); settings_command wins

    std::string settingsFile() const  { return configDir + "/settings"; }
    std::string favoritesFile() const { return configDir + "/favorites"; }   // "category<TAB>id" lines
    std::string thumbDir() const      { return cacheDir + "/thumbs"; }
    std::string tabsFile() const      { return configDir + "/tabs"; }    // the tabs System Settings lists
};
extern Config cfg;

constexpr const char* kMyListName    = "My List";
constexpr const char* kMenuCategory  = "System";   // apps.puppy category taken out of the tabs
constexpr const char* kSettingsName  = "System Settings";   // entry of that category opened by START

bool loadConfig(int argc, char** argv);

// The interface font for a fonts.h key: its file next to puppy.conf's font, or that font itself for
// "default", an unknown key or a missing file.
void interfaceFont(const std::string& key, std::string& path, float& scale);
