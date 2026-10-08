#pragma once
// The cards: HOME, the second card (TF-2 slot), the trash, and growing HOME over the rest of the card.
#include <map>
#include <string>

struct Usage {
    bool mounted = false;
    unsigned long long totalKb = 0, usedKb = 0, freeKb = 0;
};
Usage homeUsage();
Usage externalCard();       // external-card.sh mounts it at /media/external
void detectCard();          // looks for a card again (external-card.sh, in the background)
void ejectCard();

// Games moved to the trash in the launcher (L2 + R2), deleted for good only from System Settings.
struct TrashStats {
    unsigned long long files = 0, bytes = 0;
};
TrashStats trashStats();
void emptyTrash();

// Resize Home: S01resize-home grows the HOME partition to the end of the card at the next boot, when
// asked to by the request flag. It backs HOME up to /tmp (a RAM disk) while it reformats, so it only
// works while HOME is nearly empty (right after flashing).
struct Resize {
    bool valid = false;         // the partition table could be read
    bool pending = false;       // a resize is waiting for the next boot
    unsigned long long cardKb = 0, partitionKb = 0, unusedKb = 0;
    Usage home;
    unsigned long long tmpFreeKb = 0;
    std::map<std::string, std::string> last;   // the last attempt's result= and time=

    bool canGrow() const;       // enough room left on the card to be worth it
    bool fits() const;          // HOME's files fit in /tmp
    static Resize read();
};
bool requestResize(std::string& error);
bool cancelResize(std::string& error);
