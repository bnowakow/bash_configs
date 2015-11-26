#!/bin/bash

LOCAL_DIR="/cygdrive/d/barte/Videos/Movies";
REMOTE_DIR="/home/kszczep/torrents/_Seriale";
REMOTE_SSH="kszczep@tbox"
PID_FILE="/var/run/sync_tbox.pid"

declare -a FILES=('Castle' 'Homeland' 'How.to.Get.Away.with.Murder' 'Fargo' 'Last.Week.Tonight');

if [ -f $PID_FILE ]; then
    echo "Progam already runs in PID=`cat $PID_FILE`, exiting.";
    exit
fi
echo $! > $PID_FILE;

for file in "${FILES[@]}"; do
	echo $file;
	rsync -r --partial --progress --rsh=ssh --include="*/" --include="*$file*" --include="*$file*/" --include="*/*$file*" --exclude="*" --remove-source-files $REMOTE_SSH:"$REMOTE_DIR" $LOCAL_DIR;
done

rm $PID_FILE;
