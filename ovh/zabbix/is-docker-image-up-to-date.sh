#!/bin/bash

if ! which docker > /dev/null; then
    echo not-present,docker;
    exit
fi

image_name="${1:-wordpress}"

if ! echo $image_name | grep '/' > /dev/null; then
        image_namespace="library/";
else
        image_namespace="";
fi

# https://stackoverflow.com/questions/16679369/count-occurrences-of-a-char-in-a-string-using-bash
number_of_of_version_segments=$(curl -L -s "https://registry.hub.docker.com/v2/repositories/$image_namespace$image_name/tags?page_size=1024" | jq '."results"[]["name"]' | egrep '^"[0-9]*\.[0-9]*\.[0-9]*"$' | head -1 | awk -F"." '{print NF}')

maximum_number_of_digits_in_version_segment=0
# TODO working currently only for 3 version segments
for version_current in $(curl -L -s "https://registry.hub.docker.com/v2/repositories/$image_namespace$image_name/tags?page_size=1024" | jq '."results"[]["name"]' | egrep '^"[0-9]*\.[0-9]*\.[0-9]*"$' | sed 's/^\"//' | sed 's/\"$//'); do
    for version_current_segment in $(echo $version_current | sed 's/.*-//' | tr '.' ' '); do
        version_segment_length=$(echo $version_current_segment | wc -c)
        ((version_segment_length--))

        if [ $version_segment_length -gt $maximum_number_of_digits_in_version_segment ]; then
            maximum_number_of_digits_in_version_segment=$version_segment_length
        fi
    done  
done 

# we have to do below for all results from dockerhub and local version :/
# below is to address 1.9 vs 1.19 where string comparison needs 001.009 vs 001.019
newest_numerical_version_current=""
newest_version_current=""
for (( i=0; i<$number_of_of_version_segments; i++ )); do
    newest_numerical_version_current="$newest_numerical_version_current"".""$(printf "%0"$maximum_number_of_digits_in_version_segment"d" 0)"
    newest_version_current=$newest_version_current".0"
done
newest_version_current=$(echo $newest_version_current | sed 's/^\.//')
for version_current in $(curl -L -s "https://registry.hub.docker.com/v2/repositories/$image_namespace$image_name/tags?page_size=1024" | jq '."results"[]["name"]' | egrep '^"[0-9]*\.[0-9]*\.[0-9]*"$' | sed 's/^\"//' | sed 's/\"$//'); do
    numerical_version_current=""
    for i in $(echo $version_current | sed 's/.*-//' | tr '.' ' '); do
        numerical_version_current=$numerical_version_current.$(printf "%0"$maximum_number_of_digits_in_version_segment"d" $i);
    done
    
    if [ $(echo -e "$newest_numerical_version_current\n$numerical_version_current" | sort | tail -1) = $numerical_version_current ]; then
        # version_current is newer than newest_numerical_version_current
        newest_numerical_version_current=$numerical_version_current
        newest_version_current=$version_current
    fi
done

#echo "dockerhub:        "$image_name:$newest_version_current
#echo "localhost:        "$(docker ps --format '{{.Image}}' | grep $image_name)

if docker ps --format '{{.Image}}' | grep "$image_name:$newest_version_current" > /dev/null; then
        echo true;
else
        echo false,$(docker ps --format '{{.Image}}' | grep $image_name),$newest_version_current;
fi

