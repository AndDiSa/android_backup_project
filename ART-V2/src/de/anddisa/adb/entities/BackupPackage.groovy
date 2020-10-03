package de.anddisa.adb.entities

class BackupPackage {
	String packageName
	String appDirectoryOnDevice
	String dataDirectoryOnDevice
	String localAppPath
	String localDataPath
	boolean selected
	boolean successful
	
	public String toString() {
		packageName + " : " + appDirectoryOnDevice + " : " + dataDirectoryOnDevice + " : " + localAppPath + " : " + localDataPath + " : " + selected + " : " + successful
	}
}
