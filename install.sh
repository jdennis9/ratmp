#!/bin/bash

if [ $# -eq 0 ]; then
echo "install.sh <prefix>"
echo "Example: install.sh ~/.local"
exit
fi

prefix=$1

desktop_entry="
[Desktop Entry]
Type=Application
Name=RAT MP
Version=1.0
Comment=Extensible music player
Path=${prefix}/bin
Exec=${prefix}/bin/ratmp
Icon=ratmp
Terminal=false
Categories=AudioVideo;Audio;
"

echo "${desktop_entry}"
echo "======================="

echo "Compiling..."

./build.sh -o:speed

echo "Installing into prefix ${prefix}"
cp out/ratmp ${prefix}/bin/ratmp
cp src/resources/ratmp.png ${prefix}/share/icons/hicolor/32x32/ratmp.png
echo "${desktop_entry}" > ${prefix}/share/applications/ratmp.desktop
