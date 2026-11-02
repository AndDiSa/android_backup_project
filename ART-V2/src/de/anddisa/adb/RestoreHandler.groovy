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

/**
 * RestoreHandler implements the restoration logic for APKs, images, and tar archives.
 * It matches local backup files to the device state, handles APK installation,
 * and restores data directories with proper ownership and SELinux contexts.
 */
class RestoreHandler extends BackupRestoreHandler {

    /** Local temporary directory for extracting APKs before installation */
    String tempDir = "/tmp/"

    public RestoreHandler(ADBCommander commander) {
        super(commander)
    }

    String getRootWrappedCommand(String cmd) {
        if (commander.rootCommand) {
            return "${commander.rootCommand} \"${cmd}\""
        } else {
            return cmd
        }
    }

    /**
     * Reads backup_info.txt metadata from localBackupDirectory to determine target userId
     * if --user was not explicitly specified on the command line.
     */
    void readBackupMetadata() {
        File metaFile = new File(localBackupDirectory, "backup_info.txt")
        if (metaFile.exists()) {
            println "Reading metadata from ${metaFile.absolutePath}"
            String savedName = null
            String savedId = null
            metaFile.eachLine { line ->
                line = line.trim()
                if (line.startsWith("USER_NAME=")) {
                    savedName = line.substring("USER_NAME=".length()).trim()
                } else if (line.startsWith("BACKUP_USER_ID=")) {
                    savedId = line.substring("BACKUP_USER_ID=".length()).trim()
                }
            }
            if (savedName && savedName != "Owner") {
                println "Backup was for user name: ${savedName}"
                int resolved = commander.resolveUserId(savedName)
                if (resolved >= 0) {
                    userId = resolved
                }
            } else if (savedId && savedId.isInteger()) {
                println "Backup was for user ID: ${savedId}"
                userId = savedId.toInteger()
            }
        } else {
            println "No metadata file found, defaulting to User ID ${userId}"
        }
    }

    /**
     * Scans the local backup directory for files matching 'app_*.tar.gz'
     * and populates the internal 'packages' list.
     */
    void getLocalPackages() {
        packages = []
        def allPackages = []
        new File(localBackupDirectory).eachFileMatch(~/app_.*.tar.gz/) { file -> allPackages.add(file.getName()) }

        // Read installers.txt if available
        Map<String, String> installers = [:]
        File installersFile = new File(localBackupDirectory, "installers.txt")
        if (installersFile.exists()) {
            installersFile.eachLine { line ->
                line = line.trim()
                if (line.startsWith("package:")) {
                    def parts = line.replace("package:", "").split("\\s+installer=")
                    if (parts.length == 2) {
                        installers[parts[0].trim()] = parts[1].trim()
                    }
                }
            }
        }

        for (String p : allPackages) {
            BackupPackage bp = new BackupPackage()
            bp.packageName = p.replace("app_", "").replace(".tar.gz", "")
            bp.localAppPath = localBackupDirectory + p
            bp.localDataPath = bp.localAppPath.replace("app_", "data_")
            bp.selected = false
            bp.successful = false
            bp.installer = installers[bp.packageName]
            packages.add(bp)
        }
    }

    /**
     * Orchestrates restoration of multiple partition images.
     */
    void doImageRestore(String[] blockDeviceConfigs) {
        if (blockDeviceConfigs != null) {
            blockDeviceConfigs.each { doImageRestore( it ) }
        }
    }

    /**
     * Restores a single partition image from a file to a block device using 'dd'.
     * @param blockDevice Format: "/dev/block/partition=filename.img"
     */
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
                println "flashing ${f.getAbsolutePath()} to ${parts[0]}"
                stopRuntime()
                ByteArrayOutputStream baos = new ByteArrayOutputStream()
                // Use Tradefed's DeviceManager and NativeDevice for robust file streaming to shell
                DeviceManager mgr = new DeviceManager()
                DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
                NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
                NativeDevice nd = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
                // Stream local file contents into 'dd' on the device
                nd.executeShellV2Command(getRootWrappedCommand("${ADBCommander.BB} dd of=${parts[0]} 2>/dev/null").toString(), f, baos, 5, TimeUnit.MINUTES, 1)
                baos.flush()
                startRuntime()
                println "... finished"
                baos.close()
            }
        }
    }

    /**
     * Restores all selected application packages.
     * Runs 'restorecon' globally after processing all apps to fix SELinux contexts.
     */
    void doPackageRestore() {
        for (BackupPackage bp : packages) {
            if (bp.selected) {
                println "restoring ${bp.packageName} ..."
                doPackageRestore(bp)
            }
        }
        // Fix SELinux labels for all restored app data
        String dataDir = (userId == 0) ? "/data/data" : "/data/user/${userId}"
        commander.execAsRoot("restorecon -FRDv ${dataDir}")
    }

    /**
     * Queries the device to find the current APK path and data directory for a package.
     * This is necessary after installation as paths may change.
     */
    void updatePackageWithDataFromDevice(BackupPackage bp) {
        String[] allPackages = commander.execForResult("pm list packages --user ${userId} -f").split("\\r?\\n")
        for (String p : allPackages) {
            p = p.trim()
            if (!p.startsWith("package:")) continue
            def pathConfig = p.replace("package:", "")
            def index = pathConfig.lastIndexOf("=")
            def appPath = pathConfig.substring(0, index)
            if (bp.packageName.equals(pathConfig.substring(index + 1))) {
                bp.appDirectoryOnDevice = appPath.substring(0, appPath.lastIndexOf("/"))
                if (userId == 0) {
                    bp.dataDirectoryOnDevice = "/data/data/" + bp.packageName
                } else {
                    bp.dataDirectoryOnDevice = "/data/user/${userId}/" + bp.packageName
                }
                break
            }
        }
    }

    /**
     * Restores a single package: installs APK, clears data, and streams data archive back.
     */
    void doPackageRestore(BackupPackage p) {
        println "restoring apk ${p.packageName} ..."
        File tmp = new File(tempDir)
        // Extract APKs from the backup tarball to a temporary directory
        List<String> extractedApks = decompress(p.localAppPath, tmp, ".*.apk")
        List<File> apks = new ArrayList<File>()
        for (String apk : extractedApks) {
            apks.add(new File(tmp, apk))
        }
        if (apks.isEmpty()) {
            println "No APK found in ${p.localAppPath}"
            return
        }
        // Install the extracted APKs
        List<String> installOptions = ["-t", "--user", "${userId}"]
        if (p.installer && p.installer != "null") {
            installOptions.add("-i")
            installOptions.add(p.installer)
        }
        commander.installApks(apks, true, installOptions)
        // Cleanup temporary APK files
        for (File apk : apks) {
            apk.delete()
        }

        updatePackageWithDataFromDevice(p)
        if (!p.dataDirectoryOnDevice) {
            p.dataDirectoryOnDevice = (userId == 0) ? "/data/data/${p.packageName}" : "/data/user/${userId}/${p.packageName}"
        }

        // Explicitly set installer package if provided (sometimes -i flag during install is ignored)
        if (p.installer && p.installer != "null") {
            println "Setting installer attribution to ${p.installer} ..."
            commander.execAsRoot("pm set-installer-package ${p.packageName} ${p.installer} 2>/dev/null || true")
        }

        // Clear initial data created during installation (with fallback for Managed/Work Profiles)
        String clearOut = commander.execAsRootForResult("pm clear --user ${userId} ${p.packageName}")
        if (!clearOut || !clearOut.contains("Success")) {
            println "WARNING: pm clear failed for ${p.packageName} (likely Profile Owner protection). Attempting manual purge..."
            commander.execAsRoot("am force-stop --user ${userId} ${p.packageName}")
            commander.execAsRoot("find ${p.dataDirectoryOnDevice} -mindepth 1 -maxdepth 1 -exec rm -rf {} +")
        }
        Thread.sleep(1000)

        // Find the UID/username of the newly installed app
        String id = null
        try {
            String result = commander.execAsRootForResult("ls -d -l ${p.dataDirectoryOnDevice} 2>/dev/null").trim()
            if (result) {
                id = result.split("\\s+")[2]
            }
        } catch (Exception e) {
        }

        if (!id) {
            println "${p.packageName} is still not installed or data dir ${p.dataDirectoryOnDevice} not created"
        } else {
            File f = new File(p.localDataPath)
            if (f.exists()) {
                println "restoring data to ${p.dataDirectoryOnDevice} (APP User id is ${id}) ..."
                ByteArrayOutputStream baos = new ByteArrayOutputStream()
                DeviceManager mgr = new DeviceManager()
                DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
                NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
                NativeDevice nd = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
                // Stream local data archive into 'tar' on the device
                nd.executeShellV2Command(getRootWrappedCommand("${ADBCommander.BB} tar -xzpf - -C ${p.dataDirectoryOnDevice} . 2>/dev/null").toString(), f, baos, 5, TimeUnit.MINUTES, 1)
                baos.flush()
                println "... finished"
                baos.close()

                // Surgical chown: Main User/Group
                commander.execAsRoot("chown -R ${id}:${id} ${p.dataDirectoryOnDevice}")

                // Surgical chown: Cache Group (if exists)
                String cacheId = "${id}_cache"
                String cacheIdCheck = commander.execAsRootForResult("id ${cacheId} >/dev/null 2>&1 && echo exists || true").trim()
                if (cacheIdCheck == "exists") {
                    println "Applying cache group ${cacheId} to cache directories"
                    commander.execAsRoot("chown -R ${id}:${cacheId} ${p.dataDirectoryOnDevice}/cache 2>/dev/null || true")
                    commander.execAsRoot("chown -R ${id}:${cacheId} ${p.dataDirectoryOnDevice}/code_cache 2>/dev/null || true")
                }

                // Force restorecon to update SELinux labels (including MCS categories for Work Profiles)
                commander.execAsRoot("restorecon -FRv ${p.dataDirectoryOnDevice}")
            } else {
                println "No data package found for ${p.packageName}"
            }
        }
    }

    /**
     * Restores full data or media archives.
     */
    void doTarRestore(String[] tarConfigs) {
        println "starting restore ..."
        stopRuntime()
        for (String config : tarConfigs) {
            doTarRestore(config)
        }
        // Final SELinux label fix for the entire /data partition
        commander.execAsRoot("restorecon -FRDv /data")
        startRuntime()
        println "... restore finished"
    }

    /**
     * Restores a tar archive to the /data partition.
     */
    void doTarRestore(String tarConfig) {
        println "restoring ${tarConfig} to /data ..."
        File f = new File(localBackupDirectory + tarConfig + ".tar.gz")
        ByteArrayOutputStream baos = new ByteArrayOutputStream()
        DeviceManager mgr = new DeviceManager()
        DeviceMonitorMultiplexer allocationMonitor = new DeviceMonitorMultiplexer()
        NativeDeviceStateMonitor stateMonitor = new NativeDeviceStateMonitor(mgr, commander.device, false)
        NativeDevice nd = new NativeDevice(commander.device, stateMonitor, allocationMonitor)
        // Stream the archive into 'tar' on the device
        println nd.executeShellV2Command(getRootWrappedCommand("${ADBCommander.BB} tar -xvzf - -C /data --exclude=./**/var/* --exclude=./**/run/* 2>&1").toString(), f)
        baos.flush()
        println baos.toString()
        println "... finished"
        baos.close()
    }
}
