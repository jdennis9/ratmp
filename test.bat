@echo off

set collections=-collection:src=../src

pushd .build

REM odin test ../src/client -vet -debug %collections% -linker:radlink
REM odin test ../src/tests -vet -debug %collections% -linker:radlink
odin test ../src/util -debug %collections% -linker:radlink
REM odin test ../src/server -o:speed %collections% -linker:radlink

popd
