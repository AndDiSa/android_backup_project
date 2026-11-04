#!/bin/bash
# License; Apache-2
# anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
# shellcheck source=functions.sh
. "$curr_dir/functions.sh"

set -e   # fail early
trap cleanup EXIT

data_backup=true
media_backup=false
image_backup=false
extra_backup=false
graceful=true
graceful_explicit=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        help|-h|--help)
            echo "Makes a full backup over ADB"
            echo "tar /data, binary img /data block"
            echo ""
            echo "Options:"
            echo "  --graceful          Don't stop the Android framework (uses force-stop on all apps)"
            echo "                      Default for file-level backups (tar) to avoid dropping"
            echo "                      FBE encryption keys on modern Android devices."
            echo "  --stop-runtime,     Stop the Android framework (stop/start) during backup."
            echo "  --no-graceful       Default when --image-backup is used."
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
        --graceful|--gracefull)
            graceful=true
            graceful_explicit=true
            ;;
        --no-graceful|--no-gracefull|--stop-runtime)
            graceful=false
            graceful_explicit=true
            ;;
        *)
            echo "Unknown argument $1"
            exit 1
            ;;
    esac
    shift
done

if $image_backup && ! $graceful_explicit; then
    echo "Note: --image-backup requested; stopping Android runtime by default for raw partition consistency (use --graceful to override)."
    graceful=false
fi

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

mkBackupDir
writeBackupMetadata
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
    # Avoid backing up duplicate User 0 app data while preserving the real directory
    exclude_dup="--exclude='./user/0'"
    if $AS "[ -L /data/data ] && [ ! -L /data/user/0 ]" 2>/dev/null; then
        exclude_dup="--exclude='./data'"
    fi
    { $AS "$BB tar -cz -C /data --exclude='./media' --exclude='./mediadrm' --exclude='./unencrypted' --exclude='./per_boot' --exclude='./gsi' --exclude='./misc/vold' --exclude='./misc/keystore' --exclude='./system_de/0/spblob' --exclude='./vendor/var/run' $exclude_dup . 2>/dev/null" || [[ $? -eq 1 ]]; } | pv -trab > data.tar.gz
fi

if $media_backup; then
    echo "Creating full tar backup of /data/media"
    { $AS "$BB tar -cz -C /data/media . 2>/dev/null" || [[ $? -eq 1 ]]; } | pv -trab > data_media.tar.gz
    if $AS "[ -d /data/mediadrm ]" 2>/dev/null; then
        { $AS "$BB tar -cz -C /data/mediadrm . 2>/dev/null" || [[ $? -eq 1 ]]; } | pv -trab > data_mediadrm.tar.gz
    fi
fi

if $image_backup; then
    echo "Creating image backup..."
    #get data image location
    PARTITION=$($AS mount | tr -d '\r' | grep " /data " | cut -d ' ' -f1)
    echo "trying to get $PARTITION as data.img.gz"
    $AS "$BB dd if=$PARTITION bs=16777216 2>/dev/null | $BB gzip" | pv -trab > data.img.gz

    echo "Verifying image backup..."
    echo -n "  Calculate checksum on device: "
    device_checksum="$($AS $BB sha256sum "$PARTITION" | tr -d '\r' | cut -d ' ' -f1)"
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

