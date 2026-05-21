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
import de.anddisa.adb.util.BusyboxManager

/**
 * ABP (Android Backup Project) - Groovy Version
 * 
 * Main entry point for the remote backup and restore tool.
 * Handles command-line argument parsing, root initialization, busybox deployment,
 * and delegates operations to specific handlers (Backup, Restore, Info).
 * 
 * Support for multi-user/Work Profiles, partition images, and metadata generation.
 */
class ABP {

	static String baseDir = "./"
	static String tmpDir = "./"
	static String subDir = ""

	public static void main(String... args) {
		// Parse command line options defined in BackupRestoreHandler
		def CommandLineParser parser = new DefaultParser()
		Options options = BackupRestoreHandler.createCommandLineOptions()
		CommandLine line
        try {
            line = parser.parse(options, args)
        } catch (Exception e) {
            // Check if user just wanted help or device list
            if (args.contains("-h") || args.contains("--help")) {
                BackupRestoreHandler.outputCommandLineHelp(options)
                System.exit(0)
            }
            if (args.contains("-d") || args.contains("--devices")) {
                def adbc = new ADBCommander()
                List<IDevice> devices = adbc.getBridge().getDevices()
                devices.each { println it }
                System.exit(0)
            }
            println "Error: ${e.message}"
            BackupRestoreHandler.outputCommandLineHelp(options)
            System.exit(1)
        }

        if (line.hasOption("help")) {
            BackupRestoreHandler.outputCommandLineHelp(options)
            System.exit(0)
        }

		// Initialize ADB interaction layer
		def adbc = new ADBCommander()

        // Option to list all connected devices
		if (line.hasOption("devices")) {
        	List<IDevice> devices = adbc.getBridge().getDevices();
			devices.each { println it }
            System.exit(0)
        }

        if (adbc.device == null) {
            println "Error: No device connected. Please connect a device or specify serial with -s."
            System.exit(1)
        }
        
        if (!adbc.checkRootType()) {
            println "Warning: Root access not detected. Some operations may fail."
        }

        // Handle Busybox deployment
        String arch = adbc.getArchitecture()
        String busyboxDir = "./busybox-ndk" // Local cache directory
        try {
            BusyboxManager.ensureBusybox(arch, busyboxDir)
            adbc.pushBusybox(busyboxDir)
        } catch (Exception e) {
            println "Error: Could not prepare Busybox: ${e.message}"
            // Fallback to parent directory if available
            String fallbackDir = "../busybox-ndk"
            if (new File(fallbackDir).exists()) {
                println "Attempting fallback to ${fallbackDir}..."
                adbc.pushBusybox(fallbackDir)
            } else {
                System.exit(1)
            }
        }
		
        // Target a specific device by its serial number
		if (line.hasOption("serial")) {
			String selectedDevice = line.getOptionValue("serial")
        	List<IDevice> devices = adbc.getBridge().getDevices();
			devices.each { it -> if (it.serialNumber == selectedDevice) { adbc.setDevice(it) } }
        }

        if (adbc.device == null) {
            println "Error: No device connected. Please connect a device or specify serial with -s."
            System.exit(1)
        }

        int userId = 0
        if (line.hasOption("user")) {
            userId = adbc.resolveUserId(line.getOptionValue("user"))
        }
		
		// Configuration for base directory where backups are stored
		if (line.hasOption("baseDir")) {
			baseDir = line.getOptionValue("baseDir")
            if (!baseDir.endsWith("/")) baseDir += "/"
        }
		
		// Automatically create a subfolder named with the current date (YYYY-MM-DD)
		if (line.hasOption("createSubfolder")) {
            // We'll handle this more dynamically in the handlers if needed
		}
		
		// Configuration for temporary directory used during restore
		if (line.hasOption("tmpDir")) {
			tmpDir = line.getOptionValue("tmpDir")
            if (!tmpDir.endsWith("/")) tmpDir += "/"
        }
		
		// --- BACKUP FLOW ---
		if (line.hasOption("backup")) {
			String appLocationFilter = null
			BackupHandler bh = new BackupHandler(adbc)
            bh.userId = userId
			
            if (line.hasOption("createSubfolder")) {
                subDir = bh.generateBackupDirName() + "/"
            }
            bh.localBackupDirectory = baseDir + subDir
            // bh.writeBackupMetadata() // Moved to after package fetch

			if (line.hasOption("apks")) {
				// Backup individual APKs and their data
				if (line.hasOption("appLocationFilter")) {
					appLocationFilter = line.getOptionValue("appLocationFilter")
				}
				bh.getInstalledPackagesFromDevice(line.hasOption("system-apps"))
                
                // apply secondary filters if provided
				if (appLocationFilter) bh.filterByInstallLocation(appLocationFilter)

                bh.writeBackupMetadata() // Now it has the package list for installers.txt
				bh.doPackageBackup()
			} else if (line.hasOption("image")) {
				// Backup raw partition images (e.g. /dev/block/...)
                bh.writeBackupMetadata()
				String[] blockDevices = line.getOptionValues("image")
                if (blockDevices && blockDevices.length > 0) {
    				bh.doImageBackup(blockDevices)
                } else {
                    bh.doAllPartitionsBackup()
                }
			} else if (line.hasOption("tar")) {
				// Backup via tar (e.g. full /data or /data/media)
                bh.writeBackupMetadata()
				String[] tarConfigs = line.getOptionValues("tar")
				// data -> /data (excluding /data/media, /data/mediadrm)
				// media -> /data/media, /data/mediadrm
				bh.doTarBackup(tarConfigs)
			}
        // --- RESTORE FLOW ---
        } else if (line.hasOption("restore")) {
			String appPackageFilter = null
			RestoreHandler rh = new RestoreHandler(adbc)
            rh.userId = userId
			rh.localBackupDirectory = baseDir
			rh.tempDir = tmpDir
			
			if (line.hasOption("apks")) {
				// Restore APKs and data from local storage to device
				if (line.hasOption("appPackageFilter")) {
					appPackageFilter = line.getOptionValue("appPackageFilter")
				}
				rh.getLocalPackages()
				rh.filterByPackageName(appPackageFilter)
				rh.doPackageRestore()
			} else if (line.hasOption("image")) {
				// Restore raw partition images
				String[] blockDeviceConfigs = line.getOptionValues("image")
				rh.doImageRestore(blockDeviceConfigs)
			} else if (line.hasOption("tar")) {
				// Restore via tar archives
				String[] tarConfigs = line.getOptionValues("tar")
				rh.doTarRestore(tarConfigs)
			}
		// --- INFO FLOW ---
		} else if (line.hasOption("info")) {
			// Query device and local backup directory for package information
			String appLocationFilter = null
			String appPackageFilter = null
			if (line.hasOption("appLocationFilter")) {
				appLocationFilter = line.getOptionValue("appLocationFilter")
			}
			if (line.hasOption("appPackageFilter")) {
				appPackageFilter = line.getOptionValue("appPackageFilter")
			}
			DeviceInfoHandler dih = new DeviceInfoHandler(adbc)
            dih.userId = userId
			dih.doInfo()
			println ""
			println "packages possible to be backed up:"
			List<BackupPackage> packages = dih.getInstalledPackagesFromDevice(appLocationFilter, line.hasOption("system-apps"))
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
