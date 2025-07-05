@echo off

set collections=-collection:src=../src

IF "%~1" == "" (
	echo "Usage: test.bat <package>. Example: test.bat server"
	exit
) ELSE (
	set args=%*
)

pushd .build

set cmd=odin test ../src/%1 -debug %collections% -linker:radlink
echo %cmd%
%cmd%

popd
