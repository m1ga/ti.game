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

	// Camera: world-space offset of the view's top-left corner. The
	// renderer shifts the projection by it and the touch controller maps
	// screen touches back into world space.
	public volatile float cameraX = 0f;
	public volatile float cameraY = 0f;

	// Native vertical follow with a dead-zone: the camera scrolls when the
	// target rises above topFraction of the screen or sinks below
	// bottomFraction, clamped to cameraMaxY (0 = never below the start).
	public volatile Sprite followTarget;
	public volatile float followTopFraction = 0.33f;
	public volatile float followBottomFraction = 0.7f;
	public volatile float cameraMaxY = 0f;

	public volatile float bgRed = 0f;
	public volatile float bgGreen = 0f;
	public volatile float bgBlue = 0f;
	public volatile float bgAlpha = 1f;

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

	/** Ticks physics, animations and tweens, then checks collisions. GL thread. */
	public void update(float dt)
	{
		List<Sprite> list = snapshot();
		for (Sprite s : list) {
			s.update(dt);
		}
		skidTrail.update(dt);
		wrapSprites(list);
		resolveSolids(list);
		checkCollisions(list);
		updateCamera();
	}

	/** Vertical dead-zone follow, after physics so the camera never lags. */
	private void updateCamera()
	{
		Sprite target = followTarget;
		float h = worldHeight;
		if (target == null || h <= 0f) {
			return;
		}
		float top = h * followTopFraction;
		float bottom = h * followBottomFraction;
		float screenY = target.y - cameraY;
		if (screenY < top) {
			cameraY = target.y - top;
		} else if (screenY > bottom) {
			cameraY = target.y - bottom;
		}
		if (cameraY > cameraMaxY) {
			cameraY = cameraMaxY;
		}
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
				if (overlapY <= overlapX) {
					// vertical resolution (compare AABB centers, *2 to avoid the division)
					if (aabbA[1] + aabbA[3] < aabbB[1] + aabbB[3]) {
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
			if (grounded && !wasOnGround) {
				Sprite.SpriteEventListener listener = s.eventListener;
				if (listener != null) {
					listener.onLand(s, groundedOn);
				}
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
			s.computeAABB(aabbA);
			for (Sprite other : list) {
				String group = other.collisionGroup;
				if (other == s || group == null || !other.visible || !groups.contains(group)) {
					continue;
				}
				other.computeAABB(aabbB);
				boolean overlap = aabbA[0] < aabbB[2] && aabbA[2] > aabbB[0]
					&& aabbA[1] < aabbB[3] && aabbA[3] > aabbB[1];
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
