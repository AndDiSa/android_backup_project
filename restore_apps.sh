#!/bin/bash
# License; Apache-2
# Originally from Raphael Moll
# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# improved / completly reworked to play nice with Android 9 / 10 by anddisa@gmail.com 2019/12

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
	echo "Usage: $0 <data-dir> [--user <ID|Name>] [apps...]"
	echo "Must be created with ./backup_apps.sh"
	exit 2
fi
shift

if [[ "$1" == "--user" ]]; then
    shift
    resolveUserId "$1"
    shift
fi

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

echo "## Installing apps"
for appPackage in $APPS
do
    [[ ! -f "$appPackage" ]] && continue

    echo "--- Restoring: $appPackage ---"

    # Extract APKs to local temp
    tar xvfz "$appPackage" -C "$LOCAL_TEMP" --wildcards "*.apk" | sed 's/\.\///'

    # Find all extracted APKs
    mapfile -t EXTRACTED_APKS < <(find "$LOCAL_TEMP" -maxdepth 1 -name "*.apk")

    if [ ${#EXTRACTED_APKS[@]} -eq 0 ]; then
        echo "No APK found in $appPackage"
        continue
    fi

	echo "Installing ${EXTRACTED_APKS[*]}"
    # install-multiple handles one or more APKs
	$A install-multiple --user $USER_ID -r -t "${EXTRACTED_APKS[@]}"
	rm -f "$LOCAL_TEMP"/*.apk

	appPrefix=$(echo "$appPackage" | sed 's/app_//' | sed 's/\.tar\.gz//')
	echo "Package Name: $appPrefix"

	dataDir=$appPrefix
	systemDataDir=$(getSystemDataDir)

	echo "## Now installing app data"
	$AS "pm clear --user $USER_ID $appPrefix"
	sleep 1

	echo "Attempting to restore data for $appPrefix (User $USER_ID)"
	# figure out current app user id
	L=( $($AS ls -d -l "$systemDataDir/$dataDir" 2>/dev/null) ) || :
	# drwx------ 10 u0_a240 u0_a240 4096 2017-12-10 13:45 .
	# => return u0_a240
	ID=${L[2]}

	if [[ -z $ID ]]; then
	    echo "Error: $appPrefix still not installed or data dir $systemDataDir/$dataDir not created"
	    continue
	fi

	echo "APP User id is $ID"

	dataPackage=$(echo "$appPackage" | sed 's/app_/data_/')
    if [[ -f "$dataPackage" ]]; then
        echo "Restoring data from $dataPackage"
        cat "$dataPackage" | pv -trab | $AS "/dev/busybox tar -xzpf - -C $systemDataDir/$dataDir"
        $AS "chown -R $ID.$ID $systemDataDir/$dataDir"
    else
        echo "No data package found for $appPrefix"
    fi
done

echo "Fixing SELinux permissions..."
$AS "restorecon -FRDv $systemDataDir"

popd > /dev/null

