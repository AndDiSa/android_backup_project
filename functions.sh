#!/bin/bash

# Ensure pipe errors are caught
set -o pipefail

A="adb"
if [[ -n "$ADB_SERIAL" ]]; then
    A="adb -s $ADB_SERIAL"
fi

AMAGISK="$A shell su root "      # -- needed for magisk rooted devices
AMAGISK2="$A shell su 0 -c "     # -- needed for magisk rooted devices (depends on su version installed)
AMAGISK3="$A shell su -c "       # -- needed for magisk rooted devices (depends on su version installed)
AROOT="$A shell "

BB="/data/local/tmp/busybox"

USER_ID=0
USER_NAME=""

function resolveUserId()
{
    local identifier="$1"
    if [[ -z "$identifier" ]]; then
        # Default to owner/main user if no identifier provided
        USER_ID=0
        return
    fi

    # If it's a number, assume it's the USER_ID directly
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        USER_ID="$identifier"
        return
    fi

    # Otherwise, try to resolve via pm list users
    # This handles work profiles which might have names like "Island" or "Work Profile"
    # Example output: UserInfo{10: Island :1030} running
    local user_line
    user_line=$($A shell pm list users | tr -d '\r' | grep -i ":[[:space:]]*$identifier[[:space:]]*:")
    if [[ -n "$user_line" ]]; then
        # Extract ID between { and :
        USER_ID=$(echo "$user_line" | cut -d "{" -f2 | cut -d ":" -f1)
        echo "Resolved user '$identifier' to ID $USER_ID"
    else
        echo "Error: Could not resolve user '$identifier'"
        # List available users to help the user choose the right identifier
        $A shell pm list users
        exit 1
    fi
}

function resolveUserName()
{
    # Example output: UserInfo{10: Island :1030} running
    local user_line
    user_line=$($A shell pm list users | tr -d '\r' | grep "^[[:space:]]*UserInfo{$USER_ID:")
    if [[ -n "$user_line" ]]; then
        # Extract name between : and :
        USER_NAME=$(echo "$user_line" | cut -d ":" -f2 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
}

function cleanup()
{
    $AS "rm $BB"
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
    local deps=("adb" "tar" "wc" "tr" "sed" "rev" "cut" "gzip" "pv")
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

    if [[ "$USER_ID" != "0" ]]; then
        if [[ -n "$USER_NAME" ]]; then
            DIR="${DIR}_${USER_NAME}"
        else
            DIR="${DIR}_u${USER_ID}"
        fi
    fi

    if [[ -d "$DIR" ]]; then
        echo "$DIR already exists, exiting"
        exit 2
    fi

    echo "### Creating dir $DIR"
    mkdir -p "$DIR"
}

function writeBackupMetadata()
{
    local meta_file="$DIR/backup_info.txt"
    echo "Creating metadata file: $meta_file"
    echo "HW=$($AS getprop ro.hardware | tr -d '\r')" > "$meta_file"
    echo "BUILD=$($AS getprop ro.build.id | tr -d '\r')" >> "$meta_file"
    echo "DATE=$(date +%F)" >> "$meta_file"
    echo "BACKUP_USER_ID=$USER_ID" >> "$meta_file"
    echo "USER_NAME=$USER_NAME" >> "$meta_file"
}

function readBackupMetadata()
{
    local meta_file="$DIR/backup_info.txt"
    if [[ -f "$meta_file" ]]; then
        echo "Reading metadata from $meta_file"
        local saved_name
        saved_name=$(grep "^USER_NAME=" "$meta_file" | cut -d "=" -f2 || true)
        local saved_id
        saved_id=$(grep "^BACKUP_USER_ID=" "$meta_file" | cut -d "=" -f2 || true)

        if [[ -n "$saved_name" ]]; then
            echo "Backup was for user name: $saved_name"
            # Try to resolve the current ID for this name on this device
            resolveUserId "$saved_name"
        elif [[ -n "$saved_id" ]]; then
            echo "Backup was for user ID: $saved_id"
            USER_ID="$saved_id"
        fi
    else
        echo "No metadata file found, defaulting to User ID $USER_ID"
    fi
}

function getSystemDataDir()
{
    # Main user (User 0) uses /data/data
    if [[ "$USER_ID" == "0" ]]; then
        echo "/data/data"
    else
        # All other users (Work Profiles, Guest, etc.) use /data/user/<id>
        echo "/data/user/$USER_ID"
    fi
}

function getInstaller()
{
    local pkg="$1"
    local installers_file="installers.txt"
    if [[ ! -f "$installers_file" && -n "$DIR" && -f "$DIR/installers.txt" ]]; then
        installers_file="$DIR/installers.txt"
    fi
    if [[ -f "$installers_file" ]]; then
        # Example line: package:com.example.app  installer=com.android.vending
        # We use a strict match to avoid partial package name matches
        grep "^package:$pkg " "$installers_file" | head -n 1 | sed 's/.*installer=//' | tr -d '\r ' || true
    fi
}

function setInstaller()
{
    local pkg="$1"
    local installer="$2"
    if [[ -n "$installer" && "$installer" != "null" ]]; then
        echo "Setting installer attribution to $installer"
        # On some Android versions, -i flag during install is not enough
        $AS "pm set-installer-package $pkg $installer" 2>/dev/null || :
    fi
}

function clearAppData()
{
    local pkg="$1"
    local systemDataDir="$2"

    echo "Attempting to clear data for $pkg via pm clear..."
    if ! $AS "pm clear --user $USER_ID $pkg"; then
        # On some Managed Profiles (Work Profiles), the Profile Owner may prevent 'pm clear'.
        # In such cases, we fall back to a manual recursive deletion of contents.
        echo "WARNING: pm clear failed for $pkg (likely Profile Owner protection). Attempting manual purge..."
        $AS "am force-stop --user $USER_ID $pkg" || :
        # Manually delete subdirectories and files, but keep the package root directory to preserve base permissions
        $AS "find $systemDataDir/$pkg -mindepth 1 -maxdepth 1 -exec rm -rf {} +" || :
        echo "Manual purge of $pkg data complete."
    fi
}

function restorePackageData()
{
    local appPrefix="$1"
    local dataPackage="$2"
    local dataDir="$appPrefix"
    local systemDataDir
    systemDataDir=$(getSystemDataDir)

    echo "## Now installing app data"
    clearAppData "$appPrefix" "$systemDataDir"
    sleep 1

    echo "Attempting to restore data for $appPrefix (User $USER_ID)"
    # figure out current app user id
    local L
    L=( $($AS ls -d -l "$systemDataDir/$dataDir" 2>/dev/null | tr -d '\r') ) || :
    # drwx------ 10 u0_a240 u0_a240 4096 2017-12-10 13:45 .
    # => return u0_a240
    local ID="${L[2]}"

    if [[ -z "$ID" ]]; then
        echo "Error: $appPrefix still not installed or data dir $systemDataDir/$dataDir not created"
        return 1
    fi

    echo "APP User id is $ID"

    if [[ -f "$dataPackage" ]]; then
        echo "Restoring data from $dataPackage"
        cat "$dataPackage" | pv -trab | $AS "$BB tar -xzpf - -C $systemDataDir/$dataDir"

        # Surgical chown: Main User/Group
        $AS "chown -R $ID:$ID $systemDataDir/$dataDir"

        # Surgical chown: Cache Group (if exists)
        # Android uses a special _cache suffix for cache directories to isolate them.
        local CACHE_ID="${ID}_cache"
        if $AS "id $CACHE_ID" >/dev/null 2>&1; then
            echo "Applying cache group $CACHE_ID to cache directories"
            $AS "chown -R $ID:$CACHE_ID $systemDataDir/$dataDir/cache" 2>/dev/null || :
            $AS "chown -R $ID:$CACHE_ID $systemDataDir/$dataDir/code_cache" 2>/dev/null || :
        fi

        # Force restorecon to update SELinux labels.
        # The -F flag is important to force-reset the context, ensuring the correct MCS
        # categories (e.g. :c512,c768) are applied for work profile data isolation.
        $AS "restorecon -FRv $systemDataDir/$dataDir"
    else
        echo "No data package found for $appPrefix"
    fi
    return 0
}

function ensureBusybox()
{
    local target_arch="$1"
    local local_dir="busybox-ndk"
    local binary_name="busybox-$target_arch"
    local local_file="$local_dir/$binary_name"
    local repo_url="https://raw.githubusercontent.com/Magisk-Modules-Repo/busybox-ndk/master/"

    mkdir -p "$local_dir"

    if [[ -s "$local_file" ]]; then
        return 0
    fi

    echo "Busybox binary not found locally. Downloading $binary_name from GitHub..."
    local tmp_file="${local_file}.tmp"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fL "${repo_url}${binary_name}" -o "$tmp_file"; then
            rm -f "$tmp_file"
            echo "Error: Failed to download $binary_name via curl"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "$tmp_file" "${repo_url}${binary_name}"; then
            rm -f "$tmp_file"
            echo "Error: Failed to download $binary_name via wget"
            exit 1
        fi
    else
        echo "Error: Neither curl nor wget found to download $binary_name"
        exit 1
    fi

    mv "$tmp_file" "$local_file"
    chmod +x "$local_file"
    echo "Download complete: $local_file"
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

    ensureBusybox "$target_arch"

    echo "Pushing busybox to device ($target_arch)..."
    $A push "busybox-ndk/busybox-$target_arch" "$BB"
    $AS "chmod 755 $BB"

    # Redirect both stdout AND stderr, and explicitly run a harmless applet 
    # to confirm it's working natively.
    if ! $AS "$BB true >/dev/null 2>&1"; then
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

function stopAllApps()
{
    echo "## Force-stopping all applications for all users..."
    # Get all user IDs
    local users
    users=$($A shell pm list users | tr -d '\r' | grep "UserInfo" | cut -d "{" -f2 | cut -d ":" -f1)

    for uid in $users; do
        echo "   Processing User $uid..."
        # Get all packages for this user
        local pkgs
        pkgs=$($A shell pm list packages --user "$uid" | tr -d '\r' | cut -d ":" -f2)
        for pkg in $pkgs; do
            # We don't need to wait for each one, so we can background or just run fast
            $AS "am force-stop --user $uid $pkg"
        done
    done
    echo "## All applications stopped."
}

function updateBusybox()
{
    # Kept for backward compatibility; pushBusybox now downloads only the required
    # architecture binary on demand via ensureBusybox (aligned with ART-V2 BusyboxManager).
    mkdir -p busybox-ndk
}

