#!/bin/bash
mkdir -p local-out
g++ -std=c++17 src/*.cpp -I../common -o local-out/puppy -O2 -lSDL2 -lSDL2_image -lSDL2_ttf -lasound
