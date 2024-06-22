#!/bin/bash -x

sd_card_path="/Volumes/sup-om2-JPG/DCIM/100OLYMP"
if cd $sd_card_path; then
    find . | tr './' ' '  | awk '{print $1}' | xargs -I {} find ~/Pictures -name "*{}*" | sed 's/.*\///g' | tr 'ORF' 'JPG' | xargs -I {} rm {}
    find . | tr './' ' '  | awk '{print $1}' | xargs -I {} find /Volumes/2024-Lightroom-private/2024-Lightroom-private -name "*{}*" | sed 's/.*\///g' | tr 'ORF' 'JPG' | xargs -I {} rm {}

    # TODO fix repetition (do foreach)
    #cd /Volumes/sup-om2-JPG/DCIM/101OLYMP;
    #find . | tr './' ' '  | awk '{print $1}' | xargs -I {} find ~/Pictures -name "*{}*" | sed 's/.*\///g' | tr 'ORF' 'JPG' | xargs -I {} rm {}
else
    echo "could enter $sd_card_path. aborting"
    exit 1
fi

