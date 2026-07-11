package de.anddisa.adb.util

import de.anddisa.adb.ADBCommander

class RemoteAccessUtilities {
	def PLAIN_ADB_COMMAND     = "adb"
	def MAGISK_ADB_COMMAND_V1 = "adb shell su root " // needed for magisk rooted devices
	def MAGISK_ADB_COMMAND_V2 = "adb shell su 0 -c " // needed for magisk rooted devices (depends on su version installed)
	def MAGISK_ADB_COMMAND_V3 = "adb shell su -c "   // needed for magisk rooted devices (depends on su version installed)
	def ADB_SHELL             = "adb shell "

	def ADBCommander commander
	
	def RemoteAccessUtilities(ADBCommander commander) {
		this.commander = commander
	}

	def String cleanup() {
		commander.exec("rm ${ADBCommander.BB}")
	}

	def boolean checkForCleanData() {
		String result = commander.execForResult("ls /data/ | wc -l")
		if (Integer.parseInt(result) <= 1) {
			commander.exec("mount /data")
			result = commander.execForResult("ls /data/ | wc -l")
		}

		if (Integer.parseInt(result) <= 4) {
			println "It seems like /data is not in a sane state!"
			println commander.execForResult("ls /data")
			println commander.execForResult("stat /data")
			return false
		}

		return true
	}

	def static boolean checkPrerequisites() {
		// to be done ...
	}

	def void stopAllApps() {
		println "## Force-stopping all applications for all users..."
		String usersList = commander.execForResult("pm list users")
		// UserInfo{0:Owner:13} running
		usersList.eachLine { line ->
			def matcher = line =~ /UserInfo\{(\d+):/
			if (matcher.find()) {
				def uid = matcher.group(1)
				println "   Processing User $uid..."
				String pkgs = commander.execForResult("pm list packages --user $uid")
				pkgs.eachLine { pkgLine ->
					if (pkgLine.startsWith("package:")) {
						def pkg = pkgLine.substring(8)
						commander.execAsRoot("am force-stop --user $uid $pkg")
					}
				}
			}
		}
		println "## All applications stopped."
	}

	def void stopRuntime() {
		println "## Stop Runtime"
		commander.execAsRoot("stop")
	}

	def void startRuntime() {
		println "## Restart Runtime"
		commander.execAsRoot("start")
	}
}
