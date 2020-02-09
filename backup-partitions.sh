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

if [[ $# -gt 0 ]]; then
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
                echo "Unknown argument $1"
                exit 1
                ;;
        esac
    done
fi

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

pushBusybox

mkBackupDir
pushd "$DIR"

PARTITIONS=$($A shell "ls /dev/block/by-name/")
echo $PARTITIONS

stopRuntime 

if $image_backup; then
    echo "Creating partition image backups ..."
    for i in $PARTITIONS; do
    	PARTITION="/dev/block/by-name/$i"
    	echo "getting $PARTITION ..."
    	$AS "/dev/busybox dd if=$PARTITION bs=4096 2>/dev/null" > $i.img

    	echo "Verifying image backup..."
    	echo -n "  Calculate checksum on device: "
    	device_checksum="$($AS /dev/busybox sha256sum $PARTITION | cut -d ' ' -f1)"
    	echo "$device_checksum"
    	echo -n "  Calculate checksum locally: "
    	local_checksum="$(sha256sum $.img | cut -d ' ' -f1)"
    	echo "$local_checksum"

    	if [ "$local_checksum" == "$device_checksum" ]; then
        	echo "Checksums match."
    	else
        	echo -e "\033[1mChecksums don't match! $local_checksum != $device_checksum\033[0m"
    	fi
    done
fi

cleanup

startRuntime

popd # $DIR

