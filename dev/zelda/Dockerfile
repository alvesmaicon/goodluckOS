# The dev image plus what Ship of Harkinian and 2 Ship 2 Harkinian need: native libs for the asset tools, armhf libs for the games.
# spdlog, tinyxml2 and libzip are left out on purpose: they are fetched (Torch, 2ship-deps.cmake) or built (build.sh) and linked statically.
FROM goodluck-dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build qemu-user lsb-release \
    zlib1g-dev libbz2-dev libpng-dev nlohmann-json3-dev \
    zlib1g-dev:armhf libbz2-dev:armhf libpng-dev:armhf libsdl2-net-dev:armhf \
    libogg-dev:armhf libvorbis-dev:armhf libopus-dev:armhf libopusfile-dev:armhf \
    libegl-dev:armhf libgles-dev:armhf \
    libsdl2-net-dev libogg-dev libvorbis-dev libopus-dev libopusfile-dev libzip-dev libegl-dev libgles-dev \
    && rm -rf /var/lib/apt/lists/*
