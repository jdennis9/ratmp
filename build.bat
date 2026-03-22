@echo off

set collections=-collection:src=src

IF "%~1" == "" (
	set args=-debug
) ELSE (
	set args=%*
)

set cmdline=odin build src/main -vet-shadowing %collections% -out:out/RATMP.exe %args% -show-timings -extra-linker-flags:"lib\\*.lib"
echo %cmdline%
%cmdline%
