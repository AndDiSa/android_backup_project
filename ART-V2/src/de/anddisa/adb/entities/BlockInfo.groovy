package de.anddisa.adb.entities

class BlockInfo {
	String name
	String blockDevice
	
	def public String toString() {
		name + " : " + blockDevice
	}
}
