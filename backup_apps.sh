#!/bin/bash
# License; Apache-2
# Originally from Raphael Moll
# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# improved / completly reworked to play nice with Android 9 / 10 by anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
# shellcheck source=functions.sh
. "$curr_dir/functions.sh"

set -e
set -o pipefail

SYSTEM_PATTERN=""
if [[ "$1" == "--system-apps" ]]; then
    shift
    SYSTEM_PATTERN="/system/app/\|/system/priv-app/\|/system/product/app/\|/system/product/priv-app/\|/product/overlay/"
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

stopRuntime

echo "## Pull apps"

DATA_PATTERN="/data/app/"
PATTERN="$DATA_PATTERN"
if [[ -n "$SYSTEM_PATTERN" ]]; then
    PATTERN="${SYSTEM_PATTERN}\|${DATA_PATTERN}"
fi

# Use a separate file descriptor (3) for the loop input.
# This prevents 'adb shell' inside the loop from consuming the list of packages from stdin.
while IFS= read -r line <&3; do
    [[ -z "$line" ]] && continue

    clean_line="${line#package:}"
    appPath=$(echo "$clean_line" | rev | cut -d "=" -f2- | rev)
    dataDir=$(echo "$clean_line" | rev | cut -d "=" -f1 | rev)
    appDir="${appPath%/*}"

    echo "--- Processing: $dataDir ---"

    if [[ "$AS" == "$AROOT" ]]; then
        echo "Backing up APK..."
        $AS "/dev/busybox tar -cz -C \"$appDir\" . 2>/dev/null" | pv -trab > "app_${dataDir}.tar.gz"
        echo "Backing up Data..."
        $AS "/dev/busybox tar -cz -C \"/data/data/$dataDir\" . 2>/dev/null" | pv -trab > "data_${dataDir}.tar.gz"
    else
        echo "Backing up APK (root)..."
        $AS "cd \"$appDir\" && /dev/busybox tar czf - . 2>/dev/null" | pv -trab > "app_${dataDir}.tar.gz"
        echo "Backing up Data (root)..."
        $AS "cd \"/data/data/$dataDir\" && /dev/busybox tar czf - . 2>/dev/null" | pv -trab > "data_${dataDir}.tar.gz"
    fi

done 3< <(echo "$PACKAGES" | tr " " "\n" | grep "${PATTERN}")

cleanup

startRuntime
popd > /dev/null
