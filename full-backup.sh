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

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

mkBackupDir
pushd "$DIR"

stopRuntime

if $data_backup; then
    echo "Creating full tar backup of /data excluding /data/media"
    if [[ "$AS" == "$AMAGISK" ]]; then
    	$AS 'cd /data && /dev/busybox tar -czf - --exclude="media" --exclude="mediadrm" ./ | base64 2>/dev/null"' | base64 -d | pv -trabi 1 > data.tar.gz
    else
    	$AS '/dev/busybox tar -cv -C /data --exclude="/data/media" --exclude="/data/mediadrm" . | gzip' | gzip -d | pv -trabi 1 | gzip -c9 > data.tar.gz
    fi
fi

if $media_backup; then
    echo "Creating full tar backup of /data/media"
    if [[ "$AS" == "$AMAGISK" ]]; then
    	$AS 'cd /data/media && /dev/busybox tar -czf - ./ | base64 2>/dev/null"' | base64 -d | pv -trabi 1 > data_media.tar.gz
    	$AS 'cd /data/mediadrm && /dev/busybox tar -czf - ./ | base64 2>/dev/null"' | base64 -d | pv -trabi 1 > data_mediadrm.tar.gz
    else
    	$AS '/dev/busybox tar -cv -C /data/media . | gzip' | gzip -d | pv -trabi 1 | gzip -c9 > data_media.tar.gz
    	$AS '/dev/busybox tar -cv -C /data/mediadrm . | gzip' | gzip -d | pv -trabi 1 | gzip -c9 > data_mediadrm.tar.gz
    fi
fi

if $image_backup; then
    echo "Creating image backup..."
    #get data image location
    PARTITION=$($AS mount | grep " /data " | cut -d ' ' -f1)
    $AS "dd if=$PARTITION bs=16777216 | gzip" | gzip -d | pv -trabi 1 | gzip -c9 > data.img.gz

    echo "Verifying image backup..."
    echo -n "  Calculate checksum on device: "
    device_checksum="$($AS /dev/busybox sha256sum $PARTITION | cut -d ' ' -f1)"
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

##
## does not yet work -> need to be super user !
##
if $extra_backup; then

    echo "Creating backup of important app data..."
    mkdir -p device_data
    pushd device_data

    if $A shell [ -d /data/data/com.google.android.apps.authenticator2 ]; then
        echo "  - Google Authenticator"
        $A pull /data/data/com.google.android.apps.authenticator2 ./
    fi
    if $A shell [ -d /data/data/com.zeapo/pwdstore ]; then
        echo "  - Password Store"
        $A pull /data/data/com.zeapo/pwdstore ./
    fi
    if $A shell [ -d /data/data/org.sufficientlysecure.keychain ]; then
        echo "  - OpenKeyChain"
        $A pull /data/data/org.sufficientlysecure.keychain ./
    fi
    if $A shell [ -d /data/data/de.fiducia.smartphone.securego.vr ]; then
        echo "  - VR SecureGo"
        $A pull /data/data/de.fiducia.smartphone.securego.vr ./
    fi
    if $A shell [ -d /data/data/de.fiduciagad.android.vrwallet ]; then
        echo "  - VR Wallet"
        $A pull /data/data/de.fiduciagad.android.vrwallet ./
    fi
    if $A shell [ -d /data/data/de.fiducia.smartphone.android.banking.vr ]; then
        echo "  - VR Banking"
        $A pull /data/data/de.fiducia.smartphone.android.banking.vr ./
    fi

    popd # device_data

    mkdir -p device_misc
    pushd device_misc

    $A pull /data/misc/. .

    popd # device_misc

    # test pulling apps

    mkdir -p device_app
    pushd device_app

    $A pull /data/app/. .

    popd # app_data

    if $A shell /dev/busybox [ -d /data/unencrypted ]; then
        mkdir -p unencrypted
        pushd unencrypted

        $A pull /data/unencrypted/. .

        popd # unencrypted
    fi
fi

cleanup

startRuntime

popd # $DIR

