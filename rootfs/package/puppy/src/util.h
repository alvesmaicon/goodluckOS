#pragma once
// Used by every Puppy source file: the std::filesystem alias, tr() and small string helpers.
#include <filesystem>
#include <string>
#include <vector>

#include "i18n.h"

namespace fs = std::filesystem;
using i18n::tr;

std::string trim(const std::string& s);
std::string upper(std::string s);
std::string lower(std::string s);
std::vector<std::string> splitList(const std::string& s);
std::string shellQuote(const std::string& s);
void replaceAll(std::string& s, const std::string& from, const std::string& to);
std::string homeDir();
std::string expandHome(const std::string& path);
