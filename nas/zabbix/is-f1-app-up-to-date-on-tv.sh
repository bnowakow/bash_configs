#!/bin/bash

directory_with_apks="/mnt/MargokPool/archive/Software/AndroidTV/f1"

current_version=$(curl https://www.androidout.com/item/android-apps/1002931/f1-tv/download/ 2>/dev/null| grep 'Version' | head -n1 | sed 's/.*Version[^0-9]*//' | sed 's/<\/div>.*//')

echo $current_version;
ls $directory_with_apks

