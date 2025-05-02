#!/bin/bash

set -x

mkdir .build
cd .build
cc -c -O2 ../src/cpp/*.cpp -lportaudio \
    $(pkgconf --libs --cflags gtk+-3.0) \
    $(pkgconf --libs --cflags gdk-3.0) \
    $(pkgconf --libs --cflags atk) \
    $(pkgconf --libs --cflags appindicator3-0.1)
rm ../src/cpp/cpp.a
ar rcs ../src/cpp/cpp.a *.o
rm ./*.o
cd ..
