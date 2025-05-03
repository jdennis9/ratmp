@echo off

set collections=-collection:player=../src/player -collection:libs=../src/libs -collection:bindings=../src/bindings

pushd .build

odin test ../src/player/library -vet -debug %collections% -linker:radlink
odin test ../src/player/playback -vet -debug %collections% -linker:radlink

popd
