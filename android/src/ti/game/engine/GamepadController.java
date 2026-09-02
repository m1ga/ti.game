package ti.game.engine;

import android.app.Activity;
import android.content.Context;
import android.hardware.input.InputManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.SparseArray;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.Window;

import java.lang.ref.WeakReference;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.ArrayList;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;

/**
 * Game controller input (Bluetooth/USB gamepads such as a Stadia, Xbox or
 * PlayStation pad). Runs on the UI thread and turns raw key/joystick
 * traffic into a handful of discrete, named events on the game view:
 *
 *   gamepadconnected / gamepaddisconnected  { gamepad, name }
 *   buttondown / buttonup   { button, gamepad, input, keyCode }
 *   stick                   { stick: 'left'|'right', x, y, gamepad }
 *   trigger                 { trigger: 'l2'|'r2', value, gamepad }
 *
 * Button names are normalized across controllers: a b x y l1 r1 l2 r2
 * l3 r3 start select home up down left right. The d-pad reaches JS as
 * up/down/left/right buttons whether the pad reports it as key events or
 * as hat axes (Stadia does the latter), and the left stick fires the same
 * four names (input 'leftstick') once it is pushed past half way — so a
 * single 'buttondown' handler can drive a game without caring which
 * control the player used. Analog values go out as 'stick'/'trigger'
 * events, throttled to ~20 Hz per channel while they change, always
 * ending with the rest value.
 *
 * Input is captured at the activity Window rather than on the GL view:
 * gamepad key events go to the focused view (or become BACK/DPAD focus
 * navigation when nothing consumes them), and a Titanium window full of
 * buttons rarely has the game view focused. Wrapping the Window.Callback
 * sees every event first, regardless of focus; mapped gamepad buttons are
 * consumed there, everything else passes through untouched.
 */
public final class GamepadController implements InputManager.InputDeviceListener
{
	private static final long AXIS_EVENT_INTERVAL_MS = 50; // ~20 Hz 'stick'/'trigger' events
	private static final float DEFAULT_STICK_PRESS = 0.5f;   // left stick → digital direction
	private static final float DEFAULT_STICK_RELEASE = 0.4f; // hysteresis
	private static final float TRIGGER_PRESS = 0.5f;
	private static final float TRIGGER_RELEASE = 0.35f;
	private static final float AXIS_EPSILON = 0.01f;

	public static final String[] DIRECTION_NAMES = { "up", "down", "left", "right" };

	// ---- Window hook: one per activity window, shared by its game views --
	// (found again through the installed proxy — no static registry, so a
	// finished activity is not kept alive by a map entry)

	private static final class WindowHook implements InvocationHandler
	{
		final Window.Callback original;
		final ArrayList<WeakReference<GamepadController>> controllers = new ArrayList<>();

		WindowHook(Window.Callback original)
		{
			this.original = original;
		}

		@Override
		public Object invoke(Object proxy, Method method, Object[] args) throws Throwable
		{
			if (args != null && args.length == 1) {
				String name = method.getName();
				if ("dispatchKeyEvent".equals(name) && args[0] instanceof KeyEvent) {
					if (dispatchKey((KeyEvent) args[0])) {
						return Boolean.TRUE;
					}
				} else if ("dispatchGenericMotionEvent".equals(name) && args[0] instanceof MotionEvent) {
					if (dispatchMotion((MotionEvent) args[0])) {
						return Boolean.TRUE;
					}
				}
			}
			try {
				return method.invoke(original, args);
			} catch (InvocationTargetException e) {
				throw e.getCause();
			}
		}

		private boolean dispatchKey(KeyEvent event)
		{
			boolean consumed = false;
			for (int i = controllers.size() - 1; i >= 0; i--) {
				GamepadController controller = controllers.get(i).get();
				if (controller == null) {
					controllers.remove(i);
				} else if (controller.onKeyEvent(event)) {
					consumed = true;
				}
			}
			return consumed;
		}

		private boolean dispatchMotion(MotionEvent event)
		{
			boolean consumed = false;
			for (int i = controllers.size() - 1; i >= 0; i--) {
				GamepadController controller = controllers.get(i).get();
				if (controller == null) {
					controllers.remove(i);
				} else if (controller.onMotionEvent(event)) {
					consumed = true;
				}
			}
			return consumed;
		}
	}

	private static WindowHook installedHook(Window window)
	{
		Window.Callback callback = window.getCallback();
		if (callback != null && Proxy.isProxyClass(callback.getClass())) {
			InvocationHandler handler = Proxy.getInvocationHandler(callback);
			if (handler instanceof WindowHook) {
				return (WindowHook) handler;
			}
		}
		return null;
	}

	/**
	 * UI thread. Android batches joystick motion and hands it to the app
	 * once per display frame, while key events (the d-pad) arrive at once
	 * — so a stick release trails a d-pad release by up to a frame. From
	 * API 30 a window can opt out for joysticks; below that there is no
	 * equivalent and the frame of latency stays. The request needs an
	 * attached view, and the game view is often created before the window
	 * is, so it waits for the attach when necessary.
	 */
	private static void requestUnbufferedJoystick(Window window)
	{
		if (Build.VERSION.SDK_INT < 30) {
			return;
		}
		final View decor = window.getDecorView();
		if (decor.isAttachedToWindow()) {
			decor.requestUnbufferedDispatch(InputDevice.SOURCE_CLASS_JOYSTICK);
			return;
		}
		decor.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
			@Override
			public void onViewAttachedToWindow(View v)
			{
				v.requestUnbufferedDispatch(InputDevice.SOURCE_CLASS_JOYSTICK);
				v.removeOnAttachStateChangeListener(this);
			}

			@Override
			public void onViewDetachedFromWindow(View v)
			{
			}
		});
	}

	/** UI thread. Installs the callback wrapper once per window. */
	private static void hook(Window window, GamepadController controller)
	{
		WindowHook hook = installedHook(window);
		if (hook == null) {
			Window.Callback original = window.getCallback();
			if (original == null) {
				return;
			}
			hook = new WindowHook(original);
			Window.Callback wrapped = (Window.Callback) Proxy.newProxyInstance(
				Window.Callback.class.getClassLoader(), new Class<?>[] { Window.Callback.class }, hook);
			window.setCallback(wrapped);
		}
		hook.controllers.add(new WeakReference<>(controller));
	}

	private static void unhook(Window window, GamepadController controller)
	{
		WindowHook hook = installedHook(window);
		if (hook == null) {
			return;
		}
		for (int i = hook.controllers.size() - 1; i >= 0; i--) {
			GamepadController other = hook.controllers.get(i).get();
			if (other == null || other == controller) {
				hook.controllers.remove(i);
			}
		}
		// The wrapper stays installed (something else may have wrapped it
		// since); with no controllers left it is a plain pass-through.
	}

	// ---- Per-device state ---------------------------------------------

	/** One throttled analog channel (a stick or a trigger). */
	private final class Channel
	{
		final String event;   // 'stick' | 'trigger'
		final String key;     // payload key: 'stick' | 'trigger'
		final String name;    // 'left' | 'right' | 'l2' | 'r2'
		final boolean twoAxes;
		final int deviceId;
		float x, y;           // last reported
		float pendingX, pendingY;
		boolean pending;
		long lastEventMs;

		Channel(int deviceId, String event, String name, boolean twoAxes)
		{
			this.deviceId = deviceId;
			this.event = event;
			this.key = event;
			this.name = name;
			this.twoAxes = twoAxes;
		}

		void update(float nx, float ny)
		{
			if (Math.abs(nx - (pending ? pendingX : x)) < AXIS_EPSILON
				&& Math.abs(ny - (pending ? pendingY : y)) < AXIS_EPSILON) {
				return;
			}
			pendingX = nx;
			pendingY = ny;
			long now = android.os.SystemClock.uptimeMillis();
			long wait = lastEventMs + AXIS_EVENT_INTERVAL_MS - now;
			// Transitions skip the throttle: leaving rest, returning to rest
			// and crossing zero are what a game reacts to, and a 50 ms wait
			// there is a felt delay (a stick let go stops the hero late)
			boolean transition = Math.signum(nx) != Math.signum(x) || Math.signum(ny) != Math.signum(y);
			if (wait <= 0 || transition) {
				if (pending) {
					pending = false;
					handler.removeCallbacks(flusher);
				}
				flush(now);
			} else if (!pending) {
				pending = true;
				handler.postDelayed(flusher, wait);
			}
		}

		final Runnable flusher = new Runnable() {
			@Override
			public void run()
			{
				if (pending) {
					pending = false;
					flush(android.os.SystemClock.uptimeMillis());
				}
			}
		};

		/** Cancels a pending flush and reports the rest value when the last
		 *  reported one was not rest — a stick still held when the app goes
		 *  to the background or the pad disconnects ends with 0, 0 in JS. */
		void rest()
		{
			if (pending) {
				pending = false;
				handler.removeCallbacks(flusher);
			}
			pendingX = pendingY = 0f;
			if (x != 0f || y != 0f) {
				flush(android.os.SystemClock.uptimeMillis());
			}
		}

		void flush(long now)
		{
			x = pendingX;
			y = pendingY;
			lastEventMs = now;
			if (viewProxy != null && viewProxy.hasListeners(event)) {
				KrollDict data = new KrollDict();
				data.put(key, name);
				if (twoAxes) {
					data.put("x", x);
					data.put("y", y);
				} else {
					data.put("value", x);
				}
				data.put("gamepad", deviceId);
				viewProxy.fireEvent(event, data);
			}
		}
	}

	private final class DeviceState
	{
		final int id;
		final String name;
		final Channel leftStick, rightStick, leftTrigger, rightTrigger;
		final ArrayList<String> pressed = new ArrayList<>(); // button names currently down
		float hatX, hatY;
		final boolean[] stickDirs = new boolean[4];  // left stick as up/down/left/right
		boolean l2Down, r2Down;                       // analog triggers as buttons
		final boolean hasZ, hasLTrigger, hasHat;

		DeviceState(InputDevice device, int id)
		{
			this.id = id;
			this.name = device != null ? device.getName() : ("gamepad " + id);
			leftStick = new Channel(id, "stick", "left", true);
			rightStick = new Channel(id, "stick", "right", true);
			leftTrigger = new Channel(id, "trigger", "l2", false);
			rightTrigger = new Channel(id, "trigger", "r2", false);
			hasZ = hasRange(device, MotionEvent.AXIS_Z);
			hasLTrigger = hasRange(device, MotionEvent.AXIS_LTRIGGER);
			hasHat = hasRange(device, MotionEvent.AXIS_HAT_X);
		}

		/** Every analog channel back to rest (reported to JS if it was not). */
		void restChannels()
		{
			leftStick.rest();
			rightStick.rest();
			leftTrigger.rest();
			rightTrigger.rest();
		}
	}

	private static boolean hasRange(InputDevice device, int axis)
	{
		return device != null && device.getMotionRange(axis, InputDevice.SOURCE_JOYSTICK) != null;
	}

	// ---- Instance ------------------------------------------------------

	private final KrollProxy viewProxy; // GameViewProxy
	private final Handler handler = new Handler(Looper.getMainLooper());
	private final SparseArray<DeviceState> devices = new SparseArray<>();
	private volatile int lastActiveDevice = -1;
	private volatile float deadzone = 0.2f;
	private volatile float stickPress = DEFAULT_STICK_PRESS;
	private volatile float stickRelease = DEFAULT_STICK_RELEASE;
	private Window window;
	private InputManager inputManager;
	private boolean released;

	public GamepadController(Activity activity, KrollProxy viewProxy)
	{
		this.viewProxy = viewProxy;
		if (activity == null) {
			return;
		}
		window = activity.getWindow();
		inputManager = (InputManager) activity.getSystemService(Context.INPUT_SERVICE);
		Runnable install = new Runnable() {
			@Override
			public void run()
			{
				if (released || window == null) {
					return;
				}
				hook(window, GamepadController.this);
				requestUnbufferedJoystick(window);
				if (inputManager != null) {
					inputManager.registerInputDeviceListener(GamepadController.this, handler);
				}
			}
		};
		if (Looper.myLooper() == Looper.getMainLooper()) {
			install.run();
		} else {
			handler.post(install);
		}
	}

	/** Any thread. Stops listening; held buttons are released to JS. */
	public void release()
	{
		Runnable uninstall = new Runnable() {
			@Override
			public void run()
			{
				if (released) {
					return;
				}
				released = true;
				if (window != null) {
					unhook(window, GamepadController.this);
				}
				if (inputManager != null) {
					inputManager.unregisterInputDeviceListener(GamepadController.this);
				}
				releaseAll();
			}
		};
		if (Looper.myLooper() == Looper.getMainLooper()) {
			uninstall.run();
		} else {
			handler.post(uninstall);
		}
	}

	/** Radial dead zone applied to both sticks (0..0.9). */
	public void setDeadzone(float value)
	{
		deadzone = Math.max(0f, Math.min(0.9f, value));
	}

	public float getDeadzone()
	{
		return deadzone;
	}

	/** Left-stick deflection that presses a direction button (0.1..0.95)
	 *  and the lower value that releases it again (hysteresis). */
	public void setStickThresholds(float press, float release)
	{
		stickPress = Math.max(0.1f, Math.min(0.95f, press));
		stickRelease = Math.max(0.05f, Math.min(stickPress, release));
	}

	/** UI thread. Fires buttonup for everything held — on activity pause,
	 *  when a pad disconnects or the view goes away, so a held direction
	 *  never sticks in JS. */
	public void releaseAll()
	{
		for (int i = 0; i < devices.size(); i++) {
			releaseDevice(devices.valueAt(i));
		}
	}

	/** UI thread. Buttons up, analog channels to rest, for one pad. */
	private void releaseDevice(DeviceState state)
	{
		while (!state.pressed.isEmpty()) {
			String name = state.pressed.get(state.pressed.size() - 1);
			setButton(state, name, false, "button", 0);
		}
		for (int d = 0; d < 4; d++) {
			state.stickDirs[d] = false;
		}
		state.hatX = state.hatY = 0;
		state.l2Down = state.r2Down = false;
		state.restChannels();
	}

	// ---- Queries for the proxy (any thread) ----------------------------

	/** Connected game controllers as [{ id, name }]. */
	public static Object[] connectedGamepads()
	{
		ArrayList<KrollDict> list = new ArrayList<>();
		for (int id : InputDevice.getDeviceIds()) {
			InputDevice device = InputDevice.getDevice(id);
			if (device != null && isGamepad(device)) {
				KrollDict entry = new KrollDict();
				entry.put("id", id);
				entry.put("name", device.getName());
				list.add(entry);
			}
		}
		return list.toArray();
	}

	/** Snapshot of the most recently used pad (null if none was used yet). */
	public KrollDict snapshot()
	{
		DeviceState state;
		synchronized (devices) {
			state = devices.get(lastActiveDevice);
		}
		if (state == null) {
			return null;
		}
		KrollDict data = new KrollDict();
		data.put("id", state.id);
		data.put("name", state.name);
		data.put("leftX", state.leftStick.pending ? state.leftStick.pendingX : state.leftStick.x);
		data.put("leftY", state.leftStick.pending ? state.leftStick.pendingY : state.leftStick.y);
		data.put("rightX", state.rightStick.pending ? state.rightStick.pendingX : state.rightStick.x);
		data.put("rightY", state.rightStick.pending ? state.rightStick.pendingY : state.rightStick.y);
		data.put("l2", state.leftTrigger.pending ? state.leftTrigger.pendingX : state.leftTrigger.x);
		data.put("r2", state.rightTrigger.pending ? state.rightTrigger.pendingX : state.rightTrigger.x);
		KrollDict buttons = new KrollDict();
		synchronized (state.pressed) {
			for (String name : state.pressed) {
				buttons.put(name, true);
			}
		}
		data.put("buttons", buttons);
		return data;
	}

	// ---- InputManager.InputDeviceListener (UI thread) ------------------

	@Override
	public void onInputDeviceAdded(int deviceId)
	{
		InputDevice device = InputDevice.getDevice(deviceId);
		if (device != null && isGamepad(device)) {
			stateFor(deviceId, device);
		}
	}

	@Override
	public void onInputDeviceRemoved(int deviceId)
	{
		DeviceState state;
		synchronized (devices) {
			state = devices.get(deviceId);
			if (state != null) {
				devices.remove(deviceId);
			}
		}
		if (state == null) {
			return;
		}
		releaseDevice(state);
		fireDevice("gamepaddisconnected", state);
	}

	@Override
	public void onInputDeviceChanged(int deviceId)
	{
	}

	// ---- Raw input (UI thread, via the window hook) --------------------

	static boolean isGamepad(InputDevice device)
	{
		int sources = device.getSources();
		return (sources & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
			|| (sources & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK;
	}

	private static boolean isGamepadSource(int source)
	{
		return (source & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
			|| (source & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
			|| (source & InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD;
	}

	private DeviceState stateFor(int deviceId, InputDevice device)
	{
		DeviceState state;
		boolean fresh = false;
		synchronized (devices) {
			state = devices.get(deviceId);
			if (state == null) {
				state = new DeviceState(device != null ? device : InputDevice.getDevice(deviceId), deviceId);
				devices.put(deviceId, state);
				fresh = true;
			}
		}
		if (fresh) {
			// A pad paired before the view existed announces itself on its
			// first input — JS always hears 'gamepadconnected' before any
			// button from that pad.
			fireDevice("gamepadconnected", state);
		}
		return state;
	}

	/** @return true when the event was a mapped gamepad button (consumed). */
	boolean onKeyEvent(KeyEvent event)
	{
		if (released) {
			return false;
		}
		int keyCode = event.getKeyCode();
		String name = buttonName(keyCode);
		boolean gamepadKey = KeyEvent.isGamepadButton(keyCode);
		if (name == null && !gamepadKey) {
			return false;
		}
		if (!gamepadKey && !isGamepadSource(event.getSource())) {
			return false; // arrow keys on a keyboard, TV remote d-pads etc.
		}
		int action = event.getAction();
		if (action == KeyEvent.ACTION_DOWN && event.getRepeatCount() > 0) {
			return true; // auto-repeat: still ours, but not a new press
		}
		if (action != KeyEvent.ACTION_DOWN && action != KeyEvent.ACTION_UP) {
			return false;
		}
		DeviceState state = stateFor(event.getDeviceId(), event.getDevice());
		lastActiveDevice = state.id;
		if (name == null) {
			name = "button" + keyCode; // unmapped KEYCODE_BUTTON_*: still reported
		}
		String source = isDirection(name) ? "dpad" : "button";
		setButton(state, name, action == KeyEvent.ACTION_DOWN, source, keyCode);
		return true;
	}

	/** @return true when the event was joystick motion we handled. */
	boolean onMotionEvent(MotionEvent event)
	{
		if (released
			|| (event.getSource() & InputDevice.SOURCE_JOYSTICK) != InputDevice.SOURCE_JOYSTICK
			|| event.getAction() != MotionEvent.ACTION_MOVE) {
			return false;
		}
		DeviceState state = stateFor(event.getDeviceId(), event.getDevice());
		lastActiveDevice = state.id;

		// Left stick — plus the digital direction it implies
		float lx = event.getAxisValue(MotionEvent.AXIS_X);
		float ly = event.getAxisValue(MotionEvent.AXIS_Y);
		float[] left = applyDeadzone(lx, ly);
		updateStickDirections(state, left[0], left[1]);
		state.leftStick.update(left[0], left[1]);

		// Right stick: Z/RZ on most pads, RX/RY on a few
		float rx, ry;
		if (state.hasZ) {
			rx = event.getAxisValue(MotionEvent.AXIS_Z);
			ry = event.getAxisValue(MotionEvent.AXIS_RZ);
		} else {
			rx = event.getAxisValue(MotionEvent.AXIS_RX);
			ry = event.getAxisValue(MotionEvent.AXIS_RY);
		}
		float[] right = applyDeadzone(rx, ry);
		state.rightStick.update(right[0], right[1]);

		// Analog triggers: LTRIGGER/RTRIGGER or BRAKE/GAS
		float lt, rt;
		if (state.hasLTrigger) {
			lt = event.getAxisValue(MotionEvent.AXIS_LTRIGGER);
			rt = event.getAxisValue(MotionEvent.AXIS_RTRIGGER);
		} else {
			lt = event.getAxisValue(MotionEvent.AXIS_BRAKE);
			rt = event.getAxisValue(MotionEvent.AXIS_GAS);
		}
		lt = clamp01(lt);
		rt = clamp01(rt);
		state.l2Down = updateTrigger(state, "l2", lt, state.l2Down);
		state.r2Down = updateTrigger(state, "r2", rt, state.r2Down);
		state.leftTrigger.update(lt, 0);
		state.rightTrigger.update(rt, 0);

		// D-pad reported as a hat (Stadia, Xbox, most modern pads)
		if (state.hasHat) {
			float hx = event.getAxisValue(MotionEvent.AXIS_HAT_X);
			float hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y);
			updateHat(state, hx, hy);
		}
		return true;
	}

	// Joystick MOTION events arrive every frame while a stick is held —
	// results go into this scratch pair instead of a fresh array each time
	private final float[] deadzoneOut = new float[2];
	private final float[] stickValues = new float[4];

	private float[] applyDeadzone(float x, float y)
	{
		float dz = deadzone;
		float len = (float) Math.sqrt(x * x + y * y);
		float[] out = deadzoneOut;
		if (len <= dz || len == 0f) {
			out[0] = 0f;
			out[1] = 0f;
			return out;
		}
		float scaled = Math.min(1f, (len - dz) / (1f - dz));
		out[0] = x / len * scaled;
		out[1] = y / len * scaled;
		return out;
	}

	private static float clamp01(float v)
	{
		return v < 0f ? 0f : (v > 1f ? 1f : v);
	}

	private void updateStickDirections(DeviceState state, float x, float y)
	{
		// order matches DIRECTION_NAMES: up, down, left, right
		float[] values = stickValues;
		values[0] = -y;
		values[1] = y;
		values[2] = -x;
		values[3] = x;
		for (int d = 0; d < 4; d++) {
			boolean was = state.stickDirs[d];
			boolean now = was ? values[d] > stickRelease : values[d] > stickPress;
			if (now != was) {
				state.stickDirs[d] = now;
				setButton(state, DIRECTION_NAMES[d], now, "leftstick", 0);
			}
		}
	}

	private boolean updateTrigger(DeviceState state, String name, float value, boolean was)
	{
		boolean now = was ? value > TRIGGER_RELEASE : value > TRIGGER_PRESS;
		if (now != was) {
			setButton(state, name, now, "trigger", 0);
		}
		return now;
	}

	private void updateHat(DeviceState state, float hx, float hy)
	{
		if (hx != state.hatX) {
			if (state.hatX < -0.5f) {
				setButton(state, "left", false, "dpad", 0);
			} else if (state.hatX > 0.5f) {
				setButton(state, "right", false, "dpad", 0);
			}
			if (hx < -0.5f) {
				setButton(state, "left", true, "dpad", 0);
			} else if (hx > 0.5f) {
				setButton(state, "right", true, "dpad", 0);
			}
			state.hatX = hx;
		}
		if (hy != state.hatY) {
			if (state.hatY < -0.5f) {
				setButton(state, "up", false, "dpad", 0);
			} else if (state.hatY > 0.5f) {
				setButton(state, "down", false, "dpad", 0);
			}
			if (hy < -0.5f) {
				setButton(state, "up", true, "dpad", 0);
			} else if (hy > 0.5f) {
				setButton(state, "down", true, "dpad", 0);
			}
			state.hatY = hy;
		}
	}

	/** Central edge detector: a name is reported down once, no matter how
	 *  many physical controls map onto it (d-pad hat + key + stick). */
	private void setButton(DeviceState state, String name, boolean down, String source, int keyCode)
	{
		synchronized (state.pressed) {
			boolean was = state.pressed.contains(name);
			if (down == was) {
				return;
			}
			if (down) {
				state.pressed.add(name);
			} else {
				state.pressed.remove(name);
			}
		}
		String event = down ? "buttondown" : "buttonup";
		if (viewProxy != null && viewProxy.hasListeners(event)) {
			KrollDict data = new KrollDict();
			data.put("button", name);
			data.put("gamepad", state.id);
			data.put("input", source); // not "source" — Titanium overwrites that key with the firing proxy
			data.put("keyCode", keyCode);
			viewProxy.fireEvent(event, data);
		}
	}

	private void fireDevice(String event, DeviceState state)
	{
		if (viewProxy != null && viewProxy.hasListeners(event)) {
			KrollDict data = new KrollDict();
			data.put("gamepad", state.id);
			data.put("name", state.name);
			viewProxy.fireEvent(event, data);
		}
	}

	private static boolean isDirection(String name)
	{
		return "up".equals(name) || "down".equals(name) || "left".equals(name) || "right".equals(name);
	}

	/** Normalized button name for a key code; null for keys that are not
	 *  gamepad buttons (BACK, VOLUME_..., letters — left to the system). */
	static String buttonName(int keyCode)
	{
		switch (keyCode) {
			case KeyEvent.KEYCODE_BUTTON_A: return "a";
			case KeyEvent.KEYCODE_BUTTON_B: return "b";
			case KeyEvent.KEYCODE_BUTTON_X: return "x";
			case KeyEvent.KEYCODE_BUTTON_Y: return "y";
			case KeyEvent.KEYCODE_BUTTON_C: return "c";
			case KeyEvent.KEYCODE_BUTTON_Z: return "z";
			case KeyEvent.KEYCODE_BUTTON_L1: return "l1";
			case KeyEvent.KEYCODE_BUTTON_R1: return "r1";
			case KeyEvent.KEYCODE_BUTTON_L2: return "l2";
			case KeyEvent.KEYCODE_BUTTON_R2: return "r2";
			case KeyEvent.KEYCODE_BUTTON_THUMBL: return "l3";
			case KeyEvent.KEYCODE_BUTTON_THUMBR: return "r3";
			case KeyEvent.KEYCODE_BUTTON_START: return "start";
			case KeyEvent.KEYCODE_BUTTON_SELECT: return "select";
			case KeyEvent.KEYCODE_BUTTON_MODE: return "home";
			case KeyEvent.KEYCODE_DPAD_UP: return "up";
			case KeyEvent.KEYCODE_DPAD_DOWN: return "down";
			case KeyEvent.KEYCODE_DPAD_LEFT: return "left";
			case KeyEvent.KEYCODE_DPAD_RIGHT: return "right";
			default: return null;
		}
	}
}
