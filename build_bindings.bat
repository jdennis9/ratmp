@echo off

mkdir .build

set input=..\src\bindings

pushd .build
cl /Zi /c /EHsc /std:c++17 ^
/I %input%\ffmpeg_2 ^
%input%\media_controls\*.cpp ^
%input%\taglib\*.cpp ^
%input%\windows_misc\*.cpp ^
%input%\ffmpeg_2\*.cpp

lib .\*.obj /OUT:%input%\bindings.lib
del .\*.obj
popd
