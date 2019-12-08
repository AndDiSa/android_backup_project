#!/bin/bash

A="adb"
AMAGISK="adb shell su -c "      # -- needed for magisk rooted devices
AROOT="adb shell su root " # -- needed for adb inscure devices

function cleanup()
{
	$AS "rm /dev/busybox"
}

function checkForCleanData()
{
	if ! [ "$($AS ls /data/ | wc -l)" -gt 1 ]; then
		$AS mount /data
	fi

	if ! [ "$($AS ls /data/ | wc -l)" -gt 4 ]; then
		echo "It seems like /data is not in a sane state!"
		$AS ls /data || :
		$AS stat /data || :
		exit 1
	fi
}

function checkRootType()
{
	echo "Checking for root access..."
	if [[ $($AMAGISK whoami) == "root" ]]; then
        	AS=$AMAGISK
	else
        	if [[ $($AROOT whoami) == "root" ]]; then
			AS=$AROOT
		else
			echo "Requesting root..."
			$A root
			echo "Waiting for device..."
			$A wait-for-any
		fi
		if [[ $($AROOT whoami) == "root" ]]; then
			AS=$AROOT
		else
			echo "Fianlly root is not available for this device, exiting execution."
			exit 1
		fi
	fi
}

function lookForAdbDevice()
{
	echo "Waiting for device..."
	$A wait-for-any

	echo "Devices detected:"
	$A devices
}

function mkBackupDir()
{
	HW=`$AS getprop ro.hardware | tr -d '\r'`
	BUILD=`$AS getprop ro.build.id | tr -d '\r'`

	DATE=`date +%F`
	DIR="${HW}_${DATE}_${BUILD}"
	if test -d "$DIR"; then
    		echo "$DIR already exists, exiting"
    		exit 2
	fi

	echo "### Creating dir $DIR"
	mkdir -p $DIR
}

function pushBusybox()
{
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
}

function stopRuntime()
{
	echo "## Stop Runtime" && $AS stop
}

function startRuntime()
{
	echo "## Restart Runtime" && $AS start
}

function updateBusybox()
{
	if [ ! -d busybox-ndk ]; then
		git clone https://github.com/Magisk-Modules-Repo/busybox-ndk
	else
		pushd busybox-ndk
		git pull
		popd
	fi
}

