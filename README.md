# RAT MP
An extensible music player for Windows and Linux, inspired by foobar2000.

Uses FFmpeg libraries for audio codecs so most audio files are supported out the box.

## Building
Both Windows and Linux require the latest Odin compiler from [text](https://github.com/odin-lang/Odin)

### Windows
Requirements:
- vcpkg
- Visual Studio (release builds are built with 2022, others are untested but C++17 support is required)
- Python 3

These dependencies need to installed via vcpkg:
- ffmpeg (with zlib support for png)
- freetype
- taglib (including C binding)
- fftw3

First, dependency files need to be imported from vcpkg. There is a Python script for this named import_deps_from_vcpkg.py which takes the path to the root of the triple where you installed the dependencies.
For example:
`
import_deps_from_vcpkg.py C:\path\to\vcpkg\installed\x64-windows-release
`

