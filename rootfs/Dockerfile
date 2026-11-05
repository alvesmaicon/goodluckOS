FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir /src
WORKDIR /src
RUN git clone --depth 1 -b 2026.08-rc2 https://gitlab.com/buildroot.org/buildroot.git buildroot

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libncurses-dev \
    file \
    wget \
    cpio \
    unzip \
    rsync \
    bc \
    cmake \
    llvm-19-dev \
    libclang-19-dev \
    libclang-cpp19-dev \
    libclc-19-dev \
    libllvmspirvlib-19-dev \
    spirv-tools \
    && rm -rf /var/lib/apt/lists/*
# Create external.desc
RUN echo "name: GOODLUCKOS\n\
desc: An enthusiast OS for the GA36-MB" > /src/external.desc

# Create external.mk
RUN echo 'include $(sort $(wildcard $(BR2_EXTERNAL_GOODLUCKOS_PATH)/package/*/*.mk))' > /src/external.mk

# Create Config.in
RUN echo 'source "/src/package/Config.in"' > /src/Config.in
