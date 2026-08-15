package ti.game.engine;

import java.util.Random;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Native particle emitter, ticked and drawn entirely in the game loop —
 * zero bridge traffic while running. Configuration fields are volatile
 * (JS thread writes, GL thread reads); the particle pool itself is GL
 * thread only.
 *
 * Continuous mode spawns `rate` particles per second while `emitting`;
 * emit(n) queues a one-shot burst on top (explosions). Particles fly from
 * the emitter position (or the followed target sprite, plus offset) in a
 * cone of `spread` degrees around `angle` (0 = up, clockwise — the same
 * heading convention as thrust), with speed randomized between 50% and
 * 100% of `speed` so bursts don't form perfect rings. Over each
 * particle's lifetime, scale and opacity interpolate start → end.
 *
 * All particles of an emitter share one sheet frame, so an emitter is
 * drawn in a single batch run (one draw call unless the texture changes).
 */
public class ParticleEmitter
{
	public static final int HARD_CAP = 1000;

	// Configuration (JS thread writes, GL thread reads)
	public volatile SpriteSheet sheet;
	public volatile int frame = 0;
	public volatile float x = 0f;
	public volatile float y = 0f;
	public volatile float offsetX = 0f;
	public volatile float offsetY = 0f;
	public volatile int zIndex = 0;
	public volatile float rate = 0f;          // particles per second
	public volatile float lifetime = 0.8f;    // seconds
	public volatile float speed = 100f;       // px/s (randomized 50%..100%)
	public volatile float angle = 0f;         // base direction, 0 = up, clockwise degrees
	public volatile float spread = 360f;      // cone width in degrees
	public volatile float gravity = 0f;       // px/s^2, applied to particle vy
	public volatile float size = 0f;          // base particle width in px; 0 = frame size
	public volatile float startScale = 1f;
	public volatile float endScale = 1f;
	public volatile float startOpacity = 1f;
	public volatile float endOpacity = 0f;
	public volatile float tintR = 1f;
	public volatile float tintG = 1f;
	public volatile float tintB = 1f;
	public volatile boolean emitting = true;
	public volatile Sprite target;            // follow this sprite instead of x/y
	private volatile int maxParticles = 200;

	// Cross-thread requests, consumed by update() on the GL thread
	private final AtomicInteger pendingBurst = new AtomicInteger();
	private volatile boolean clearRequested = false;

	// Particle pool — GL thread only
	private float[] px, py, vx, vy, age, life;
	private int capacity = 0;
	private int count = 0;
	private float emitAccumulator = 0f;
	private final Random random = new Random();

	public void setMaxParticles(int value)
	{
		maxParticles = Math.max(1, Math.min(HARD_CAP, value));
	}

	public int getMaxParticles()
	{
		return maxParticles;
	}

	/** Queues a one-shot burst of n particles (JS thread safe). */
	public void emit(int n)
	{
		if (n > 0) {
			pendingBurst.addAndGet(n);
		}
	}

	/** Kills all live particles on the next frame (JS thread safe). */
	public void clear()
	{
		clearRequested = true;
	}

	/** Spawn, integrate and age all particles. GL thread, once per frame. */
	public void update(float dt)
	{
		if (clearRequested) {
			clearRequested = false;
			count = 0;
		}
		int cap = maxParticles;
		ensureCapacity(cap);

		// Emitter position: followed sprite or own x/y, plus offset
		Sprite t = target;
		float ex = ((t != null) ? t.x : x) + offsetX;
		float ey = ((t != null) ? t.y : y) + offsetY;

		int toSpawn = pendingBurst.getAndSet(0);
		if (emitting && rate > 0f) {
			emitAccumulator += rate * dt;
			int continuous = (int) emitAccumulator;
			emitAccumulator -= continuous;
			toSpawn += continuous;
		}
		while (toSpawn-- > 0 && count < cap) {
			spawn(ex, ey);
		}

		float g = gravity;
		for (int i = 0; i < count; ) {
			age[i] += dt;
			if (age[i] >= life[i]) {
				// swap-remove: order doesn't matter for particles
				count--;
				px[i] = px[count];
				py[i] = py[count];
				vx[i] = vx[count];
				vy[i] = vy[count];
				age[i] = age[count];
				life[i] = life[count];
				continue;
			}
			vy[i] += g * dt;
			px[i] += vx[i] * dt;
			py[i] += vy[i] * dt;
			i++;
		}
	}

	private void spawn(float ex, float ey)
	{
		double rad = Math.toRadians(angle + (random.nextFloat() - 0.5f) * spread);
		float s = speed * (0.5f + 0.5f * random.nextFloat());
		px[count] = ex;
		py[count] = ey;
		vx[count] = (float) Math.sin(rad) * s;
		vy[count] = -(float) Math.cos(rad) * s;
		age[count] = 0f;
		life[count] = Math.max(0.01f, lifetime);
		count++;
	}

	private void ensureCapacity(int cap)
	{
		if (cap <= capacity) {
			if (count > cap) {
				count = cap; // maxParticles was lowered — drop the tail
			}
			return;
		}
		float[] npx = new float[cap], npy = new float[cap];
		float[] nvx = new float[cap], nvy = new float[cap];
		float[] nage = new float[cap], nlife = new float[cap];
		if (count > 0) {
			System.arraycopy(px, 0, npx, 0, count);
			System.arraycopy(py, 0, npy, 0, count);
			System.arraycopy(vx, 0, nvx, 0, count);
			System.arraycopy(vy, 0, nvy, 0, count);
			System.arraycopy(age, 0, nage, 0, count);
			System.arraycopy(life, 0, nlife, 0, count);
		}
		px = npx;
		py = npy;
		vx = nvx;
		vy = nvy;
		age = nage;
		life = nlife;
		capacity = cap;
	}

	/** Draws all live particles through the shared batcher. GL thread. */
	public void draw(SpriteBatch batch)
	{
		SpriteSheet sh = sheet;
		if (count == 0 || sh == null || !sh.isReady()) {
			return;
		}
		SpriteSheet.Frame f = sh.frame(frame);
		if (f == null || f.width <= 0f) {
			return;
		}
		float baseWidth = (size > 0f) ? size : f.width;
		float aspect = f.height / f.width;
		float r = tintR;
		float g = tintG;
		float b = tintB;
		float scaleDelta = endScale - startScale;
		float opacityDelta = endOpacity - startOpacity;
		int texture = sh.textureId();
		for (int i = 0; i < count; i++) {
			float t = age[i] / life[i];
			float scale = startScale + scaleDelta * t;
			float alpha = startOpacity + opacityDelta * t;
			if (alpha <= 0f || scale <= 0f) {
				continue;
			}
			float halfW = baseWidth * scale * 0.5f;
			batch.drawFrame(texture, f, px[i], py[i], halfW, halfW * aspect,
				r, g, b, Math.min(1f, alpha));
		}
	}
}
