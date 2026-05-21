package de.anddisa.adb

import java.util.concurrent.TimeUnit

import org.apache.commons.cli.HelpFormatter
import org.apache.commons.cli.Option
import org.apache.commons.cli.OptionGroup
import org.apache.commons.cli.Options
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.gzip.GzipCompressorInputStream
import org.apache.commons.compress.utils.IOUtils

import de.anddisa.adb.entities.BackupPackage

class BackupRestoreHandler {
	ADBCommander commander
	String localBackupDirectory = "/tmp/1/"
	List<BackupPackage> packages = []
    int userId = 0

	static Options createCommandLineOptions() {
		
		final Options options = new Options()
		options.addOption(Option.builder("s")
			.longOpt("serial")
			.desc("connect to device with serial number")
			.required(false)
			.hasArg()
			.build())

		options.addOption(Option.builder("alf")
				.longOpt("appLocationFilter")
				.desc("filter apks to backup (regex, e.g. '/data/app.*|/data/priv-app.*') (default: all apks and data on the device)")
				.required(false)
				.hasArg()
				.build())
	
		options.addOption(Option.builder("apf")
				.longOpt("appPackageFilter")
				.desc("filter apks to restore (regex, e.g. '.*google.*') (default: all packages found the the selected directory)")
				.required(false)
				.hasArg()
				.build())

        options.addOption(Option.builder("u")
                .longOpt("user")
                .desc("User ID or Name (e.g. 0, Island, Work Profile)")
                .required(false)
                .hasArg()
                .build())

        options.addOption(Option.builder("sa")
                .longOpt("system-apps")
                .desc("Include system apps in backup/list")
                .required(false)
                .build())

		OptionGroup location = new OptionGroup()
		location.addOption(Option.builder("bd")
				.longOpt("baseDir")
				.desc("base directory to backup to / restore from (default: current directory)")
				.hasArg()
				.build())
		location.addOption(Option.builder("cs")
				.longOpt("createSubfolder")
				.desc("create subfolder 'yyyy-MM-dd' in <baseDir> for storing the backup data")
				.build())
		location.addOption(Option.builder("td")
				.longOpt("tmpDir")
				.desc("directory for temporary files (default: current directory)")
				.hasArg()
				.build())
		options.addOptionGroup(location)

		OptionGroup commands = new OptionGroup()
		commands.addOption(Option.builder("b")
				.longOpt("backup")
				.desc("create a backup")
				.build())
		commands.addOption(Option.builder("r")
				.longOpt("restore")
				.desc("restore a backup")
				.build())
		commands.addOption(Option.builder("d")
				.longOpt("devices")
				.desc("list available devices through adb")
				.build())
		commands.addOption(Option.builder("i")
				.longOpt("info")
				.desc("dump device info of selected device")
				.build())
		commands.addOption(Option.builder("h")
				.longOpt("help")
				.desc("print help")
				.build())
		commands.setRequired(true)

		options.addOptionGroup(commands)

		OptionGroup mode = new OptionGroup()
		mode.addOption(Option.builder("a")
				.longOpt("apks")
				.desc("backup / restore apks (and data)")
				.build())
		mode.addOption(Option.builder("i")
				.longOpt("image")
				.desc("backup / restore partition images (optional: list specific partitions)")
				.hasArgs()
				.build())
		mode.addOption(Option.builder("t")
				.longOpt("tar")
				.desc("backup / restore tar files")
				.hasArgs()
				.build())
		mode.setRequired(true)
		options.addOptionGroup(mode)

		return options
	}

	public static void outputCommandLineHelp(final Options options) {
		final HelpFormatter formater = new HelpFormatter();
		formater.printHelp("abp [OPTIONS] ... (-backup | -devices | -restore | -info)", options)
	}

	public BackupRestoreHandler(ADBCommander commander) {
		this.commander = commander
	}
	
	void stopRuntime() {
		println "stopping runtime (to prevent parallel modification)..."
		println commander.execAsRootForResult("stop")
		Thread.sleep(10000)
	}

	void startRuntime() {
		println "starting runtime ..."
		println commander.execAsRootForResult("start")
	}

	List<String> decompress(String tarFileName, File out, String filter) throws IOException {
		List<String> extractedFiles = []
		TarArchiveInputStream fin
		try {
			fin = new TarArchiveInputStream(new GzipCompressorInputStream(new FileInputStream(tarFileName)))
			TarArchiveEntry entry;
			while ((entry = fin.getNextTarEntry()) != null) {
				if (entry.isDirectory()) {
					continue;
				}
				if (entry.getName().matches(filter)) {
					File curfile = new File(out, entry.getName());
					File parent = curfile.getParentFile();
					if (!parent.exists()) {
						parent.mkdirs();
					}
					IOUtils.copy(fin, new FileOutputStream(curfile));
					extractedFiles.add(entry.getName())
				}
			}
		} catch (Exception e) {
			
		} finally {
			if (fin != null)
				try {
					fin.close()
				} catch (Exception e) {
				}
		}
		return extractedFiles
	}

	void getInstalledPackagesFromDevice(boolean includeSystem = false) {
		packages = []
        String pmFlags = "-f"
        if (!includeSystem) {
            pmFlags += " -3"
        }
		String[] allPackages = commander.execForResult("pm list packages --user ${userId} ${pmFlags}").split(System.lineSeparator())
        
        // Fetch installer info: pm list packages -i
        Map<String, String> installers = [:]
        String installerOutput = commander.execForResult("pm list packages --user ${userId} -i ${pmFlags.replace('-f', '')}")
        installerOutput.split(System.lineSeparator()).each { line ->
            if (line.startsWith("package:")) {
                // Format: package:com.example.app  installer=com.android.vending
                def parts = line.replace("package:", "").split("\\s+installer=")
                if (parts.length == 2) {
                    installers[parts[0]] = parts[1]
                } else if (parts.length == 1) {
                    installers[parts[0]] = "null"
                }
            }
        }

		for (String p : allPackages) {
            if (!p.startsWith("package:")) continue
			def pathConfig = p.replace("package:", "")
			def index = pathConfig.lastIndexOf("=")
			def appPath = pathConfig.substring(0, index)
			BackupPackage bp = new BackupPackage()
			bp.packageName = pathConfig.substring(index + 1)
			bp.appDirectoryOnDevice = appPath.substring(0, appPath.lastIndexOf("/"))
            if (userId == 0) {
    			bp.dataDirectoryOnDevice = "/data/data/" + bp.packageName
            } else {
                bp.dataDirectoryOnDevice = "/data/user/${userId}/" + bp.packageName
            }
			bp.selected = true // Default to true if they came back from pm list packages
			bp.successful = false
            bp.installer = installers[bp.packageName]
			packages.add(bp)
		}
	}

	void listSelectedPackages() {
		for (BackupPackage p : packages) {
			if (p.selected) {
				println p.packageName + " : " + p.appDirectoryOnDevice + " : " + p.dataDirectoryOnDevice + " : " + p.localAppPath + " : " + p.localDataPath
			}
		}
	}

	void filterByPackageName(String filter) {
		for (BackupPackage p : packages) {
			p.selected = (filter == null || filter.trim().isEmpty() || p.packageName.matches(filter)) ? true : false
		}
	}

	void filterByInstallLocation(String filter) {
		for (BackupPackage p : packages) {
			p.selected = (filter == null || filter.trim().isEmpty() || p.appDirectoryOnDevice.matches(filter)) ? true : false
		}
	}

	void selectUserPackages() {
		for (BackupPackage p : packages) {
			p.selected = p.appDirectoryOnDevice.startsWith("/data/app") ? true : p.selected
		}
	}

	void selectSystemPackages() {
		for (BackupPackage p : packages) {
			p.selected = p.appDirectoryOnDevice.startsWith("/system/") ? true : p.selected
		}
	}

	void selectProductPackages() {
		for (BackupPackage p : packages) {
			p.selected = p.appDirectoryOnDevice.startsWith("/product/") ? true : p.selected
		}
	}

	void selectAllPackages() {
		for (BackupPackage p : packages) {
			p.selected = true
		}
	}
}
