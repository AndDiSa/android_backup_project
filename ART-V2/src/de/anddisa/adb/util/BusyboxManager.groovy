package de.anddisa.adb.util

import java.nio.file.Files
import java.nio.file.Paths
import java.nio.file.StandardCopyOption

/**
 * BusyboxManager handles the location and automatic download of architecture-specific 
 * Busybox binaries from the official Magisk-Modules-Repo.
 */
class BusyboxManager {

    static final String REPO_URL = "https://raw.githubusercontent.com/Magisk-Modules-Repo/busybox-ndk/master/"

    /**
     * Ensures the busybox binary for the given architecture is available locally.
     * @param arch Normalized architecture (arm, arm64, x86, x86_64)
     * @param localDir The directory to search in and download to
     * @return The absolute path to the local busybox binary
     */
    static String ensureBusybox(String arch, String localDir) {
        File dir = new File(localDir)
        if (!dir.exists()) dir.mkdirs()

        String binaryName = "busybox-${arch}"
        File localFile = new File(dir, binaryName)

        if (localFile.exists()) {
            return localFile.absolutePath
        }

        println "Busybox binary not found locally. Downloading ${binaryName} from GitHub..."
        try {
            URI uri = new URI("${REPO_URL}${binaryName}")
            uri.toURL().withInputStream { is ->
                Files.copy(is, localFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
            localFile.setExecutable(true)
            println "Download complete: ${localFile.absolutePath}"
            return localFile.absolutePath
        } catch (Exception e) {
            throw new RuntimeException("Failed to download busybox binary: ${e.message}", e)
        }
    }
}
