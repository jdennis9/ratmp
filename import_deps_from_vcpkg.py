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
	os.makedirs(os.path.dirname(dst), exist_ok=True)
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
	taglib_headers = glob.glob(pathname=f"taglib\\*.h", root_dir=f"{vcpkg}\\include")

	if len(taglib_headers) == 0:
		print("Missing TagLib headers")
		return
	
	for file in taglib_headers:
		copy_ensuring_dirs(f"{vcpkg}\\include\\{file}", "src\\cpp\\taglib")

	# Copy binding libraries
	libs = [
		["kissfft-float.lib", "src\\bindings\\kissfft"],
		["samplerate.lib", "src\\bindings\\samplerate"],
		["sndfile.lib", "src\\bindings\\sndfile"],
		["FLAC.lib", "src\\bindings\\sndfile"],
		["libmp3lame-static.lib", "src\\bindings\\sndfile"],
		["libmpghip-static.lib", "src\\bindings\\sndfile"],
		["mpg123.lib", "src\\bindings\\sndfile"],
		["ogg.lib", "src\\bindings\\sndfile"],
		["opus.lib", "src\\bindings\\sndfile"],
		["vorbis.lib", "src\\bindings\\sndfile"],
		["vorbisenc.lib", "src\\bindings\\sndfile"],
		["vorbisfile.lib", "src\\bindings\\sndfile"],
	]

	for lib in libs:
		copy_ensuring_dirs(f"{vcpkg}\\lib\\{lib[0]}", lib[1])
	

if __name__ == "__main__":
	main()
