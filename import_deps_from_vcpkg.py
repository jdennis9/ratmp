import sys
import os
import glob
import shutil

dry_run = False

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
	if len(sys.argv) < 2:
		print("Usage: import_deps_from_vcpkg.py [--dry-run] <path-to-vcpkg-triplet-root>")

	vcpkg = sys.argv[1]
	if not os.path.exists(vcpkg):
		print(f"vcpkg path {vcpkg} does not exist")

	if "--dry-run" in sys.argv:
		dry_run = True

	# Find and copy taglib headers
	taglib_headers = glob.glob(pathname=f"taglib\\*", root_dir=f"{vcpkg}\\include")

	if not dry_run and not os.path.exists("lib"):
		os.mkdir("lib")

	if len(taglib_headers) == 0:
		print("Missing TagLib headers")
		return
	
	for file in taglib_headers:
		copy_ensuring_dirs(f"{vcpkg}\\include\\{file}", f"src\\bindings\\taglib\\{file}")

	# Copy binding libraries
	libs = [
		["fftw3f.lib", "src\\bindings\\fftw"],
		["avcodec.lib", "src\\bindings\\ffmpeg"],
		["avutil.lib", "src\\bindings\\ffmpeg"],
		["avformat.lib", "src\\bindings\\ffmpeg"],
		["swresample.lib", "src\\bindings\\ffmpeg"],
		["tag.lib", "src\\bindings\\taglib"],
		["tag_c.lib", "src\\bindings\\taglib"],

		["freetype.lib", "lib"],
		["brotlienc.lib", "lib"],
		["brotlidec.lib", "lib"],
		["brotlicommon.lib", "lib"],
		["bz2.lib", "lib"],
		["libpng16.lib", "lib"],
	]

	for lib in libs:
		copy_ensuring_dirs(f"{vcpkg}\\lib\\{lib[0]}", lib[1])
	

if __name__ == "__main__":
	main()
