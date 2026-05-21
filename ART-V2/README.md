# android-backup-project (Android / AndDiSa / ADB remote Tools V2)

ART-V2 is a Groovy-based implementation of the Android Backup Project, providing robust backup and restore capabilities for Android devices over ADB. It is designed to work with rooted devices (Magisk, etc.) and supports both application data and raw partition images.

## Features

* **Application Backup/Restore**: Back up APKs and data directories for user and system apps.
* **Partition Images**: Create and restore raw partition images via `dd`.
* **Multi-User Support**: Robust support for Android users and Work Profiles (e.g., Island).
* **Dynamic Root Detection**: Automatically detects the working `su` variant on the device.
* **Busybox Integration**: Automatically deploys the correct Busybox binary for the device architecture.
* **Metadata Tracking**: Generates `backup_info.txt` with hardware and build details for each backup.

## Preconditions

* `adb` installed and in execution path.
* `busybox-ndk` binaries available in the parent directory (`../busybox-ndk/`).
* Root access on the target device (Magisk recommended).
* Java 21+ and Gradle.

## Usage

You can build the executable fat JAR using Gradle:

```bash
gradle shadowJar
```

Then run the tool directly using Java:

```bash
# General help
java -jar build/libs/ART-V2.jar -h

# List devices
java -jar build/libs/ART-V2.jar -d

# Backup all user apps with subfolder creation
java -jar build/libs/ART-V2.jar -b -a -cs

# Backup a specific user/profile by name
java -jar build/libs/ART-V2.jar -b -a -u Island

# Backup all partition images
java -jar build/libs/ART-V2.jar -b -i

# Restore apps from a specific directory
java -jar build/libs/ART-V2.jar -r -a -bd ./backup_dir
```

> [!TIP]
> Running via `java -jar` avoids conflicts with Gradle's own command-line options (like `-u`).

### Options

* `-b, --backup`: Create a backup.
* `-r, --restore`: Restore a backup.
* `-a, --apks`: Process applications (APKs and data).
* `-i, --image`: Process partition images (all if no args).
* `-t, --tar`: Process tar archives (data, media).
* `-u, --user <id|name>`: Specify target user or profile name.
* `-sa, --system-apps`: Include system apps.
* `-bd, --baseDir <dir>`: Base directory for storage.
* `-cs, --createSubfolder`: Auto-generate directory name based on device info.

## Build

```bash
gradle build
```

The compiled JAR will be in `build/libs/`.

### Special thanks
Especially I would like to thank topjohnwu for his great Magisk project
and osmOsis for his great collection of scripts and tools.

