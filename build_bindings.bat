@echo off

mkdir .build

pushd .build
cl /Zi /c /EHsc /std:c++17 ..\src\bindings\media_controls\*.cpp ..\src\bindings\taglib\*.cpp ..\src\bindings\windows_misc\*.cpp
lib .\*.obj /OUT:..\src\bindings\bindings.lib
del .\*.obj
popd
