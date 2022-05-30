#!/bin/bash

base_path=/mnt/MargokPool/archive/TimeMachine

cd $base_path

depth=5;

for dir in "Taerar2 Taerar3 Taerar4 Taerar5"; do

    # todo tee sudo
    find $dir -type d -maxdepth $depth -mindepth $depth ! -path "*/Users" -print0 | xargs  -0 -I {} rm -rf "{}";
done

