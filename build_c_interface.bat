@echo off

set collections=-collection:src=src

IF "%~1" == "" (
	set args=-debug
) ELSE (
	set args=%*
)

set cmdline=odin build src/main/c_interface -build-mode:obj -min-link-libs -no-entry-point -vet-shadowing %collections% -out:lib/ratmp.obj %args% -show-timings -resource:src/resources.rc
echo %cmdline%
%cmdline%
