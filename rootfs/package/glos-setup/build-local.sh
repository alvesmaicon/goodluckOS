#!/bin/bash
set -e

mkdir -p local-out

# Fetch Dear ImGui if missing
if [ ! -d "imgui" ]; then
    echo "=> Fetching Dear ImGui..."
    git clone --depth 1 -b master https://github.com/ocornut/imgui.git
fi

echo "Compiling glos-setup locally..."

g++ -O2 -std=c++11 \
    -I./imgui \
    -I./imgui/backends \
    -lSDL2_image \
    $(pkg-config --cflags sdl2) \
    glos-setup.cpp \
    imgui/imgui.cpp \
    imgui/imgui_draw.cpp \
    imgui/imgui_tables.cpp \
    imgui/imgui_widgets.cpp \
    imgui/backends/imgui_impl_sdl2.cpp \
    imgui/backends/imgui_impl_sdlrenderer2.cpp \
    -o local-out/glos-setup \
    $(pkg-config --libs sdl2)

echo "Sucess!"
