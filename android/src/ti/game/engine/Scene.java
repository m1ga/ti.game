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

	/** Renders debug overlays for every sprite (GameView.debug = true). */
	public volatile boolean debugAll = false;

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
			if (sprites.remove(sprite)) {
				sprite.scene = null;
			}
		}
	}

	public void clear()
	{
		synchronized (lock) {
			for (Sprite s : sprites) {
				s.scene = null;
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
	private final float[] sweptResult = new float[2];

	/**
	 * Swept AABB: does a point moving from (cx, cy) by (dx, dy) this frame
	 * cross the box? Callers inflate the box by the mover's half extents
	 * (Minkowski sum), turning box-vs-box sweeping into this segment test
	 * (slab method). Catches fast movers that would tunnel straight
	 * through thin targets between frames. GL thread only.
	 */
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

	/** Shape-aware overlap test (rect/rect, circle/circle, circle/rect). */
	private boolean shapesOverlap(Sprite a, Sprite b)
	{
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
	 * Platformer collision resolution: sprites with `solidWith` groups are
	 * pushed out of overlapping solids along the axis of least penetration.
	 * Landing on top zeroes downward velocity, sets onGround and fires the
	 * land callback on the ground-touch transition.
	 */
	private void resolveSolids(List<Sprite> list)
	{
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
						float bounce = (s.restitution > 0f && s.velocityY > 0f)
							? s.velocityY * s.restitution : 0f;
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
							s.velocityY = (s.restitution > 0f) ? -s.velocityY * s.restitution : 0f;
						}
					}
				} else {
					// horizontal resolution (walls); bouncy sprites reflect,
					// others keep velocity so held-button movement resumes
					// as soon as the wall ends
					if (aabbA[0] + aabbA[2] < aabbB[0] + aabbB[2]) {
						s.x -= overlapX;
						if (s.restitution > 0f && s.velocityX > 0f) {
							s.velocityX = -s.velocityX * s.restitution;
						}
					} else {
						s.x += overlapX;
						if (s.restitution > 0f && s.velocityX < 0f) {
							s.velocityX = -s.velocityX * s.restitution;
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
	 */
	private void sweepAgainstSolids(Sprite s, List<Sprite> list, Set<String> groups)
	{
		float dx = s.frameDeltaX;
		float dy = s.frameDeltaY;
		float len2 = dx * dx + dy * dy;
		if (len2 < 1e-4f) {
			return;
		}
		s.computeAABB(aabbA);
		float hw = (aabbA[2] - aabbA[0]) / 2f;
		float hh = (aabbA[3] - aabbA[1]) / 2f;
		float cx = (aabbA[0] + aabbA[2]) / 2f - dx; // center at frame start
		float cy = (aabbA[1] + aabbA[3]) / 2f - dy;
		float earliest = Float.MAX_VALUE;
		for (Sprite solid : list) {
			String group = solid.collisionGroup;
			if (solid == s || group == null || !solid.visible || !groups.contains(group)) {
				continue;
			}
			solid.computeAABB(aabbB);
			if (!sweptHit(cx, cy, dx, dy,
					aabbB[0] - hw, aabbB[1] - hh, aabbB[2] + hw, aabbB[3] + hh)) {
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
	 * Circle-vs-AABB solid resolution: the ball is pushed out along the
	 * contact normal (closest point on the solid), so it bounces off
	 * corners naturally. Velocity reflects about the normal with
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
			s.hitCenter(centerA);
			float cx = centerA[0];
			float cy = centerA[1];
			solid.computeAABB(aabbB);
			float closestX = Math.min(Math.max(cx, aabbB[0]), aabbB[2]);
			float closestY = Math.min(Math.max(cy, aabbB[1]), aabbB[3]);
			float dx = cx - closestX;
			float dy = cy - closestY;
			float d2 = dx * dx + dy * dy;
			if (d2 >= r * r) {
				continue;
			}
			float nx, ny, penetration;
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
			if (solid.oneWay && (ny > -0.7f || s.velocityY < 0f)) {
				continue; // one-way: balls only land on the top face
			}
			s.x += nx * penetration;
			s.y += ny * penetration;
			float vn = s.velocityX * nx + s.velocityY * ny;
			if (vn < 0f) {
				float bounce = -vn * s.restitution;
				if (s.restitution > 0f && bounce > 40f) {
					s.velocityX -= (1f + s.restitution) * vn * nx;
					s.velocityY -= (1f + s.restitution) * vn * ny;
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
