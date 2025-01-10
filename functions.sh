#!/bin/bash

A="adb"
AMAGISK="adb shell su root "      # -- needed for magisk rooted devices
AMAGISK2="adb shell su 0 -c "     # -- needed for magisk rooted devices (depends on su version installed)
AMAGISK3="adb shell su -c "       # -- needed for magisk rooted devices (depends on su version installed)
AROOT="adb shell "

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
	adb=`adb --version`
        if [ $? -ne 0 ]; then
                echo "adb not found, please install adb"
                exit 1
        fi

	git=`git --version`
        if [ $? -ne 0 ]; then
                echo "git not found, please install git"
                exit 1
        fi

	tar=`tar --help`
        if [ $? -ne 0 ]; then
                echo "tar not found, please install tar"
                exit 1
	fi 

        wc=`wc --help`
        if [ $? -ne 0 ]; then
                echo "wc not found, please install wc"
                exit 1
        fi

        tr=`tr --help`
        if [ $? -ne 0 ]; then
                echo "tr not found, please install tr"
                exit 1
        fi

        sed=`sed --help`
        if [ $? -ne 0 ]; then
                echo "sed not found, please install sed"
                exit 1
        fi

        rev=`rev --help`
        if [ $? -ne 0 ]; then
                echo "rev not found, please install rev"
                exit 1
        fi

        cut=`cut --help`
        if [ $? -ne 0 ]; then
                echo "cut not found, please install cut"
                exit 1
        fi

        gzip=`gzip --help`
        if [ $? -ne 0 ]; then
                echo "gzip not found, please install gzip"
                exit 1
        fi

	pv_required="1.6.6"
 	pv_current=`pv -V | head -n 1 | cut -d " " -f2`
	if [ $? -ne 0 ]; then
		echo "pv not found, please install pv"
		exit 1
	else
		if [ "$(printf '%s\n' "$pv_required" "$pv_current" | sort -V | head -n1)" != "$pv_required" ]; then
                	echo "current version $pv_current of pv is lower than required version: $pv_required"
			exit 1
		fi
	fi
}

function checkRootType()
{
	echo "Checking for root access..."
	echo "1) Requesting adbd as root..."
	$A root
	echo "Waiting for device..."
	$A wait-for-any-device

	result=`$AROOT whoami`
	echo $result
	if [[ "$result" == "root" ]]; then
		AS=$AROOT
	else
		result=`$AMAGISK3 whoami`
		echo $result
        	if [[ "$result" == "root" ]]; then
        		AS=$AMAGISK3
		else

			result=`$AMAGISK2 whoami`
			echo $result
        		if [[ "$result" == "root" ]]; then
        			AS=$AMAGISK2
			else
				result=`$AMAGISK whoami`
				echo $result
	                	if [[ "$result" == "root" ]]; then
                        		AS=$AMAGISK
				else
					echo "Fianlly root is not available for this device, exiting execution."
					exit 1
				fi
			fi
		fi
	fi
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

