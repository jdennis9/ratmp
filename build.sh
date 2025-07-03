#!/bin/sh

collections=-collection:src=src

cmd="odin build src -vet-shadowing $collections -out:out/linux/ratmp -debug -show-timings"

$cmd

