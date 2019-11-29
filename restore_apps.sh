#!/bin/bash

# License; Apache-2

# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# Added support for filenames/directories with spaces
# improved / modified to work with Android 9 / 10 by anddisa@gmail.com

set -e   # fail early

A="adb"
AS="adb shell su root"
OLDIFS="$IFS"

DRY="echo"
if [[ "$1" == "--doit" ]]; then 
	DRY="" 
	shift
else
cat <<EOF
WARNING: restoring random system apps is quite likely to make things worse
unless you are copying between 2 identical devices.
You probably want to mv backupdir/data/{com.android,com.google}* /backup/location
This will cause this script not to try and restore system app data

EOF
sleep 3
fi
DIR="$1"

if [[ ! -d "$DIR" ]]; then
	echo "Usage: $0 [--doit] <data-dir>"
	echo "Must be created with ./backup_apps.sh"
	echo "Will be dry run by default unless --doit is given"
	exit 2
fi
shift

if [ ! -d busybox-ndk ]; then
    git clone https://github.com/Magisk-Modules-Repo/busybox-ndk
else
    pushd busybox-ndk
    git pull
    popd
fi

echo "Waiting for device..."
$A wait-for-any

echo "Devices detected:"
$A devices

echo "Checking for root access..."
if [ $($AS whoami) != "root" ]; then
    echo "Need root access. Please use TWRP or a rooted device for this!"
    if $use_adb_root; then
        echo "Requesting root..."
        $A root
        echo "Waiting for device..."
        $A wait-for-any
    else
        exit 1
    fi
fi

cd $DIR

if [ $# -gt 0 ]; then
	APPS="$@"
	echo "## Push apps: $APPS"
else
	APPS=$(echo app_*)
	echo "## Push all apps in $DIR: $APPS"
fi

echo "## Install missing apps"
for appPackage in $APPS
do
	APP=`tar xvfz $appPackage -C /tmp/ --wildcards "*.apk" | sed 's/\.\///'`
	echo $appPackage
	echo $APP
	echo "Installing $APP"
	pushd /tmp
	error=`$DRY exec $A install -r -t ${APP}`
	echo "error=$error"
	rm *.apk
	popd

	appPrefix=`echo $appPackage | sed 's/app_//' | sed 's/\.tar\.gz//'`
	echo $appPrefix
	#allApps=`$AS cmd package list packages -f`
	#appConfig=`echo $appApps | tr " " "\n" | grep $appPrefix`
	#echo $appConfig

	#dataDir=`echo $appConfig | sed 's/package://' | rev | cut -d "=" -f1 | rev`
	dataDir=$appPrefix
	echo $dataDir

	echo
	echo "## Now installing app data"
	echo "## Stop Runtime" && $DRY $AS stop
	$DRY sleep 5	

	echo "Attempting to restore data for $APP"
	# figure out current app user id
	L=( $($AS ls -d -l /data/data/$dataDir 2>/dev/null) ) || :
	# drwx------ 10 u0_a240 u0_a240 4096 2017-12-10 13:45 .
	# => return u0_a240
	ID=${L[2]}

	if [[ -z $ID ]]; then
	    echo "Error: $APP still not installed"
	    $DRY exit 2
	fi

	echo "APP User id is $ID"

	dataPackage=`echo $appPackage | sed 's/app_/data_/'`
	$DRY $A push $dataPackage /sdcard/
	echo "mkdir -p /data/data/$dataDir"
	$DRY $AS "mkdir -p /data/data/$dataDir"
	$DRY $AS "/dev/busybox tar xfz /sdcard/$dataPackage -C /data/data/$dataDir"
	$DRY $AS "rm /sdcard/$dataPackage"
	$DRY $AS "chown -R $ID.$ID /data/data/$dataDir" || true
	echo "## Restart Runtime" 
	$DRY $AS start
	$DRY sleep 5	
done
[[ -n $DRY ]] && echo "==== This is DRY MODE. Use --doit to actually copy."
echo "Yoscript exiting after adb install will want to fix securelinux perms with: restorecon -FRDv /data/data"
$DRY $AS "restorecon -FRDV /data/data"
