#!/bin/bash
# License; Apache-2
# anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
. "$curr_dir/functions.sh"

set -e   # fail early

use_adb_root=false
data_backup=true
media_backup=false
image_backup=false
extra_backup=false

if [[ $# -gt 1 ]]; then
    for param in $@; do
        case "$param" in
            help|-h|--help)
                echo "Makes a full backup over ADB"
                echo "tar /data, binary img /data block"
                exit 0
                ;;
            --data-backup)
                data_backup=true
                ;;
            --no-data-backup)
                data_backup=false
                ;;
            --media-backup)
                media_backup=true
                ;;
            --no-media-backup)
                media_backup=false
                ;;
            --image-backup)
                image_backup=true
                ;;
            --no-image-backup)
                image_backup=false
                ;;
            --extra-backup)
                extra_backup=true
                ;;
            --no-extra-backup)
                extra_backup=false
                ;;
            *)
		break
                ;;
        esac
	shift
    done
fi

if [[ $# -gt 0 ]]; then
    echo "parm: $1"
    RESTOREDIR=$1
    if test ! -d "$RESTOREDIR"; then
        echo "$RESTOREDIR does not exist, exiting"
        exit 2
    fi
else
    echo "Missing directory from which to restore ..."
    exit 1
fi

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

echo "restoring from $RESTOREDIR"

stopRuntime
pushd $RESTOREDIR

if $data_backup; then
    echo "Restoring full tar backup of /data excluding /data/media ... "
    if [[ "$AS" == "$AMAGISK" ]]; then
        cat data.tar.gz | pv -trab | $AS 'cd /data && /dev/busybox tar -xzpf - --exclude=./vendor/var/run' 
    else
        cat data.tar.gz | pv -trab | $AS '/dev/busybox tar -xzpf - -C /data --exclude=./vendor/var/run' 
    fi
    $AS "restorecon -FRDv /data/data"
fi


if $media_backup; then
    echo "Restoring full tar backup of /data/media ... "
    $AS mkdir -p /data/media
    if [[ "$AS" == "$AMAGISK" ]]; then
        cat data_media.tar.gz | pv -trab | $AS 'cd /data/media && /dev/busybox tar -xzpf - --exclude=./vendor/var/run' 
    else
        cat data_media.tar.gz | pv -trab | $AS '/dev/busybox tar -xzpf - -C /data/media --exclude=./vendor/var/run' 
    fi
    echo "Restoring full tar backup of /data/mediadrm ... "
    $AS mkdir -p /data/mediadrm
    if [[ "$AS" == "$AMAGISK" ]]; then
        cat data_mediadrm.tar.gz | pv -trab | $AS 'cd /data/mediadrm && /dev/busybox tar -xzpf - --exclude=./vendor/var/run' 
    else
        cat data_mediadrm.tar.gz | pv -trab | $AS '/dev/busybox tar -xzpf - -C /data/mediadrm --exclude=./vendor/var/run' 
    fi
fi

if $image_backup; then
    echo "Restoring image backup..."
    #get data image location
    PARTITION=$($AS mount | grep " /data " | cut -d ' ' -f1)
    echo "Restoring to $PARTITION"
    zcat data.img.gz 2>/dev/null | pv -trab | $AS "/dev/busybox dd of=$PARTITION 2>/dev/null"
fi

cleanup

startRuntime
