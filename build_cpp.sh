#!/bin/sh

mkdir .build
cd .build
cc -c ../src/cpp/*.cpp -lportaudio
ar rcs ../src/cpp/cpp.a *.o
cd ..
