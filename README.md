# android-backup-project

The android backup project provides a set of scripts and tools to
backup and/or restore applications installed on Android devices.

This is **not** adb backup which didn't work for my requirements as
* it doesn't backup applications if those are requesting not to be backed up
* it does not support restoring to different devices quite well
* Google warns that it might be discontinued in future versions of Android
 

## Motivation

I never was really happy about the possibilities to backup / restore Android
devices. Especially when you are developing with (different) Android devices,
you wish you were able to transfer "configurations" from one device to a
different one. Or you would like to revert to an older version of an app or
...

The same is valid when you change your "main" device. The Google mechanism
to set up a new device from another one or from a backup works quite well,
but has almost the same deficits as adb backup: it doesn't restore all of
your apps and data.

Also TWRP or other custom recovery implementation do not really help to get
out of this situation. It's fine for creating a backup and restoring it
later on the same device but there is no support for switching devices.
In addition Android often changes architecture so that TWRP support for a
specific device is not guaranteed and at the time of writing there is not
even TWRP support for Android 10 yet.

There is another very interesting project related to backup and migration
on XDA (https://forum.xda-developers.com/android/apps-games/app-migrate-custom-rom-migration-tool-t3862763).
Unfortunately it relays on TWRP, too, and has still some issues to be solved.

Last but not least there is Titanium Backup which is available for a very
long time now. It works quite well but the free version is very limited in
functionality and provides only the possibility to store the backup on the
device itself which is a kind of contradiction for a backup.

Some time ago I started already a similar project (https://github.com/AndDiSa/ART)
to manage backup and restore of Android devices remotely. Unfortunately it
never finished and due to architectural changes of Android it would need
a complete workover so that I decided to start over from scratch :-)


## Precondition

* adb installed and in execution path
* Ubuntu Linux (other should work, too)
* package ``pv`` installed: ```sudo apt install -y pv```


## Usage
Theses scripts kind of do that TiBackup is doing, but controlling the
backup- and restore process remotely.

### backup_apps.sh

./backup_apps.sh [--system-apps]

This script creates a backup of all user (and system) applications and their data.
The backup files will be stored in a directory newly created named by the device
and the current date.


### restore_apps.sh

./restore_apps.sh [<directory_name>]

This script restores the apps and their data of a previous backup created by
backup_apps.sh
Either the directory is identified automatically by the device connected and the
current date or you can pass a directory name as parameter. In that case **all**
the apps and data found in the given directory will be restored.

If you want to restore only a part of them, please copy them into a different
directory and give that directory as a parameter to the script.

**Important**

Keep in mind that restoring all apps may cause issues as some have unique
IDs that end up causing problems if you use the same unique ID on different
devices.

You also may want to consider only restoring apps that are missing from
google play or apps that sadly decide to prevent backups of their (i.e. your)
data.


### full-backup.sh

./full-backup.sh [--data-backup][--no-data-backup][--media-backup][--no-media-backup][--image-backup][--no-image-backup]

This script does a full backup of (different parts of) the /data partition. There
are several options to control the behaviour.

--data-backup will backup /data without /data/media and /data/mediadrm

--media-backup will backup /data/media and data/mediadrm

--image-backup will backup the whole partition which is mounted as /data as a 1:1 copy

As it cannot be guaranteed that during the backup process there will be no single modification
on the /data partition it's quite common to get a checksum validation failure after the
backup is finished.


### full-restore.sh

./full-restore.sh [--data-backup][--no-data-backup][--media-backup][--no-media-backup][--image-backup][--no-image-backup] <directory_name>

This script is restoring data previously created by full-backup.sh
It accepts the same parameters as full-backup.sh and takes in addition the name of the
directory from where the backup shall be restored.


**Important**

Be **very** careful in using this method, especially when you are restoring /data 
It will overwrite everything on the /data partition and this may cause major issues
up to the point that your device becomes no longer usable. In that case you probably
need to do a full wipe to get it working again.


### Special thanks
Credit goes to Raphael Moll who initiated a similar project some time ago
and Marc Merlin who improved it to work with Android O. I took some ideas
and inspiration from these projects and from my first trial I started
years ago. The current implementation does not have much in common with
neither of those versions.

Especially I would like to thank topjohnwu for his great Magisk project
and osmOsis for his great collection of scripts and tools.

