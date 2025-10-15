#!/bin/bash

collections=-collection:src=src

odin build src/main -vet-shadowing $collections -out:out/debug/ratmp -debug -show-timings \
	-extra-linker-flags:"-no-pie -lfreetype $(pkgconf --libs gtk+-3.0) \
	$(pkgconf --libs libavcodec) \
	$(pkgconf --libs libavformat) \
	$(pkgconf --libs libavutil) \
	$(pkgconf --libs libswresample) \
	$(pkgconf --libs libswscale) \
	$(pkgconf --libs appindicator3-0.1)
	"

$cmd

