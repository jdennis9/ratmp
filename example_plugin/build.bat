@echo off

mkdir out\debug\Plugins
odin build example_plugin -debug -build-mode:dll -out:out\Plugins\example.dll
