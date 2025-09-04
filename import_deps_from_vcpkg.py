import sys
import os
import glob
import shutil

dry_run = False
copy_dlls = False

def copy_ensuring_dirs(src, dst):
	global dry_run
	if dry_run:
		if not os.path.exists(src): print(f"{src} not found!")
		else: print(f"{src} -> {dst}")
		return
	print(f"{src} -> {dst}")
	try: os.makedirs(os.path.dirname(dst), exist_ok=True)
	except: pass
	shutil.copy(src, f"{dst}")

def multicopy_ensuring_dirs(files, dst):
	for f in files:
		copy_ensuring_dirs(f, dst)

def main():
	global dry_run
	global copy_dlls

	if len(sys.argv) < 2:
		print("Usage: import_deps_from_vcpkg.py [--dry-run] <path-to-vcpkg-triplet-root>")

	vcpkg = sys.argv[1]
	if not os.path.exists(vcpkg):
		print(f"vcpkg path {vcpkg} does not exist")

	if "--dry-run" in sys.argv:
		dry_run = True
	if "--dynamic" in sys.argv:
		copy_dlls = True

	# Find and copy taglib headers
	wanted_headers = [
		["taglib", "taglib"],
		["libavutil", "ffmpeg_2"],
		["libavcodec", "ffmpeg_2"],
		["libavformat", "ffmpeg_2"],
		["libswresample", "ffmpeg_2"],
		["libswscale", "ffmpeg_2"],
	]

	include_dir = f"{vcpkg}\\include"
	for want in wanted_headers:
		headers = glob.glob(pathname=f"{want[0]}\\*", root_dir=include_dir)
		if len(headers) == 0:
			print(f"Missing headers for {want[0]}")
			return
		for file in headers:
			copy_ensuring_dirs(f"{vcpkg}\\include\\{file}", f"src\\bindings\\{want[1]}\\{file}")

	if not dry_run and not os.path.exists("lib"):
		os.mkdir("lib")

	libs = [
		["fftw3f.lib", "src\\bindings\\fftw"],
		["avcodec.lib", "src\\bindings\\ffmpeg"],
		["avutil.lib", "src\\bindings\\ffmpeg"],
		["avformat.lib", "src\\bindings\\ffmpeg"],
		["swresample.lib", "src\\bindings\\ffmpeg"],
		["swscale.lib", "src\\bindings\\ffmpeg"],

		["avcodec.lib", "lib"],
		["avutil.lib", "lib"],
		["avformat.lib", "lib"],
		["swresample.lib", "lib"],
		["swscale.lib", "lib"],
		["zlib.lib", "lib"],

		["tag.lib", "src\\bindings\\taglib"],
		["tag_c.lib", "src\\bindings\\taglib"],

		["freetype.lib", "lib"],
		["brotlienc.lib", "lib"],
		["brotlidec.lib", "lib"],
		["brotlicommon.lib", "lib"],
		["bz2.lib", "lib"],
		["libpng16.lib", "lib"],
	]

	dlls = [
		"fftw3f.dll",
		"libavcodec.dll",
		"libavutil.dll",
		"libavformat.dll",
		"libswresample.dll",
		"libswscale.dll",
		"zlib.dll",
		"tag.dll",
		"tag_c.dll",
		"freetype.dll",
		"brotlienc.dll",
		"brotlidec.dll",
		"bz2.dll",
		"libpng16.dll",
	]

	for lib in libs:
		copy_ensuring_dirs(f"{vcpkg}\\lib\\{lib[0]}", lib[1])

	if copy_dlls:
		for dll in dlls:
			copy_ensuring_dirs(f"{vcpkg}\\bin\\{dll}", "lib")
	

if __name__ == "__main__":
	main()
