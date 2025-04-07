@echo off

odin build src/player/main_win32 -out:out/release/ratmp.exe -o:speed -show-timings -subsystem:windows -resource:src/player/resources.rc
