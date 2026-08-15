package ti.game.engine;

import android.content.Context;
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
 * Touch coordinates map 1:1 onto the scene's pixel coordinate system.
 */
public class TouchController implements View.OnTouchListener
{
	private static final long DRAG_EVENT_INTERVAL_MS = 100; // ~10 Hz 'drag' events
	private static final long TAP_TIMEOUT_MS = 300;

	private final Scene scene;
	private final KrollProxy viewProxy; // GameViewProxy — receives view-level press/tap/release
	private final ScaleGestureDetector scaleDetector;
	private final int touchSlop;

	private Sprite activeSprite;
	private int activePointerId = MotionEvent.INVALID_POINTER_ID;
	private float grabOffsetX, grabOffsetY;
	private float downX, downY;
	private long downTime;
	private boolean dragging = false;
	private long lastDragEventMs = 0;

	// Two-finger rotation state
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
				Sprite s = activeSprite;
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
				// world space: hit-testing and drags must track camera + zoom
				downX = scene.screenToWorldX(event.getX());
				downY = scene.screenToWorldY(event.getY());
				downTime = event.getEventTime();
				activePointerId = event.getPointerId(0);
				dragging = false;
				rotating = false;
				activeSprite = scene.hitTest(downX, downY);
				if (activeSprite != null) {
					grabOffsetX = downX - activeSprite.x;
					grabOffsetY = downY - activeSprite.y;
					KrollDict data = positionData(activeSprite);
					data.put("touchX", downX);
					data.put("touchY", downY);
					fire(activeSprite, "press", data);
				}
				fireOnView("press", downX, downY);
				return true;
			}

			case MotionEvent.ACTION_POINTER_DOWN: {
				if (event.getPointerCount() == 2 && activeSprite != null && activeSprite.rotatable) {
					rotating = true;
					lastAngle = angleBetween(event);
				}
				return true;
			}

			case MotionEvent.ACTION_MOVE: {
				Sprite s = activeSprite;

				if (rotating && event.getPointerCount() >= 2 && s != null) {
					float angle = angleBetween(event);
					s.rotation += angle - lastAngle;
					lastAngle = angle;
					KrollDict data = new KrollDict();
					data.put("rotation", s.rotation);
					fire(s, "rotate", data);
				}

				// Single-finger drag
				if (s != null && s.draggable && event.getPointerCount() == 1) {
					int pointerIndex = event.findPointerIndex(activePointerId);
					if (pointerIndex < 0) {
						return true;
					}
					float tx = scene.screenToWorldX(event.getX(pointerIndex));
					float ty = scene.screenToWorldY(event.getY(pointerIndex));

					if (!dragging && distance(tx, ty, downX, downY) > touchSlop) {
						dragging = true;
						s.dragged = true;
						s.clearPositionTweens();
						fire(s, "dragstart", positionData(s));
					}
					if (dragging) {
						float nx = tx - grabOffsetX;
						float ny = ty - grabOffsetY;
						// Clamp against any fixed-anchor rope tethering this
						// sprite here at the source — the rope's own
						// per-frame clamp would only pull it back a frame
						// later, which renders as a visible jump past the
						// rope end. Sprite-headed ropes are skipped: those
						// tow the head sprite behind the drag instead.
						for (Rope r : scene.ropesSnapshot()) {
							if (r.tail == s && r.maxLength > 0f && r.head == null) {
								float ax = r.x;
								float ay = r.y;
								float dx = nx - ax;
								float dy = ny - ay;
								float d = (float) Math.sqrt(dx * dx + dy * dy);
								if (d > r.maxLength && d > 1e-5f) {
									nx = ax + dx / d * r.maxLength;
									ny = ay + dy / d * r.maxLength;
								}
							}
						}
						s.x = nx;
						s.y = ny;
						// The finger owns the sprite: keep physics from
						// accumulating velocity underneath the drag.
						s.velocityX = 0f;
						s.velocityY = 0f;
						long now = event.getEventTime();
						if (now - lastDragEventMs >= DRAG_EVENT_INTERVAL_MS) {
							lastDragEventMs = now;
							fire(s, "drag", positionData(s));
						}
					}
				}
				return true;
			}

			case MotionEvent.ACTION_POINTER_UP: {
				if (event.getPointerCount() <= 2) {
					rotating = false;
				}
				return true;
			}

			case MotionEvent.ACTION_UP: {
				float upX = scene.screenToWorldX(event.getX());
				float upY = scene.screenToWorldY(event.getY());
				if (!rotating
						&& event.getEventTime() - downTime < TAP_TIMEOUT_MS
						&& distance(upX, upY, downX, downY) <= touchSlop) {
					fireOnView("tap", upX, upY);
				}
				fireOnView("release", upX, upY);
				Sprite s = activeSprite;
				if (s != null) {
					if (dragging) {
						fire(s, "dragend", positionData(s));
					} else if (!rotating
							&& event.getEventTime() - downTime < TAP_TIMEOUT_MS
							&& distance(upX, upY, downX, downY) <= touchSlop) {
						KrollDict data = positionData(s);
						data.put("touchX", upX);
						data.put("touchY", upY);
						fire(s, "tap", data);
					}
					fire(s, "release", positionData(s));
				}
				resetGesture();
				return true;
			}

			case MotionEvent.ACTION_CANCEL: {
				fireOnView("release", scene.screenToWorldX(event.getX()), scene.screenToWorldY(event.getY()));
				Sprite s = activeSprite;
				if (s != null) {
					if (dragging) {
						fire(s, "dragend", positionData(s));
					}
					fire(s, "release", positionData(s));
				}
				resetGesture();
				return true;
			}
		}
		return false;
	}

	private void resetGesture()
	{
		Sprite s = activeSprite;
		if (s != null) {
			s.dragged = false;
		}
		activeSprite = null;
		activePointerId = MotionEvent.INVALID_POINTER_ID;
		dragging = false;
		rotating = false;
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
