# The dev image plus what the Stardew pack needs. A separate tag, so goodluck-dev stays as it is.
FROM goodluck-dev

RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake ninja-build mono-mcs mono-runtime qemu-user \
    libegl-dev:armhf libgles-dev:armhf libgbm-dev:armhf \
    && rm -rf /var/lib/apt/lists/*
