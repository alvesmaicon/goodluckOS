#pragma once
// The clock: the top bar's format (from the HUD's options), setting the time, and the time zone.
#include <ctime>
#include <string>
#include <vector>

std::string clockFormat();      // strftime format of the top bar's clock: the date and the time
std::string clockText(const std::string& fmt);
void setClock(time_t when);     // set-time.sh: the system clock and the RTC

// Time zones as UTC offsets in minutes. There is no zoneinfo: ~/.config/timezone holds the POSIX TZ
// string, which /etc/profile.d/timezone.sh gives every app.
const std::vector<int>& timezones();
std::string timezoneLabel(int minutes);     // "UTC-03:00"
int timezoneIndex();                        // in timezones()
void setTimezone(int index);                // for the apps started next, and this one now
