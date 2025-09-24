# RAT MP
Extensible music player for Windows and Linux, inspired by foobar2000.

Uses FFmpeg libraries for audio codecs, so whatever FFmpeg supports is supported by RAT MP.

## Building From Source
Prerequisites:
- Latest odin compiler from [https://github.com/odin-lang/Odin](https://github.com/odin-lang/Odin)
- Python 3.11+
- For Windows:
	- Visual Studio 2016+ (release builds are compiled with 2022, but 2016 should theoretically work)
	- vcpkg

Clone the repository and set up submodules:
`git clone https://github.com/jdennis9/ratmp.git && cd ratmp`

`git submodule update --init --recursive`

#### [Windows] Setting up dependencies

Make sure these packages are installed via vcpkg in your desired triplet:
- ffmpeg [with zlib support]
- fftw3
- freetype
- taglib [with tag_c]

Run the `import_dependencies_from_vcpkg.py` script.

Usage:

`import_dependencies_from_vcpkg.py [--dry-run, --dynamic] <path-to-vcpkg-triplet-root>`

Example importing headers and dynamic libraries from x64-windows-release triplet:

`import_dependencies_from_vcpkg.py --dynamic C:\vcpkg\installed\x64-windows-release`

Or importing static libraries:

`import_dependencies_from_vcpkg.py C:\vcpkg\installed\x64-windows-static-release`

#### Building ImGui
Change directory into `src/thirdparty/odin-imgui`.

In `build.py`:
- **[Windows]** Set `wanted_backends` to `["win32", "dx11"]`
- **[Linux]** Set `wanted_backends` to `["glfw", "opengl3"]`
- Set `use_freetype` to `True`

Then run the script.

#### Building bindings
Go back to the root directory.

**[Windows]** Run `build_bindings.bat`.

**[Linux]** Run `build_bindings.sh`

If all dependencies were installed properly, this should just work.

#### Compiling executable
Create directory `out/debug`

**[Windows]** Run `build.bat`.

**[Linux]** Run `build.sh`.

All arguments passed to the script will be passed to the Odin compiler.
If no arguments are passed, a debug build is produced.

For example, to produce a release build on Windows:

`build.bat -o:speed -subsystem:windows`



