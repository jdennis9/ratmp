@echo off

odin build src/player/main_win32 -out:out/debug/ratmp.exe -debug -show-timings -linker:radlink
