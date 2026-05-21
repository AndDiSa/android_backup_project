package de.anddisa.adb

import java.util.concurrent.TimeUnit
import java.text.SimpleDateFormat

import de.anddisa.adb.entities.BackupPackage

/**
 * BackupHandler implements the backup logic for apps, images, and full data archives.
 * It uses ADBCommander to execute 'tar' or 'dd' commands on the device and
 * streams the output back to the local machine using FileReceiver.
 * 
 * New features:
 * - Metadata generation (backup_info.txt)
 * - Dynamic backup directory naming (Hardware_Date_Build)
 * - Automatic discovery and backup of all partitions
 */
class BackupHandler extends BackupRestoreHandler {

	public BackupHandler(ADBCommander commander) {
		super(commander)
	}

	/**
	 * Orchestrates backing up multiple partition images.
	 */
	void doImageBackup(String[] blockDevices) {
		if (blockDevices != null) {
			blockDevices.each { doImageBackup( it ) }
		}
	}

	/**
	 * Backs up a raw partition image using 'dd'.
	 * Uses 'stty raw' to ensure binary data isn't corrupted by terminal settings.
	 */
	void doImageBackup(String blockDevice) {
		String[] parts = blockDevice.split("/")
		FileReceiver frImg = new FileReceiver(localBackupDirectory + "${parts[parts.length - 1]}.img")
		commander.execAsRootForResult("/dev/busybox stty raw; /dev/busybox dd if=${blockDevice} bs=4096 2>/dev/null", frImg, 15, TimeUnit.MINUTES)
		frImg.flush()
		if (frImg.isCancelled()) {
			println "error while transferring file ..."
		} else {
			println "image transfer successful"
            
            // Checksum verification
            println "Verifying image backup..."
            String deviceChecksum = commander.execAsRootForResult("/dev/busybox sha256sum ${blockDevice}").split("\\s+")[0].trim()
            println "  Device checksum: ${deviceChecksum}"
            // We'd need a local sha256sum implementation or call system command
            // For now, just log the device checksum.
		}
	}

    /**
     * Backs up all named partitions found in /dev/block/by-name/
     */
    void doAllPartitionsBackup() {
        println "Querying partitions from /dev/block/by-name/..."
        String result = commander.execAsRootForResult("ls /dev/block/by-name/")
        String[] partitions = result.split("\\s+")
        println "Found ${partitions.length} partitions."
        
        stopRuntime()
        for (String p : partitions) {
            if (p.trim()) {
                println "Backing up partition: ${p}..."
                doImageBackup("/dev/block/by-name/${p}")
            }
        }
        startRuntime()
    }

	/**
	 * Backs up selected application packages (APK and data).
	 * Temporarily stops the Android runtime to ensure data consistency.
	 */
	void doPackageBackup() {
		File f = new File(localBackupDirectory)
		if (!f.exists()) {
			f.mkdirs()
		} else {
			if (f.isDirectory()) {
				if (f.list().length != 0) {
					println "$localBackupDirectory is not empty exiting files may be overwritten"
				}
			} else {
				println "$localBackupDirectory exists but is no directory ... bailing out"
				System.exit(-1)
			}
		}
		println "starting backup ..."
		stopRuntime() // Equivalent to 'adb shell stop'
		for (BackupPackage p : packages) {
			 if (p.selected) {
				 doPackageBackup(p)
			 }
	    }
		startRuntime() // Equivalent to 'adb shell start'
		println "... backup finished"
	}

	/**
	 * Backs up a single package by creating tar archives of its APK and data directories.
	 */
	void doPackageBackup(BackupPackage p) {
        println "--- Processing: ${p.packageName} ---"
		// Backup APK
		FileReceiver frApp = new FileReceiver(localBackupDirectory + "app_${p.packageName}.tar.gz")
		commander.execAsRootForResult("/dev/busybox stty raw; cd ${p.appDirectoryOnDevice} && /dev/busybox tar cfz - ./ 2>/dev/null", frApp, 15, TimeUnit.MINUTES)
		frApp.flush()
		if (frApp.isCancelled()) {
			p.successful &= false
			println "error while transferring file"
		} else {
			p.successful &= true
			println "app package transfer successful"
		}
		// Backup Data
		FileReceiver frData = new FileReceiver(localBackupDirectory + "data_${p.packageName}.tar.gz")
		commander.execAsRootForResult("/dev/busybox stty raw; cd ${p.dataDirectoryOnDevice} && /dev/busybox tar cfz - ./ 2>/dev/null", frData, 15, TimeUnit.MINUTES)
		frData.flush()
		if (frData.isCancelled()) {
			p.successful &= false
			println "error while transferring file"
		} else {
			p.successful &= true
			println "data package transfer successful"
		}
	}
	
	/**
	 * Backs up partitions or directories as tar archives.
	 */
	void doTarBackup(String[] tarConfigs) {
		println "starting backup ..."
		stopRuntime()
		if (tarConfigs != null) {
			tarConfigs.each { doTarBackup( it ) }
		}
		startRuntime()
		println "... backup finished"
	}

	/**
	 * Specifically handles backing up /data (excluding media) or /data/media.
	 */
	void doTarBackup(String tarConfig) {
		FileReceiver frTar = new FileReceiver(localBackupDirectory + "${tarConfig}.tar.gz")
		if (tarConfig.equals("data")) {
			// Back up /data excluding media and mediadrm
			commander.execAsRootForResult("/dev/busybox stty raw; cd /data; /dev/busybox tar czf - ./ --exclude=media --exclude=mediadrm 2>/dev/null", frTar, 15, TimeUnit.MINUTES)
		} else if (tarConfig.equals("media")) {
			// Back up media directories only
			commander.execAsRootForResult("/dev/busybox stty raw; cd /data; /dev/busybox tar czf - ./media ./mediadrm 2>/dev/null", frTar, 15, TimeUnit.MINUTES)
	    }
		frTar.flush()
		if (frTar.isCancelled()) {
			println "error while transferring file ..."
		} else {
			println "transfer successful"
		}
	}

    /**
     * Writes backup metadata to a file.
     */
    void writeBackupMetadata() {
        File metaFile = new File(localBackupDirectory, "backup_info.txt")
        println "Creating metadata file: ${metaFile.absolutePath}"
        
        String hw = commander.execForResult("getprop ro.hardware").trim()
        String build = commander.execForResult("getprop ro.build.id").trim()
        String date = new SimpleDateFormat("yyyy-MM-dd").format(new Date())
        String userName = commander.resolveUserName(userId)

        metaFile.withWriter { writer ->
            writer.writeLine("HW=${hw}")
            writer.writeLine("BUILD=${build}")
            writer.writeLine("DATE=${date}")
            writer.writeLine("BACKUP_USER_ID=${userId}")
            writer.writeLine("USER_NAME=${userName}")
        }

        // Also write installers list if apps are being backed up
        File installersFile = new File(localBackupDirectory, "installers.txt")
        installersFile.withWriter { writer ->
            packages.each { p ->
                if (p.selected) {
                    writer.writeLine("package:${p.packageName}  installer=${p.installer ?: "null"}")
                }
            }
        }
    }

    /**
     * Generates a backup directory name based on device info.
     */
    String generateBackupDirName() {
        String hw = commander.execForResult("getprop ro.hardware").trim()
        String build = commander.execForResult("getprop ro.build.id").trim()
        String date = new SimpleDateFormat("yyyy-MM-dd").format(new Date())
        String userName = commander.resolveUserName(userId)

        String dirName = "${hw}_${date}_${build}"
        if (userId != 0) {
            dirName += "_${userName}"
        }
        return dirName
    }
}
