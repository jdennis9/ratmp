@echo off

odin build src/player ^
	-collection:player=src/player -collection:libs=src/libs -collection:bindings=src/bindings^
	-out:out/release/ratmp.exe -o:speed -show-timings -subsystem:windows -resource:src/player/resources.rc
