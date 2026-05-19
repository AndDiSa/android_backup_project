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

SYSTEM_APPS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --system-apps)
            SYSTEM_APPS=1
            shift
            ;;
        --user)
            # Support for multi-user / work profiles
            # Usage: --user <ID> or --user <Name> (e.g. Island)
            shift
            resolveUserId "$1"
            shift
            ;;
        *)
            break
            ;;
    esac
done

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

checkForCleanData

pushBusybox

resolveUserName
mkBackupDir
writeBackupMetadata
pushd "$DIR" > /dev/null

PM_FLAGS="-f"
if [[ "$SYSTEM_APPS" == "0" ]]; then
    PM_FLAGS="$PM_FLAGS -3"
fi

# Capture installer info first
echo "## Capturing installer metadata"
# We remove -f here to get clean package names without APK paths
# The --user flag is essential to see apps specifically installed in the work profile
$A shell "pm list packages --user $USER_ID -i ${PM_FLAGS/-f/}" | tr -d '\r' > "installers.txt"

# Get the list of packages with their APK paths (-f) and data directory names
PACKAGES=$($A shell "pm list packages --user $USER_ID $PM_FLAGS")

stopRuntime

echo "## Pull apps"

# Use a separate file descriptor (3) for the loop input.
# This prevents 'adb shell' inside the loop from consuming the list of packages from stdin.
while IFS= read -r line <&3; do
    [[ -z "$line" ]] && continue

    clean_line="${line#package:}"
    appPath=$(echo "$clean_line" | rev | cut -d "=" -f2- | rev)
    dataDir=$(echo "$clean_line" | rev | cut -d "=" -f1 | rev)
    appDir="${appPath%/*}"
    systemDataDir=$(getSystemDataDir)

    echo "--- Processing: $dataDir ---"

    if [[ "$AS" == "$AROOT" ]]; then
        echo "Backing up APK..."
        $AS "/dev/busybox tar -cz -C \"$appDir\" . 2>/dev/null" | pv -trab > "app_${dataDir}.tar.gz"
        echo "Backing up Data..."
        $AS "/dev/busybox tar -cz -C \"$systemDataDir/$dataDir\" . 2>/dev/null" | pv -trab > "data_${dataDir}.tar.gz"
    else
        echo "Backing up APK (root)..."
        $AS "cd \"$appDir\" && /dev/busybox tar czf - . 2>/dev/null" | pv -trab > "app_${dataDir}.tar.gz"
        echo "Backing up Data (root)..."
        $AS "cd \"$systemDataDir/$dataDir\" && /dev/busybox tar czf - . 2>/dev/null" | pv -trab > "data_${dataDir}.tar.gz"
    fi

done 3< <(echo "$PACKAGES" | tr " " "\n")

cleanup

startRuntime
popd > /dev/null
