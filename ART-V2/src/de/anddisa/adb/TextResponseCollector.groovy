package de.anddisa.adb

import com.android.ddmlib.IShellOutputReceiver
import com.android.ddmlib.MultiLineReceiver

class TextResponseCollector extends MultiLineReceiver implements IShellOutputReceiver {
		StringWriter sw = new StringWriter()

		@Override
		boolean isCancelled() {
			return false
		}

		@Override
		void processNewLines(String[] lines) {
			for (int i = 0; i < lines.length; i++) {
				sw.write(lines[i])
				sw.write(System.lineSeparator())
			}
		}

		String get() {
			sw.flush()
			String content = sw.toString()
			sw = new StringWriter()
			return content
		}
}
