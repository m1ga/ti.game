package ti.game;

import android.app.Activity;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollFunction;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.proxy.TiViewProxy;
import org.appcelerator.titanium.util.TiConvert;
import org.appcelerator.titanium.view.TiUIView;

import android.graphics.Color;

import ti.game.engine.PostEffect;
import ti.game.engine.ParticleEmitter;
import ti.game.engine.Rope;
import ti.game.engine.Scene;
import ti.game.engine.ScreenOverlay;
import ti.game.engine.Sprite;

/**
 * The game canvas: createGameView({ backgroundColor: '#202030' }).
 *
 * Owns the native Scene, so sprites can be added before (or after) the view
 * is realized. Rendering runs continuously once the view is on screen.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class GameViewProxy extends TiViewProxy
	implements Scene.TimerListener
{
	private final Scene scene = new Scene();
	private TiGameView gameView;
	private int maxFps = 0;
	private final ConcurrentHashMap<Integer, KrollFunction> timerCallbacks = new ConcurrentHashMap<>();

	public GameViewProxy()
	{
		scene.timerListener = this;
	}

	@Override
	public TiUIView createView(Activity activity)
	{
		gameView = new TiGameView(this, scene);
		gameView.getLayoutParams().autoFillsWidth = true;
		gameView.getLayoutParams().autoFillsHeight = true;
		gameView.getRenderer().setMaxFps(maxFps);
		// Titanium only delivers eventListenerAdded once the proxy has a view
		// (KrollProxy drops MSG_LISTENER_ADDED while modelListener is null), so
		// a listener attached in the natural order — create the view, wire it
		// up, then add it to the window — is never announced. Ask directly
		// now that the view exists, or measuring stays off forever.
		refreshStats();
		return gameView;
	}

	// TiViewProxy only nulls its own view reference; dropping ours too is
	// what lets the GLSurfaceView (and the Activity it holds) get collected
	// while JS keeps the proxy alive across a window close.
	@Override
	public void releaseViews()
	{
		super.releaseViews();
		gameView = null;
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
			applyDebug(options.get("debug"));
		}
		if (options.containsKey("cameraEffect")) {
			setCameraEffect(TiConvert.toString(options.get("cameraEffect")));
		}
		if (options.containsKey("cameraTint")) {
			setCameraTint(TiConvert.toString(options.get("cameraTint")));
		}
		if (options.containsKey("cameraEffectIntensity")) {
			scene.effectIntensity = Values.ratio(options.get("cameraEffectIntensity"), scene.effectIntensity);
		}
		if (options.containsKey("timeScale")) {
			setTimeScale(options.get("timeScale"));
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
	public void setCameraEffectIntensity(Object value)
	{
		scene.effectIntensity = Values.ratio(value, scene.effectIntensity);
	}

	// Developer aids, both off by default:
	//   debug: true                        collision shapes for every sprite
	//   debug: { hitbox: true }            the same, spelled out
	//   debug: { hud: true }               performance HUD in the default corner
	//   debug: { hud: 'topRight' }         ...in the corner you pick
	//   debug: { hud: true, hudFont: f }   ...in the game's own typeface
	// The HUD key name is not settled with the maintainer yet; it appears
	// here and in the iOS twin, nowhere else.
	private static final String KEY_HITBOX = "hitbox";
	private static final String KEY_HUD = "hud";
	private static final String KEY_HUD_FONT = "hudFont";

	/**
	 * Reads back the normalized form, whichever form was written:
	 * { hitbox: <boolean>, hud: false | 'topLeft' | ... }.
	 */
	@Kroll.getProperty
	public Object getDebug()
	{
		org.appcelerator.kroll.KrollDict value = new org.appcelerator.kroll.KrollDict();
		value.put(KEY_HITBOX, scene.debugAll);
		value.put(KEY_HUD, scene.hud.enabled ? ScreenOverlay.cornerName(scene.hud.corner) : Boolean.FALSE);
		return value;
	}

	@Kroll.setProperty
	public void setDebug(Object value)
	{
		applyDebug(value);
	}

	private void applyDebug(Object value)
	{
		if (value instanceof java.util.Map) {
			java.util.Map<?, ?> options = (java.util.Map<?, ?>) value;
			scene.debugAll = TiConvert.toBoolean(options.get(KEY_HITBOX), false);
			applyHud(options.get(KEY_HUD));
			Object fontValue = options.get(KEY_HUD_FONT);
			scene.hud.font = (fontValue instanceof FontProxy)
				? ((FontProxy) fontValue).getFont() : null;
		} else {
			// debug: true — the shorthand that predates the object form
			scene.debugAll = TiConvert.toBoolean(value, false);
			applyHud(null);
			scene.hud.font = null;
		}
		refreshStats();
	}

	private void applyHud(Object value)
	{
		if (value == null) {
			scene.hud.enabled = false;
			return;
		}
		if (value instanceof String) {
			scene.hud.corner = ScreenOverlay.cornerFromName((String) value, ScreenOverlay.TOP_LEFT);
			scene.hud.enabled = true;
			return;
		}
		scene.hud.enabled = TiConvert.toBoolean(value, false);
	}

	// Measuring costs nothing while nobody is looking: the flag only goes
	// up for the HUD or for a live 'performance' listener.
	private boolean performanceListening = false;

	private void refreshStats()
	{
		// hasListeners() is the truth; performanceListening only caches what
		// the callbacks told us, and those do not fire before the view exists.
		scene.stats.enabled = scene.hud.enabled
			|| performanceListening
			|| hasListeners("performance");
	}

	@Override
	public void eventListenerAdded(String event, int count, org.appcelerator.kroll.KrollProxy proxy)
	{
		super.eventListenerAdded(event, count, proxy);
		if ("performance".equals(event)) {
			performanceListening = count > 0;
			refreshStats();
		}
	}

	@Override
	public void eventListenerRemoved(String event, int count, org.appcelerator.kroll.KrollProxy proxy)
	{
		super.eventListenerRemoved(event, count, proxy);
		if ("performance".equals(event)) {
			performanceListening = count > 0;
			refreshStats();
		}
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
	// Object, not SpriteProxy: a typed proxy parameter makes the generated
	// JNI binding pass non-proxy values (a plain JS object arrives as a
	// HashMap) straight into the typed slot, aborting the app on the JNI
	// type check — see SpriteProxy.attachTo.
	@Kroll.method
	public void follow(Object target, @Kroll.argument(optional = true) KrollDict options)
	{
		if (!(target instanceof SpriteProxy)) {
			scene.followTarget = null;
			return;
		}
		SpriteProxy spriteProxy = (SpriteProxy) target;
		scene.followTopFraction = 0.33f;
		scene.followBottomFraction = 0.7f;
		scene.followLeftFraction = -1f;
		scene.followRightFraction = 0.65f;
		scene.followSmoothing = 0f;
		scene.cameraMaxY = 0f;
		if (options != null) {
			if (options.containsKey("topMargin")) {
				scene.followTopFraction = Values.ratio(options.get("topMargin"), scene.followTopFraction);
			}
			if (options.containsKey("bottomMargin")) {
				scene.followBottomFraction = Values.ratio(options.get("bottomMargin"), scene.followBottomFraction);
			}
			boolean horizontal = false;
			if (options.containsKey("leftMargin")) {
				scene.followLeftFraction = Values.ratio(options.get("leftMargin"), scene.followLeftFraction);
				horizontal = true;
			}
			if (options.containsKey("rightMargin")) {
				scene.followRightFraction = Values.ratio(options.get("rightMargin"), scene.followRightFraction);
				horizontal = true;
			}
			if (horizontal && scene.followLeftFraction < 0f) {
				scene.followLeftFraction = 0.35f;
			}
			if (options.containsKey("smoothing")) {
				scene.followSmoothing = Values.ratio(options.get("smoothing"), scene.followSmoothing);
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
	public void setTimeScale(Object value)
	{
		scene.timeScale = Math.max(0f, Values.ratio(value, scene.timeScale));
	}

	/** Zoom, anchored on the view center (1 = no zoom, 2 = 2x). */
	@Kroll.getProperty
	public float getCameraScale()
	{
		return scene.cameraScale;
	}

	@Kroll.setProperty
	public void setCameraScale(Object value)
	{
		scene.cameraScale = Math.max(0.05f, Values.ratio(value, scene.cameraScale));
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

	// --- Game-clock timers ------------------------------------------------

	/**
	 * gameView.after(ms, callback): runs the callback once after `ms` of
	 * game time — it stretches with slow motion and freezes at
	 * timeScale 0, unlike setTimeout. Returns an id for cancelTimer().
	 * Without a callback, the view fires a 'timer' event with the id.
	 */
	@Kroll.method
	public int after(float ms, @Kroll.argument(optional = true) Object callback)
	{
		return addGameTimer(ms, callback, false);
	}

	/** gameView.every(ms, callback): like after(), repeating until cancelled. */
	@Kroll.method
	public int every(float ms, @Kroll.argument(optional = true) Object callback)
	{
		return addGameTimer(ms, callback, true);
	}

	@Kroll.method
	public void cancelTimer(int id)
	{
		scene.cancelTimer(id);
		timerCallbacks.remove(id);
	}

	private int addGameTimer(float ms, Object callback, boolean repeats)
	{
		int id = scene.addTimer(ms / 1000f, repeats);
		if (callback instanceof KrollFunction) {
			timerCallbacks.put(id, (KrollFunction) callback);
		}
		return id;
	}

	/** GL thread — callAsync/fireEvent both hand off to the JS thread. */
	@Override
	public void onTimer(int id, boolean repeats)
	{
		KrollFunction callback = repeats ? timerCallbacks.get(id) : timerCallbacks.remove(id);
		if (callback != null) {
			KrollDict data = new KrollDict();
			data.put("id", id);
			callback.callAsync(getKrollObject(), new Object[] { data });
		} else if (hasListeners("timer")) {
			KrollDict data = new KrollDict();
			data.put("id", id);
			fireEvent("timer", data);
		}
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

	/**
	 * gameView.findPath(from, to, options): grid A* over the visible
	 * sprites whose collisionGroup is in options.groups (omit for any
	 * tagged sprite). `from`/`to` are { x, y } world points; returns an
	 * array of { x, y } waypoints ready for sprite.followPath(), or null
	 * when no route exists. Options: cellSize (grid resolution in px,
	 * default 32), clearance (extra obstacle inflation in px — about half
	 * the walker's width keeps it from scraping corners), bounds
	 * ({ minX, minY, maxX, maxY } search rect, default the surface),
	 * diagonals (default true), simplify (line-of-sight waypoint
	 * reduction, default true). A blocked start or goal snaps to the
	 * nearest free cell a few cells out, so tapping an obstacle walks to
	 * its edge. A discrete query like raycast — run it on taps and AI
	 * timers, not per frame.
	 */
	@Kroll.method
	public Object[] findPath(KrollDict from, KrollDict to,
							 @Kroll.argument(optional = true) KrollDict options)
	{
		if (from == null || to == null) {
			return null;
		}
		float cellSize = 32f;
		float clearance = 0f;
		boolean diagonals = true;
		boolean simplify = true;
		Set<String> groupSet = null;
		float minX = 0f;
		float minY = 0f;
		float maxX = scene.worldWidth;
		float maxY = scene.worldHeight;
		if (options != null) {
			cellSize = TiConvert.toFloat(options.get("cellSize"), 32f);
			clearance = TiConvert.toFloat(options.get("clearance"), 0f);
			diagonals = TiConvert.toBoolean(options.get("diagonals"), true);
			simplify = TiConvert.toBoolean(options.get("simplify"), true);
			if (options.get("groups") instanceof Object[]) {
				groupSet = new HashSet<>();
				for (Object group : (Object[]) options.get("groups")) {
					groupSet.add(TiConvert.toString(group));
				}
			}
			KrollDict bounds = options.getKrollDict("bounds");
			if (bounds != null) {
				minX = TiConvert.toFloat(bounds.get("minX"), minX);
				minY = TiConvert.toFloat(bounds.get("minY"), minY);
				maxX = TiConvert.toFloat(bounds.get("maxX"), maxX);
				maxY = TiConvert.toFloat(bounds.get("maxY"), maxY);
			}
		}
		float[] points = scene.findPath(
			TiConvert.toFloat(from.get("x"), 0f), TiConvert.toFloat(from.get("y"), 0f),
			TiConvert.toFloat(to.get("x"), 0f), TiConvert.toFloat(to.get("y"), 0f),
			groupSet, cellSize, clearance, minX, minY, maxX, maxY, diagonals, simplify);
		if (points == null) {
			return null;
		}
		Object[] result = new Object[points.length / 2];
		for (int i = 0; i < result.length; i++) {
			KrollDict point = new KrollDict();
			point.put("x", points[i * 2]);
			point.put("y", points[i * 2 + 1]);
			result[i] = point;
		}
		return result;
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
