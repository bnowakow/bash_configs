#!/bin/bash

image_name="${1:-wordpress}"

if ! echo $image_name | grep '/' > /dev/null; then
        image_namespace="library/";
else
        image_namespace="";
fi

newest_dockerhub_tag=$(curl -L -s "https://registry.hub.docker.com/v2/repositories/$image_namespace$image_name/tags?page_size=1024" | jq '."results"[]["name"]' | egrep '^"[0-9]*\.[0-9]*\.[0-9]*"$' | head -1 | sed 's/\"//g');

#echo "dockerhub:       $image_name:$newest_dockerhub_tag"
#echo "localhost:       "$(sudo docker ps --format '{{.Image}}' | grep $image_name)

if sudo docker ps --format '{{.Image}}' | grep "$image_name:$newest_dockerhub_tag" > /dev/null; then
        echo true;
else
        echo false;
fi

