package de.anddisa.adb

import com.android.ddmlib.IShellOutputReceiver

/**
 * class which receives data from remote and writes it to the
 * local file system
 *
 */
public class FileReceiver implements IShellOutputReceiver {

	private FileOutputStream fos = null
	boolean isCancelled = false
	private long size = 0
	private long block = 0
	private int n = 0

	public FileReceiver(String fileName) {
		try {
			this.fos = new FileOutputStream(fileName)
		} catch (FileNotFoundException e) {
			isCancelled = true
		}
		println "transferring file:" + fileName
	}

	public void addOutput(byte[] data, int offset, int length) {
		try {
			fos.write(data, offset, length)
			size += length
			block++
			print "."
			if (++n > 120) {
				println ""
				n = 0
			}
		} catch (IOException e) {
			isCancelled = true
		}
	}

	public void flush() {
		try {
			fos.flush()
			println "finished"
			println "size:" + size
			fos.close()
		} catch (IOException e) {
			isCancelled = true
		}
	}

	public boolean isCancelled() {
		return isCancelled
	}
}
