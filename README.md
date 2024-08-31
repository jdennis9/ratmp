# Rat Music Player

A music player for Windows using ImGui.

Supported formats:

- wav
- mp3
- m4a
- opus
- flac
- aiff

## Theme customization
Rat comes with a built-in realtime theme editor. There are a few preset themes available.
You can set an image background for themes, which supports formats jpeg, png and tga.

## Building
Requires CMake and vcpkg.

Make sure these packages are installed with vcpkg:
- ffmpeg:x64-windows
- freetype:x64-windows
- glew:x64-windows

Issue the following commands in the repository root:
```
mkdir .build
cd .build
cmake .. -DCMAKE_TOOLCHAIN_FILE=<path-to-vcpkg>\scripts\buildsystems\vcpkg.cmake
cmake --build . --config Release
cmake --install . --config Release
```

All binaries will be ready in the Release folder.
Copy data from the data directory into the folder where the binaries were installed.
