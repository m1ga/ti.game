package ti.game.engine;

import android.content.Context;
import android.util.SparseArray;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.ViewConfiguration;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;

/**
 * Runs on the UI thread and drives all interaction natively: hit-testing,
 * drag and drop, pinch-to-scale and two-finger rotation. JS only receives
 * high-level events (tap, dragstart, throttled drag, dragend, pinch,
 * rotate) — never per-frame move traffic.
 *
 * Multi-touch: every pointer runs its own gesture, so several sprites can
 * be pressed/tapped/dragged simultaneously. A second finger that lands on
 * empty space (or on the sprite already held) instead modifies the held
 * sprite: pinch-to-scale and two-finger rotation.
 *
 * Touch coordinates map 1:1 onto the scene's pixel coordinate system.
 */
public class TouchController implements View.OnTouchListener
{
	private static final long DRAG_EVENT_INTERVAL_MS = 100; // ~10 Hz 'drag' events
	private static final long TAP_TIMEOUT_MS = 300;

	/** One finger's interaction with one sprite. */
	private static final class Gesture
	{
		final Sprite sprite;
		final float downX, downY;
		final long downTime;
		final float grabOffsetX, grabOffsetY;
		boolean dragging = false;
		long lastDragEventMs = 0;

		Gesture(Sprite sprite, float downX, float downY, long downTime)
		{
			this.sprite = sprite;
			this.downX = downX;
			this.downY = downY;
			this.downTime = downTime;
			this.grabOffsetX = downX - sprite.x;
			this.grabOffsetY = downY - sprite.y;
		}
	}

	private final Scene scene;
	private final KrollProxy viewProxy; // GameViewProxy — receives view-level press/tap/release
	private final ScaleGestureDetector scaleDetector;
	private final int touchSlop;

	private final SparseArray<Gesture> gestures = new SparseArray<>(); // by pointerId

	// View-level (first finger) state for the view tap
	private float downX, downY;
	private long downTime;

	// Two-finger pinch/rotate state: set while a modifier finger is down
	private Sprite modifierTarget;
	private boolean rotating = false;
	private float lastAngle = 0f;

	public TouchController(Context context, Scene scene, KrollProxy viewProxy)
	{
		this.scene = scene;
		this.viewProxy = viewProxy;
		this.touchSlop = ViewConfiguration.get(context).getScaledTouchSlop();
		this.scaleDetector = new ScaleGestureDetector(context, new ScaleGestureDetector.SimpleOnScaleGestureListener() {
			@Override
			public boolean onScale(ScaleGestureDetector detector)
			{
				Sprite s = modifierTarget;
				if (s != null && s.pinchable) {
					s.scaleX *= detector.getScaleFactor();
					s.scaleY *= detector.getScaleFactor();
					KrollDict data = new KrollDict();
					data.put("scaleX", s.scaleX);
					data.put("scaleY", s.scaleY);
					fire(s, "pinch", data);
					return true;
				}
				return false;
			}
		});
	}

	@Override
	public boolean onTouch(View view, MotionEvent event)
	{
		scaleDetector.onTouchEvent(event);

		switch (event.getActionMasked()) {
			case MotionEvent.ACTION_DOWN: {
				resetAll();
				// world space: hit-testing and drags must track camera + zoom
				downX = scene.screenToWorldX(event.getX());
				downY = scene.screenToWorldY(event.getY());
				downTime = event.getEventTime();
				pointerDown(event.getPointerId(0), downX, downY, downTime);
				fireOnView("press", downX, downY);
				return true;
			}

			case MotionEvent.ACTION_POINTER_DOWN: {
				int index = event.getActionIndex();
				float wx = scene.screenToWorldX(event.getX(index));
				float wy = scene.screenToWorldY(event.getY(index));
				boolean claimed = pointerDown(event.getPointerId(index), wx, wy, event.getEventTime());
				if (!claimed && event.getPointerCount() == 2) {
					// second finger on empty space (or the held sprite
					// itself) modifies the held sprite: pinch / rotate
					modifierTarget = heldSprite();
					if (modifierTarget != null && modifierTarget.rotatable) {
						rotating = true;
						lastAngle = angleBetween(event);
					}
				}
				return true;
			}

			case MotionEvent.ACTION_MOVE: {
				Sprite target = modifierTarget;
				if (rotating && event.getPointerCount() >= 2 && target != null) {
					float angle = angleBetween(event);
					target.rotation += angle - lastAngle;
					lastAngle = angle;
					KrollDict data = new KrollDict();
					data.put("rotation", target.rotation);
					fire(target, "rotate", data);
				}

				for (int i = 0; i < event.getPointerCount(); i++) {
					Gesture g = gestures.get(event.getPointerId(i));
					if (g == null || !g.sprite.draggable) {
						continue;
					}
					if (g.sprite == target) {
						continue; // two-finger gesture owns this sprite
					}
					drag(g, scene.screenToWorldX(event.getX(i)),
						scene.screenToWorldY(event.getY(i)), event.getEventTime());
				}
				return true;
			}

			case MotionEvent.ACTION_POINTER_UP: {
				int index = event.getActionIndex();
				finishGesture(event.getPointerId(index),
					scene.screenToWorldX(event.getX(index)),
					scene.screenToWorldY(event.getY(index)),
					event.getEventTime(), true);
				if (event.getPointerCount() <= 2) {
					rotating = false;
					modifierTarget = null;
				}
				return true;
			}

			case MotionEvent.ACTION_UP: {
				float upX = scene.screenToWorldX(event.getX());
				float upY = scene.screenToWorldY(event.getY());
				if (event.getEventTime() - downTime < TAP_TIMEOUT_MS
						&& distance(upX, upY, downX, downY) <= touchSlop) {
					fireOnView("tap", upX, upY);
				}
				fireOnView("release", upX, upY);
				finishGesture(event.getPointerId(0), upX, upY, event.getEventTime(), true);
				resetAll();
				return true;
			}

			case MotionEvent.ACTION_CANCEL: {
				fireOnView("release", scene.screenToWorldX(event.getX()), scene.screenToWorldY(event.getY()));
				for (int i = 0; i < gestures.size(); i++) {
					Gesture g = gestures.valueAt(i);
					if (g.dragging) {
						fire(g.sprite, "dragend", positionData(g.sprite));
					}
					fire(g.sprite, "release", positionData(g.sprite));
				}
				resetAll();
				return true;
			}
		}
		return false;
	}

	/** Hit-tests a new finger and claims the sprite (a new Gesture) if no
	 *  other finger holds it yet. Returns whether a sprite was claimed. */
	private boolean pointerDown(int pointerId, float wx, float wy, long time)
	{
		Sprite hit = scene.hitTest(wx, wy);
		if (hit == null || isClaimed(hit)) {
			return false;
		}
		gestures.put(pointerId, new Gesture(hit, wx, wy, time));
		KrollDict data = positionData(hit);
		data.put("touchX", wx);
		data.put("touchY", wy);
		fire(hit, "press", data);
		return true;
	}

	private void drag(Gesture g, float tx, float ty, long now)
	{
		Sprite s = g.sprite;
		if (!g.dragging && distance(tx, ty, g.downX, g.downY) > touchSlop) {
			g.dragging = true;
			s.dragged = true;
			s.clearPositionTweens();
			fire(s, "dragstart", positionData(s));
		}
		if (!g.dragging) {
			return;
		}
		float nx = tx - g.grabOffsetX;
		float ny = ty - g.grabOffsetY;
		// Clamp against any rope tethering this sprite here at the
		// source — the rope's own per-frame clamp would only pull it
		// back a frame later, which renders as a visible jump past the
		// rope end. The anchor is the fixed x/y, or the sprite at the
		// other end when a finger owns that one too (multi-touch: both
		// ends held, neither yields — see Rope.update). A free other
		// end is skipped: the rope tows it behind the drag instead.
		for (Rope r : scene.ropesSnapshot()) {
			if (r.maxLength <= 0f) {
				continue;
			}
			float ax, ay;
			if (r.tail == s && r.head == null) {
				ax = r.x;
				ay = r.y;
			} else if (r.tail == s && r.head != null && r.head.dragged) {
				ax = r.head.x;
				ay = r.head.y;
			} else if (r.head == s && r.tail != null && r.tail.dragged) {
				ax = r.tail.x;
				ay = r.tail.y;
			} else {
				continue;
			}
			float dx = nx - ax;
			float dy = ny - ay;
			float d = (float) Math.sqrt(dx * dx + dy * dy);
			if (d > r.maxLength && d > 1e-5f) {
				nx = ax + dx / d * r.maxLength;
				ny = ay + dy / d * r.maxLength;
			}
		}
		s.x = nx;
		s.y = ny;
		// The finger owns the sprite: keep physics from
		// accumulating velocity underneath the drag.
		s.velocityX = 0f;
		s.velocityY = 0f;
		if (now - g.lastDragEventMs >= DRAG_EVENT_INTERVAL_MS) {
			g.lastDragEventMs = now;
			fire(s, "drag", positionData(s));
		}
	}

	private void finishGesture(int pointerId, float upX, float upY, long time, boolean allowTap)
	{
		Gesture g = gestures.get(pointerId);
		if (g == null) {
			return;
		}
		gestures.remove(pointerId);
		Sprite s = g.sprite;
		s.dragged = false;
		if (g.dragging) {
			fire(s, "dragend", positionData(s));
		} else if (allowTap && time - g.downTime < TAP_TIMEOUT_MS
				&& distance(upX, upY, g.downX, g.downY) <= touchSlop) {
			KrollDict data = positionData(s);
			data.put("touchX", upX);
			data.put("touchY", upY);
			fire(s, "tap", data);
		}
		fire(s, "release", positionData(s));
	}

	private void resetAll()
	{
		for (int i = 0; i < gestures.size(); i++) {
			gestures.valueAt(i).sprite.dragged = false;
		}
		gestures.clear();
		modifierTarget = null;
		rotating = false;
	}

	private boolean isClaimed(Sprite sprite)
	{
		for (int i = 0; i < gestures.size(); i++) {
			if (gestures.valueAt(i).sprite == sprite) {
				return true;
			}
		}
		return false;
	}

	/** The sprite held by the earliest still-active finger, if any. */
	private Sprite heldSprite()
	{
		return gestures.size() > 0 ? gestures.valueAt(0).sprite : null;
	}

	private static float angleBetween(MotionEvent event)
	{
		double dx = event.getX(1) - event.getX(0);
		double dy = event.getY(1) - event.getY(0);
		return (float) Math.toDegrees(Math.atan2(dy, dx));
	}

	private static float distance(float x0, float y0, float x1, float y1)
	{
		float dx = x1 - x0;
		float dy = y1 - y0;
		return (float) Math.sqrt(dx * dx + dy * dy);
	}

	private static KrollDict positionData(Sprite s)
	{
		KrollDict data = new KrollDict();
		data.put("x", s.x);
		data.put("y", s.y);
		return data;
	}

	/** View-level input: fires on the game view for every touch, whether or
	 *  not it hit a sprite — e.g. tap-anywhere controls. */
	private void fireOnView(String event, float x, float y)
	{
		if (viewProxy != null && viewProxy.hasListeners(event)) {
			KrollDict data = new KrollDict();
			data.put("x", x);
			data.put("y", y);
			viewProxy.fireEvent(event, data);
		}
	}

	private static void fire(Sprite sprite, String event, KrollDict data)
	{
		KrollProxy proxy = sprite.proxy;
		if (proxy != null && proxy.hasListeners(event)) {
			proxy.fireEvent(event, data);
		}
	}
}
