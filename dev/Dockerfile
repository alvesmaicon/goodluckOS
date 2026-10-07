# Dev image for fast, partial builds (see dev/README.md). Native on amd64 and arm64 hosts
# (Apple Silicon under Colima): nothing here runs under emulation.
FROM debian:trixie

RUN dpkg --add-architecture armhf && apt-get update && apt-get install -y --no-install-recommends \
    build-essential crossbuild-essential-armhf pkg-config git ca-certificates curl wget \
    libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libasound2-dev libdrm-dev \
    libsdl2-dev:armhf libsdl2-image-dev:armhf libsdl2-ttf-dev:armhf libasound2-dev:armhf libdrm-dev:armhf \
    xvfb xdotool x11-apps imagemagick \
    libncurses-dev file cpio unzip rsync bc patch perl python3 \
    bison flex libssl-dev kmod device-tree-compiler mkbootimg \
    e2fsprogs dosfstools fakeroot \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
