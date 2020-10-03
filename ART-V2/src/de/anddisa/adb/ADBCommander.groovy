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

public class ADBCommander {

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

    public ADBCommander() {
        try {
            // make sure start-up adb
            Runtime.getRuntime().exec("adb start-server").waitFor()

            AndroidDebugBridge.initIfNeeded(true)
            bridge = AndroidDebugBridge.createBridge()

            waitDeviceList(bridge)

            List<IDevice> devices = bridge.getDevices()
            if(devices == null || devices.size() <= 0) {
                throw new RuntimeException("No device detected.")
            }
            device = devices.get(0)
            System.out.println("Connected, device is " + device.getName())
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

    void exec(String cmd) {
        try {
            device.executeShellCommand(cmd, outputToStdOut ? RECEIVER_STD : RECEIVER_SILENT, 20, TimeUnit.SECONDS);
        } catch (ShellCommandUnresponsiveException e) {
            exec(cmd)
        } catch (Exception e) {
            throw new RuntimeException(e)
        }
    }

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
