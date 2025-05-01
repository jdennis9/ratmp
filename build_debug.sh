#!/bin/sh

odin build src/player -debug -show-timings \
    -collection:player=src/player -collection:libs=src/libs -collection:bindings=src/bindings \
    -out:out/debug/ratmp -extra-linker-flags:-lportaudio
