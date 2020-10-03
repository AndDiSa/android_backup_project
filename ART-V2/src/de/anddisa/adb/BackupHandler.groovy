package de.anddisa.adb

import java.util.concurrent.TimeUnit

import de.anddisa.adb.entities.BackupPackage

class BackupHandler extends BackupRestoreHandler {

	public BackupHandler(ADBCommander commander) {
		super(commander)
	}

	void doImageBackup(String[] blockDevices) {
		if (blockDevices != null) {
			blockDevices.each { doImageBackup( it ) }
		}
	}

	void doImageBackup(String blockDevice) {
		String[] parts = blockDevice.split("/")
		FileReceiver frImg = new FileReceiver(localBackupDirectory + "${parts[parts.length - 1]}.img")
		commander.execForResult("su 0 -c '/data/adb/magisk/busybox stty raw; /data/adb/magisk/busybox dd if=${blockDevice} bs=4096 2>/dev/null'", frImg, 15, TimeUnit.MINUTES)
		frImg.flush()
		if (frImg.isCancelled()) {
			println "error while transferring file ..."
		} else {
			println "image transfer successful"
		}
	}

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
		stopRuntime()
		for (BackupPackage p : packages) {
			 if (p.selected) {
				 doPackageBackup(p)
			 }
	    }
		startRuntime()
		println "... backup finished"
	}

	void doPackageBackup(BackupPackage p) {
		FileReceiver frApp = new FileReceiver(localBackupDirectory + "app_${p.packageName}.tar.gz")
		commander.execForResult("su 0 -c '/data/adb/magisk/busybox stty raw; cd ${p.appDirectoryOnDevice} && /data/adb/magisk/busybox tar cfz - ./ 2>/dev/null'", frApp, 15, TimeUnit.MINUTES)
		frApp.flush()
		if (frApp.isCancelled()) {
			p.successful &= false
			println "error while transferring file"
		} else {
			p.successful &= true
			println "app package transfer successful"
		}
		FileReceiver frData = new FileReceiver(localBackupDirectory + "data_${p.packageName}.tar.gz")
		commander.execForResult("su 0 -c '/data/adb/magisk/busybox stty raw; cd ${p.dataDirectoryOnDevice} && /data/adb/magisk/busybox tar cfz - ./ 2>/dev/null'", frData, 15, TimeUnit.MINUTES)
		frData.flush()
		if (frData.isCancelled()) {
			p.successful &= false
			println "error while transferring file"
		} else {
			p.successful &= true
			println "data package transfer successful"
		}
	}
	
	void doTarBackup(String[] tarConfigs) {
		println "starting backup ..."
		stopRuntime()
		if (tarConfigs != null) {
			tarConfigs.each { doTarBackup( it ) }
		}
		startRuntime()
		println "... backup finished"
	}

	void doTarBackup(String tarConfig) {
		FileReceiver frTar = new FileReceiver(localBackupDirectory + "${tarConfig}.tar.gz")
		if (tarConfig.equals("data")) {
			commander.execForResult("su 0 -c '/data/adb/magisk/busybox stty raw; cd /data; /data/adb/magisk/busybox tar czf - ./ --exclude=media --exclude=mediadrm 2>/dev/null'", frTar, 15, TimeUnit.MINUTES)
		} else if (tarConfig.equals("media")) {
			commander.execForResult("su 0 -c '/data/adb/magisk/busybox stty raw; cd /data; /data/adb/magisk/busybox tar czf - ./media ./mediadrm 2>/dev/null'", frTar, 15, TimeUnit.MINUTES)
	    }
		frTar.flush()
		if (frTar.isCancelled()) {
			println "error while transferring file ..."
		} else {
			println "transfer successful"
		}
	}
}
