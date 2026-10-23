package ti.game.engine;

import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.titanium.proxy.TiViewProxy;

/**
 * Keyboard and mouse input delivered to this canvas (UI thread) — never a
 * global keyboard or mouse hook. Feeds the InputResolver and fires the
 * discrete keydown/keyup events.
 */
public final class CanvasInput
{
	private final InputResolver resolver;
	private final TiViewProxy proxy;

	public CanvasInput(InputResolver resolver, TiViewProxy proxy)
	{
		this.resolver = resolver;
		this.proxy = proxy;
	}

	/** @return true when the key event was consumed. */
	public boolean key(KeyEvent event)
	{
		// gamepad buttons belong to the GamepadController
		if ((event.getSource() & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD
			|| KeyEvent.isGamepadButton(event.getKeyCode())) {
			return false;
		}
		String code = keyCode(event.getKeyCode());
		int action = event.getAction();
		if (code == null || (action != KeyEvent.ACTION_DOWN && action != KeyEvent.ACTION_UP)) {
			return false;
		}
		boolean down = action == KeyEvent.ACTION_DOWN;
		if (down && event.getRepeatCount() > 0) {
			return true; // auto-repeat: ours, but not a new press
		}
		String id = Integer.toString(event.getDeviceId());
		if (event.isCanceled()) {
			resolver.releaseDevice("keyboard", id);
			return true;
		}
		if (!resolver.transition("keyboard", id, code, down)) {
			return true;
		}
		String name = down ? "keydown" : "keyup";
		if (proxy.hasListeners(name)) {
			KrollDict data = new KrollDict();
			data.put("code", code);
			int unicode = event.getUnicodeChar();
			boolean printable = unicode > 0 && unicode <= Character.MAX_CODE_POINT;
			data.put("character", printable ? new String(Character.toChars(unicode)) : "");
			KrollDict modifiers = new KrollDict();
			modifiers.put("shift", event.isShiftPressed());
			modifiers.put("control", event.isCtrlPressed());
			modifiers.put("alt", event.isAltPressed());
			modifiers.put("meta", event.isMetaPressed());
			data.put("modifiers", modifiers);
			proxy.fireEvent(name, data);
		}
		return true;
	}

	/**
	 * @return true when the pointer event came from a mouse and the active
	 * context binds mouse buttons (the event is then consumed, so sprite
	 * tap/drag handling does not see it).
	 */
	public boolean mouse(MotionEvent event)
	{
		if ((event.getSource() & InputDevice.SOURCE_MOUSE) != InputDevice.SOURCE_MOUSE) {
			return false;
		}
		String id = Integer.toString(event.getDeviceId());
		if (event.getActionMasked() == MotionEvent.ACTION_CANCEL) {
			resolver.releaseDevice("mouse", id);
			return resolver.hasBindings("mouse");
		}
		int buttons = event.getButtonState();
		resolver.transition("mouse", id, "left", (buttons & MotionEvent.BUTTON_PRIMARY) != 0);
		resolver.transition("mouse", id, "middle", (buttons & MotionEvent.BUTTON_TERTIARY) != 0);
		resolver.transition("mouse", id, "right", (buttons & MotionEvent.BUTTON_SECONDARY) != 0);
		return resolver.hasBindings("mouse");
	}

	/** Android key code -> W3C KeyboardEvent.code name, or null when unsupported. */
	public static String keyCode(int key)
	{
		if (key >= KeyEvent.KEYCODE_A && key <= KeyEvent.KEYCODE_Z) {
			return "Key" + (char) ('A' + key - KeyEvent.KEYCODE_A);
		}
		if (key >= KeyEvent.KEYCODE_0 && key <= KeyEvent.KEYCODE_9) {
			return "Digit" + (key - KeyEvent.KEYCODE_0);
		}
		if (key >= KeyEvent.KEYCODE_F1 && key <= KeyEvent.KEYCODE_F12) {
			return "F" + (key - KeyEvent.KEYCODE_F1 + 1);
		}
		switch (key) {
			case KeyEvent.KEYCODE_DPAD_UP: return "ArrowUp";
			case KeyEvent.KEYCODE_DPAD_DOWN: return "ArrowDown";
			case KeyEvent.KEYCODE_DPAD_LEFT: return "ArrowLeft";
			case KeyEvent.KEYCODE_DPAD_RIGHT: return "ArrowRight";
			case KeyEvent.KEYCODE_SPACE: return "Space";
			case KeyEvent.KEYCODE_ESCAPE: return "Escape";
			case KeyEvent.KEYCODE_ENTER: return "Enter";
			case KeyEvent.KEYCODE_TAB: return "Tab";
			case KeyEvent.KEYCODE_DEL: return "Backspace";
			case KeyEvent.KEYCODE_FORWARD_DEL: return "Delete";
			case KeyEvent.KEYCODE_MOVE_HOME: return "Home";
			case KeyEvent.KEYCODE_MOVE_END: return "End";
			case KeyEvent.KEYCODE_PAGE_UP: return "PageUp";
			case KeyEvent.KEYCODE_PAGE_DOWN: return "PageDown";
			case KeyEvent.KEYCODE_SHIFT_LEFT: return "ShiftLeft";
			case KeyEvent.KEYCODE_SHIFT_RIGHT: return "ShiftRight";
			case KeyEvent.KEYCODE_CTRL_LEFT: return "ControlLeft";
			case KeyEvent.KEYCODE_CTRL_RIGHT: return "ControlRight";
			case KeyEvent.KEYCODE_ALT_LEFT: return "AltLeft";
			case KeyEvent.KEYCODE_ALT_RIGHT: return "AltRight";
			case KeyEvent.KEYCODE_META_LEFT: return "MetaLeft";
			case KeyEvent.KEYCODE_META_RIGHT: return "MetaRight";
			default: return null;
		}
	}
}
