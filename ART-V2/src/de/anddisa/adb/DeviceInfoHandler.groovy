package de.anddisa.adb

import com.android.ddmlib.IDevice
import com.android.tradefed.device.DeviceManager
import com.android.tradefed.device.DeviceMonitorMultiplexer
import com.android.tradefed.device.ITestDevice.MountPointInfo
import com.android.tradefed.device.NativeDevice
import com.android.tradefed.device.NativeDeviceStateMonitor

import de.anddisa.adb.entities.BackupPackage
import de.anddisa.adb.entities.BlockInfo


class DeviceInfoHandler {
	ADBCommander commander
	NativeDevice currentDevice

	public DeviceInfoHandler(ADBCommander commander) {
		this.commander = commander
		DeviceManager mgr =  new DeviceManager()
		DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
		NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
		currentDevice = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
	}

	public List<BackupPackage> getInstalledPackagesFromDevice(String filter) {
		List<BackupPackage> packages = []

		String[] allPackages = commander.execForResult("cmd package list packages -f").split(System.lineSeparator())
		for (String p : allPackages) {
			def pathConfig = p.replace("package:", "")
			def index = pathConfig.lastIndexOf("=")
			def appPath = pathConfig.substring(0, index)
			if (filter == null || filter.trim().isEmpty() || appPath.matches(filter)) {				
				BackupPackage bp = new BackupPackage()
				bp.packageName = pathConfig.substring(index + 1)
				bp.appDirectoryOnDevice = appPath.substring(0, appPath.lastIndexOf("/"))
				bp.dataDirectoryOnDevice = "/data/data/" + pathConfig.substring(index + 1)
				bp.selected = false
				bp.successful = false
				packages.add(bp)
			}
		}
		return packages
	}

	public List<BackupPackage> getLocalPackagesFromDirectory(String directory, String filter) {
		List<BackupPackage> packages = []

		def allPackages = []
		new File(directory).eachFileMatch(~/app_.*.tar.gz/) { file -> allPackages.add(file.getName()) }
		for (String p : allPackages) {
			String packageName = p.replace("app_", "").replace(".tar.gz","")
			if (filter == null || filter.trim().isEmpty() || packageName.matches(filter)) {
				BackupPackage bp = new BackupPackage()
				bp.packageName = packageName
				bp.localAppPath = directory + p
				bp.localDataPath = bp.localAppPath.replace("app_","data_")
				bp.selected = false
				bp.successful = false
				packages.add(bp)
			}
		}
		
		return packages
	}

	List<BlockInfo> listBlockDeviceMapping() {
		List<BlockInfo> result = []
		String[] allBlockDevices = commander.execForResult("su 0 -c 'ls -l /dev/block/mapper/'").split(System.lineSeparator())
		for (String block : allBlockDevices) {
			String[] parts = block.split(" ")
			if (parts[0].startsWith("l")) {
				BlockInfo bi = new BlockInfo()
				bi.name = parts[8]
				bi.blockDevice = parts[10]
				result.add(bi)
			}
		}
		return result
	}

	List<BlockInfo> listBlockDeviceByName() {
		List<BlockInfo> result = []
		String[] allBlockDevices = commander.execForResult("su 0 -c 'ls -l /dev/block/by-name/'").split(System.lineSeparator())
		for (String block : allBlockDevices) {
			String[] parts = block.split(" ")
			if (parts[0].startsWith("l")) {
				BlockInfo bi = new BlockInfo()
				bi.name = parts[7]
				bi.blockDevice = parts[9]
				result.add(bi)
			}
		}
		return result
	}


	public void doInfo() {
		if (currentDevice != null) {
			try {
				println "apexes: " + currentDevice.getActiveApexes()
			} catch (Exception e) {}
			try {
				println "device allocation state: " + currentDevice.getAllocationState()
			} catch (Exception e) {}
			try {
				println "api level: " + currentDevice.getApiLevel()
			} catch (Exception e) {}
			try {
				println "package infos: " + currentDevice.getAppPackageInfos()
			} catch (Exception e) {}
			try {
				println "build alias: " + currentDevice.getBuildAlias()
			} catch (Exception e) {}
			try {
				println "build flavor: " + currentDevice.getBuildFlavor()
			} catch (Exception e) {}
			try {
				println "build id: " + currentDevice.getBuildId()
			} catch (Exception e) {}
			try {
				println "build signing keys: " + currentDevice.getBuildSigningKeys()
			} catch (Exception e) {}
			try {
				println currentDevice.getInstalledPackageNames()
			} catch (Exception e) {}
			try {
				println ""
				println "mount points:"
				List<MountPointInfo> mountPoints = currentDevice.getMountPointInfo()
				mountPoints.each { println it }
			} catch (Exception e) {}
			try {
				println "product type: " + currentDevice.getProductType()
			} catch (Exception e) {}
			try {
				println "product variant: " + currentDevice.getProductVariant()
			} catch (Exception e) {}
			try {
				println currentDevice.getUninstallablePackageNames()		
			} catch (Exception e) {}
			println ""
			println "device block information:"
			println "device blocks by name:"
			List<BlockInfo> blockInfo = listBlockDeviceByName()
			blockInfo.each { println it }
			println ""
			println "device block mapping:"
			blockInfo = listBlockDeviceMapping()
			blockInfo.each { println it }
		} else {
			println "error: device not available ..."
		}
	}
}
