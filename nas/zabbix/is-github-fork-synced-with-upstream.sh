#!/bin/bash

# preqequisite: gh auth login on zabbix account
# https://cli.github.com/manual/gh_auth_login

repo_name="${1:-medihunter}"

source_branch="master"
if [ "$repo_name" = "truetool" ]; then
    source_branch="main"
fi

# https://docs.github.com/en/rest/branches/branches?apiVersion=2022-11-28#sync-a-fork-branch-with-the-upstream-repository
master_merge_upstream=$(gh api --method POST -H "Accept: application/vnd.github+json" /repos/bnowakow/$repo_name/merge-upstream -f branch="$source_branch" | jq .message)
# "Successfully fetched and fast-forwarded from upstream Frederic-Boulanger-UPS:master."
# "This branch is not behind the upstream Frederic-Boulanger-UPS:master."

if [ "$repo_name" = "universal-trakt-scrobbler" ]; then
    if echo $master_merge_upstream | grep "This branch is not behind the upstream"; then
        echo true;
    else
        echo false;
    fi
    exit
fi

branch="bnowakow"
if [ "$repo_name" = "docker-ubuntu-novnc-crashplan" ]; then
    branch="crashplan"
fi
if [ "$repo_name" = "docker-jdupes-gui" ]; then
    branch="rw_ro"
fi
if [ "$repo_name" = "docker-mailserver" ]; then
    branch="aeonus"
fi

# https://docs.github.com/en/rest/branches/branches?apiVersion=2022-11-28#merge-a-branch
branch_merge_master=$(gh api --method POST -H "Accept: application/vnd.github+json" /repos/bnowakow/$repo_name/merges -f base="$branch" -f head="$source_branch" -f commit_message='merge with upstream repo' | jq .sha)

if [ "$branch_merge_master" == "" ]; then
    echo "true"
else
    echo "false,$branch_merge_master"
fi

