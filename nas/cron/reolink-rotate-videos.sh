#!/bin/bash

maximum_number_of_days=90;

cameras_path="/mnt/MargokPool/archive/Data/ftp/reolink"

cd $cameras_path;

for camera in `ls -1`; do
    echo camera=$camera
    cd $camera;
    number_of_days=$(find . -maxdepth 3 -mindepth 3 -type d | wc -l)
    echo -e "\t"number_of_days=$number_of_days;
    if [ $number_of_days -gt $maximum_number_of_days ]; then
        number_of_days_to_delete=$((number_of_days-maximum_number_of_days));
        echo -e "\t"number_of_days_to_delete=$number_of_days_to_delete
        find . -maxdepth 3 -mindepth 3 -type d | sort | head -n $number_of_days_to_delete | xargs -i rm -rf $cameras_path/$camera/{};
    fi
    cd ../;
done

