#!/bin/bash

# License; Apache-2

# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# Added support for filenames/directories with spaces
# improved / modified to work with Android 9 / 10 by anddisa@gmail.com

set -e   # fail early

A="adb"
AMAGISK="adb shell su -c "	# -- needed for magisk rooted devices
AROOT="adb shell su root "	# -- needed for adb inscure devices

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
if [ $($AMAGISK whoami) == "root" ]; then
       AS=$AMAGISK
else
       if [ $($AROOT whoami) == "root" ]; then
               AS=$AROOT
       else
               echo "Requesting root..."
               $A root
               echo "Waiting for device..."
               $A wait-for-any
       fi
       if [ $($AROOT whoami) == "root" ]; then
               AS=$AROOT
       else
               exit 1
       fi
fi

echo "Determining architecture..."
target_arch="$($AS uname -m)"
case $target_arch in
    aarch64|arm64|armv8|armv8a)
        target_arch=arm64
        ;;
    aarch32|arm32|arm|armv7|armv7a|arm-neon|armv7a-neon|aarch|ARM)
        target_arch=arm
        ;;
    mips|MIPS|mips32|arch-mips32)
        target_arch=mips
        ;;
    mips64|MIPS64|arch-mips64)
        target_arch=mips64
        ;;
    x86|x86_32|IA32|ia32|intel32|i386|i486|i586|i686|intel)
        target_arch=x86
        ;;
    x86_64|x64|amd64|AMD64|amd)
        target_arch=x86_64
        ;;
    *)
        echo "Unrecognized architecture $target_arch"
        exit 1
        ;;
esac

echo "Pushing busybox to device..."
$A push busybox-ndk/busybox-$target_arch /sdcard/busybox
$AS "mv /sdcard/busybox /dev/busybox"
$AS "chmod +x /dev/busybox"

if ! $AS "/dev/busybox >/dev/null"; then
    echo "Busybox doesn't work here!"
    exit 1
fi

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
	error=`$DRY $A install -r -t ${APP}`
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
	$DRY $AS "pm clear $appPrefix"
	$DRY sleep 1

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
done
[[ -n $DRY ]] && echo "==== This is DRY MODE. Use --doit to actually copy."
echo "Yoscript exiting after adb install will want to fix securelinux perms with: restorecon -FRDv /data/data"
$DRY $AS "restorecon -FRDv /data/data"
$DRY $AS "rm /dev/busybox"

