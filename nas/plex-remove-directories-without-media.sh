#!/bin/bash -x

declare -a root_directories=("/mnt/PlexPool/plex/TV-Series" "/mnt/PlexPool/plex/Movies");

for root_directory in "${root_directories[@]}"; do
    echo "$root_directory";
    for directory in $root_directory/*/; do
        echo $directory;
        find "$directory" ! -name '*.jpg' ! -name '*.nfo' ! -name '*.png' ! -name '.plexmatch' | wc -l
        if [ $(find "$directory" ! -name '*.jpg' ! -name '*.nfo' ! -name '*.png' ! -name '.plexmatch' | wc -l) == "1" ]; then 
            ls -a "$directory";
            echo -e "\tEMPTY";
            rm -rfI "$directory";
        else
            echo -e "\tnon-empty";
        fi
        echo
    done
done

