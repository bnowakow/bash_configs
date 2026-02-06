#!/bin/bash

# preqequisite: gh auth login on zabbix account
# https://cli.github.com/manual/gh_auth_login

repo_name="${1:-truecharts-charts}"

source_branch="master"

# sync fork with upstream
# https://docs.github.com/en/rest/branches/branches?apiVersion=2022-11-28#sync-a-fork-branch-with-the-upstream-repository
master_merge_upstream=$(gh api --method POST -H "Accept: application/vnd.github+json" /repos/bnowakow/$repo_name/merge-upstream -f branch="$source_branch" | jq .message)
# "Successfully fetched and fast-forwarded from upstream Frederic-Boulanger-UPS:master."
# "This branch is not behind the upstream Frederic-Boulanger-UPS:master."

branch="bnowakow"
if [ "$repo_name" = "docker-jdupes-gui" ]; then
    branch="rw_ro"
fi
if [ "$repo_name" = "truecharts-charts" ]; then
    branch="master"
fi

# merge master to my branch
# https://docs.github.com/en/rest/branches/branches?apiVersion=2022-11-28#merge-a-branch
branch_merge_master=$(gh api --method POST -H "Accept: application/vnd.github+json" /repos/bnowakow/$repo_name/merges -f base="$branch" -f head="$source_branch" -f commit_message='merge with upstream repo' | jq .sha)

# check if local repo is pulled
dir=$repo_name
if [ "$repo_name" = "medihunter" ]; then
    dir="medihunter-kasia"
fi
if [ "$repo_name" = "truecharts-charts" ]; then
    dir="bash_configs/repos/truecharts"
fi
if [ "$repo_name" = "truenas-charts" ]; then
    dir="bash_configs/repos/truenas"
fi

sha_upstream=$(gh api -H "Accept: application/vnd.github+json" /repos/bnowakow/$repo_name/branches | jq "map(select(.name == \"$source_branch\"))" | jq .[0].commit.sha | sed 's/"//g')
cd /mnt/MargokPool/home/sup/code/$dir

# comparing if master of upstream repo is the same as master of forked repo
sha_local_of_master=$(git rev-parse $source_branch)
if [ "$sha_upstream" != "$sha_local_of_master" ]; then
    echo "false,$source_branch"
fi

# checking if master of upstream repo is merged into $branch of forked repo
sha_local_of_branch=$(git merge-base master $branch)
if [ "$sha_upstream" = "$sha_local_of_branch" ]; then
    echo "true"
else
    echo "false,$branch"
fi


