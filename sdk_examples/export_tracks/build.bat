@echo off

odin build sdk_examples\export_tracks -build-mode:shared -collection:src=src -linker:msvc -out:out\plugins\export_tracks.dll

@echo on
