package ti.game;

import android.app.Activity;
import android.graphics.Color;
import android.opengl.GLSurfaceView;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.titanium.TiBaseActivity;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.TiLifecycle;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiUIView;

import ti.game.engine.Scene;
import ti.game.engine.SceneRenderer;
import ti.game.engine.TouchController;

/**
 * TiUIView wrapping the GLSurfaceView. The renderer runs continuously on
 * the GL thread (the native game loop); the TouchController handles all
 * interaction on the UI thread. Hooks Titanium's activity lifecycle into
 * GLSurfaceView.onPause/onResume.
 */
public class TiGameView extends TiUIView implements TiLifecycle.OnLifecycleEvent
{
	private final GLSurfaceView glView;
	private final SceneRenderer renderer;
	private final Scene scene;
	private final TouchController touchController;

	public TiGameView(TiViewProxy proxy, Scene scene)
	{
		super(proxy);
		this.scene = scene;

		Activity activity = proxy.getActivity();
		glView = new GLSurfaceView(activity);
		glView.setEGLContextClientVersion(2);
		glView.setEGLConfigChooser(8, 8, 8, 8, 0, 0);
		glView.setPreserveEGLContextOnPause(true);
		renderer = new SceneRenderer(scene, proxy);
		glView.setRenderer(renderer);
		touchController = new TouchController(activity, scene, proxy);
		glView.setOnTouchListener(touchController);
		setNativeView(glView);

		if (activity instanceof TiBaseActivity) {
			((TiBaseActivity) activity).addOnLifecycleEventListener(this);
		}
	}

	public SceneRenderer getRenderer()
	{
		return renderer;
	}

	public void pauseRendering()
	{
		glView.onPause();
	}

	public void resumeRendering()
	{
		glView.onResume();
	}

	// TiUIView installs its own OnTouchListener during processProperties
	// (registerForTouch), which would silently replace the game's
	// TouchController and kill all sprite interaction. Keep ours in charge;
	// standard Titanium touch/click events are not supported on this view —
	// use the sprite events (press/tap/drag.../pinch/rotate) instead.
	@Override
	protected void registerForTouch(final android.view.View touchable)
	{
		if (touchable != null) {
			touchable.setOnTouchListener(touchController);
		}
	}

	@Override
	protected void registerTouchEvents(final android.view.View touchable)
	{
		if (touchable != null) {
			touchable.setOnTouchListener(touchController);
		}
	}

	@Override
	public void processProperties(KrollDict d)
	{
		if (d.containsKey(TiC.PROPERTY_BACKGROUND_COLOR)) {
			applyBackgroundColor(TiConvert.toString(d.get(TiC.PROPERTY_BACKGROUND_COLOR)));
			// Consumed by the GL clear color; keep it away from TiUIView's
			// background drawable handling underneath the surface.
			d.remove(TiC.PROPERTY_BACKGROUND_COLOR);
		}
		super.processProperties(d);
	}

	@Override
	public void propertyChanged(String key, Object oldValue, Object newValue, org.appcelerator.kroll.KrollProxy proxy)
	{
		if (TiC.PROPERTY_BACKGROUND_COLOR.equals(key)) {
			applyBackgroundColor(TiConvert.toString(newValue));
			return;
		}
		super.propertyChanged(key, oldValue, newValue, proxy);
	}

	private void applyBackgroundColor(String value)
	{
		if (value == null) {
			return;
		}
		try {
			int color = Color.parseColor(expandShortHex(value));
			scene.bgAlpha = Color.alpha(color) / 255f;
			scene.bgRed = Color.red(color) / 255f;
			scene.bgGreen = Color.green(color) / 255f;
			scene.bgBlue = Color.blue(color) / 255f;
		} catch (IllegalArgumentException e) {
			// leave previous clear color
		}
	}

	/** Color.parseColor can't handle Titanium's '#rgb' shorthand. */
	private static String expandShortHex(String value)
	{
		if (value.length() == 4 && value.charAt(0) == '#') {
			return new String(new char[] {
				'#',
				value.charAt(1), value.charAt(1),
				value.charAt(2), value.charAt(2),
				value.charAt(3), value.charAt(3)
			});
		}
		return value;
	}

	// --- TiLifecycle.OnLifecycleEvent ------------------------------------

	@Override
	public void onCreate(Activity activity, android.os.Bundle savedInstanceState)
	{
	}

	@Override
	public void onResume(Activity activity)
	{
		glView.onResume();
	}

	@Override
	public void onPause(Activity activity)
	{
		glView.onPause();
	}

	@Override
	public void onStart(Activity activity)
	{
	}

	@Override
	public void onStop(Activity activity)
	{
	}

	@Override
	public void onDestroy(Activity activity)
	{
	}
}
