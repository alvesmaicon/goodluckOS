#!/bin/sh
# Writes credentials.h for gl-scrape: ScreenScraper's developer credentials from SS_DEVID and
# SS_DEVPASSWORD in the environment, as byte lists that main.cpp hides in the binary. Without
# them the lists are empty and gl-scrape says so.
bytes() { [ -n "$1" ] && printf '%s' "$1" | od -An -tu1 | tr -s ' \n' ',' | sed 's/^,//'; }
printf '#define SS_DEVID_BYTES %s\n' "$(bytes "${SS_DEVID:-}")"
printf '#define SS_DEVPASSWORD_BYTES %s\n' "$(bytes "${SS_DEVPASSWORD:-}")"
