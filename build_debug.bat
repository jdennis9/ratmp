@echo off

set collections=-collection:player=src/player -collection:libs=src/libs -collection:bindings=src/bindings

odin build src/player -vet %collections% -out:out/debug/ratmp.exe -debug -show-timings -linker:radlink
