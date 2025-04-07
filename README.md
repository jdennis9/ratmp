# RAT MP
Lightweight music player using ImGui.
Supports formats: mp3, wav, opus, flac, ape, aiff, riff.

Linux build is WIP.

## Building
Requirements:
- An Odin compiler in the system PATH
### Windows
1. .lib files need to be manually added. Released builds use x64-windows-static libraries from vcpkg. You can see which libraries are needed by looking at the .odin files for each binding.
2. Run ```build_cpp.bat```. You'll need to manually run vcvars. C++17 is required for winrt components.
3. Run the build batch script for the configuration you want to use.

