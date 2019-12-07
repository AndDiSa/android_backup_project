#!/bin/bash
# License; Apache-2
# anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
. "$curr_dir/functions.sh"

set -e   # fail early

use_adb_root=false
tar_backup=true
image_backup=true
extra_backup=false

if [[ $# -gt 0 ]]; then
    for param in $@; do
        case "$param" in
            help|-h|--help)
                echo "Makes a full backup over ADB"
                echo "tar /data, binary img /data block"
                exit 0
                ;;
            --tar-backup)
                tar_backup=true
                ;;
            --no-tar-backup)
                tar_backup=false
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

if $tar_backup; then
    echo "Creating full tar backup of /data"
    $AS '/dev/busybox tar -cv -C /data . | gzip' | gzip -d | pv -trabi 1 | gzip -c9 > data.tar.gz
fi

if $image_backup; then
    echo "Creating image backup..."
    #get data image location
    $AS 'dd if=/dev/block/dm-0 bs=16777216 | gzip' | gzip -d | pv -trabi 1 | gzip -c9 > data.img.gz

    echo "Verifying image backup..."
    echo -n "  Calculate checksum on device: "
    device_checksum="$($AS /dev/busybox sha256sum /dev/block/dm-0 | cut -d ' ' -f1)"
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

startRuntime

cleanUp

popd # $DIR

