#pragma once
// What the launcher does with its entries: launching, autolaunch, favourites, the extra tabs,
// renaming and trashing games, the System menu and the launcher options.
#include <string>
#include <vector>

#include "model.h"

bool loadModel(Model& m);
bool readAutoStartId(std::string& category, std::string& name);
void toggleAutoStart(Model& m);
bool launch(const Model& m, const Entry& e);
bool runAutoStart();
void restoreCursor(Model& m);
void addAllGamesTab(Model& m);
void loadFavorites(Model& m);
void addMyListTab(Model& m);
void addExternalTab(Model& m);
void toggleFavorite(Model& m);
std::string renameEntry(Model& m, const Entry& e, const std::string& newName);
std::string deleteEntry(Model& m, const Entry& e);
void extractSystemMenu(Model& m);
void applySettingsCommand(Model& m);
std::vector<PowerItem> powerItems();
void loadSettings(Model& m);
