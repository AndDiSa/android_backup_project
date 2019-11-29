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
AS="adb shell su root"


if [ ! -d busybox-ndk ]; then
    git clone https://github.com/Magisk-Modules-Repo/busybox-ndk
else
    pushd busybox-ndk
    git pull
    popd
fi

echo "Waiting for device..."
adb wait-for-any

echo "Devices detected:"
adb devices

echo "Checking for root access..."
if [ $($AS whoami) != "root" ]; then
    echo "Need root access. Please use TWRP for this!"
    if $use_adb_root; then
        echo "Requesting root..."
        adb root
        echo "Waiting for device..."
        adb wait-for-any
    else
        exit 1
    fi
fi

echo "Checking for presence of /data"
if ! [ "$($AS ls /data/ | wc -l)" -gt 1 ]; then
    $DRY $AS mount /data
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

PACKAGES=`$DRY $AS "cmd package list packages -f"`
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

	#echo $appPath
	#echo $appDir
	#echo $dataDir

	$DRY $AS "/dev/busybox tar -cv -C $appDir . | gzip" | gzip -d | pv -trabi 1 | gzip -c9 > app_${dataDir}.tar.gz
	$DRY $AS "/dev/busybox tar -cv -C /data/data/$dataDir . | gzip" | gzip -d | pv -trabi 1 | gzip -c9 > data_${dataDir}.tar.gz
done

echo "## Restart Runtime" && $DRY $AS start
[[ $DRY ]] && echo "DRY RUN ONLY! Use $0 -f to actually download."
