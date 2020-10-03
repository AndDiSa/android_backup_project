package de.anddisa.adb

import java.util.concurrent.TimeUnit

import javax.imageio.stream.FileImageInputStream

import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.utils.IOUtils

import com.android.ddmlib.AndroidDebugBridge
import com.android.ddmlib.IShellOutputReceiver
import com.android.tradefed.device.DeviceManager
import com.android.tradefed.device.DeviceMonitorMultiplexer
import com.android.tradefed.device.NativeDevice
import com.android.tradefed.device.NativeDeviceStateMonitor

import de.anddisa.adb.entities.BackupPackage

class RestoreHandler extends BackupRestoreHandler {

	String tempDir = "/tmp/"

	public RestoreHandler(ADBCommander commander) {
		super(commander)
	}

	void getLocalPackages() {
		packages = []
		def allPackages = []
		new File(localBackupDirectory).eachFileMatch(~/app_.*.tar.gz/) { file -> allPackages.add(file.getName()) }
		for (String p : allPackages) {
			BackupPackage bp = new BackupPackage()
			bp.packageName = p.replace("app_", "").replace(".tar.gz","")
			bp.localAppPath = localBackupDirectory + p
			bp.localDataPath = bp.localAppPath.replace("app_","data_")
			bp.selected = false
			bp.successful = false
			packages.add(bp)
		}
	}
	void doImageRestore(String[] blockDeviceConfigs) {
		if (blockDeviceConfigs != null) {
			blockDeviceConfigs.each { doImageRestore( it ) }
		}
	}

	void doImageRestore(String blockDevice) {
		String[] parts = blockDevice.split("=")
		if (parts.length == 2 && parts[0].startsWith("/dev/block") && parts[1].endsWith(".img")) {
			File f = new File(parts[1])
			if (!f.exists()) {
				f = new File(localBackupDirectory + parts[1])
			}
			if (f.exists()) {
				println "caution: this may fail and leave your device unbootable and may even brick your device ... continue on your own risk"
				Thread.sleep(10000)
				println "flashing ${f.getAbsolutePath()} to ${parts[1]}"
				stopRuntime()
				ByteArrayOutputStream baos = new ByteArrayOutputStream()
				DeviceManager mgr =  new DeviceManager()
				DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
				NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
				NativeDevice nd = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
				nd.executeShellV2Command("su 0 -c '/data/adb/magisk/busybox dd of=${parts[0]} 2>/dev/null'".toString(), f, baos, 5, TimeUnit.MINUTES, 1)
				baos.flush()
				startRuntime()
				println "... finished"
				baos.close()
			}
		}
	}	
	
	void doPackageRestore() {
		for (BackupPackage bp : packages) {
			if (bp.selected) {
				println "restoring ${bp.packageName} ..."
				doPackageRestore(bp)
			}
		}
		commander.exec("su 0 -c 'restorecon -FRDv /data/data'")
	}

	void updatePackageWithDataFromDevice(BackupPackage bp) {
		String[] allPackages = commander.execForResult("cmd package list packages -f").split(System.lineSeparator())
		for (String p : allPackages) {
			def pathConfig = p.replace("package:", "")
			def index = pathConfig.lastIndexOf("=")
			def appPath = pathConfig.substring(0, index)
			if (bp.packageName.equals(pathConfig.substring(index + 1))) {
				bp.appDirectoryOnDevice = appPath.substring(0, appPath.lastIndexOf("/"))
				bp.dataDirectoryOnDevice = "/data/data/" + pathConfig.substring(index + 1)
				break;
			}
		}
	}

	void doPackageRestore(BackupPackage p) {
		println  "restoring apk ${p.packageName} ..."
		File tmp = new File(tempDir)
		List<String> extractedApks = decompress(p.localAppPath, tmp, ".*.apk")
		List<File> apks = new ArrayList<File>()
		for (String apk : extractedApks) {
			apks.add(new File(tempDir + apk))
		}
		commander.installApks((List<File>) apks, true, (List<String>)["-t"])
		for (String apk : apks) {
			File f = new File(apk)
			f.delete()
		}

		updatePackageWithDataFromDevice(p)

		commander.exec("su 0 -c 'pm clear ${p.packageName}'")
		Thread.sleep(1000)
		String id = null;
		try {
			String result = commander.execForResult("su 0 -c 'ls -d -l ${p.dataDirectoryOnDevice} 2>/dev/null'")
			id = result.split(" ")[2]
		} catch (Exception e) {
		}
		if (id == null) {
			println "${p.packageName} is still not installed"
		} else {
			println "restoring data to ${p.dataDirectoryOnDevice} ..."
			File f = new File (p.localDataPath)
			ByteArrayOutputStream baos = new ByteArrayOutputStream()
			DeviceManager mgr =  new DeviceManager()
			DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
			NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
			NativeDevice nd = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
			nd.executeShellV2Command("su 0 -c '/data/adb/magisk/busybox tar xpzf - -C ${p.dataDirectoryOnDevice} 2>/dev/null'".toString(), f, baos, 5, TimeUnit.MINUTES, 1)
			baos.flush()
			println "... finished"
			baos.close()
			commander.exec("su 0 -c 'chown -R ${id}.${id} ${p.dataDirectoryOnDevice}'")
		}
	}

	void doTarRestore(String[] tarConfigs) {
		println "starting restore ..."
		stopRuntime()
		for (String config : tarConfigs) {
			doTarRestore(config)
		}
		commander.exec("su 0 -c 'restorecon -FRDv /data'")
		startRuntime()
		println "... restore finished"
	}

	void doTarRestore(String tarConfig) {
		println "restoring ${tarConfig} to /data ..."
		File f = new File (localBackupDirectory + tarConfig + ".tar.gz")
		ByteArrayOutputStream baos = new ByteArrayOutputStream()
		DeviceManager mgr =  new DeviceManager()
		DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
		NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
		NativeDevice nd = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
		println nd.executeShellV2Command("su 0 -c '/data/adb/magisk/busybox tar xvzf - -C /data --exclude=./**/var/* --exclude=./**/run/* 2>&1'".toString(), f)
		baos.flush()
		println baos.toString()
		println "... finished"
		baos.close()
	}
}
