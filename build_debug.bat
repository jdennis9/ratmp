@echo off

odin build src/player/main_win32 ^
	-collection:player=src/player -collection:libs=src/libs -collection:bindings=src/bindings^
	-out:out/debug/ratmp.exe -debug -show-timings -linker:radlink
