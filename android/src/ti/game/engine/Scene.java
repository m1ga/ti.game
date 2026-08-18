package ti.game.engine;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.Set;

/**
 * The native scene graph: an ordered list of sprites plus background color.
 * Shared between the JS thread (add/remove/property writes), the UI thread
 * (touch hit-testing) and the GL thread (update + draw), so all list access
 * goes through `lock`.
 */
public class Scene
{
	public final Object lock = new Object();

	private final List<Sprite> sprites = new ArrayList<>();
	private final List<ParticleEmitter> emitters = new ArrayList<>();
	private final List<Rope> ropes = new ArrayList<>();
	private volatile boolean zOrderDirty = false;

	/** Renders debug overlays for every sprite (GameView.debug = { hitbox: true }). */
	public volatile boolean debugAll = false;

	/** On-screen performance HUD (GameView.debug = { hud: 'topRight' }).
	 *  Lives here because three threads reach it: the JS thread configures
	 *  it, the GL thread lays it out, the UI thread hit-tests it. */
	public final DebugHud hud = new DebugHud();

	/** Render telemetry behind the HUD and the 'performance' event. Off
	 *  until one of the two asks for it; see FrameStats. */
	public final FrameStats stats = new FrameStats();

	/** Fading skid-mark segments emitted by carMode sprites (skidMarks).
	 *  Drawn above sprites with zIndex <= 0 and below everything else. */
	public final SkidTrail skidTrail = new SkidTrail();

	// Surface size in pixels, kept current by the renderer — the world
	// bounds used for wrapAround sprites.
	public volatile float worldWidth = 0f;
	public volatile float worldHeight = 0f;

	// Camera: world-space offset of the view's top-left corner (at scale
	// 1). The renderer shifts the projection by it and the touch
	// controller maps screen touches back into world space.
	public volatile float cameraX = 0f;
	public volatile float cameraY = 0f;

	// Zoom, anchored on the view center: the visible region shrinks to
	// surface/cameraScale around the center of the scale-1 view rect.
	public volatile float cameraScale = 1f;

	// Global time multiplier: 1 = normal, 0.5 = slow motion, 0 = frozen.
	// Scales the dt fed to sprites, emitters, ropes, camera and shake —
	// rendering and touch input keep running, so 0 works as a pause that
	// still draws (menus, hit-stop juice).
	public volatile float timeScale = 1f;

	// Native dead-zone follow. Vertical is always active while a target is
	// set (topFraction/bottomFraction of the visible height); horizontal
	// only when followLeftFraction >= 0. cameraMaxY = legacy vertical
	// clamp (0 = never below the start). followSmoothing 0 = snap, else
	// the fraction of the remaining distance covered per 1/60 s.
	public volatile Sprite followTarget;
	public volatile float followTopFraction = 0.33f;
	public volatile float followBottomFraction = 0.7f;
	public volatile float followLeftFraction = -1f;
	public volatile float followRightFraction = 0.65f;
	public volatile float followSmoothing = 0f;
	public volatile float cameraMaxY = 0f;

	// Camera bounds: clamp the visible rect into this world rect.
	public volatile boolean cameraBoundsEnabled = false;
	public volatile float boundsMinX, boundsMinY, boundsMaxX, boundsMaxY;

	// Camera shake, requested from any thread, animated on the GL thread.
	private volatile float pendingShakeStrength = -1f;
	private volatile float pendingShakeDuration = 0f;
	private float shakeStrength, shakeDuration, shakeRemaining, shakeTime;
	public float shakeOffsetX, shakeOffsetY; // GL thread (renderer) only

	/** Kicks off (or restarts) a camera shake. strength px, duration s. */
	public void shake(float strength, float duration)
	{
		pendingShakeDuration = duration;
		pendingShakeStrength = strength;
	}

	// --- Game-clock timers ------------------------------------------------
	// Ticked with the timeScale-scaled dt, so they slow down with the scene
	// and freeze at timeScale 0 — unlike JS setTimeout. Added from the JS
	// thread, fired from the GL thread through the listener (discrete,
	// never per frame).

	/** Receives expired timer ids on the GL thread. */
	public interface TimerListener {
		void onTimer(int id, boolean repeats);
	}

	public volatile TimerListener timerListener;

	private static final class GameTimer
	{
		final int id;
		final float interval; // seconds, game time
		final boolean repeats;
		float remaining;

		GameTimer(int id, float interval, boolean repeats)
		{
			this.id = id;
			this.interval = interval;
			this.repeats = repeats;
			this.remaining = interval;
		}
	}

	private final List<GameTimer> timers = new ArrayList<>();
	private int nextTimerId = 1;

	/** Schedules a timer on the game clock; returns its cancel id. */
	public int addTimer(float seconds, boolean repeats)
	{
		synchronized (timers) {
			GameTimer timer = new GameTimer(nextTimerId++, Math.max(0.001f, seconds), repeats);
			timers.add(timer);
			return timer.id;
		}
	}

	public void cancelTimer(int id)
	{
		synchronized (timers) {
			for (Iterator<GameTimer> it = timers.iterator(); it.hasNext();) {
				if (it.next().id == id) {
					it.remove();
					return;
				}
			}
		}
	}

	/** Ticks timers with scaled dt; fires listeners outside the lock. */
	private void updateTimers(float dt)
	{
		if (dt <= 0f) {
			return; // frozen (timeScale 0) — game time stands still
		}
		List<GameTimer> fired = null;
		synchronized (timers) {
			for (Iterator<GameTimer> it = timers.iterator(); it.hasNext();) {
				GameTimer timer = it.next();
				timer.remaining -= dt;
				if (timer.remaining <= 0f) {
					if (fired == null) {
						fired = new ArrayList<>();
					}
					fired.add(timer);
					if (timer.repeats) {
						// at most one fire per frame; after a long stall,
						// restart the interval instead of bursting
						timer.remaining += timer.interval;
						if (timer.remaining < 0f) {
							timer.remaining = timer.interval;
						}
					} else {
						it.remove();
					}
				}
			}
		}
		TimerListener listener = timerListener;
		if (fired != null && listener != null) {
			for (GameTimer timer : fired) {
				listener.onTimer(timer.id, timer.repeats);
			}
		}
	}

	/** World x of the visible rect's left edge (accounts for zoom). */
	public float viewOriginX()
	{
		float s = Math.max(0.0001f, cameraScale);
		return cameraX + (worldWidth - worldWidth / s) / 2f;
	}

	public float viewOriginY()
	{
		float s = Math.max(0.0001f, cameraScale);
		return cameraY + (worldHeight - worldHeight / s) / 2f;
	}

	/** Maps a surface touch position into world space (camera + zoom). */
	public float screenToWorldX(float sx)
	{
		return viewOriginX() + sx / Math.max(0.0001f, cameraScale);
	}

	public float screenToWorldY(float sy)
	{
		return viewOriginY() + sy / Math.max(0.0001f, cameraScale);
	}

	/** Maps a world position back to surface coordinates (screenFixed sprites). */
	public float worldToScreenX(float wx)
	{
		return (wx - viewOriginX()) * Math.max(0.0001f, cameraScale);
	}

	public float worldToScreenY(float wy)
	{
		return (wy - viewOriginY()) * Math.max(0.0001f, cameraScale);
	}

	public volatile float bgRed = 0f;
	public volatile float bgGreen = 0f;
	public volatile float bgBlue = 0f;
	public volatile float bgAlpha = 1f;

	// Fullscreen camera effect (JS thread writes, GL thread reads): the
	// scene renders into an offscreen texture and PostEffect draws it to
	// the screen through the effect shader. NONE renders directly.
	public volatile int cameraEffect = PostEffect.NONE;
	public volatile float effectTintR = 1f;
	public volatile float effectTintG = 1f;
	public volatile float effectTintB = 1f;
	public volatile float effectIntensity = 1f; // 0..1 mix/strength

	private static final Comparator<Sprite> BY_Z = new Comparator<Sprite>() {
		@Override
		public int compare(Sprite a, Sprite b)
		{
			int z = Integer.compare(a.zIndex, b.zIndex);
			if (z != 0) {
				return z;
			}
			if (a.ySort && b.ySort) {
				return Float.compare(bottomEdge(a), bottomEdge(b));
			}
			return 0;
		}
	};

	private static float bottomEdge(Sprite s)
	{
		return s.y + s.drawHeight() * Math.abs(s.scaleY) * (1f - s.anchorY);
	}

	private volatile boolean hasYSort = false;

	/** Re-scan for ySort sprites; while any exist, draw order re-sorts every frame. */
	public void recomputeYSort()
	{
		synchronized (lock) {
			for (Sprite s : sprites) {
				if (s.ySort) {
					hasYSort = true;
					return;
				}
			}
			hasYSort = false;
		}
	}

	// This scene's built-in pixel font, shared by every default-font text
	// sprite in the view — one instance per scene, because the font's GL
	// texture belongs to this view's context (a global one would go stale
	// when another GameView creates its own context).
	private volatile BitmapFont defaultFont;

	private synchronized BitmapFont defaultFont()
	{
		BitmapFont font = defaultFont;
		if (font == null) {
			font = DefaultFont.create();
			defaultFont = font;
		}
		return font;
	}

	/** Points default-font text at this scene's own font instance. */
	public void resolveTextFont(Sprite sprite)
	{
		if (sprite instanceof TextSprite && ((TextSprite) sprite).usesDefaultFont) {
			((TextSprite) sprite).setFont(defaultFont());
		}
	}

	public void add(Sprite sprite)
	{
		synchronized (lock) {
			if (!sprites.contains(sprite)) {
				sprites.add(sprite);
				sprite.scene = this;
				resolveTextFont(sprite);
				zOrderDirty = true;
				if (sprite.ySort) {
					hasYSort = true;
				}
			}
		}
	}

	/** Adds a group in one protected scene mutation. */
	public void addAll(List<Sprite> newSprites, List<ParticleEmitter> newEmitters, List<Rope> newRopes)
	{
		synchronized (lock) {
			boolean spritesAdded = false;
			for (Sprite sprite : newSprites) {
				if (sprite != null && !sprites.contains(sprite)) {
					sprites.add(sprite);
					sprite.scene = this;
					resolveTextFont(sprite);
					spritesAdded = true;
					if (sprite.ySort) {
						hasYSort = true;
					}
				}
			}
			for (ParticleEmitter emitter : newEmitters) {
				if (emitter != null && !emitters.contains(emitter)) {
					emitters.add(emitter);
				}
			}
			for (Rope rope : newRopes) {
				if (rope != null && !ropes.contains(rope)) {
					ropes.add(rope);
				}
			}
			if (spritesAdded) {
				zOrderDirty = true;
			}
		}
	}

	public void remove(Sprite sprite)
	{
		synchronized (lock) {
			removeWithAttachments(sprite);
		}
	}

	/**
	 * Removes a sprite and, recursively, every sprite attached to it — a
	 * name tag or health bar never outlives its owner, and a chain (a hat
	 * on the tag) goes with it. Cycle-safe: a sprite no longer in the
	 * list is skipped. Caller holds `lock`.
	 */
	private void removeWithAttachments(Sprite sprite)
	{
		if (!sprites.remove(sprite)) {
			return;
		}
		sprite.scene = null;
		sprite.attachTarget = null;
		sprite.attachOpacity = 1f;
		List<Sprite> attached = null;
		for (Sprite s : sprites) {
			if (s.attachTarget == sprite) {
				if (attached == null) {
					attached = new ArrayList<>();
				}
				attached.add(s);
			}
		}
		if (attached != null) {
			for (Sprite s : attached) {
				removeWithAttachments(s);
			}
		}
	}

	public void clear()
	{
		synchronized (lock) {
			for (Sprite s : sprites) {
				s.scene = null;
				s.attachTarget = null;
				s.attachOpacity = 1f;
			}
			sprites.clear();
		}
	}

	public void markZOrderDirty()
	{
		zOrderDirty = true;
	}

	public void addEmitter(ParticleEmitter emitter)
	{
		synchronized (lock) {
			if (!emitters.contains(emitter)) {
				emitters.add(emitter);
			}
		}
	}

	public void removeEmitter(ParticleEmitter emitter)
	{
		synchronized (lock) {
			emitters.remove(emitter);
		}
	}

	/** Snapshot sorted by zIndex (emitters are few; sorted every call). */
	public List<ParticleEmitter> emittersSnapshot()
	{
		synchronized (lock) {
			List<ParticleEmitter> copy = new ArrayList<>(emitters);
			Collections.sort(copy, BY_EMITTER_Z);
			return copy;
		}
	}

	private static final Comparator<ParticleEmitter> BY_EMITTER_Z = new Comparator<ParticleEmitter>() {
		@Override
		public int compare(ParticleEmitter a, ParticleEmitter b)
		{
			return Integer.compare(a.zIndex, b.zIndex);
		}
	};

	public void addRope(Rope rope)
	{
		synchronized (lock) {
			if (!ropes.contains(rope)) {
				ropes.add(rope);
			}
		}
	}

	public void removeRope(Rope rope)
	{
		synchronized (lock) {
			ropes.remove(rope);
		}
	}

	/** Snapshot sorted by zIndex (ropes are few; sorted every call). */
	public List<Rope> ropesSnapshot()
	{
		synchronized (lock) {
			List<Rope> copy = new ArrayList<>(ropes);
			Collections.sort(copy, BY_ROPE_Z);
			return copy;
		}
	}

	private static final Comparator<Rope> BY_ROPE_Z = new Comparator<Rope>() {
		@Override
		public int compare(Rope a, Rope b)
		{
			return Integer.compare(a.zIndex, b.zIndex);
		}
	};

	/** Snapshot in draw order (back to front). Caller holds no lock. */
	public List<Sprite> snapshot()
	{
		synchronized (lock) {
			if (zOrderDirty || hasYSort) {
				Collections.sort(sprites, BY_Z);
				zOrderDirty = false;
			}
			return new ArrayList<>(sprites);
		}
	}

	private final float[] aabbA = new float[4];
	private final float[] aabbB = new float[4];
	private final float[] centerA = new float[2];
	private final float[] centerB = new float[2];

	// sweptHit result: entry time in 0..1, entry axis (0 = x, 1 = y)
	private final float[] boxA = new float[5];   // oriented hitbox: cx, cy, hx, hy, radians
	private final float[] boxB = new float[5];
	private final float[] satAxes = new float[8];
	private final float[] contact = new float[3]; // nx, ny, penetration

	// Allowed penetration, in pixels. A body resting on a solid is pulled
	// into it by gravity every frame — at 1400 px/s² and 60 fps that is
	// 0.39 px of sink — and shoving it back out in full, 60 times a second,
	// is what makes a settled pile tremble. Overlaps under this are left
	// alone; the closing velocity is still cancelled, so the sink can never
	// grow past it. Big enough to swallow a frame of gravity, small enough
	// to stay invisible.
	private static final float SLOP = 0.5f;
	private final float[] sweptResult = new float[2];

	/**
	 * Swept AABB: does a point moving from (cx, cy) by (dx, dy) this frame
	 * cross the box? Callers inflate the box by the mover's half extents
	 * (Minkowski sum), turning box-vs-box sweeping into this segment test
	 * (slab method). Catches fast movers that would tunnel straight
	 * through thin targets between frames. GL thread only.
	 */
	/** Segment vs circle, same frame as the caller: smallest t in [0,1], or
	 *  -1 when it misses. Starting inside counts as t = 0. */
	private float segmentVsCircle(float px, float py, float dx, float dy,
								  float cx, float cy, float radius)
	{
		float fx = px - cx;
		float fy = py - cy;
		if (fx * fx + fy * fy <= radius * radius) {
			return 0f;
		}
		float a = dx * dx + dy * dy;
		float b = 2f * (fx * dx + fy * dy);
		float c = fx * fx + fy * fy - radius * radius;
		float disc = b * b - 4f * a * c;
		if (a < 1e-6f || disc < 0f) {
			return -1f;
		}
		float t = (-b - (float) Math.sqrt(disc)) / (2f * a);
		return (t >= 0f && t <= 1f) ? t : -1f;
	}

	private boolean sweptHit(float cx, float cy, float dx, float dy,
							 float minX, float minY, float maxX, float maxY)
	{
		return segmentVsAabb(cx, cy, dx, dy, minX, minY, maxX, maxY, sweptResult);
	}

	/** The slab test itself, writing {entry time, entry axis} into result —
	 *  static so raycast() can run it from the JS thread with its own
	 *  buffer, never racing the GL thread's sweptResult. */
	private static boolean segmentVsAabb(float cx, float cy, float dx, float dy,
										 float minX, float minY, float maxX, float maxY,
										 float[] result)
	{
		float tmin = 0f;
		float tmax = 1f;
		float axis = 0f;
		if (dx > -1e-6f && dx < 1e-6f) {
			if (cx < minX || cx > maxX) {
				return false;
			}
		} else {
			float t1 = (minX - cx) / dx;
			float t2 = (maxX - cx) / dx;
			if (t1 > t2) {
				float t = t1;
				t1 = t2;
				t2 = t;
			}
			if (t1 > tmin) {
				tmin = t1;
			}
			if (t2 < tmax) {
				tmax = t2;
			}
			if (tmin > tmax) {
				return false;
			}
		}
		if (dy > -1e-6f && dy < 1e-6f) {
			if (cy < minY || cy > maxY) {
				return false;
			}
		} else {
			float t1 = (minY - cy) / dy;
			float t2 = (maxY - cy) / dy;
			if (t1 > t2) {
				float t = t1;
				t1 = t2;
				t2 = t;
			}
			if (t1 > tmin) {
				tmin = t1;
				axis = 1f;
			}
			if (t2 < tmax) {
				tmax = t2;
			}
			if (tmin > tmax) {
				return false;
			}
		}
		result[0] = tmin;
		result[1] = axis;
		return true;
	}

	/**
	 * One-shot segment query from (x0, y0) to (x1, y1) against every
	 * visible sprite carrying a collisionGroup in `groups` (null or empty
	 * = any tagged sprite). Returns the nearest hit sprite with
	 * {x, y, distance, normalX, normalY} written into `out`, or null for
	 * a clear ray. Rect hitboxes use the slab test on their AABB, circle
	 * hitboxes an exact ray/circle intersection; screenFixed sprites are
	 * skipped (they live in surface, not world, coordinates). A ray that
	 * starts inside a hitbox reports that sprite at distance 0.
	 *
	 * Safe from any thread — it's meant for discrete JS-initiated checks
	 * (line of sight on an AI timer, ground probes, hitscan weapons), not
	 * per-frame polling, and allocates its own scratch instead of sharing
	 * the GL thread's buffers.
	 */
	public Sprite raycast(float x0, float y0, float x1, float y1,
						  Set<String> groups, float[] out)
	{
		float dx = x1 - x0;
		float dy = y1 - y0;
		float rayLength = (float) Math.hypot(dx, dy);
		float[] box = new float[4];
		float[] rayBox = new float[5];
		float[] center = new float[2];
		float[] entry = new float[2];
		float bestT = Float.MAX_VALUE;
		Sprite best = null;
		float bestNormalX = 0f;
		float bestNormalY = 0f;
		for (Sprite s : snapshot()) {
			String group = s.collisionGroup;
			if (group == null || !s.visible || s.screenFixed
					|| (groups != null && !groups.isEmpty() && !groups.contains(group))) {
				continue;
			}
			if (s.circleHitbox) {
				// Ray vs circle: solve |P0 + t*d - C|^2 = r^2 for the
				// smallest t in [0, 1]
				s.hitCenter(center);
				float r = s.hitRadius();
				float fx = x0 - center[0];
				float fy = y0 - center[1];
				float t;
				if (fx * fx + fy * fy <= r * r) {
					t = 0f; // started inside
				} else {
					float a = dx * dx + dy * dy;
					float b = 2f * (fx * dx + fy * dy);
					float c = fx * fx + fy * fy - r * r;
					float disc = b * b - 4f * a * c;
					if (a < 1e-6f || disc < 0f) {
						continue;
					}
					t = (-b - (float) Math.sqrt(disc)) / (2f * a);
					if (t < 0f || t > 1f) {
						continue;
					}
				}
				if (t < bestT) {
					bestT = t;
					best = s;
					float hx = x0 + dx * t;
					float hy = y0 + dy * t;
					float nl = (float) Math.hypot(hx - center[0], hy - center[1]);
					bestNormalX = (nl > 1e-6f) ? (hx - center[0]) / nl : 0f;
					bestNormalY = (nl > 1e-6f) ? (hy - center[1]) / nl : 0f;
				}
			} else if (s.circleHitbox == false && s.obbHitbox) {
				// Ray vs a turned rect: take the ray into the box's frame,
				// run the same slab test, rotate the normal back out
				s.hitBox(rayBox);
				float bc = (float) Math.cos(rayBox[4]);
				float bs = (float) Math.sin(rayBox[4]);
				float rx = x0 - rayBox[0];
				float ry = y0 - rayBox[1];
				float lx = rx * bc + ry * bs;
				float ly = -rx * bs + ry * bc;
				float ldx = dx * bc + dy * bs;
				float ldy = -dx * bs + dy * bc;
				if (!segmentVsAabb(lx, ly, ldx, ldy,
						-rayBox[2], -rayBox[3], rayBox[2], rayBox[3], entry)) {
					continue;
				}
				if (entry[0] < bestT) {
					bestT = entry[0];
					best = s;
					float lnx, lny;
					if (entry[1] == 0f) {
						lnx = (ldx > 0f) ? -1f : (ldx < 0f) ? 1f : 0f;
						lny = 0f;
					} else {
						lnx = 0f;
						lny = (ldy > 0f) ? -1f : (ldy < 0f) ? 1f : 0f;
					}
					bestNormalX = lnx * bc - lny * bs;
					bestNormalY = lnx * bs + lny * bc;
				}
			} else {
				s.computeAABB(box);
				if (!segmentVsAabb(x0, y0, dx, dy, box[0], box[1], box[2], box[3], entry)) {
					continue;
				}
				if (entry[0] < bestT) {
					bestT = entry[0];
					best = s;
					if (entry[1] == 0f) {
						bestNormalX = (dx > 0f) ? -1f : (dx < 0f) ? 1f : 0f;
						bestNormalY = 0f;
					} else {
						bestNormalX = 0f;
						bestNormalY = (dy > 0f) ? -1f : (dy < 0f) ? 1f : 0f;
					}
				}
			}
		}
		if (best == null) {
			return null;
		}
		out[0] = x0 + dx * bestT;
		out[1] = y0 + dy * bestT;
		out[2] = rayLength * bestT;
		out[3] = bestNormalX;
		out[4] = bestNormalY;
		return best;
	}

	/**
	 * Grid A* path query (gameView.findPath): rasterizes the visible
	 * sprites whose collisionGroup is in `groups` (null/empty = any tagged
	 * sprite) into a blocked/free grid inside the bounds rect, inflated by
	 * `clearance` px, and returns simplified waypoints as a flat
	 * {x0, y0, x1, y1, ...} array, or null when no route exists. Like
	 * raycast(), a discrete JS-initiated query, safe from any thread.
	 */
	public float[] findPath(float startX, float startY, float goalX, float goalY,
							Set<String> groups, float cellSize, float clearance,
							float minX, float minY, float maxX, float maxY,
							boolean diagonals, boolean simplify)
	{
		return Pathfinder.find(snapshot(), groups, startX, startY, goalX, goalY,
			cellSize, clearance, minX, minY, maxX, maxY, diagonals, simplify);
	}

	/**
	 * Path-of-travel overlap test for swept sprites: did the mover's box
	 * cross the target's box at any point this frame? Relative motion, so
	 * a fast target can't slip past a slow bullet either.
	 */
	private boolean sweptShapesOverlap(Sprite s, Sprite other)
	{
		float dx = s.frameDeltaX - other.frameDeltaX;
		float dy = s.frameDeltaY - other.frameDeltaY;
		if (dx * dx + dy * dy < 1e-4f) {
			return false;
		}
		s.computeAABB(aabbA);
		other.computeAABB(aabbB);
		float hw = (aabbA[2] - aabbA[0]) / 2f;
		float hh = (aabbA[3] - aabbA[1]) / 2f;
		float cx = (aabbA[0] + aabbA[2]) / 2f - dx; // center at frame start
		float cy = (aabbA[1] + aabbA[3]) / 2f - dy;
		return sweptHit(cx, cy, dx, dy,
			aabbB[0] - hw, aabbB[1] - hh, aabbB[2] + hw, aabbB[3] + hh);
	}

	/** Shape-aware overlap test (rect/rect, circle/circle, circle/rect,
	 *  and either of those against a rect that turns with its sprite). */
	private boolean shapesOverlap(Sprite a, Sprite b)
	{
		if (a.obbHitbox || b.obbHitbox) {
			if (a.circleHitbox || b.circleHitbox) {
				Sprite circle = a.circleHitbox ? a : b;
				Sprite box = a.circleHitbox ? b : a;
				circle.hitCenter(centerA);
				box.hitBox(boxB);
				// overlap only needs the yes/no, so the contact normal is moot here
				return circleVsObb(centerA[0], centerA[1], circle.hitRadius(), boxB, 0f, 0f, contact);
			}
			a.hitBox(boxA);
			b.hitBox(boxB);
			return obbVsObb(boxA, boxB, contact);
		}
		if (a.circleHitbox && b.circleHitbox) {
			a.hitCenter(centerA);
			b.hitCenter(centerB);
			float dx = centerB[0] - centerA[0];
			float dy = centerB[1] - centerA[1];
			float r = a.hitRadius() + b.hitRadius();
			return dx * dx + dy * dy < r * r;
		}
		if (a.circleHitbox || b.circleHitbox) {
			Sprite circle = a.circleHitbox ? a : b;
			Sprite rect = a.circleHitbox ? b : a;
			circle.hitCenter(centerA);
			rect.computeAABB(aabbB);
			float closestX = Math.min(Math.max(centerA[0], aabbB[0]), aabbB[2]);
			float closestY = Math.min(Math.max(centerA[1], aabbB[1]), aabbB[3]);
			float dx = centerA[0] - closestX;
			float dy = centerA[1] - closestY;
			float r = circle.hitRadius();
			return dx * dx + dy * dy < r * r;
		}
		a.computeAABB(aabbA);
		b.computeAABB(aabbB);
		return aabbA[0] < aabbB[2] && aabbA[2] > aabbB[0]
			&& aabbA[1] < aabbB[3] && aabbA[3] > aabbB[1];
	}

	/** Ticks physics, animations and tweens, then checks collisions. GL thread. */
	public void update(float dt)
	{
		dt *= Math.max(0f, timeScale);
		List<Sprite> list = snapshot();
		for (Sprite s : list) {
			s.update(dt);
		}
		for (ParticleEmitter e : emittersSnapshot()) {
			e.update(dt);
		}
		// Ropes after sprites, so a dragged/physics-moved head is current
		for (Rope rope : ropesSnapshot()) {
			rope.update(dt);
		}
		skidTrail.update(dt);
		updateTimers(dt);
		wrapSprites(list);
		resolveSolids(list);
		applyAttachments(list);
		checkCollisions(list);
		updateCamera(dt);
		updateShake(dt);
	}

	/** Dead-zone follow + bounds, after physics so the camera never lags. */
	private void updateCamera(float dt)
	{
		updateFollow(dt);
		applyCameraBounds();
	}

	private void updateFollow(float dt)
	{
		Sprite target = followTarget;
		float scale = Math.max(0.0001f, cameraScale);
		float visibleH = worldHeight / scale;
		if (target == null || visibleH <= 0f) {
			return;
		}
		// vertical dead-zone (fractions of the visible height)
		float top = visibleH * followTopFraction;
		float bottom = visibleH * followBottomFraction;
		float screenY = target.y - viewOriginY();
		float desiredY = cameraY;
		if (screenY < top) {
			desiredY += screenY - top;
		} else if (screenY > bottom) {
			desiredY += screenY - bottom;
		}
		if (desiredY > cameraMaxY) {
			desiredY = cameraMaxY;
		}
		// horizontal dead-zone, only when enabled via follow options
		float desiredX = cameraX;
		if (followLeftFraction >= 0f) {
			float visibleW = worldWidth / scale;
			float left = visibleW * followLeftFraction;
			float right = visibleW * followRightFraction;
			float screenX = target.x - viewOriginX();
			if (screenX < left) {
				desiredX += screenX - left;
			} else if (screenX > right) {
				desiredX += screenX - right;
			}
		}
		float smoothing = followSmoothing;
		if (smoothing > 0f) {
			// time-corrected lerp: `smoothing` of the remaining distance per 1/60 s
			float factor = 1f - (float) Math.pow(1f - Math.min(0.99f, smoothing), dt * 60f);
			cameraX += (desiredX - cameraX) * factor;
			cameraY += (desiredY - cameraY) * factor;
		} else {
			cameraX = desiredX;
			cameraY = desiredY;
		}
	}

	/** Keeps the visible rect inside the bounds rect (centers if smaller). */
	private void applyCameraBounds()
	{
		if (!cameraBoundsEnabled) {
			return;
		}
		float scale = Math.max(0.0001f, cameraScale);
		float visibleW = worldWidth / scale;
		float visibleH = worldHeight / scale;
		float originX = viewOriginX();
		float originY = viewOriginY();
		float maxOriginX = boundsMaxX - visibleW;
		float maxOriginY = boundsMaxY - visibleH;
		float clampedX = (maxOriginX < boundsMinX)
			? (boundsMinX + maxOriginX) / 2f
			: Math.min(Math.max(originX, boundsMinX), maxOriginX);
		float clampedY = (maxOriginY < boundsMinY)
			? (boundsMinY + maxOriginY) / 2f
			: Math.min(Math.max(originY, boundsMinY), maxOriginY);
		cameraX += clampedX - originX;
		cameraY += clampedY - originY;
	}

	/**
	 * Camera shake: two fast, detuned sine waves scaled by a linear
	 * falloff — organic rumble instead of random jitter. The offset only
	 * shifts the projection (renderer), never cameraX/Y, so follow,
	 * bounds and touch mapping stay unaffected.
	 */
	private void updateShake(float dt)
	{
		float pending = pendingShakeStrength;
		if (pending >= 0f) {
			pendingShakeStrength = -1f;
			shakeStrength = pending;
			shakeDuration = Math.max(0.001f, pendingShakeDuration);
			shakeRemaining = shakeDuration;
			shakeTime = 0f;
		}
		if (shakeRemaining <= 0f) {
			shakeOffsetX = 0f;
			shakeOffsetY = 0f;
			return;
		}
		shakeRemaining -= dt;
		shakeTime += dt;
		float falloff = Math.max(0f, shakeRemaining / shakeDuration);
		shakeOffsetX = shakeStrength * falloff * (float) Math.sin(shakeTime * 71f);
		shakeOffsetY = shakeStrength * falloff * (float) Math.sin(shakeTime * 83f + 1.3f);
	}

	/** Asteroids-style edge wrap: leaving one side re-enters the opposite. */
	private void wrapSprites(List<Sprite> list)
	{
		float w = worldWidth;
		float h = worldHeight;
		if (w <= 0f || h <= 0f) {
			return;
		}
		for (Sprite s : list) {
			if (!s.wrapAround) {
				continue;
			}
			float marginX = s.drawWidth() * Math.abs(s.scaleX) / 2f;
			float marginY = s.drawHeight() * Math.abs(s.scaleY) / 2f;
			if (s.x < -marginX) {
				s.x = w + marginX;
			} else if (s.x > w + marginX) {
				s.x = -marginX;
			}
			if (s.y < -marginY) {
				s.y = h + marginY;
			} else if (s.y > h + marginY) {
				s.y = -marginY;
			}
		}
	}

	/**
	 * Circle against an oriented rect. The circle's center is taken into the
	 * box's own frame, where the box is axis-aligned and the existing
	 * closest-point test applies unchanged; the contact normal is rotated
	 * back out at the end. out = { nx, ny, penetration }, normal pointing
	 * from the box toward the circle. False when they miss.
	 */
	private boolean circleVsObb(float cx, float cy, float r, float[] box,
								float vx, float vy, float[] out)
	{
		float cos = (float) Math.cos(box[4]);
		float sin = (float) Math.sin(box[4]);
		float rx = cx - box[0];
		float ry = cy - box[1];
		float lx = rx * cos + ry * sin;   // into the box's frame
		float ly = -rx * sin + ry * cos;
		float hx = box[2];
		float hy = box[3];
		float clampedX = Math.min(Math.max(lx, -hx), hx);
		float clampedY = Math.min(Math.max(ly, -hy), hy);
		float dx = lx - clampedX;
		float dy = ly - clampedY;
		float d2 = dx * dx + dy * dy;
		if (d2 >= r * r) {
			return false;
		}
		// A corner is a point, and a point cannot hold anything up. Left with
		// the corner-to-center normal, a ball landing on the tip of a turned
		// box takes the hit almost straight up: at high restitution it pops
		// into the air and hangs there, at low restitution the bounce falls
		// under the settle threshold and the ball perches on the point and
		// creeps off. Both read as the ball freezing. Resolving against the
		// face it is actually running into makes it glance off in a third of
		// a second instead.
		if (Math.abs(Math.abs(clampedX) - hx) < 1e-4f
				&& Math.abs(Math.abs(clampedY) - hy) < 1e-4f) {
			float lvx = vx * cos + vy * sin;
			float lvy = -vx * sin + vy * cos;
			float faceX = Math.signum(clampedX);
			float faceY = Math.signum(clampedY);
			boolean useX = (lvx * faceX) < (lvy * faceY); // the one it runs into
			float fnx = useX ? faceX : 0f;
			float fny = useX ? 0f : faceY;
			float gap = (lx * fnx + ly * fny) - (useX ? hx : hy);
			float pen = r - gap;
			if (pen > 0f) {
				out[0] = fnx * cos - fny * sin;
				out[1] = fnx * sin + fny * cos;
				out[2] = pen;
				return true;
			}
		}
		float lnx, lny, penetration;
		if (d2 > 1e-6f) {
			float d = (float) Math.sqrt(d2);
			lnx = dx / d;
			lny = dy / d;
			penetration = r - d;
		} else {
			// center inside the box — out through the nearest face
			float toLeft = lx + hx;
			float toRight = hx - lx;
			float toTop = ly + hy;
			float toBottom = hy - ly;
			float min = Math.min(Math.min(toLeft, toRight), Math.min(toTop, toBottom));
			lnx = (min == toLeft) ? -1f : (min == toRight) ? 1f : 0f;
			lny = (lnx != 0f) ? 0f : (min == toTop) ? -1f : 1f;
			penetration = min + r;
		}
		out[0] = lnx * cos - lny * sin;   // back into world space
		out[1] = lnx * sin + lny * cos;
		out[2] = penetration;
		return true;
	}

	/**
	 * Two oriented rects, by separating axes. Rectangles only need four
	 * candidate axes — each box's own two — and if the boxes overlap on all
	 * four, the smallest of those overlaps is the shortest way out. An
	 * unrotated box is just an oriented one at zero radians, so this also
	 * covers a plain rect against a tilted platform. out = { nx, ny,
	 * penetration }, normal pointing from b toward a. False when any axis
	 * separates them.
	 */
	private boolean obbVsObb(float[] a, float[] b, float[] out)
	{
		float ca = (float) Math.cos(a[4]);
		float sa = (float) Math.sin(a[4]);
		float cb = (float) Math.cos(b[4]);
		float sb = (float) Math.sin(b[4]);
		satAxes[0] = ca;   satAxes[1] = sa;    // a's own two axes
		satAxes[2] = -sa;  satAxes[3] = ca;
		satAxes[4] = cb;   satAxes[5] = sb;    // b's
		satAxes[6] = -sb;  satAxes[7] = cb;
		float dx = a[0] - b[0];
		float dy = a[1] - b[1];
		float best = Float.MAX_VALUE;
		float bestX = 0f;
		float bestY = 0f;
		for (int i = 0; i < 4; i++) {
			float nx = satAxes[i * 2];
			float ny = satAxes[i * 2 + 1];
			// how far each box reaches along this axis from its own center
			float ra = a[2] * Math.abs(nx * ca + ny * sa) + a[3] * Math.abs(-nx * sa + ny * ca);
			float rb = b[2] * Math.abs(nx * cb + ny * sb) + b[3] * Math.abs(-nx * sb + ny * cb);
			float along = dx * nx + dy * ny;
			float overlap = ra + rb - Math.abs(along);
			if (overlap <= 0f) {
				return false; // a separating axis: they cannot be touching
			}
			if (overlap < best) {
				best = overlap;
				float sign = (along < 0f) ? -1f : 1f; // orient from b toward a
				bestX = nx * sign;
				bestY = ny * sign;
			}
		}
		out[0] = bestX;
		out[1] = bestY;
		out[2] = best;
		return true;
	}

	/**
	 * Bilateral circle solids: a pair that lists each other's groups and
	 * whose sprites are both in `solidMode: 'push'` is resolved once, not
	 * once per direction. Each body takes half the separation, and the
	 * closing part of the relative velocity is exchanged at equal mass —
	 * for two equal circles with restitution 1 that is a straight swap of
	 * the normal components, which is what a break shot needs. Tangential
	 * velocity is untouched: no friction, no spin.
	 *
	 * Runs before the one-sided resolver, which skips push solids, so a
	 * pair is never corrected twice in a frame.
	 */
	private void resolveBilateralPairs(List<Sprite> list)
	{
		int n = list.size();
		for (int i = 0; i < n; i++) {
			Sprite a = list.get(i);
			Set<String> ga = a.solidWith;
			if (!a.circleHitbox || !a.visible || ga == null || ga.isEmpty()
					|| a.solidMode != Sprite.SOLID_PUSH) {
				continue;
			}
			for (int j = i + 1; j < n; j++) {
				Sprite b = list.get(j);
				if (!bilateralPair(a, b, ga)) {
					continue;
				}
				a.hitCenter(centerA);
				b.hitCenter(centerB);
				float dx = centerA[0] - centerB[0];
				float dy = centerA[1] - centerB[1];
				float sum = a.hitRadius() + b.hitRadius();
				float d2 = dx * dx + dy * dy;
				if (d2 >= sum * sum) {
					continue;
				}
				float nx, ny, penetration;
				if (d2 > 1e-6f) {
					float d = (float) Math.sqrt(d2);
					nx = dx / d;
					ny = dy / d;
					penetration = sum - d;
				} else {
					// concentric — the geometry carries no direction
					nx = 0f;
					ny = -1f;
					penetration = sum;
				}
				// Split the separation instead of moving one body all of it
				if (penetration > SLOP) {
					float half = penetration * 0.5f;
					a.x += nx * half;
					a.y += ny * half;
					b.x -= nx * half;
					b.y -= ny * half;
				}
				float vn = (a.velocityX - b.velocityX) * nx
						 + (a.velocityY - b.velocityY) * ny;
				if (vn >= 0f) {
					continue; // already separating — leave the velocities alone
				}
				// Equal masses: each body takes half of (1 + e) * vn, in
				// opposite directions. The springier of the two wins — the
				// same mix a body gets against a static surface.
				float e = Math.max(a.restitution, b.restitution);
				float impulse = -(1f + e) * vn * 0.5f;
				a.velocityX += impulse * nx;
				a.velocityY += impulse * ny;
				b.velocityX -= impulse * nx;
				b.velocityY -= impulse * ny;
			}
		}
	}

	/** Both circles, both visible, both in push mode, and each listing the
	 *  other's group. Anything less falls through to the ordinary one-sided
	 *  resolver, so `solidWith` keeps its old meaning by default — including
	 *  a one-way pairing, where only one side names the other. */
	private boolean bilateralPair(Sprite a, Sprite b, Set<String> ga)
	{
		if (!a.circleHitbox || !a.visible || a.solidMode != Sprite.SOLID_PUSH) {
			return false;
		}
		if (!b.circleHitbox || !b.visible || b.solidMode != Sprite.SOLID_PUSH) {
			return false;
		}
		Set<String> gb = b.solidWith;
		return ga != null && gb != null
			&& a.collisionGroup != null && b.collisionGroup != null
			&& ga.contains(b.collisionGroup) && gb.contains(a.collisionGroup);
	}

	/**
	 * Platformer collision resolution: sprites with `solidWith` groups are
	 * pushed out of overlapping solids along the axis of least penetration.
	 * Landing on top zeroes downward velocity, sets onGround and fires the
	 * land callback on the ground-touch transition.
	 */
	private void resolveSolids(List<Sprite> list)
	{
		resolveBilateralPairs(list);
		for (Sprite s : list) {
			Set<String> groups = s.solidWith;
			if (groups == null || groups.isEmpty() || !s.visible) {
				continue;
			}
			carryByGround(s);
			if (s.swept) {
				sweepAgainstSolids(s, list, groups);
			}
			if (s.circleHitbox) {
				resolveCircleSolids(s, list, groups);
				continue;
			}
			boolean wasOnGround = s.onGround;
			boolean grounded = false;
			Sprite groundedOn = null;
			s.computeAABB(aabbA);
			for (Sprite solid : list) {
				String group = solid.collisionGroup;
				if (solid == s || group == null || !solid.visible || !groups.contains(group)) {
					continue;
				}
				// Bounciness belongs to the contact, not to one side of it: the
				// springier of the two surfaces wins, the way Box2D mixes it.
				// Every solid defaults to 0, so a scene that never sets it on a
				// surface behaves exactly as before — but a floor can now be
				// given a bounce of its own without making the ball bouncy
				// everywhere else it touches.
				float e = Math.max(s.restitution, solid.restitution);
				if (solid.obbHitbox || s.obbHitbox) {
					// Separating axes instead of the two screen axes, so a
					// tilted platform pushes along its own face — which is
					// what lets a rider slide down a slope instead of
					// standing on an invisible ledge.
					s.hitBox(boxA);
					solid.hitBox(boxB);
					if (!obbVsObb(boxA, boxB, contact)) {
						continue;
					}
					float nx = contact[0];
					float ny = contact[1];
					float penetration = contact[2];
					if (solid.oneWay && (ny > -0.7f || s.velocityY < 0f)) {
						continue; // one-way: riders only catch on the upper face
					}
					if (penetration > SLOP) {
						s.x += nx * penetration;
						s.y += ny * penetration;
					}
					float vn = s.velocityX * nx + s.velocityY * ny;
					if (vn < 0f) {
						float bounce = -vn * e;
						if (e > 0f && bounce > 40f) {
							s.velocityX -= (1f + e) * vn * nx;
							s.velocityY -= (1f + e) * vn * ny;
						} else {
							s.velocityX -= vn * nx;
							s.velocityY -= vn * ny;
							if (ny < -0.7f) {
								grounded = true;
								groundedOn = solid;
							}
						}
					}
					s.computeAABB(aabbA); // position changed — refresh for the next solid
					continue;
				}
				solid.computeAABB(aabbB);
				float overlapX = Math.min(aabbA[2], aabbB[2]) - Math.max(aabbA[0], aabbB[0]);
				float overlapY = Math.min(aabbA[3], aabbB[3]) - Math.max(aabbA[1], aabbB[1]);
				if (overlapX <= 0f || overlapY <= 0f) {
					continue;
				}
				boolean fromAbove = aabbA[1] + aabbA[3] < aabbB[1] + aabbB[3];
				if (solid.oneWay) {
					// pass-through except when falling onto the top edge:
					// the rider's bottom was above it last frame
					if (s.velocityY < 0f || aabbA[3] - s.frameDeltaY > aabbB[1] + 2f) {
						continue;
					}
					fromAbove = true; // one-way only ever resolves as a landing
				}
				if (overlapY <= overlapX || solid.oneWay) {
					// vertical resolution (compare AABB centers, *2 to avoid the division)
					if (fromAbove) {
						s.y -= overlapY; // hit the solid from above
						float bounce = (e > 0f && s.velocityY > 0f)
							? s.velocityY * e : 0f;
						if (bounce > 40f) {
							s.velocityY = -bounce; // rigid-body bounce
						} else {
							if (s.velocityY > 0f) {
								s.velocityY = 0f;
							}
							grounded = true;
							groundedOn = solid;
						}
					} else {
						s.y += overlapY; // bumped from below
						if (s.velocityY < 0f) {
							s.velocityY = (e > 0f) ? -s.velocityY * e : 0f;
						}
					}
				} else {
					// horizontal resolution (walls); bouncy sprites reflect,
					// others keep velocity so held-button movement resumes
					// as soon as the wall ends
					if (aabbA[0] + aabbA[2] < aabbB[0] + aabbB[2]) {
						s.x -= overlapX;
						if (e > 0f && s.velocityX > 0f) {
							s.velocityX = -s.velocityX * e;
						}
					} else {
						s.x += overlapX;
						if (e > 0f && s.velocityX < 0f) {
							s.velocityX = -s.velocityX * e;
						}
					}
				}
				s.computeAABB(aabbA); // position changed — refresh for the next solid
			}
			s.onGround = grounded;
			s.groundSprite = grounded ? groundedOn : null;
			if (grounded && !wasOnGround) {
				Sprite.SpriteEventListener listener = s.eventListener;
				if (listener != null) {
					listener.onLand(s, groundedOn);
				}
			}
		}
	}

	/**
	 * Swept solid blocking: finds the earliest wall the sprite's movement
	 * crossed this frame and pulls the sprite back to the impact point,
	 * half a pixel past contact — the static resolver below then sees an
	 * ordinary touch and handles push-out, restitution, onGround and the
	 * land event exactly like a slow collision. Without this, a sprite
	 * faster than a solid is thick teleports straight through it.
	 *
	 * Two circle hitboxes sweep as circles: the Minkowski sum of two
	 * circles is a circle of radius r1 + r2, so the test is the same ray
	 * vs circle the raycast API solves. Every other pairing — including a
	 * circle against a rectangular solid — stays on the inflated-AABB
	 * Minkowski box.
	 */
	private void sweepAgainstSolids(Sprite s, List<Sprite> list, Set<String> groups)
	{
		float dx = s.frameDeltaX;
		float dy = s.frameDeltaY;
		float len2 = dx * dx + dy * dy;
		if (len2 < 1e-4f) {
			return;
		}
		boolean circle = s.circleHitbox;
		float r = 0f;
		float cx, cy, hw = 0f, hh = 0f;
		if (circle) {
			s.hitCenter(centerA);
			r = s.hitRadius();
			cx = centerA[0] - dx; // center at frame start
			cy = centerA[1] - dy;
		} else {
			s.computeAABB(aabbA);
			hw = (aabbA[2] - aabbA[0]) / 2f;
			hh = (aabbA[3] - aabbA[1]) / 2f;
			cx = (aabbA[0] + aabbA[2]) / 2f - dx; // center at frame start
			cy = (aabbA[1] + aabbA[3]) / 2f - dy;
		}
		float earliest = Float.MAX_VALUE;
		for (Sprite solid : list) {
			String group = solid.collisionGroup;
			if (solid == s || group == null || !solid.visible || !groups.contains(group)
					|| solid.solidMode != Sprite.SOLID_BLOCK) {
				// contain would stop the ball against the OUTSIDE of the
				// boundary, and push bodies are meant to move — neither is a
				// wall, so neither belongs in a blocking sweep
				continue;
			}
			if (solid.obbHitbox) {
				// Take the whole sweep into the box's frame, where the box is
				// axis-aligned again and the existing Minkowski segment test
				// applies unchanged.
				solid.hitBox(boxB);
				float bc = (float) Math.cos(boxB[4]);
				float bs = (float) Math.sin(boxB[4]);
				float rx = cx - boxB[0];
				float ry = cy - boxB[1];
				float lx = rx * bc + ry * bs;
				float ly = -rx * bs + ry * bc;
				float ldx = dx * bc + dy * bs;
				float ldy = -dx * bs + dy * bc;
				float best = Float.MAX_VALUE;
				if (circle) {
					// The Minkowski sum of a circle and a rect is a ROUNDED
					// rect: the box grown on each axis, plus a quarter circle
					// at each corner. Growing it as a square instead pokes out
					// by 1.41r along the diagonal — which is exactly where a
					// ball dropped on a turned box's tip arrives. It gets
					// stopped short of a contact that then never happens, and
					// hangs in mid-air for a quarter second until it drifts
					// off the phantom corner.
					if (sweptHit(lx, ly, ldx, ldy,
							-boxB[2] - r, -boxB[3], boxB[2] + r, boxB[3])) {
						best = sweptResult[0];
					}
					if (sweptHit(lx, ly, ldx, ldy,
							-boxB[2], -boxB[3] - r, boxB[2], boxB[3] + r)
							&& sweptResult[0] < best) {
						best = sweptResult[0];
					}
					for (int i = 0; i < 4; i++) {
						float ccx = ((i & 1) == 0) ? -boxB[2] : boxB[2];
						float ccy = (i < 2) ? -boxB[3] : boxB[3];
						float t = segmentVsCircle(lx, ly, ldx, ldy, ccx, ccy, r);
						if (t >= 0f && t < best) {
							best = t;
						}
					}
				} else if (sweptHit(lx, ly, ldx, ldy,
						-boxB[2] - hw, -boxB[3] - hh, boxB[2] + hw, boxB[3] + hh)) {
					best = sweptResult[0];
				}
				if (best == Float.MAX_VALUE || best <= 0f) {
					// t = 0 means the sprite was already touching when the
					// frame began, and you cannot tunnel out of a contact you
					// are already in. Pulling it back for that is what pins a
					// body resting on a slope: it is dragged back to where it
					// started every frame while its speed along the surface
					// keeps climbing, until it finally breaks loose and looks
					// like it was launched. The static resolver owns this case.
					continue;
				}
				if (solid.oneWay && (dy <= 0f || s.velocityY < 0f)) {
					continue; // one-way: only a fall onto the upper face counts
				}
				if (best < earliest) {
					earliest = best;
				}
				continue;
			}
			if (circle && solid.circleHitbox) {
				solid.hitCenter(centerB);
				float sum = r + solid.hitRadius();
				float fx = cx - centerB[0];
				float fy = cy - centerB[1];
				float t;
				if (fx * fx + fy * fy <= sum * sum) {
					continue; // already touching: nothing to sweep, see above
				} else {
					float a = dx * dx + dy * dy;
					float b = 2f * (fx * dx + fy * dy);
					float c = fx * fx + fy * fy - sum * sum;
					float disc = b * b - 4f * a * c;
					if (disc < 0f) {
						continue;
					}
					t = (-b - (float) Math.sqrt(disc)) / (2f * a);
					if (t < 0f || t > 1f) {
						continue;
					}
				}
				if (solid.oneWay) {
					// same top-face rule as the static resolver: the contact
					// normal has to point up out of the solid
					float hy = cy + dy * t - centerB[1];
					float nl = (float) Math.hypot(cx + dx * t - centerB[0], hy);
					float ny = (nl > 1e-6f) ? hy / nl : -1f;
					if (ny > -0.7f || s.velocityY < 0f) {
						continue;
					}
				}
				if (t < earliest) {
					earliest = t;
				}
				continue;
			}
			solid.computeAABB(aabbB);
			if (!sweptHit(cx, cy, dx, dy,
					aabbB[0] - hw, aabbB[1] - hh, aabbB[2] + hw, aabbB[3] + hh)) {
				continue;
			}
			if (sweptResult[0] <= 0f) {
				// Already overlapping when the frame began. There is nothing
				// to sweep out of a contact you are already in, and pulling
				// the sprite back for it drags a resting body backwards every
				// frame while its speed along the surface keeps building.
				continue;
			}
			if (solid.oneWay
					&& (sweptResult[1] != 1f || dy <= 0f || s.velocityY < 0f)) {
				continue; // one-way: only falling onto the top face counts
			}
			if (sweptResult[0] < earliest) {
				earliest = sweptResult[0];
			}
		}
		if (earliest >= 1f) {
			return; // no crossing (end-position overlaps resolve statically)
		}
		float t = Math.min(1f, earliest + 0.5f / (float) Math.sqrt(len2));
		float back = 1f - t;
		s.x -= dx * back;
		s.y -= dy * back;
		// keep the carry delta honest in case something rides this sprite
		s.frameDeltaX -= dx * back;
		s.frameDeltaY -= dy * back;
	}

	/**
	 * Moving platforms carry: before resolving, the rider inherits the
	 * per-frame movement of the solid it stood on last frame, so it is
	 * carried sideways and stays glued on the way down instead of
	 * re-landing every frame. frameDelta excludes wrap teleports, and
	 * direct JS position writes never enter it, so a teleporting
	 * platform leaves its rider behind (as it should).
	 */
	private void carryByGround(Sprite s)
	{
		Sprite ground = s.groundSprite;
		if (ground == null || s.dragged) { // a held finger outranks the platform
			return;
		}
		if (!ground.visible || ground.scene != this) {
			s.groundSprite = null; // platform vanished under the rider
			return;
		}
		if (!ground.carryRiders) {
			return; // world-scroll terrain: the rider stays put
		}
		s.x += ground.frameDeltaX;
		s.y += ground.frameDeltaY;
	}

	/**
	 * Pins attached sprites to their targets' final positions — after
	 * physics and solid resolution, so a tag never lags its owner by a
	 * frame, and before collision checks, so an attached hitbox tests at
	 * its real position. Chains resolve parent-first via recursion
	 * (re-applying a parent is harmless, placement is absolute) and the
	 * depth cap breaks accidental cycles.
	 */
	private void applyAttachments(List<Sprite> list)
	{
		for (Sprite s : list) {
			if (s.attachTarget != null) {
				applyAttachment(s, 0);
			}
		}
	}

	private void applyAttachment(Sprite s, int depth)
	{
		Sprite target = s.attachTarget;
		if (target == null || target == s || target.scene != this) {
			return; // orphaned — keep the last applied state
		}
		if (target.attachTarget != null && depth < 8) {
			applyAttachment(target, depth + 1);
		}
		// Opacity inherits even while dragged; parent-first recursion
		// means a chain multiplies down correctly.
		s.attachOpacity = target.effectiveOpacity();
		if (s.dragged) {
			return; // held by a finger — the finger outranks the position
		}
		float ox = s.attachOffsetX;
		float oy = s.attachOffsetY;
		if (s.attachRotate) {
			double rad = Math.toRadians(target.rotation);
			float cos = (float) Math.cos(rad);
			float sin = (float) Math.sin(rad);
			float rx = ox * cos - oy * sin;
			oy = ox * sin + oy * cos;
			ox = rx;
			s.rotation = target.rotation;
		}
		float tx = target.x;
		float ty = target.y;
		// Cross-space attach (screenFixed tag on a world sprite, or the
		// reverse): convert the target position into this sprite's space,
		// so the offset stays in the sprite's own coordinates.
		if (s.screenFixed != target.screenFixed) {
			if (s.screenFixed) {
				tx = worldToScreenX(tx);
				ty = worldToScreenY(ty);
			} else {
				tx = screenToWorldX(tx);
				ty = screenToWorldY(ty);
			}
		}
		s.x = tx + ox;
		s.y = ty + oy;
	}

	/**
	 * Circle-vs-solid resolution: the ball is pushed out along the contact
	 * normal, so it bounces off corners naturally. A solid that declares a
	 * circle hitbox is resolved as a circle — normal from center to center,
	 * no phantom faces or corners — and every other solid keeps the
	 * closest-point-on-AABB normal. Velocity reflects about the normal with
	 * restitution; small bounces come to rest and ground the sprite when
	 * the normal points up.
	 */
	private void resolveCircleSolids(Sprite s, List<Sprite> list, Set<String> groups)
	{
		boolean wasOnGround = s.onGround;
		boolean grounded = false;
		Sprite groundedOn = null;
		float r = s.hitRadius();
		for (Sprite solid : list) {
			String group = solid.collisionGroup;
			if (solid == s || group == null || !solid.visible || !groups.contains(group)) {
				continue;
			}
			if (bilateralPair(s, solid, groups)) {
				continue; // already resolved once, in resolveBilateralPairs
			}
			// Bounciness belongs to the contact, not to one side of it: the
			// springier of the two surfaces wins, the way Box2D mixes it.
			// Every solid defaults to 0, so a scene that never sets it on a
			// surface behaves exactly as before — but a floor can now be
			// given a bounce of its own without making the ball bouncy
			// everywhere else it touches.
			float e = Math.max(s.restitution, solid.restitution);
			s.hitCenter(centerA);
			float cx = centerA[0];
			float cy = centerA[1];
			float nx, ny, penetration;
			if (solid.solidMode == Sprite.SOLID_CONTAIN && solid.circleHitbox) {
				// Inward boundary: keep the ball's center within R - r of the
				// container's. The correcting normal points back toward the
				// center, so the whole tail below (push-out, restitution,
				// grounding on the lower arc, land) works unchanged.
				solid.hitCenter(centerB);
				float allowed = solid.hitRadius() - r;
				float dx = cx - centerB[0];
				float dy = cy - centerB[1];
				float d2 = dx * dx + dy * dy;
				if (allowed <= 0f || d2 <= allowed * allowed) {
					continue; // ball still inside, or it does not fit at all
				}
				float d = (float) Math.sqrt(d2);
				nx = -dx / d;
				ny = -dy / d;
				penetration = d - allowed;
			} else if (solid.obbHitbox) {
				// Rect that turns with its sprite: the normal comes out
				// perpendicular to the real face, not to a phantom axis
				solid.hitBox(boxB);
				if (!circleVsObb(cx, cy, r, boxB, s.velocityX, s.velocityY, contact)) {
					continue;
				}
				nx = contact[0];
				ny = contact[1];
				penetration = contact[2];
			} else if (solid.circleHitbox) {
				// Circle vs circle: the normal is the line between the two
				// centers and the overlap is r1 + r2 - d.
				solid.hitCenter(centerB);
				float sum = r + solid.hitRadius();
				float dx = cx - centerB[0];
				float dy = cy - centerB[1];
				float d2 = dx * dx + dy * dy;
				if (d2 >= sum * sum) {
					continue;
				}
				if (d2 > 1e-6f) {
					float d = (float) Math.sqrt(d2);
					nx = dx / d;
					ny = dy / d;
					penetration = sum - d;
				} else {
					// concentric — the geometry carries no direction, so pick
					// a fixed one rather than dividing by zero
					nx = 0f;
					ny = -1f;
					penetration = sum;
				}
			} else {
				solid.computeAABB(aabbB);
				float closestX = Math.min(Math.max(cx, aabbB[0]), aabbB[2]);
				float closestY = Math.min(Math.max(cy, aabbB[1]), aabbB[3]);
				float dx = cx - closestX;
				float dy = cy - closestY;
				float d2 = dx * dx + dy * dy;
				if (d2 >= r * r) {
					continue;
				}
				if (d2 > 1e-6f) {
					float d = (float) Math.sqrt(d2);
					nx = dx / d;
					ny = dy / d;
					penetration = r - d;
				} else {
					// center inside the solid — push out along the nearest face
					float toLeft = cx - aabbB[0];
					float toRight = aabbB[2] - cx;
					float toTop = cy - aabbB[1];
					float toBottom = aabbB[3] - cy;
					float min = Math.min(Math.min(toLeft, toRight), Math.min(toTop, toBottom));
					nx = (min == toLeft) ? -1f : (min == toRight) ? 1f : 0f;
					ny = (nx != 0f) ? 0f : (min == toTop) ? -1f : 1f;
					penetration = min + r;
				}
			}
			if (solid.oneWay && solid.solidMode == Sprite.SOLID_BLOCK
					&& (ny > -0.7f || s.velocityY < 0f)) {
				continue; // one-way: balls only land on the top face
			}
			if (penetration > SLOP) {
				s.x += nx * penetration;
				s.y += ny * penetration;
			}
			float vn = s.velocityX * nx + s.velocityY * ny;
			if (vn < 0f) {
				float bounce = -vn * e;
				if (e > 0f && bounce > 40f) {
					s.velocityX -= (1f + e) * vn * nx;
					s.velocityY -= (1f + e) * vn * ny;
				} else {
					s.velocityX -= vn * nx;
					s.velocityY -= vn * ny;
					if (ny < -0.7f) {
						grounded = true;
						groundedOn = solid;
					}
				}
			}
		}
		s.onGround = grounded;
		s.groundSprite = grounded ? groundedOn : null;
		if (grounded && !wasOnGround) {
			Sprite.SpriteEventListener listener = s.eventListener;
			if (listener != null) {
				listener.onLand(s, groundedOn);
			}
		}
	}

	/**
	 * AABB overlap test between sprites that declare `collidesWith` groups
	 * and visible sprites carrying a matching `collisionGroup`. Fires the
	 * collision callback once per overlap-enter and the collision-end
	 * callback once per separation (also when the contact partner is
	 * hidden, removed from the scene, or stops matching the groups) —
	 * the enter/exit contact lifecycle of Unity/Godot triggers, minus a
	 * per-frame "stay" that would need bridge traffic.
	 */
	private void checkCollisions(List<Sprite> list)
	{
		for (Sprite s : list) {
			Set<String> groups = s.collidesWith;
			if (groups == null || groups.isEmpty() || !s.visible) {
				// hidden or de-configured mid-contact: everything separates
				endAllCollisions(s);
				continue;
			}
			for (Sprite other : list) {
				String group = other.collisionGroup;
				if (other == s || group == null || !other.visible || !groups.contains(group)) {
					continue;
				}
				boolean overlap = shapesOverlap(s, other);
				if (!overlap && s.swept) {
					overlap = sweptShapesOverlap(s, other);
				}
				if (overlap) {
					if (s.colliding.add(other)) {
						Sprite.SpriteEventListener listener = s.eventListener;
						if (listener != null) {
							listener.onCollision(s, other);
						}
					}
				} else if (s.colliding.remove(other)) {
					fireCollisionEnd(s, other);
				}
			}
			// Contacts the loop above can no longer see: partner left the
			// scene, went invisible, or the group filter changed.
			if (!s.colliding.isEmpty()) {
				Iterator<Sprite> it = s.colliding.iterator();
				while (it.hasNext()) {
					Sprite other = it.next();
					String group = other.collisionGroup;
					if (other.scene != this || !other.visible
							|| group == null || !groups.contains(group)) {
						it.remove();
						fireCollisionEnd(s, other);
					}
				}
			}
		}
	}

	/** Separates every tracked contact of a sprite (hidden/de-configured). */
	private void endAllCollisions(Sprite s)
	{
		if (s.colliding.isEmpty()) {
			return;
		}
		Iterator<Sprite> it = s.colliding.iterator();
		while (it.hasNext()) {
			Sprite other = it.next();
			it.remove();
			fireCollisionEnd(s, other);
		}
	}

	private static void fireCollisionEnd(Sprite s, Sprite other)
	{
		Sprite.SpriteEventListener listener = s.eventListener;
		if (listener != null) {
			listener.onCollisionEnd(s, other);
		}
	}

	/** Topmost sprite under the point (front to back), or null. */
	public Sprite hitTest(float x, float y)
	{
		List<Sprite> list = snapshot();
		for (int i = list.size() - 1; i >= 0; i--) {
			Sprite s = list.get(i);
			if (s.hitTest(x, y)) {
				return s;
			}
		}
		return null;
	}
}
