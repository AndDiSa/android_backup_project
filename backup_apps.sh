#!/bin/bash

# License; Apache-2

# Originally from Raphael Moll
# Tested/Fixed for Android O by marc_soft@merlins.org 2017/12
# improved / modified to work with Android 9 / 10 by anddisa@gmail.com

set -e   # fail early

DRY=""
if [[ "$1" == "-d" ]]; then shift; DRY="echo" ; fi

SYSTEM_PATTERN=""
if [[ "$1" == "-system" ]]; then shift; SYSTEM_PATTERN="/system/app" ; fi

A="adb"
AMAGISK="adb shell su -c " 	# -- needed for magisk rooted devices
AROOT="adb shell su root " # -- needed for adb inscure devices

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

echo "Checking for presence of /data"
if ! [ "$($AS ls /data/ | wc -l)" -gt 1 ]; then
    $DRY $AS mount /data
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

HW=`$AS getprop ro.hardware | tr -d '\r'`
BUILD=`$AS getprop ro.build.id | tr -d '\r'`

DATE=`date +%F`
DIR="${HW}_${DATE}_${BUILD}"
if test -d "$DIR"; then
    echo "$DIR already exists, exiting"
    exit 2
fi

if ! [ "$($AS ls /data/ | wc -l)" -gt 4 ]; then
    echo "It seems like /data is not in a sane state!"
    $AS ls /data || :
    $AS stat /data || :
    exit 1
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
$DRY $A push busybox-ndk/busybox-$target_arch /sdcard/busybox
$DRY $AS mv /sdcard/busybox /dev/busybox
$DRY $AS chmod +x /dev/busybox
if ! $AS /dev/busybox >/dev/null; then
    echo "Busybox doesn't work here!"
    exit 1
fi

echo "### Creating dir $DIR"
$DRY mkdir -p $DIR
$DRY cd $DIR

PACKAGES=`$DRY $A shell "cmd package list packages -f"`
echo $PACKAGES
echo "## Stop Runtime" && $DRY $AS stop
echo "## Pull apps"

DATADIR=""
DATA_PATTERN="/data/app"
PATTERN=$DATA_PATTERN
if [[ "$SYSTEM_PATTERN" != "" ]]; then PATTERN="$SYSTEM_PATTERN}\|$DATA_PATTERN" ; fi

for APP in `echo $PACKAGES | tr " " "\n" | grep "${PATTERN}"`; do
	echo $APP

	appPath=`echo $APP | sed 's/package://' | rev | cut -d "=" -f2- | rev`
	appDir=${appPath%/*}
	dataDir=`echo $APP | sed 's/package://' | rev | cut -d "=" -f1 | rev`

	echo $appPath
	echo $appDir
	echo $dataDir

#	package:/data/app/com.google.android.apps.gcs-EmZxhIV4iomj2W20ERQ4xQ==/base.apk=com.google.android.apps.gcs
#	/data/app/com.google.android.apps.gcs-EmZxhIV4iomj2W20ERQ4xQ==/base.apk
#	/data/app/com.google.android.apps.gcs-EmZxhIV4iomj2W20ERQ4xQ==
#	com.google.android.apps.gcs

        if [[ "$AS" == "$AMAGISK" ]]; then
#
# --- version for magisk rooted
#
		$DRY $AS "'cd $appDir && /dev/busybox tar czf - ./ | base64' 2>/dev/null" | base64 -d | pv -trabi 1 > app_${dataDir}.tar.gz
		$DRY $AS "'cd /data/data/$dataDir && /dev/busybox tar czf - ./ | base64' 2>/dev/null" | base64 -d | pv -trabi 1 > data_${dataDir}.tar.gz
		#adb shell "su -c 'cd $appDir && /dev/busybox tar czf - ./ | base64' 2>/dev/null" | base64 -d | pv -trabi 1 > app_${dataDir}.tar.gz
		#adb shell "su -c 'cd /data/data/$dataDir && /dev/busybox tar czf - ./ | base64' 2>/dev/null" | base64 -d | pv -trabi 1 > data_${dataDir}.tar.gz
	else
#
# --- version for adb insecure
#
       		$DRY $AS "/dev/busybox tar -cv -C $appDir . | gzip" | gzip -d | pv -trabi 1 | gzip -c9 > app_${dataDir}.tar.gz
       		$DRY $AS "/dev/busybox tar -cv -C /data/data/$dataDir . | gzip" | gzip -d | pv -trabi 1 | gzip -c9 > data_${dataDir}.tar.gz
	fi
done

$DRY $AS "rm /dev/busybox"
echo "## Restart Runtime" && $DRY $AS start
[[ $DRY ]] && echo "DRY RUN ONLY! Use $0 -f to actually download."
