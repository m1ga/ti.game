package ti.game;

import android.app.Activity;

import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.view.TiUIView;

import ti.game.engine.Scene;

/**
 * The game canvas: createGameView({ backgroundColor: '#202030' }).
 *
 * Owns the native Scene, so sprites can be added before (or after) the view
 * is realized. Rendering runs continuously once the view is on screen.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class GameViewProxy extends TiViewProxy
{
	private final Scene scene = new Scene();
	private TiGameView gameView;

	@Override
	public TiUIView createView(Activity activity)
	{
		gameView = new TiGameView(this, scene);
		gameView.getLayoutParams().autoFillsWidth = true;
		gameView.getLayoutParams().autoFillsHeight = true;
		return gameView;
	}

	public Scene getScene()
	{
		return scene;
	}

	@Override
	public void handleCreationDict(org.appcelerator.kroll.KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("debug")) {
			scene.debugAll = org.appcelerator.titanium.util.TiConvert.toBoolean(options.get("debug"));
		}
	}

	/** Renders debug overlays (collision box, bounds, anchor) for every sprite. */
	@Kroll.getProperty
	public boolean getDebug()
	{
		return scene.debugAll;
	}

	@Kroll.setProperty
	public void setDebug(boolean value)
	{
		scene.debugAll = value;
	}

	@Kroll.method
	public void add(Object proxy)
	{
		if (proxy instanceof SpriteProxy) {
			scene.add(((SpriteProxy) proxy).getSprite());
		} else if (proxy instanceof EmitterProxy) {
			scene.addEmitter(((EmitterProxy) proxy).getEmitter());
		} else if (proxy instanceof RopeProxy) {
			scene.addRope(((RopeProxy) proxy).getRope());
		}
	}

	@Kroll.method
	public void remove(Object proxy)
	{
		if (proxy instanceof SpriteProxy) {
			scene.remove(((SpriteProxy) proxy).getSprite());
		} else if (proxy instanceof EmitterProxy) {
			scene.removeEmitter(((EmitterProxy) proxy).getEmitter());
		} else if (proxy instanceof RopeProxy) {
			scene.removeRope(((RopeProxy) proxy).getRope());
		}
	}

	@Kroll.method
	public void removeAllSprites()
	{
		scene.clear();
	}

	/**
	 * Native camera follow with dead-zones. Vertical is always active: the
	 * view scrolls when the sprite rises above `topMargin` (fraction of the
	 * visible height, default 0.33) or sinks below `bottomMargin` (default
	 * 0.7), clamped to `maxY` (default 0 — never scrolls below the start).
	 * Horizontal follow turns on when `leftMargin` and/or `rightMargin`
	 * (fractions of the visible width, defaults 0.35/0.65) are given.
	 * `smoothing` (0..1, default 0 = snap) eases the camera toward the
	 * target by that fraction of the remaining distance per 1/60 s.
	 * Each call resets unspecified options to their defaults.
	 */
	@Kroll.method
	public void follow(SpriteProxy spriteProxy, @Kroll.argument(optional = true) org.appcelerator.kroll.KrollDict options)
	{
		if (spriteProxy == null) {
			scene.followTarget = null;
			return;
		}
		scene.followTopFraction = 0.33f;
		scene.followBottomFraction = 0.7f;
		scene.followLeftFraction = -1f;
		scene.followRightFraction = 0.65f;
		scene.followSmoothing = 0f;
		scene.cameraMaxY = 0f;
		if (options != null) {
			if (options.containsKey("topMargin")) {
				scene.followTopFraction = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("topMargin"));
			}
			if (options.containsKey("bottomMargin")) {
				scene.followBottomFraction = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("bottomMargin"));
			}
			boolean horizontal = false;
			if (options.containsKey("leftMargin")) {
				scene.followLeftFraction = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("leftMargin"));
				horizontal = true;
			}
			if (options.containsKey("rightMargin")) {
				scene.followRightFraction = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("rightMargin"));
				horizontal = true;
			}
			if (horizontal && scene.followLeftFraction < 0f) {
				scene.followLeftFraction = 0.35f;
			}
			if (options.containsKey("smoothing")) {
				scene.followSmoothing = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("smoothing"));
			}
			if (options.containsKey("maxY")) {
				scene.cameraMaxY = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("maxY"));
			}
		}
		scene.followTarget = spriteProxy.getSprite();
	}

	/**
	 * Camera shake: gameView.shake({ strength: 14, duration: 400 }).
	 * strength in px, duration in ms; runs natively, only offsets the
	 * projection so follow/bounds/touches are unaffected.
	 */
	@Kroll.method
	public void shake(@Kroll.argument(optional = true) org.appcelerator.kroll.KrollDict options)
	{
		float strength = 12f;
		float duration = 400f;
		if (options != null) {
			if (options.containsKey("strength")) {
				strength = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("strength"));
			}
			if (options.containsKey("duration")) {
				duration = org.appcelerator.titanium.util.TiConvert.toFloat(options.get("duration"));
			}
		}
		scene.shake(strength, duration / 1000f);
	}

	/** Zoom, anchored on the view center (1 = no zoom, 2 = 2x). */
	@Kroll.getProperty
	public float getCameraScale()
	{
		return scene.cameraScale;
	}

	@Kroll.setProperty
	public void setCameraScale(float value)
	{
		scene.cameraScale = Math.max(0.05f, value);
	}

	/**
	 * Clamps the visible rect into a world rect:
	 * gameView.cameraBounds = { minX: 0, minY: -2000, maxX: 4000, maxY: H };
	 * null removes the bounds. Applied every frame, also without follow.
	 */
	@Kroll.setProperty
	public void setCameraBounds(org.appcelerator.kroll.KrollDict bounds)
	{
		cameraBoundsDict = bounds;
		if (bounds == null) {
			scene.cameraBoundsEnabled = false;
			return;
		}
		scene.boundsMinX = bounds.containsKey("minX")
			? org.appcelerator.titanium.util.TiConvert.toFloat(bounds.get("minX")) : -Float.MAX_VALUE;
		scene.boundsMinY = bounds.containsKey("minY")
			? org.appcelerator.titanium.util.TiConvert.toFloat(bounds.get("minY")) : -Float.MAX_VALUE;
		scene.boundsMaxX = bounds.containsKey("maxX")
			? org.appcelerator.titanium.util.TiConvert.toFloat(bounds.get("maxX")) : Float.MAX_VALUE;
		scene.boundsMaxY = bounds.containsKey("maxY")
			? org.appcelerator.titanium.util.TiConvert.toFloat(bounds.get("maxY")) : Float.MAX_VALUE;
		scene.cameraBoundsEnabled = true;
	}

	@Kroll.getProperty
	public org.appcelerator.kroll.KrollDict getCameraBounds()
	{
		return cameraBoundsDict;
	}

	private org.appcelerator.kroll.KrollDict cameraBoundsDict;

	@Kroll.method
	public void stopFollow()
	{
		scene.followTarget = null;
	}

	@Kroll.getProperty
	public float getCameraX()
	{
		return scene.cameraX;
	}

	@Kroll.setProperty
	public void setCameraX(float value)
	{
		scene.cameraX = value;
	}

	@Kroll.getProperty
	public float getCameraY()
	{
		return scene.cameraY;
	}

	@Kroll.setProperty
	public void setCameraY(float value)
	{
		scene.cameraY = value;
	}

	/** Manually pause the render loop (also happens on activity pause). */
	@Kroll.method
	public void pause()
	{
		if (gameView != null) {
			gameView.pauseRendering();
		}
	}

	@Kroll.method
	public void resume()
	{
		if (gameView != null) {
			gameView.resumeRendering();
		}
	}

	/** Rendered surface size in pixels — the scene coordinate space. */
	@Kroll.getProperty
	public int getSurfaceWidth()
	{
		return (gameView != null) ? gameView.getRenderer().surfaceWidth() : 0;
	}

	@Kroll.getProperty
	public int getSurfaceHeight()
	{
		return (gameView != null) ? gameView.getRenderer().surfaceHeight() : 0;
	}

	@Override
	public String getApiName()
	{
		return "ti.game.GameView";
	}
}
