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
		commander.exec("rm /dev/busybox")
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

	def void stopRuntime() {
		commander.exec("stop")
	}

	def void startRuntime() {
		commander.exec("start")
	}
}
