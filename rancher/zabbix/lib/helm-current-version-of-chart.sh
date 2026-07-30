#!/bin/bash

name="${1:-duckdns}"
# TODO below is crap because it doesn't parse argument, it will just check if second argument is not empty
do_not_update_helm="${2:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
repositories_file="$script_dir/helm-repositories.sh"

# OCI charts are not returned by `helm search repo`; resolve their configured
# reference directly and ask Helm for the chart metadata instead.
if [ -f "$repositories_file" ]; then
    # shellcheck source=/dev/null
    source "$repositories_file"
    chart_ref="$(helm_chart_ref_for_app "$name" 2>/dev/null || true)"
    if [ -n "$chart_ref" ]; then
        chart_metadata="$(helm show chart "$chart_ref" 2>/dev/null)"
        helm_status=$?
        if [ "$helm_status" -ne 0 ] || [ -z "$chart_metadata" ]; then
            exit 1
        fi
        printf '%s\n' "$chart_metadata" |
            awk -F': *' '$1 == "version" { print $2; exit }'
        exit 0
    fi
fi

# The local Zabbix checkout can lag behind the configured Helm repository.
# Prefer the repository's chart version when it has an exact Zabbix chart.
if [ "$name" = "zabbix" ]; then
    repository_version="$(helm search repo "$name" --versions 2>/dev/null | awk '
        NR > 1 {
            chart=$1
            sub(/^.*\//, "", chart)
            if (chart == "zabbix") {
                print $2
                exit
            }
        }')"
    if [ -n "$repository_version" ]; then
        printf '%s\n' "$repository_version"
        exit 0
    fi
fi

chart_repo_dir=$(/etc/zabbix/zabbix_agent2.d/bash_configs/rancher/zabbix/lib/helm-chart-repo-dir.sh $name) 

if [ "$chart_repo_dir" == "" ]; then
    # there's no repo on disk, so we'll be checking helm repos
    if helm search repo $name | grep "No results found" > /dev/null; then
        # no results was find in helm repo
        exit 1
    else
        if [ -z "${do_not_update_helm}" ]; then
            helm repo update > /dev/null
        fi
        # return only first result. elasticsearch is present in elastic helm repo and bitnami. adding zz-prefixes to get expected one as first. could be problematic in future
        helm search repo "$name" --versions 2>/dev/null | awk -v app="$name" '
            NR > 1 {
                chart=$1
                sub(/^.*\//, "", chart)
                if (chart == app || chart == "helm-" app) {
                    print $2
                    exit
                }
            }'
        exit
    fi
else
    # there is a repo on disk, so we'll be checking it
    cd $chart_repo_dir
    #git reset --hard 2>/dev/null >/dev/null 
    #git clean -f -d -x 2>/dev/null >/dev/null
    #git pull 2>/dev/null >/dev/null # &
    #if [ $? -gt 0 ]; then 
    #    echo false,git-pull-fail; 
    #fi
    # TODO check git status -uno if branch is not behind origin, downside would be if it takes too long

    file_path=Chart.yaml
    if [ -f $file_path ]; then 
        helm dependency build . > /dev/null 2>&1
        echo $(grep ^version $file_path | sed 's/.*: //' | sed 's/\ .*//')
        exit
    fi

    if ls *.tgz > /dev/null 2>&1; then
        latest_tarbal=$(ls -1 *tgz | tail -1)
        # TODO | sed 's/.*: //' | sed 's/\ .*//' part is repeated with above
        tar -Oxvf $latest_tarbal $name/Chart.yaml 2> /dev/null | grep  ^version | sed 's/.*: //' | sed 's/\ .*//'
        exit
    fi
fi

exit 1
