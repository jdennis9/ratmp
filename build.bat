@echo off

set collections=-collection:src=src

IF "%~1" == "" (
	set args=-debug
) ELSE (
	set args=%*
)

set cmdline=odin build src/main -vet-shadowing %collections% -out:out/debug/RATMP.exe %args% -show-timings -resource:src/resources.rc -extra-linker-flags:"lib\\*.lib"
echo %cmdline%
%cmdline%
