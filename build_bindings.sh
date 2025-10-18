#!/bin/bash

mkdir .build

cd .build

input=../src/bindings

g++ -c -g $input/fontconfig/*.cpp $input/linux_misc/*.cpp $input/ffmpeg_2/*.cpp \
	$input/media_controls/linux/*.cpp \
	$(pkgconf --libs --cflags gtk+-3.0) \
	$(pkgconf --libs --cflags dbus-1) \
    $(pkgconf --libs --cflags gdk-3.0) \
    $(pkgconf --libs --cflags atk) \
    $(pkgconf --libs --cflags appindicator3-0.1) \
    $(pkgconf --libs --cflags libavcodec) \
    $(pkgconf --libs --cflags libavformat) \
    $(pkgconf --libs --cflags libavutil) \
    $(pkgconf --libs --cflags libswresample) \
    $(pkgconf --libs --cflags libswscale)

ar rcs $input/bindings.a ./*.o

cd ..
