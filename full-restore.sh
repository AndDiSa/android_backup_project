#!/bin/bash
# License; Apache-2
# anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
# shellcheck source=functions.sh
. "$curr_dir/functions.sh"

set -e   # fail early

data_backup=true
media_backup=false
image_backup=false
extra_backup=false
RESTOREDIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        help|-h|--help)
            echo "Restores a full backup over ADB"
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
        -*)
            echo "Unknown argument $1"
            exit 1
            ;;
        *)
            RESTOREDIR="$1"
            ;;
    esac
    shift
done

if [[ -z "$RESTOREDIR" ]]; then
    echo "Missing directory from which to restore ..."
    exit 1
fi

if [[ ! -d "$RESTOREDIR" ]]; then
    echo "$RESTOREDIR does not exist, exiting"
    exit 2
fi

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

echo "restoring from $RESTOREDIR"

stopRuntime
pushd "$RESTOREDIR" > /dev/null

if $data_backup; then
    echo "Restoring full tar backup of /data excluding /data/media ... "
    if [[ -f data.tar.gz ]]; then
        cat data.tar.gz | pv -trab | $AS '/dev/busybox tar -xzpf - -C /data --exclude=./vendor/var/run || true'
        $AS "restorecon -FRDv /data/data"
    else
        echo "data.tar.gz not found!"
    fi
fi


if $media_backup; then
    echo "Restoring full tar backup of /data/media ... "
    if [[ -f data_media.tar.gz ]]; then
        $AS mkdir -p /data/media
        cat data_media.tar.gz | pv -trab | $AS '/dev/busybox tar -xzpf - -C /data/media --exclude=./vendor/var/run || true'
    fi
    echo "Restoring full tar backup of /data/mediadrm ... "
    if [[ -f data_mediadrm.tar.gz ]]; then
        $AS mkdir -p /data/mediadrm
        cat data_mediadrm.tar.gz | pv -trab | $AS '/dev/busybox tar -xzpf - -C /data/mediadrm --exclude=./vendor/var/run || true'
    fi
fi

if $image_backup; then
    echo "Restoring image backup..."
    if [[ -f data.img.gz ]]; then
        #get data image location
        PARTITION=$($AS mount | grep " /data " | cut -d ' ' -f1)
        echo "Restoring to $PARTITION"
        zcat data.img.gz | pv -trab | $AS "/dev/busybox dd of=$PARTITION 2>/dev/null || true"
    else
        echo "data.img.gz not found!"
    fi
fi

cleanup

startRuntime
popd > /dev/null
