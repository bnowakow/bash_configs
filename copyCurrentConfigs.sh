#!/bin/bash

cp ~/.bash_profile .
cp ~/.gitconfig .
cp ~/.screenrc .

curl -o .git-prompt.sh https://raw.githubusercontent.com/git/git/master/contrib/completion/git-prompt.sh
