@echo off

set collections=-collection:player=../src/player -collection:libs=../src/libs -collection:bindings=../src/bindings

pushd .build

odin test ../src/player/library -vet %collections% -show-timings -linker:radlink

popd
