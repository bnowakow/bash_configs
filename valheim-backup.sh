#!/bin/bash

number_of_backpus_to_keep=30
backup_path=/home/sup/web/valheim.bnowakowski.pl/public_html/backups

mkdir -p $backup_path
ls -1t $backup_path/*.tar.gz | tail -n +$number_of_backpus_to_keep | xargs rm;

