#!/bin/bash

collections=-collection:src=src

odin build src/main -vet-shadowing $collections -out:out/linux/ratmp -debug -show-timings \
	-extra-linker-flags:"-lfreetype $(pkgconf --libs gtk+-3.0)"

$cmd

