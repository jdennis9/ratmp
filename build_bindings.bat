@echo off

mkdir .build

set input=..\src\bindings

IF "%~1" == "" (
	set args=/Zi
) ELSE (
	set args=%*
)

pushd .build
cl %args% /c /EHsc /std:c++17 ^
/I %input%\ffmpeg_2 ^
%input%\media_controls\windows\*.cpp ^
%input%\taglib\*.cpp ^
%input%\windows_misc\*.cpp ^
%input%\ffmpeg_2\*.cpp

lib .\*.obj /OUT:%input%\bindings.lib
del .\*.obj
popd
