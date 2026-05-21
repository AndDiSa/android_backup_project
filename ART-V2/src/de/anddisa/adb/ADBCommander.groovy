package de.anddisa.adb

import com.android.annotations.Nullable
import com.android.ddmlib.AdbCommandRejectedException
import com.android.ddmlib.TimeoutException
import com.android.ddmlib.AdbHelper


import com.android.ddmlib.AndroidDebugBridge
import com.android.ddmlib.IDevice
import com.android.ddmlib.IShellOutputReceiver
import com.android.ddmlib.MultiLineReceiver
import com.android.ddmlib.RawImage
import com.android.ddmlib.ShellCommandUnresponsiveException

import javax.imageio.ImageIO
import java.awt.*
import java.awt.image.BufferedImage
import java.nio.ByteBuffer
import java.text.SimpleDateFormat
import java.util.List
import java.util.concurrent.TimeUnit
import java.util.regex.Matcher
import java.util.regex.Pattern

/**
 * ADBCommander provides a high-level API for interacting with Android devices.
 * It uses the Android Debug Bridge (ddmlib) to execute shell commands,
 * manage files, and perform UI interactions (tap, swipe, etc.).
 * 
 * Features include:
 * - Dynamic root detection (trying multiple su variants)
 * - Automatic architecture detection and Busybox deployment
 * - User/Profile name resolution to numeric IDs
 * - Root-wrapped command execution (execAsRoot)
 */
public class ADBCommander {

	/** Thread-safe collector for shell command output */
	public ThreadLocal<TextResponseCollector> responseCollector = new ThreadLocal<TextResponseCollector>() {
		@Override protected TextResponseCollector initialValue() { return new TextResponseCollector() }
	}

    final IShellOutputReceiver RECEIVER_SILENT = new IShellOutputReceiver() {
        @Override
        boolean isCancelled() {
            return false
        }

        @Override
        void flush() {
        }

        @Override
        void addOutput(byte[] data, int offset, int length) {
        }
    }

    final IShellOutputReceiver RECEIVER_STD = new IShellOutputReceiver() {
        @Override
        void addOutput(byte[] data, int offset, int length) {
            System.out.write(data, offset, length)
        }

        @Override
        void flush() {
        }

        @Override
        boolean isCancelled() {
            return false
        }
    }

	final AndroidDebugBridge bridge

    IDevice device

    boolean outputToStdOut = false

    String rootCommand = ""

    void waitDeviceList(AndroidDebugBridge bridge) {
        int count = 0
        for (; count < 300 && bridge.hasInitialDeviceList() == false; count++) {
            try { Thread.sleep(100); count++; } catch (InterruptedException e) { }
        }
        if(count >= 300) {
            throw new RuntimeException("Timeout when waiting for device list")
        }
    }
	
    public void setOutputToStdOut(boolean outputToStdOut) {
        this.outputToStdOut = outputToStdOut
    }

    public boolean isOutputToStdOut() {
        return outputToStdOut
    }

    /**
     * Constructor: Initializes the Android Debug Bridge (ADB).
     * It ensures the adb server is running and selects the first available device by default.
     */
    public ADBCommander() {
        try {
            // make sure start-up adb
            Runtime.getRuntime().exec("adb start-server").waitFor()

            AndroidDebugBridge.initIfNeeded(true)
            bridge = AndroidDebugBridge.createBridge()

            waitDeviceList(bridge)

            List<IDevice> devices = bridge.getDevices()
            if(devices != null && devices.size() > 0) {
                device = devices.get(0)
                System.out.println("Connected, device is " + device.getName())
            } else {
                System.out.println("No device detected initially.")
            }
        } catch(Exception e) {
            if(e instanceof RuntimeException) {
                throw (RuntimeException)e
            } else {
                throw new RuntimeException(e)
            }
        }
    }

	public void setDevice(IDevice device) {
		this.device = device
		System.out.println("Connected, device is " + device.getName())
	}

    /**
     * Checks for root access using various 'su' commands.
     * Sets 'rootCommand' to the first successful command.
     */
    public boolean checkRootType() {
        println "Checking for root access..."
        
        // Try 'adb root' first
        try {
            device.root()
            Thread.sleep(1000) // Give it a moment to restart adbd if necessary
        } catch (Exception e) {
            println "adb root failed or not supported: ${e.message}"
        }

        String result = execForResult("whoami").trim()
        if (result == "root") {
            rootCommand = ""
            println "Root access available via adbd (AROOT)"
            return true
        }

        // Try different su variants
        String[] suVariants = ["su 0 -c", "su -c", "su root"]
        for (String su : suVariants) {
            result = execForResult("${su} whoami").trim()
            if (result == "root") {
                rootCommand = su
                println "Root access available via '${su}'"
                return true
            }
        }

        println "Finally root is not available for this device."
        return false
    }

    /**
     * Detects device architecture and pushes the appropriate Busybox binary.
     */
    public void pushBusybox(String localBusyboxDir) {
        println "Determining architecture..."
        String arch = execForResult("uname -m").trim()
        String targetArch = ""

        switch (arch) {
            case ~/aarch64|arm64|armv8|armv8a/:
                targetArch = "arm64"
                break
            case ~/aarch32|arm32|arm|armv7|armv7a|armv7l|armv8l|arm-neon|armv7a-neon|aarch|ARM/:
                targetArch = "arm"
                break
            case ~/x86_64|x64|amd64|AMD64|amd/:
                targetArch = "x86_64"
                break
            case ~/x86|x86_32|IA32|ia32|intel32|i386|i486|i586|i686|intel/:
                targetArch = "x86"
                break
            default:
                throw new RuntimeException("Unrecognized architecture: ${arch}")
        }

        println "Pushing busybox for ${targetArch}..."
        String localPath = "${localBusyboxDir}/busybox-${targetArch}"
        try {
            device.pushFile(localPath, "/sdcard/busybox")
            execAsRoot("mv /sdcard/busybox /dev/busybox")
            execAsRoot("chmod +x /dev/busybox")
            
            String version = execAsRootForResult("/dev/busybox --help") ?: ""
            if (version.contains("BusyBox")) {
                println "Busybox deployed successfully to /dev/busybox"
            } else {
                throw new RuntimeException("Busybox deployment failed: Help output invalid")
            }
        } catch (Exception e) {
            throw new RuntimeException("Failed to push busybox: ${e.message}", e)
        }
    }

    /**
     * Resolves a user identifier (ID or Name) to a User ID.
     */
    public int resolveUserId(String identifier) {
        if (!identifier || identifier == "0") return 0
        if (identifier.isInteger()) return identifier.toInteger()

        String usersList = execForResult("pm list users")
        // Example: UserInfo{10: Island :1030} running
        Pattern p = Pattern.compile("UserInfo\\{(\\d+):\\s*" + Pattern.quote(identifier) + "\\s*:")
        Matcher m = p.matcher(usersList)
        if (m.find()) {
            int id = m.group(1).toInteger()
            println "Resolved user '${identifier}' to ID ${id}"
            return id
        }
        
        println "Error: Could not resolve user '${identifier}'"
        println usersList
        return -1
    }

    /**
     * Resolves a User ID to a User Name.
     */
    public String resolveUserName(int userId) {
        if (userId == 0) return "Owner"
        String usersList = execForResult("pm list users")
        Pattern p = Pattern.compile("UserInfo\\{" + userId + ":\\s*([^:]+)\\s*:")
        Matcher m = p.matcher(usersList)
        if (m.find()) {
            return m.group(1).trim()
        }
        return "u${userId}"
    }

    /**
     * Executes a command as root.
     */
    public void execAsRoot(String cmd) {
        if (rootCommand) {
            exec("${rootCommand} \"${cmd}\"")
        } else {
            exec(cmd)
        }
    }

    public String execAsRootForResult(String cmd) {
        if (rootCommand) {
            return execForResult("${rootCommand} \"${cmd}\"")
        } else {
            return execForResult(cmd)
        }
    }

    public void execAsRootForResult(String cmd, IShellOutputReceiver collector, int time, TimeUnit unit) {
        if (rootCommand) {
            execForResult("${rootCommand} \"${cmd}\"", collector, time, unit)
        } else {
            execForResult(cmd, collector, time, unit)
        }
    }

    void tap(int x, int y) {
        execf("input tap %d %d", x, y)
    }

    void press(int x, int y, int tm) {
        execf("input swipe %d %d %d %d %d", x, y, x, y, tm)
    }

    void swipe(int x0, int y0, int x1, int y1, int tm) {
        execf("input swipe %d %d %d %d %d", x0, y0, x1, y1, tm)
    }

    void back() {
        exec("input keyevent 4")
    }

	    void home() {
        exec("input keyevent 3")
    }

    void power() {
        exec("input keyevent 26")
    }
	
    BufferedImage capture(boolean landscape, int sample) {
        try {
            RawImage raw = device.getScreenshot()

            if (raw == null) {
                return null
            }

            int w = (landscape ? raw.height : raw.width) / sample
            int h = (landscape ? raw.width : raw.height) / sample

            BufferedImage ret = new BufferedImage(w, h, BufferedImage.TYPE_3BYTE_BGR)

            int index = 0
            int indexInc = raw.bpp >> 3
            if (landscape) {
                for (int y = 0; y < raw.height; y += sample) {
                    for (int x = 0; x < raw.width;) { x += sample; index += indexInc * sample
                        ret.setRGB(y / sample, (raw.width - x - 1) / sample, raw.getARGB(index))
                    }
                    index += indexInc * raw.width * (sample - 1)
                }
            } else {
                for (int y = 0; y < raw.height; y += sample) {
                    for (int x = 0; x < raw.width;) { x += sample; index += indexInc * sample
                        ret.setRGB(x / sample, y / sample, raw.getARGB(index))
                    }
                    index += indexInc * raw.width * (sample - 1)
                }
            }
            return ret
        } catch (Exception e) {
            return null
        }
    }

    ThreadLocal<ByteBuffer> buffers = new ThreadLocal<ByteBuffer>() {
        @Override
        protected ByteBuffer initialValue() {
            // 4M bytes per buffer, which is quiet sufficient.
            return ByteBuffer.allocate(1024 * 1024 * 4)
        }
    }

    IShellOutputReceiver capReceiver = new IShellOutputReceiver() {
        @Override public boolean isCancelled() { return false; }
        @Override public void flush() { }
        @Override public void addOutput(byte[] data, int offset, int length) {
            buffers.get().put(data, offset, length)
        }
    };

    BufferedImage capture2(int scale) {
        try {
            ByteBuffer buf = buffers.get()
            buf.clear()
            device.executeShellCommand("screencap -p", capReceiver)
            buf.flip();
            BufferedImage img = ImageIO.read(
                    new ByteArrayInputStream(buf.array(), 0, buf.limit()))
            if(img != null && scale > 1) {
                int w = img.getWidth() / scale, h = img.getHeight() / scale
                BufferedImage scaled = new BufferedImage(w, h, BufferedImage.TYPE_3BYTE_BGR)
                Graphics g = scaled.getGraphics();
                g.drawImage(img, 0, 0, w, h, 0, 0, w * scale, h * scale, null)
                return scaled
            }
            return img
        } catch (Exception e) {
            if(e instanceof ShellCommandUnresponsiveException) {
                // just retry
                return capture2(scale)
            }
            e.printStackTrace()
            return null
        }
    }

    void execf(String cmd, Object... args) {
        exec(String.format(cmd, args))
    }

    @SuppressWarnings("unused")
    String execfForResult(String cmd, Object... args) {
        return execForResult(String.format(cmd, args))
    }

    /**
     * Executes a shell command on the device without returning output.
     * @param cmd The shell command to execute.
     */
    void exec(String cmd) {
        try {
            device.executeShellCommand(cmd, outputToStdOut ? RECEIVER_STD : RECEIVER_SILENT, 20, TimeUnit.SECONDS);
        } catch (ShellCommandUnresponsiveException e) {
            exec(cmd)
        } catch (Exception e) {
            throw new RuntimeException(e)
        }
    }

    /**
     * Executes a shell command and returns the output as a String.
     * @param cmd The shell command to execute.
     * @return The command output collected via TextResponseCollector.
     */
    String execForResult(String cmd) {
        try {
            TextResponseCollector collector
            device.executeShellCommand(cmd, collector = responseCollector.get(), 20, TimeUnit.SECONDS);
            return collector.get()
        } catch (ShellCommandUnresponsiveException e) {
            return execForResult(cmd)
        } catch (Exception e) {
            throw new RuntimeException(e)
        }
    }

    void execForResult(String cmd, IShellOutputReceiver collector, int time, TimeUnit unit) {
        try {
            device.executeShellCommand(cmd, collector, time, unit);
        } catch (Exception e) {
            throw new RuntimeException(e)
        }
    }
	
	void installApks(List<File> apks, boolean reinstall, List<String> installOptions) {
		try {
			device.installPackages(apks, reinstall, installOptions)
		} catch (Exception e) {
			throw new RuntimeException(e)
		}
	}

    public String whoAmI() {
        return execForResult("whoami");
    }

    public Date readDate() {
        String unix = execForResult("date +%s");
        return new Date(Long.parseLong(unix.replaceAll("[\\r\\n\\\"]", "")) * 1000)
    }

    final SimpleDateFormat DATE_SET_FORMATTER = new SimpleDateFormat("MMddHHmmyyyy.ss")
    void setDate(Date d) {
        execf("su -c date %s", DATE_SET_FORMATTER.format(d))
    }

    void launch(String pkg, String className) {
        exec("am start " + pkg + "/" + className)
    }

    void kill(String pkg) {
        exec("am force-stop " + pkg)
    }
	
    void ding() {
        exec("am startservice -a net.flyingff.PLAY -c android.intent.category.DEFAULT")
    }

	private static final Pattern PATTERN_TOP_ACTIVITY = Pattern.compile("topActivity=ComponentInfo\\{([^/]+)/([^/]+)\\}")
	public String[] topActivity() {
		Matcher mt = PATTERN_TOP_ACTIVITY.matcher(execForResult("am stack list"));
		if(mt.find()) {
			return [mt.group(1), mt.group(2)]
		} else {
			return null
		}
	}
}
