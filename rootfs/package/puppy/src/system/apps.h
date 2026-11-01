#pragma once
// Installed apps (docs/making-apps.md): a folder each in HOME/apps with an app.puppy in it. Their zips
// wait in HOME/apps too, until System Settings -> System -> App Installer installs them.
#include <functional>
#include <string>
#include <vector>

struct AppItem {
    std::string path;           // the zip, or the installed app's folder
    std::string folder;         // the folder in HOME/apps it installs to / lives in
    std::string prefix;         // inside the zip: "" or "Folder/"
    std::string name, description, version;
    unsigned long long bytes = 0;   // unpacked (zip) or on the card (installed)
    std::string error;          // a zip that can't be installed, and why (translated)
    bool update = false;        // installing replaces an installed copy
};

std::vector<AppItem> appZips();         // the zips in HOME/apps, by name
std::vector<AppItem> installedApps();   // the app folders, by name
void recoverApps();                     // puts right an install that a power cut stopped

// "" when it worked, else why not (translated). progress(0..1) is called now and then, from the
// thread that installs.
std::string installApp(const AppItem& zip, const std::function<void(float)>& progress);
std::string uninstallApp(const AppItem& app);
