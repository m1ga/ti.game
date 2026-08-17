package ti.game.engine;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
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

	public void add(Sprite sprite)
	{
		synchronized (lock) {
			if (!sprites.contains(sprite)) {
				sprites.add(sprite);
				sprite.scene = this;
				zOrderDirty = true;
				if (sprite.ySort) {
					hasYSort = true;
				}
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
	 * collision callback once per overlap-enter (re-fires after separation).
	 */
	private void checkCollisions(List<Sprite> list)
	{
		for (Sprite s : list) {
			Set<String> groups = s.collidesWith;
			if (groups == null || groups.isEmpty() || !s.visible) {
				continue;
			}
			for (Sprite other : list) {
				String group = other.collisionGroup;
				if (other == s || group == null || !other.visible || !groups.contains(group)) {
					continue;
				}
				boolean overlap = shapesOverlap(s, other);
				if (overlap) {
					if (s.colliding.add(other)) {
						Sprite.SpriteEventListener listener = s.eventListener;
						if (listener != null) {
							listener.onCollision(s, other);
						}
					}
				} else {
					s.colliding.remove(other);
				}
			}
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
