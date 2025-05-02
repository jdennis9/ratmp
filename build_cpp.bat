@echo off

mkdir .build
pushd .build

cl /c /O2 /EHsc /std:c++17 ..\src\cpp\*.cpp
lib *.obj /OUT:..\src\cpp\cpp.lib

popd
