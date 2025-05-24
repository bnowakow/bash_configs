#!/bin/bash

cd /mnt/MargokPool/archive/Data;

#du -sh ftp; rm -rf ftp/reolink/*/2025/05/15; du -sh ftp;
#du -sh ftp; rm -rf ftp/reolink/qyCQYItwa0/*/2025-05-25-*; du -sh ftp;
#du -sh rancher/shinobi; rm -rf rancher/shinobi/videos/qyCQYItwa0/*/2025-05-20*; du -sh rancher/shinobi;

# Shinobi
for root_dir in "docker/shinobi/reolink/qyCQYItwa0" "rancher/shinobi/videos/qyCQYItwa0"; do
    echo root_dir=$root_dir;
    echo "size of root dir before delete "$(du -sh $root_dir)
    for camera_dir in $(ls $root_dir | grep -v _timelapse); do
        echo -e '\tcamera_dir='$camera_dir;
        oldest_day_files_prefix=$(ls -1 $root_dir/$camera_dir | head -1 | sed 's/T.*//'); 
        files_to_be_deleted_prefix="$root_dir/$camera_dir/$oldest_day_files_prefix"
        echo -e '\t\tfiles_to_be_deleted_prefixr='$files_to_be_deleted_prefix
        sudo rm -f "$files_to_be_deleted_prefix"*;
    done
    echo "size of root dir before after "$(du -sh $root_dir)
done

# Reolink uploading to FTP
for root_dir in "ftp/reolink"; do
    echo root_dir=$root_dir;
    echo "size of root dir before delete "$(du -sh $root_dir)
    for camera_dir in $(ls $root_dir); do
        echo -e '\tcamera_dir='$camera_dir;
        oldest_year_dir=$(ls -1 $root_dir/$camera_dir | head -1);
        oldest_month_dir=$(ls -1 $root_dir/$camera_dir/$oldest_year_dir | head -1);
        oldest_day_dir=$(ls -1 $root_dir/$camera_dir/$oldest_year_dir/$oldest_month_dir | head -1);
        echo -e '\t\toldest_year_dir='$oldest_year_dir oldest_month_dir=$oldest_month_dir oldest_day_dir=$oldest_day_dir
        dir="$root_dir/$camera_dir/$oldest_year_dir/$oldest_month_dir/$oldest_day_dir"
        echo -e '\t\t'$(du -sh $dir)
        rm -rf $dir
        # running it 3 times in case we removed last day of month that was also last month in a given year
        find "$root_dir/$camera_dir" -type d -empty -print
        find "$root_dir/$camera_dir" -type d -empty -print
        find "$root_dir/$camera_dir" -type d -empty -print
    done
    echo "size of root dir before after "$(du -sh $root_dir)
done

