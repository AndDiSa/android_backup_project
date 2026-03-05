#!/bin/bash
# This script automates the multi-APK installation on an Android device using ADB and PM commands.
# It extracts APKs from a tar file, calculates their combined size, creates an installation session,
# writes each APK into the session with its specific size, and commits the session.

curr_dir="$(dirname "$0")"
. "$curr_dir/functions.sh"

set -e   # fail early

OLDIFS="$IFS"

cat <<EOF
WARNING: restoring random system apps is quite likely to make things worse
unless you are copying between 2 identical devices.
You probably want to mv backupdir/app_{com.android,com.google}* /backup/location
This will cause this script not to try and restore system app data

EOF
sleep 5

DIR="$1"

if [[ ! -d "$DIR" ]]; then
	echo "Usage: $0 <data-dir>"
	echo "Must be created with ./backup_apps.sh"
	exit 2
fi
shift

checkPrerequisites

updateBusybox

lookForAdbDevice

checkRootType

pushBusybox

cd $DIR

if [ $# -gt 0 ]; then
	APPS="$@"
	echo "## Push apps: $APPS"
else
	APPS=$(echo app_*)
	echo "## Push all apps in $DIR: $APPS"
fi

TEMP_DIR=/tmp/
error=0
for appPackage in $APPS
do
        # Create a temporary directory
        temp_dir="${TEMP_DIR}/apkinstaller-$(date +%s)"
        mkdir -p "$temp_dir"
        if [ $? -ne 0 ]; then
            echo "Failed to create temporary directory."
            error=1
            continue
        fi

        # Extract the tar file of the app into the temporary directory
	APP=`tar xvfz $appPackage -C $temp_dir --wildcards "*.apk" | sed 's/\.\///'`

        # Check if the tar file exists
        tar_file="$appPackage"
        if [ ! -f "$tar_file" ]; then
            echo "The specified tar file does not exist."
            rm -rf "$temp_dir"
            error=1
            continue
        fi

        # Initialize total size of APKs
        total_size=$(($(find "$temp_dir" -type f -name "*.apk" -printf '%s+')0))

        # Create a new installation session with the calculated total size
        create_cmd="pm install-create -S ${total_size}"
        echo "Executing: $create_cmd"
        session=$($AS $create_cmd)
        read session_id <<<${session//[^0-9]/ }
        if [ $? -ne 0 ]; then
            echo "Failed to create installation session."
            rm -rf "$temp_dir"
            error=1
            continue
        fi
        echo "session_id=$session_id"

        # Write each APK into the session in order
        index=0
        find "$temp_dir" -name "*.apk" -print0 | while read -d '' file_path; do
            size=$(stat --format="%s" "$file_path")
    
            echo "Installing APK: $file_path with expected size $size"
            cat "$file_path" |$AS pm install-write -S ${size} ${session_id} ${index}
            status=$?
            if [ $status -ne 0 ]; then
                echo "Error during installation of APK: $file_path"
                rm -rf "$temp_dir"
                error=1
                continue
            fi
            index=$((index + 1))
        done

        # Commit the session to complete the installation
        commit_cmd="pm install-commit ${session_id}"
        echo "Executing: $commit_msg"
        $AS $commit_cmd
        if [ $? -ne 0 ]; then
            echo "Failed to commit installation."
            rm -rf "$temp_dir"
            error=1
            continue
        fi

        # Clean up the temporary directory
        echo "Cleaning up temporary files..."
        rm -rf "$temp_dir"

        appPrefix=$(echo $appPackage | sed 's/app_//' | sed 's/\.tar\.gz//')

	echo $appPrefix
	dataDir=$appPrefix
	echo $dataDir

	echo
	echo "## Now installing app data"
	$AS "pm clear $appPrefix"
	sleep 1

	echo "Attempting to restore data for $APP"
	# figure out current app user id
	L=( $($AS ls -d -l /data/data/$dataDir 2>/dev/null) ) || :
	# drwx------ 10 u0_a240 u0_a240 4096 2017-12-10 13:45 .
	# => return u0_a240
	ID=${L[2]}

	if [[ -z $ID ]]; then
	    echo "Error: $APP still not installed"
            error=1
	    continue
	fi

	echo "APP User id is $ID"

	dataPackage=`echo $appPackage | sed 's/app_/data_/'`
	echo "mkdir -p /dev/tmp/$dataDir"
	$AS "mkdir -p /dev/tmp/$dataDir"
	cat $dataPackage | pv -trab | $AS "/dev/busybox tar -xzpf - -C /data/data/$dataDir"
	echo "$AS chown -R $ID.$ID /data/data/$dataDir"
	$AS "chown -R $ID.$ID /data/data/$dataDir"
done
echo "script exiting after adb install will want to fix securelinux perms with: restorecon -FRDv /data/data"
$AS "restorecon -FRDv /data/data"
cleanup
if [ $error -ne 0 ]; then
    echo "restore could not be finished without errors"
fi
exit 0
