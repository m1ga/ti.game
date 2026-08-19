package ti.game;

import android.app.Activity;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiUIView;

import android.graphics.Color;

import ti.game.engine.PostEffect;
import ti.game.engine.ParticleEmitter;
import ti.game.engine.Rope;
import ti.game.engine.Scene;
import ti.game.engine.Sprite;

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
	private int maxFps = 0;

	@Override
	public TiUIView createView(Activity activity)
	{
		gameView = new TiGameView(this, scene);
		gameView.getLayoutParams().autoFillsWidth = true;
		gameView.getLayoutParams().autoFillsHeight = true;
		gameView.getRenderer().setMaxFps(maxFps);
		return gameView;
	}

	public Scene getScene()
	{
		return scene;
	}

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("debug")) {
			scene.debugAll = TiConvert.toBoolean(options.get("debug"), false);
		}
		if (options.containsKey("cameraEffect")) {
			setCameraEffect(TiConvert.toString(options.get("cameraEffect")));
		}
		if (options.containsKey("cameraTint")) {
			setCameraTint(TiConvert.toString(options.get("cameraTint")));
		}
		if (options.containsKey("cameraEffectIntensity")) {
			scene.effectIntensity = TiConvert.toFloat(options.get("cameraEffectIntensity"));
		}
		if (options.containsKey("timeScale")) {
			setTimeScale(TiConvert.toFloat(options.get("timeScale"), 1f));
		}
		if (options.containsKey("maxFps")) {
			setMaxFps(TiConvert.toInt(options.get("maxFps")));
		}
	}

	/** Frame rate cap (e.g. 60 on a 120 Hz display); 0 = display refresh rate. */
	@Kroll.setProperty
	public void setMaxFps(int value)
	{
		maxFps = Math.max(0, value);
		if (gameView != null) {
			gameView.getRenderer().setMaxFps(maxFps);
		}
	}

	@Kroll.getProperty
	public int getMaxFps()
	{
		return maxFps;
	}

	// --- Fullscreen camera effects ---------------------------------------

	/** 'none', 'tint' or 'glitch' — applied to the whole rendered scene. */
	@Kroll.setProperty
	public void setCameraEffect(String value)
	{
		if ("tint".equals(value)) {
			scene.cameraEffect = PostEffect.TINT;
		} else if ("glitch".equals(value)) {
			scene.cameraEffect = PostEffect.GLITCH;
		} else {
			scene.cameraEffect = PostEffect.NONE;
		}
	}

	@Kroll.getProperty
	public String getCameraEffect()
	{
		switch (scene.cameraEffect) {
			case PostEffect.TINT:
				return "tint";
			case PostEffect.GLITCH:
				return "glitch";
			default:
				return "none";
		}
	}

	/** Tint color for the 'tint' effect, e.g. '#3f6' or '#33ff66'. */
	@Kroll.setProperty
	public void setCameraTint(String value)
	{
		cameraTint = value;
		if (value == null) {
			scene.effectTintR = 1f;
			scene.effectTintG = 1f;
			scene.effectTintB = 1f;
			return;
		}
		try {
			int color = Color.parseColor(expandShortHex(value));
			scene.effectTintR = Color.red(color) / 255f;
			scene.effectTintG = Color.green(color) / 255f;
			scene.effectTintB = Color.blue(color) / 255f;
		} catch (IllegalArgumentException e) {
			// keep previous tint
		}
	}

	@Kroll.getProperty
	public String getCameraTint()
	{
		return cameraTint;
	}

	private String cameraTint;

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

	/** Effect strength 0..1 (tint mix / glitch amount). */
	@Kroll.getProperty
	public float getCameraEffectIntensity()
	{
		return scene.effectIntensity;
	}

	@Kroll.setProperty
	public void setCameraEffectIntensity(float value)
	{
		scene.effectIntensity = value;
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
		if (proxy instanceof Object[]) {
			addAll((Object[]) proxy);
			return;
		}
		if (proxy instanceof SpriteProxy) {
			scene.add(((SpriteProxy) proxy).getSprite());
		} else if (proxy instanceof EmitterProxy) {
			scene.addEmitter(((EmitterProxy) proxy).getEmitter());
		} else if (proxy instanceof RopeProxy) {
			scene.addRope(((RopeProxy) proxy).getRope());
		}
	}

	private void addAll(Object[] proxies)
	{
		List<Sprite> sprites = new ArrayList<>();
		List<ParticleEmitter> emitters = new ArrayList<>();
		List<Rope> ropes = new ArrayList<>();
		for (Object proxy : proxies) {
			if (proxy instanceof SpriteProxy) {
				sprites.add(((SpriteProxy) proxy).getSprite());
			} else if (proxy instanceof EmitterProxy) {
				emitters.add(((EmitterProxy) proxy).getEmitter());
			} else if (proxy instanceof RopeProxy) {
				ropes.add(((RopeProxy) proxy).getRope());
			}
		}
		scene.addAll(sprites, emitters, ropes);
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
	public void follow(SpriteProxy spriteProxy, @Kroll.argument(optional = true) KrollDict options)
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
				scene.followTopFraction = TiConvert.toFloat(options.get("topMargin"));
			}
			if (options.containsKey("bottomMargin")) {
				scene.followBottomFraction = TiConvert.toFloat(options.get("bottomMargin"));
			}
			boolean horizontal = false;
			if (options.containsKey("leftMargin")) {
				scene.followLeftFraction = TiConvert.toFloat(options.get("leftMargin"));
				horizontal = true;
			}
			if (options.containsKey("rightMargin")) {
				scene.followRightFraction = TiConvert.toFloat(options.get("rightMargin"));
				horizontal = true;
			}
			if (horizontal && scene.followLeftFraction < 0f) {
				scene.followLeftFraction = 0.35f;
			}
			if (options.containsKey("smoothing")) {
				scene.followSmoothing = TiConvert.toFloat(options.get("smoothing"));
			}
			if (options.containsKey("maxY")) {
				scene.cameraMaxY = TiConvert.toFloat(options.get("maxY"));
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
	public void shake(@Kroll.argument(optional = true) KrollDict options)
	{
		float strength = 12f;
		float duration = 400f;
		if (options != null) {
			if (options.containsKey("strength")) {
				strength = TiConvert.toFloat(options.get("strength"));
			}
			if (options.containsKey("duration")) {
				duration = TiConvert.toFloat(options.get("duration"));
			}
		}
		scene.shake(strength, duration / 1000f);
	}

	/** Global time multiplier: 1 = normal, 0.5 = slow motion, 0 freezes
	 *  the whole scene while rendering and touch keep running (pause
	 *  menus, hit-stop). Negative values clamp to 0. */
	@Kroll.getProperty
	public float getTimeScale()
	{
		return scene.timeScale;
	}

	@Kroll.setProperty
	public void setTimeScale(float value)
	{
		scene.timeScale = Math.max(0f, value);
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
	public void setCameraBounds(KrollDict bounds)
	{
		cameraBoundsDict = bounds;
		if (bounds == null) {
			scene.cameraBoundsEnabled = false;
			return;
		}
		scene.boundsMinX = bounds.containsKey("minX")
			? TiConvert.toFloat(bounds.get("minX")) : -Float.MAX_VALUE;
		scene.boundsMinY = bounds.containsKey("minY")
			? TiConvert.toFloat(bounds.get("minY")) : -Float.MAX_VALUE;
		scene.boundsMaxX = bounds.containsKey("maxX")
			? TiConvert.toFloat(bounds.get("maxX")) : Float.MAX_VALUE;
		scene.boundsMaxY = bounds.containsKey("maxY")
			? TiConvert.toFloat(bounds.get("maxY")) : Float.MAX_VALUE;
		scene.cameraBoundsEnabled = true;
	}

	@Kroll.getProperty
	public KrollDict getCameraBounds()
	{
		return cameraBoundsDict;
	}

	private KrollDict cameraBoundsDict;

	@Kroll.method
	public void stopFollow()
	{
		scene.followTarget = null;
	}

	/**
	 * gameView.raycast(x0, y0, x1, y1, groups): one-shot nearest-hit query
	 * along the segment, against visible sprites whose collisionGroup is
	 * in `groups` (omit for any tagged sprite). Returns null for a clear
	 * ray, else { x, y, distance, group, sprite, normal: { x, y } }.
	 * Line of sight, ground probes, hitscan weapons — a discrete query,
	 * not something to poll every frame from JS.
	 */
	@Kroll.method
	public KrollDict raycast(float x0, float y0, float x1, float y1,
							 @Kroll.argument(optional = true) Object[] groups)
	{
		// Kroll binds a trailing Object[] parameter as varargs, so a JS
		// groups array arrives wrapped as the single first element —
		// unwrap it (raycast(..., ['a', 'b']) and raycast(..., 'a', 'b')
		// both work).
		if (groups != null && groups.length == 1 && groups[0] instanceof Object[]) {
			groups = (Object[]) groups[0];
		}
		Set<String> groupSet = null;
		if (groups != null && groups.length > 0) {
			groupSet = new HashSet<>();
			for (Object group : groups) {
				groupSet.add(TiConvert.toString(group));
			}
		}
		float[] out = new float[5];
		Sprite hit = scene.raycast(x0, y0, x1, y1, groupSet, out);
		if (hit == null) {
			return null;
		}
		KrollDict data = new KrollDict();
		data.put("x", out[0]);
		data.put("y", out[1]);
		data.put("distance", out[2]);
		KrollDict normal = new KrollDict();
		normal.put("x", out[3]);
		normal.put("y", out[4]);
		data.put("normal", normal);
		data.put("group", hit.collisionGroup);
		data.put("sprite", hit.proxy);
		return data;
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
