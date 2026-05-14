#!/bin/bash
# License; Apache-2
# Originally from Raphael Moll
# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# improved / completly reworked to play nice with Android 9 / 10 by anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
# shellcheck source=functions.sh
. "$curr_dir/functions.sh"

set -e   # fail early

SYSTEM_PATTERN=""
if [[ "$1" == "--system-apps" ]]; then
    shift
    SYSTEM_PATTERN="/system/app\|/system/priv-app\|/system/product/app\|/system/product/priv-app\|/product/overlay"
fi

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

mkBackupDir
pushd "$DIR" > /dev/null

PACKAGES=$($A shell "cmd package list packages -f")
# echo "$PACKAGES"

stopRuntime

echo "## Pull apps"

DATA_PATTERN="/data/app"
PATTERN=$DATA_PATTERN
if [[ -n "$SYSTEM_PATTERN" ]]; then
    PATTERN="${SYSTEM_PATTERN}\|$DATA_PATTERN"
fi

# Use a while loop with process substitution to handle package names correctly
while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    # Extract package path and name
    # Format: package:/path/to/apk=com.package.name
    appPath=$(echo "$line" | sed 's/package://' | rev | cut -d "=" -f2- | rev)
    appDir="${appPath%/*}"
    dataDir=$(echo "$line" | sed 's/package://' | rev | cut -d "=" -f1 | rev)

    echo "--- Processing: $dataDir ---"
    echo "App Path: $appPath"
    echo "App Dir:  $appDir"

    if [[ "$AS" == "$AROOT" ]]; then
        # Use simpler pipe to avoid redundant compression/decompression
        echo "Backing up APK..."
        $AS "/dev/busybox tar -cz -C \"$appDir\" . 2>/dev/null" | pv -trab > "app_${dataDir}.tar.gz"
        echo "Backing up Data..."
        $AS "/dev/busybox tar -cz -C \"/data/data/$dataDir\" . 2>/dev/null" | pv -trab > "data_${dataDir}.tar.gz"
    else
        # Magisk version
        echo "Backing up APK (root)..."
        $AS "cd \"$appDir\" && /dev/busybox tar czf - . 2>/dev/null" | pv -trab > "app_${dataDir}.tar.gz"
        echo "Backing up Data (root)..."
        $AS "cd \"/data/data/$dataDir\" && /dev/busybox tar czf - . 2>/dev/null" | pv -trab > "data_${dataDir}.tar.gz"
    fi
done < <(echo "$PACKAGES" | tr " " "\n" | grep "${PATTERN}")

cleanup

startRuntime
popd > /dev/null
