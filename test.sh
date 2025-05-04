#!/bin/sh

cd .build

collections="-collection:player=../src/player -collection:libs=../src/libs -collection:bindings=../src/bindings"

odin test ../src/player/library -vet -debug $collections
odin test ../src/player/playback -vet -debug $collections

cd ..
