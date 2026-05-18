#!/bin/bash

# Ensure pipe errors are caught
set -o pipefail

A="adb"
if [[ -n "$ADB_SERIAL" ]]; then
    A="adb -s $ADB_SERIAL"
fi

AMAGISK="adb shell su root "      # -- needed for magisk rooted devices
AMAGISK2="adb shell su 0 -c "     # -- needed for magisk rooted devices (depends on su version installed)
AMAGISK3="adb shell su -c "       # -- needed for magisk rooted devices (depends on su version installed)
AROOT="adb shell "

USER_ID=0

function resolveUserId()
{
	local identifier="$1"
	if [[ -z "$identifier" ]]; then
		USER_ID=0
		return
	fi

	# If it's a number, assume it's the USER_ID
	if [[ "$identifier" =~ ^[0-9]+$ ]]; then
		USER_ID="$identifier"
		return
	fi

	# Otherwise, try to resolve via pm list users
	# Example output: UserInfo{10:Island:1030} running
	local user_line
	user_line=$($A shell pm list users | grep ":$identifier:")
	if [[ -n "$user_line" ]]; then
		# Extract ID between { and :
		USER_ID=$(echo "$user_line" | cut -d "{" -f2 | cut -d ":" -f1)
		echo "Resolved user '$identifier' to ID $USER_ID"
	else
		echo "Error: Could not resolve user '$identifier'"
		exit 1
	fi
}

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

function checkPrerequisites()
{
	local deps=("adb" "git" "tar" "wc" "tr" "sed" "rev" "cut" "gzip" "pv")
	for dep in "${deps[@]}"; do
		if ! command -v "$dep" >/dev/null 2>&1; then
			echo "$dep not found, please install $dep"
			exit 1
		fi
	done

	local pv_required="1.6.6"
	local pv_current
	pv_current=$(pv -V | head -n 1 | cut -d " " -f2)
	if [ "$(printf '%s\n' "$pv_required" "$pv_current" | sort -V | head -n1)" != "$pv_required" ]; then
		echo "current version $pv_current of pv is lower than required version: $pv_required"
		exit 1
	fi
}

function checkRootType()
{
	echo "Checking for root access..."
	echo "1) Requesting adbd as root..."
	$A root
	echo "Waiting for device..."
	$A wait-for-any-device

	local result
	result=$($AROOT whoami 2>/dev/null | tr -d '\r')
	echo "AROOT: $result"
	if [[ "$result" == "root" ]]; then
		AS=$AROOT
		return 0
	fi

	for SU_CMD in "$AMAGISK3" "$AMAGISK2" "$AMAGISK"; do
		result=$($SU_CMD whoami 2>/dev/null | tr -d '\r')
		echo "SU_CMD ($SU_CMD): $result"
		if [[ "$result" == "root" ]]; then
			AS=$SU_CMD
			return 0
		fi
	done

	echo "Finally root is not available for this device, exiting execution."
	exit 1
}

function lookForAdbDevice()
{
	echo "Waiting for device..."
	$A wait-for-any-device

	echo "Devices detected:"
	$A devices
}

function mkBackupDir()
{
	local HW
	HW=$($AS getprop ro.hardware | tr -d '\r')
	local BUILD
	BUILD=$($AS getprop ro.build.id | tr -d '\r')

	local DATE
	DATE=$(date +%F)
	DIR="${HW}_${DATE}_${BUILD}"
	if [[ -d "$DIR" ]]; then
		echo "$DIR already exists, exiting"
		exit 2
	fi

	echo "### Creating dir $DIR"
	mkdir -p "$DIR"
}

function getSystemDataDir()
{
    if [[ "$USER_ID" == "0" ]]; then
        echo "/data/data"
    else
        echo "/data/user/$USER_ID"
    fi
}

function pushBusybox()
{
	echo "Determining architecture..."
	local target_arch
	target_arch="$($AS uname -m | tr -d '\r')"
	case $target_arch in
		aarch64|arm64|armv8|armv8a)
			target_arch=arm64
			;;
		aarch32|arm32|arm|armv7|armv7a|armv7l|armv8l|arm-neon|armv7a-neon|aarch|ARM)
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

	echo "Pushing busybox to device ($target_arch)..."

	$A push "busybox-ndk/busybox-$target_arch" /sdcard/busybox
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
		pushd busybox-ndk > /dev/null
		git pull
		popd > /dev/null
	fi
}

