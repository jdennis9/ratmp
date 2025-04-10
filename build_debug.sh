#!/bin/sh

odin build src/player/main_linux -debug -show-timings -out:out/debug/ratmp -extra-linker-flags:-lportaudio
