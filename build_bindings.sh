#!/bin/bash

mkdir .build

cd .build

input=../src/bindings

g++ -c -O2 $input/fontconfig/*.cpp $input/linux_misc/*.cpp \
	$(pkgconf --libs --cflags gtk+-3.0) \
    $(pkgconf --libs --cflags gdk-3.0) \
    $(pkgconf --libs --cflags atk) \
    $(pkgconf --libs --cflags appindicator3-0.1)
ar rcs $input/bindings.a ./*.o

cd ..
