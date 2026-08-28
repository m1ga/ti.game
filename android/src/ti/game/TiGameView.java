package ti.game;

import android.app.Activity;
import android.graphics.Color;
import android.opengl.GLSurfaceView;
import android.view.ViewGroup;
import android.view.ViewParent;

import java.lang.ref.WeakReference;
import java.util.ArrayList;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.common.TiMessenger;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.TiBaseActivity;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.TiLifecycle;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiUIView;

import ti.game.engine.GamepadController;
import ti.game.engine.Scene;
import ti.game.engine.SceneRenderer;
import ti.game.engine.TouchController;

/**
 * TiUIView wrapping the GLSurfaceView. The renderer runs continuously on
 * the GL thread (the native game loop); the TouchController handles all
 * interaction on the UI thread. Hooks Titanium's activity lifecycle into
 * GLSurfaceView.onPause/onResume.
 */
public final class TiGameView extends TiUIView implements TiLifecycle.OnLifecycleEvent
{
	private static final Object activeViewsLock = new Object();
	private static final ArrayList<WeakReference<TiGameView>> activeViews = new ArrayList<>();

	private final GLSurfaceView glView;
	private final SceneRenderer renderer;
	private final Scene scene;
	private final TouchController touchController;
	private final GamepadController gamepadController;
	private final TiBaseActivity lifecycleActivity;
	private volatile boolean renderingShutdown;

	/**
	 * Titanium LiveView replaces the JS runtime without always releasing the
	 * previous native view hierarchy. Java statics survive that soft restart,
	 * so a new module generation can explicitly retire any old GL threads.
	 */
	static void beginRuntimeGeneration()
	{
		ArrayList<TiGameView> staleViews = new ArrayList<>();
		synchronized (activeViewsLock) {
			for (WeakReference<TiGameView> reference : activeViews) {
				TiGameView view = reference.get();
				if (view != null) {
					staleViews.add(view);
				}
			}
			activeViews.clear();
		}

		for (TiGameView view : staleViews) {
			view.shutdownRendering();
		}
	}

	private static void registerActiveView(TiGameView view)
	{
		synchronized (activeViewsLock) {
			for (int i = activeViews.size() - 1; i >= 0; i--) {
				if (activeViews.get(i).get() == null) {
					activeViews.remove(i);
				}
			}
			activeViews.add(new WeakReference<>(view));
		}
	}

	private static void unregisterActiveView(TiGameView view)
	{
		synchronized (activeViewsLock) {
			for (int i = activeViews.size() - 1; i >= 0; i--) {
				TiGameView activeView = activeViews.get(i).get();
				if (activeView == null || activeView == view) {
					activeViews.remove(i);
				}
			}
		}
	}

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
		// The surface is in real pixels; the HUD sizes itself in dp so it
		// reads the same on a 1x tablet and a 3x phone
		renderer.setScreenScale(activity.getResources().getDisplayMetrics().density);
		glView.setRenderer(renderer);
		touchController = new TouchController(activity, scene, proxy);
		glView.setOnTouchListener(touchController);
		// Bluetooth/USB game controllers — captured at the activity window so
		// they work no matter which view holds focus
		gamepadController = new GamepadController(activity, proxy);
		setNativeView(glView);

		if (activity instanceof TiBaseActivity) {
			lifecycleActivity = (TiBaseActivity) activity;
			lifecycleActivity.addOnLifecycleEventListener(this);
		} else {
			lifecycleActivity = null;
		}
		registerActiveView(this);
	}

	public SceneRenderer getRenderer()
	{
		return renderer;
	}

	public GamepadController getGamepadController()
	{
		return gamepadController;
	}

	public void pauseRendering()
	{
		if (!renderingShutdown) {
			glView.onPause();
		}
	}

	public void resumeRendering()
	{
		if (!renderingShutdown) {
			glView.onResume();
		}
	}

	/** Stops and detaches the native surface exactly once. */
	public void shutdownRendering()
	{
		synchronized (this) {
			if (renderingShutdown) {
				return;
			}
			renderingShutdown = true;
		}

		unregisterActiveView(this);
		if (lifecycleActivity != null) {
			lifecycleActivity.removeOnLifecycleEventListener(this);
		}
		gamepadController.release();

		Runnable detachSurface = new Runnable() {
			@Override
			public void run()
			{
				glView.setOnTouchListener(null);
				ViewParent parent = glView.getParent();
				if (parent instanceof ViewGroup) {
					// GLSurfaceView stops its GLThread in onDetachedFromWindow().
					((ViewGroup) parent).removeView(glView);
				} else {
					glView.onPause();
				}
			}
		};

		if (TiApplication.isUIThread()) {
			detachSurface.run();
		} else {
			TiMessenger.postOnMain(detachSurface);
		}
	}

	@Override
	public void release()
	{
		shutdownRendering();
		super.release();
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
		if (!renderingShutdown) {
			glView.onResume();
			updateDisplayRefreshRate();
			ti.game.engine.SoundEngine.notifyActivityResumed();
		}
	}

	/** The baseline the debug HUD's dropped-frame count is measured
	 *  against. Display.getRefreshRate is a UI-thread call, so it is
	 *  pushed into the renderer instead of pulled from the GL thread. */
	private void updateDisplayRefreshRate()
	{
		android.view.Display display = glView.getDisplay();
		if (display != null) {
			renderer.setDisplayRefreshRate(display.getRefreshRate());
		}
	}

	@Override
	public void onPause(Activity activity)
	{
		if (!renderingShutdown) {
			glView.onPause();
			ti.game.engine.SoundEngine.notifyActivityPaused();
			// key-up events are lost while in the background — don't leave
			// a direction held down in JS
			gamepadController.releaseAll();
		}
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
		shutdownRendering();
	}
}
