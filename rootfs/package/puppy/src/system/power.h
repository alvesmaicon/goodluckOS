#pragma once
// The power supplies, as the kernel announces them: a uevent of the power_supply class on a charger
// going in or out and on a change of the battery's state. This only tells the app to read the
// battery again; with nothing else moving, the top bar reads it once a minute.
#include <cstdint>

namespace power {

// Starts a thread that waits on the kernel's uevents and pushes an SDL event of the returned type on
// each one from a power supply. 0 when the socket can't be opened (nothing runs then).
uint32_t watch();

}  // namespace power
