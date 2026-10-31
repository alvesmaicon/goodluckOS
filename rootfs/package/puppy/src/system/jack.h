#pragma once
// The headphone jack, as the kernel reports it (the codec's SW_HEADPHONE_INSERT input switch).
// triggerhappy moves the sound (audio-output.sh); this only tells the app to read the mixer again.
#include <cstdint>

namespace jack {

// Starts a thread that waits on the jack's input device and pushes an SDL event of the returned
// type on every plug or unplug. 0 when the kernel has no jack (nothing runs then).
uint32_t watch();

}  // namespace jack
