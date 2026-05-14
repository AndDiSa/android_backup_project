#!/bin/bash
# This script automates the multi-APK installation on an Android device using ADB and PM commands.
# It extracts APKs from a tar file, calculates their combined size, creates an installation session,
# writes each APK into the session with its specific size, and commits the session.

curr_dir="$(dirname "$0")"
# shellcheck source=functions.sh
. "$curr_dir/functions.sh"

set -e   # fail early

cat <<EOF
WARNING: restoring random system apps is quite likely to make things worse
unless you are copying between 2 identical devices.
You probably want to mv backupdir/app_{com.android,com.google}* /backup/location
This will cause this script not to try and restore system app data

EOF
sleep 5

DIR="$1"

if [[ ! -d "$DIR" ]]; then
	echo "Usage: $0 <data-dir> [apps...]"
	echo "Must be created with ./backup_apps.sh"
	exit 2
fi
shift

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

pushBusybox

# Create a local temporary directory for APK extraction
LOCAL_TEMP=$(mktemp -d)
function cleanup_local() {
    rm -rf "$LOCAL_TEMP"
    cleanup
}
trap cleanup_local EXIT

pushd "$DIR" > /dev/null

if [ $# -gt 0 ]; then
	APPS="$*"
	echo "## Push apps: $APPS"
else
	APPS=$(echo app_*)
	echo "## Push all apps in $DIR: $APPS"
fi

overall_error=0
for appPackage in $APPS
do
    [[ ! -f "$appPackage" ]] && continue
    echo "--- Restoring: $appPackage ---"

    # Create a sub-temp directory for this specific app
    temp_dir="${LOCAL_TEMP}/apkinstaller-$(date +%s)"
    mkdir -p "$temp_dir"

    # Extract the tar file of the app into the temporary directory
    tar xvfz "$appPackage" -C "$temp_dir" --wildcards "*.apk" > /dev/null

    # Initialize total size of APKs
    total_size=$(find "$temp_dir" -type f -name "*.apk" -printf '%s+')
    total_size=$(echo "${total_size}0" | bc)

    if [ "$total_size" -eq 0 ]; then
        echo "No APKs found in $appPackage"
        rm -rf "$temp_dir"
        continue
    fi

    # Create a new installation session with the calculated total size
    create_cmd="pm install-create -S ${total_size}"
    echo "Executing: $create_cmd"
    session=$($AS "$create_cmd")
    session_id=$(echo "$session" | grep -o '[0-9]\+')

    if [ -z "$session_id" ]; then
        echo "Failed to create installation session. Output: $session"
        rm -rf "$temp_dir"
        overall_error=1
        continue
    fi
    echo "session_id=$session_id"

    # Write each APK into the session in order
    index=0
    error=0
    # Use dedicated file descriptor 3 to prevent adb from consuming the file list
    while IFS= read -r -d '' file_path <&3; do
        size=$(stat --format="%s" "$file_path")

        echo "Installing APK: $file_path with expected size $size"

        # Stream bytes from Host to Device using Input Redirection (<)
        if ! < "$file_path" $AS "pm install-write -S ${size} ${session_id} ${index} -"; then
            echo "Error during installation of APK: $file_path"
            error=1
            break
        fi
        index=$((index + 1))
    done 3< <(find "$temp_dir" -name "*.apk" -print0)

    if [ "$error" -eq 1 ]; then
        echo "Abandoning session ${session_id} due to write errors."
        $AS "pm install-abandon ${session_id}"
        rm -rf "$temp_dir"
        overall_error=1
        continue
    fi

    # Commit the session to complete the installation
    echo "Committing session ${session_id}..."
    if ! $AS "pm install-commit ${session_id}"; then
        echo "Failed to commit installation."
        rm -rf "$temp_dir"
        overall_error=1
        continue
    fi

    # Clean up the temporary directory
    rm -rf "$temp_dir"

    appPrefix=$(echo "$appPackage" | sed 's/app_//' | sed 's/\.tar\.gz//')
    dataDir=$appPrefix

    echo "## Now installing app data"
    $AS "pm clear $appPrefix"
    sleep 1

    # figure out current app user id
    L=( $($AS ls -d -l "/data/data/$dataDir" 2>/dev/null) ) || :
    ID=${L[2]}

    if [[ -z "$ID" ]]; then
        echo "Error: $appPrefix still not installed or data dir not created"
        overall_error=1
        continue
    fi

    echo "APP User id is $ID"

    dataPackage=$(echo "$appPackage" | sed 's/app_/data_/')
    if [[ -f "$dataPackage" ]]; then
        cat "$dataPackage" | pv -trab | $AS "/dev/busybox tar -xzpf - -C /data/data/$dataDir"
        $AS "chown -R $ID.$ID /data/data/$dataDir"
    fi
done

echo "Fixing SELinux permissions..."
$AS "restorecon -FRDv /data/data"

popd > /dev/null

if [ $overall_error -ne 0 ]; then
    echo "Restore completed with some errors."
    exit 1
fi
exit 0
