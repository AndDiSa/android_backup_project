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
graceful=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        help|-h|--help)
            echo "Makes a full backup over ADB"
            echo "tar /data, binary img /data block"
            echo ""
            echo "Options:"
            echo "  --graceful          Don't stop the Android framework (uses force-stop on all apps)"
            echo "                      Recommended for file-level backups (tar) to avoid dropping"
            echo "                      encryption keys on some devices."
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
        --graceful)
            graceful=true
            ;;
        *)
            echo "Unknown argument $1"
            exit 1
            ;;
    esac
    shift
done

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

mkBackupDir
pushd "$DIR" > /dev/null

if $graceful; then
    stopAllApps
    if $image_backup; then
        echo "WARNING: Partition image backup requested with --graceful."
        echo "A live backup of a mounted filesystem may result in corruption!"
        sleep 5
    fi
else
    stopRuntime
fi

if $data_backup; then
    echo "Creating full tar backup of /data excluding /data/media"
    $AS "$BB tar -cz -C /data --exclude='./media' --exclude='./mediadrm' --exclude='./user/0' . 2>/dev/null" | pv -trab > data.tar.gz
fi

if $media_backup; then
    echo "Creating full tar backup of /data/media"
    $AS "$BB tar -cz -C /data/media . 2>/dev/null" | pv -trab > data_media.tar.gz
    $AS "$BB tar -cz -C /data/mediadrm . 2>/dev/null" | pv -trab > data_mediadrm.tar.gz
fi

if $image_backup; then
    echo "Creating image backup..."
    #get data image location
    PARTITION=$($AS mount | grep " /data " | cut -d ' ' -f1)
    echo "trying to get $PARTITION as data.img.gz"
    $AS "$BB dd if=$PARTITION bs=16777216 2>/dev/null | $BB gzip" | pv -trab > data.img.gz

    echo "Verifying image backup..."
    echo -n "  Calculate checksum on device: "
    device_checksum="$($AS $BB sha256sum "$PARTITION" | cut -d ' ' -f1)"
    echo "$device_checksum"
    echo -n "  Calculate checksum locally: "
    local_checksum="$(gzip -d < data.img.gz | sha256sum | cut -d ' ' -f1)"
    echo "$local_checksum"

    if [ "$local_checksum" == "$device_checksum" ]; then
        echo "Checksums match."
    else
        echo -e "\033[1mChecksums don't match! $local_checksum != $device_checksum\033[0m"
    fi
fi

cleanup

if ! $graceful; then
    startRuntime
fi

popd > /dev/null

