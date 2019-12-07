#!/bin/bash
# License; Apache-2
# Originally from Raphael Moll
# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# improved / completly reworked to play nice with Android 9 / 10 by anddisa@gmail.com 2019/12

curr_dir="$(dirname "$0")"
. "$curr_dir/functions.sh"

set -e   # fail early

OLDIFS="$IFS"

cat <<EOF
WARNING: restoring random system apps is quite likely to make things worse
unless you are copying between 2 identical devices.
You probably want to mv backupdir/data/{com.android,com.google}* /backup/location
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

echo "## Installng apps"
for appPackage in $APPS
do
	APP=`tar xvfz $appPackage -C /tmp/ --wildcards "*.apk" | sed 's/\.\///'`
	echo $appPackage
	echo $APP
	echo "Installing $APP"
	pushd /tmp
	error=`$A install -r -t ${APP}`
	echo "error=$error"
	rm *.apk
	popd

	appPrefix=$(echo $appPackage | sed 's/app_//' | sed 's/\.tar\.gz//')
	echo $appPrefix
	allApps=`$A shell cmd package list packages -f`
	#echo $allApps
	appConfig=$(echo $allApps | tr " " "\n" | grep $appPrefix)
	echo "$appConfig"

	#dataDir=`echo $appConfig | sed 's/package://' | rev | cut -d "=" -f1 | rev`
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
	    exit 2
	fi

	echo "APP User id is $ID"

	dataPackage=`echo $appPackage | sed 's/app_/data_/'`
	$A push $dataPackage /sdcard/
	echo "mkdir -p /data/data/$dataDir"
	$AS "mkdir -p /data/data/$dataDir"
	$AS "/dev/busybox tar xfpz /sdcard/$dataPackage -C /data/data/$dataDir"
	$AS "rm /sdcard/$dataPackage"
	$AS "chown -R $ID.$ID /data/data/$dataDir" || true
done
echo "script exiting after adb install will want to fix securelinux perms with: restorecon -FRDv /data/data"
$AS "restorecon -FRDv /data/data"
cleanup

