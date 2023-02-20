#!/bin/bash

# https://www.commandlinefu.com/commands/view/24283/list-docker-volumes-by-container
# https://stackoverflow.com/a/59679551

volumes_not_used_by_containers=$(docker volume ls --format '{{ .Name }}')

for used_volume in $(docker ps -a --format '{{ .ID }}' | xargs -I {} docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }}{{ end }}{{ end }}' {} | sed '/^[[:space:]]*$/d'); do
    volumes_not_used_by_containers=$(echo "$volumes_not_used_by_containers" | grep -v $used_volume)
done

for volume in $(echo "$volumes_not_used_by_containers"); do
    docker volume rm $volume;
done


