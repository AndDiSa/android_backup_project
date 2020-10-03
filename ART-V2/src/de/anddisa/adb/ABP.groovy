package de.anddisa.adb

import java.nio.ByteBuffer
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.concurrent.TimeUnit

import org.apache.commons.cli.CommandLine
import org.apache.commons.cli.CommandLineParser
import org.apache.commons.cli.DefaultParser
import org.apache.commons.cli.Options

import com.android.ddmlib.AndroidDebugBridge
import com.android.ddmlib.IDevice
import com.android.ddmlib.IShellOutputReceiver

import de.anddisa.adb.ADBCommander
import de.anddisa.adb.entities.BackupPackage

class ABP {

	static String baseDir = "./"
	static String tmpDir = "./"
	static String subDir = ""

	public static void main(String... args) {
		def CommandLineParser parser = new DefaultParser()
		Options options = BackupRestoreHandler.createCommandLineOptions()
		CommandLine line = parser.parse(options, args)

		def adbc = new ADBCommander()
		if (line.hasOption("devices")) {
        	List<IDevice> devices = adbc.getBridge().getDevices();
			devices.each { println it }
        }
		if (line.hasOption("serial")) {
			String selectedDevice = line.getOptionValue("serial")
        	List<IDevice> devices = adbc.getBridge().getDevices();
			devices.each { it -> if (it.serialNumber == selectedDevice) { adbc.setDevice(it) } }
        }
		if (line.hasOption("baseDir")) {
			baseDir = line.getOptionValue("baseDir")
        }
		if (line.hasOption("createSubfolder")) {
			DateFormat df = new SimpleDateFormat("yyyy-MM-dd");
			subDir = df.format(new Date()) + "/";
		}
		if (line.hasOption("baseDir")) {
			tmpDir = line.getOptionValue("tmpDir")
        }
		if (line.hasOption("backup")) {
			String appLocationFilter = null
			BackupHandler bh = new BackupHandler(adbc)
			bh.localBackupDirectory = baseDir + subDir

			if (line.hasOption("apks")) {
				if (line.hasOption("appLocationFilter")) {
					appLocationFilter = line.getOptionValue("appLocationFilter")
				}
				bh.getInstalledPackagesFromDevice()
				bh.filterByInstallLocation(appLocationFilter)
				bh.doPackageBackup()
			} else if (line.hasOption("image")) {
				String[] blockDevices = line.getOptionValues("image")
				bh.doImageBackup(blockDevices)
			} else if (line.hasOption("tar")) {
				String[] tarConfigs = line.getOptionValues("tar")
				// data -> /data (ohne /data/media, /data/mediadrm)
				// media -> /data/media, /data/mediadrm
				bh.doTarBackup(tarConfigs)
			}
        } else if (line.hasOption("restore")) {
			String appPackageFilter = null
			RestoreHandler rh = new RestoreHandler(adbc)
			rh.localBackupDirectory = baseDir
			rh.tempDir = tmpDir
			
			if (line.hasOption("apks")) {
				if (line.hasOption("appPackageFilter")) {
					appPackageFilter = line.getOptionValue("appPackageFilter")
				}
				rh.getLocalPackages()
				rh.filterByPackageName(appPackageFilter)
				rh.doPackageRestore()
			} else if (line.hasOption("image")) {
				String[] blockDeviceConfigs = line.getOptionValues("image")
				rh.doImageRestore(blockDeviceConfigs)
			} else if (line.hasOption("tar")) {
				String[] tarConfigs = line.getOptionValues("tar")
				rh.doTarRestore(tarConfigs)
			}
		} else if (line.hasOption("info")) {
			String appLocationFilter = null
			String appPackageFilter = null
			if (line.hasOption("appLocationFilter")) {
				appLocationFilter = line.getOptionValue("appLocationFilter")
			}
			if (line.hasOption("appPackageFilter")) {
				appPackageFilter = line.getOptionValue("appPackageFilter")
			}
			DeviceInfoHandler dih = new DeviceInfoHandler(adbc)
			dih.doInfo()
			println ""
			println "packages possible to be backed up:"
			List<BackupPackage> packages = dih.getInstalledPackagesFromDevice(appLocationFilter)
			packages.each { println it}
			println ""
			println "packages possible to be restored: ${baseDir + subDir}"
			packages = dih.getLocalPackagesFromDirectory(baseDir + subDir, appPackageFilter)
			packages.each { println it}
        } else if(line.hasOption("help")) {
	        BackupRestoreHandler.outputCommandLineHelp(options);			
	    } else {
	        BackupRestoreHandler.outputCommandLineHelp(options);			
		}
		System.exit(0)
	}
}