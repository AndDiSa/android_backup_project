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
RESTOREDIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        help|-h|--help)
            echo "Restores a full backup over ADB"
            echo "tar /data, binary img /data block"
            echo ""
            echo "Options:"
            echo "  --graceful          Don't stop the Android framework (uses force-stop on all apps)"
            echo "                      Default for file-level restores (tar) on Android 14/16+ to"
            echo "                      avoid dropping FBE encryption keys."
            echo "  --stop-runtime,     Stop the Android framework (stop/start) during restore."
            echo "  --no-graceful       Default when --image-backup is used."
            echo "  --rate-limit <rate> Rate limit transfer speed (e.g. 40m, 50m, default: 40m)"
            echo "  --no-rate-limit     Disable rate limiting (unlimited transfer speed)"
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
        --rate-limit)
            shift
            RATE_LIMIT="$1"
            ;;
        --no-rate-limit)
            RATE_LIMIT=""
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

if $image_backup && ! $graceful_explicit; then
    echo "Note: --image-backup restore requested; stopping Android runtime by default (use --graceful to override)."
    graceful=false
fi

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

echo "restoring from $RESTOREDIR"

if $graceful; then
    stopAllApps
    if $image_backup; then
        echo "WARNING: Partition image restore requested with --graceful."
        echo "Flashing a live mounted filesystem may result in severe corruption!"
        sleep 5
    fi
else
    stopRuntime
fi
pushd "$RESTOREDIR" > /dev/null

PV_CMD="pv -trab"
rl_flag=$(getRateLimitPvFlag)
[[ -n "$rl_flag" ]] && PV_CMD="pv -trab $rl_flag"

if $data_backup; then
    echo "Restoring full tar backup of /data excluding /data/media ... "
    if [[ -f data.tar.gz ]]; then
        cat data.tar.gz | $PV_CMD | $AS "$BB tar -xzpf - -C /data ${DATA_EXCLUDES[*]} || true"
        $AS "restorecon -FRDv /data/data /data/user /data/user_de /data/app /data/system /data/system_ce /data/system_de /data/misc_ce /data/misc_de 2>/dev/null || true"
    else
        echo "data.tar.gz not found!"
    fi
fi


if $media_backup; then
    echo "Restoring full tar backup of /data/media ... "
    if [[ -f data_media.tar.gz ]]; then
        $AS mkdir -p /data/media
        cat data_media.tar.gz | $PV_CMD | $AS "$BB tar -xzpf - -C /data/media --exclude=./vendor/var/run || true"
        $AS "chown -R media_rw:media_rw /data/media" 2>/dev/null || :
        $AS "restorecon -FRDv /data/media"
    elif [[ -f media.tar.gz ]]; then
        cat media.tar.gz | $PV_CMD | $AS "$BB tar -xzpf - -C /data --exclude=./vendor/var/run || true"
        $AS "chown -R media_rw:media_rw /data/media" 2>/dev/null || :
        $AS "restorecon -FRDv /data/media"
        $AS "restorecon -FRDv /data/mediadrm" 2>/dev/null || :
    fi
    if [[ -f data_mediadrm.tar.gz ]]; then
        echo "Restoring full tar backup of /data/mediadrm ... "
        $AS mkdir -p /data/mediadrm
        cat data_mediadrm.tar.gz | $PV_CMD | $AS "$BB tar -xzpf - -C /data/mediadrm --exclude=./vendor/var/run || true"
        $AS "restorecon -FRDv /data/mediadrm"
    fi
fi

if $image_backup; then
    echo "Restoring image backup..."
    if [[ -f data.img.gz ]]; then
        #get data image location
        PARTITION=$($AS mount | tr -d '\r' | grep " /data " | cut -d ' ' -f1)
        echo "Restoring to $PARTITION"
        zcat data.img.gz | $PV_CMD | $AS "$BB dd of=$PARTITION 2>/dev/null || true"
    else
        echo "data.img.gz not found!"
    fi
fi

cleanup

if ! $graceful; then
    startRuntime
fi
popd > /dev/null
