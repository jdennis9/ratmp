#!/bin/bash

collections=-collection:src=src

if [ $# -eq 0 ]; then
args=-debug
else
args=$@
fi


odin build src/main -vet-shadowing $collections -out:out/ratmp $args -show-timings \
	-extra-linker-flags:"-no-pie -lfreetype $(pkgconf --libs gtk+-3.0) \
	$(pkgconf --libs libavcodec) \
	$(pkgconf --libs libavformat) \
	$(pkgconf --libs libavutil) \
	$(pkgconf --libs libswresample) \
	$(pkgconf --libs libswscale) \
	$(pkgconf --libs dbus-1) \
	$(pkgconf --libs dbus-glib-1) \
	$(pkgconf --libs appindicator3-0.1)
	"

$cmd

