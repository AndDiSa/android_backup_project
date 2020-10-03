package de.anddisa.adb

import java.util.concurrent.TimeUnit

import org.apache.commons.cli.HelpFormatter
import org.apache.commons.cli.OptionBuilder
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

	private static Options createCommandLineOptions() {
		
		final Options options = new Options();
		options.addOption(OptionBuilder
			.withLongOpt("serial")
			.withDescription("connect to device with serial number")
			.isRequired(false)
			.hasArg()
			.create("s"));

		options.addOption(OptionBuilder
				.withLongOpt("appLocationFilter")
				.withDescription("filter apks to backup (regex, e.g. '/data/app.*|/data/priv-app.*') (default: all apks and data on the device)")
				.isRequired(false)
				.hasArg()
				.create("alf"));
	
		options.addOption(OptionBuilder
				.withLongOpt("appPackageFilter")
				.withDescription("filter apks to restore (regex, e.g. '.*google.*') (default: all packages found the the selected directory)")
				.isRequired(false)
				.hasArg()
				.create("apf"));

		OptionGroup location = new OptionGroup();
		location.addOption(OptionBuilder
				.withLongOpt("baseDir")
				.withDescription("base directory to backup to / restore from (default: current directory)")
				.hasArg()
				.create("bd"));
		location.addOption(OptionBuilder
				.withLongOpt("createSubfolder")
				.withDescription("create subfolder 'yyyy-MM-dd' in <baseDir> for storing the backup data")
				.create("cs"));
		location.addOption(OptionBuilder
				.withLongOpt("tmpDir")
				.withDescription("directory for temporary files (default: current directory)")
				.hasArg()
				.create("td"));
		options.addOptionGroup(location);

		OptionGroup commands = new OptionGroup();
		commands.addOption(OptionBuilder
				.withLongOpt("backup")
				.withDescription("create a backup")
				.create("b"));
		commands.addOption(OptionBuilder
				.withLongOpt("restore")
				.withDescription("restore a backup")
				.create("r"));
		commands.addOption(OptionBuilder
				.withLongOpt("devices")
				.withDescription("list available devices through adb")
				.create("d"));
		commands.addOption(OptionBuilder
				.withLongOpt("info")
				.withDescription("dump device info of selected device")
				.create("i"));
		commands.addOption(OptionBuilder
				.withLongOpt("help")
				.withDescription("print help")
				.create("h"));
		commands.isRequired();

		options.addOptionGroup(commands);

		OptionGroup mode = new OptionGroup();
		mode.addOption(OptionBuilder
				.withLongOpt("apks")
				.withDescription("backup / restore apks (and data)")
				.create("a"));
		mode.addOption(OptionBuilder
				.withLongOpt("image")
				.withDescription("backup / restore partition images")
				.hasArgs()
				.create("i"));
		mode.addOption(OptionBuilder
				.withLongOpt("tar")
				.withDescription("backup / restore tar files")
				.hasArgs()
				.create("t"));
		mode.isRequired()
		options.addOptionGroup(mode);

		return options;
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
		println commander.execForResult("su 0 -c 'stop'")
		Thread.sleep(10000)
	}

	void startRuntime() {
		println "starting runtime ..."
		println commander.execForResult("su 0 -c 'start'")
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

	void getInstalledPackagesFromDevice() {
		packages = []
		String[] allPackages = commander.execForResult("cmd package list packages -f").split(System.lineSeparator())
		for (String p : allPackages) {
			def pathConfig = p.replace("package:", "")
			def index = pathConfig.lastIndexOf("=")
			def appPath = pathConfig.substring(0, index)
			BackupPackage bp = new BackupPackage()
			bp.packageName = pathConfig.substring(index + 1)
			bp.appDirectoryOnDevice = appPath.substring(0, appPath.lastIndexOf("/"))
			bp.dataDirectoryOnDevice = "/data/data/" + pathConfig.substring(index + 1)
			bp.selected = false
			bp.successful = false
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
