package ti.game.engine;

/**
 * Native Verlet rope: a chain of distance-constrained points, integrated
 * and drawn entirely in the game loop — zero bridge traffic while it
 * swings. Configuration fields are volatile (JS thread writes, GL thread
 * reads); the point arrays are GL thread only.
 *
 * The head pins to a sprite (drag the sprite natively and the rope
 * follows) or to a fixed x/y; an optional tail sprite pins the other end
 * (bridges, slack chains). Each frame: Verlet integration with gravity
 * and damping, then `iterations` relaxation passes enforcing
 * segmentLength between neighbors. Segments render as textured quads
 * oriented along the rope, all from one sheet frame — one batch run.
 */
public class Rope
{
	private static final int MAX_SEGMENTS = 200;

	// Configuration (JS thread writes, GL thread reads)
	public volatile SpriteSheet sheet;
	public volatile int frame = 0;
	public volatile int segments = 10;
	public volatile float segmentLength = 30f;  // px
	public volatile float thickness = 10f;      // drawn width, px
	public volatile float gravity = 1500f;      // px/s^2
	public volatile float damping = 0.98f;      // velocity kept per step
	public volatile int iterations = 3;         // constraint passes
	public volatile int zIndex = 0;
	public volatile boolean visible = true;
	public volatile float x = 0f;               // head anchor when no head sprite
	public volatile float y = 0f;
	public volatile Sprite head;
	public volatile Sprite tail;

	// Tether: when > 0 and the head→tail distance exceeds it, the tail
	// sprite is pulled back onto the limit circle each frame (leash,
	// pendulum, yo-yo). 0 = off.
	public volatile float maxLength = 0f;

	// Live tail-end position, mirrored for JS reads (hook tips, hit tests)
	public volatile float endX, endY;

	// Verlet points — GL thread only
	private float[] px, py, prevX, prevY;
	private int pointCount = 0;

	/** Integrate + relax constraints. GL thread, once per frame. */
	public void update(float dt)
	{
		int segs = Math.max(1, Math.min(MAX_SEGMENTS, segments));
		int count = segs + 1;
		Sprite h = head;
		float headX = (h != null) ? h.x : x;
		float headY = (h != null) ? h.y : y;
		if (count != pointCount) {
			rebuild(count, headX, headY);
		}

		Sprite t = tail;
		boolean tailPinned = (t != null);
		float limit = maxLength;
		if (tailPinned && limit > 0f) {
			float tdx = t.x - headX;
			float tdy = t.y - headY;
			float td = (float) Math.sqrt(tdx * tdx + tdy * tdy);
			boolean headDragged = (h != null) && h.dragged;
			// The tether yields at the end no finger owns: drag either
			// sprite past the limit and the other is towed behind.
			// With both ends free the correction splits evenly. With a
			// finger on BOTH ends (multi-touch) neither yields — the
			// drag itself clamps at the source (TouchController), and
			// correcting here would fight the fingers every frame.
			if (td > limit && td > 1e-5f && !(headDragged && t.dragged)) {
				float nx = tdx / td;
				float ny = tdy / td;
				float excess = td - limit;
				float headShare = !headDragged && h != null ? (t.dragged ? 1f : 0.5f) : 0f;
				if (headShare > 0f) {
					h.x += nx * excess * headShare;
					h.y += ny * excess * headShare;
					// Strip the velocity component pointing away from the
					// tail so the towed sprite doesn't fight the rope.
					float radial = -(h.velocityX * nx + h.velocityY * ny);
					if (radial > 0f) {
						h.velocityX += radial * nx;
						h.velocityY += radial * ny;
					}
					headX = h.x;
					headY = h.y;
				}
				float tailShare = 1f - headShare;
				if (tailShare > 0f) {
					t.x -= nx * excess * tailShare;
					t.y -= ny * excess * tailShare;
					// Strip the outward velocity component so a hanging
					// sprite swings instead of accelerating into the leash.
					float radial = t.velocityX * nx + t.velocityY * ny;
					if (radial > 0f) {
						t.velocityX -= radial * nx;
						t.velocityY -= radial * ny;
					}
				}
			}
		}
		float damp = damping;
		float fall = gravity * dt * dt;
		int lastFree = tailPinned ? count - 2 : count - 1;
		for (int i = 1; i <= lastFree; i++) {
			float vx = (px[i] - prevX[i]) * damp;
			float vy = (py[i] - prevY[i]) * damp;
			prevX[i] = px[i];
			prevY[i] = py[i];
			px[i] += vx;
			py[i] += vy + fall;
		}
		px[0] = headX;
		py[0] = headY;
		prevX[0] = headX;
		prevY[0] = headY;
		if (tailPinned) {
			px[count - 1] = t.x;
			py[count - 1] = t.y;
			prevX[count - 1] = t.x;
			prevY[count - 1] = t.y;
		}

		float length = Math.max(1f, segmentLength);
		int passes = Math.max(1, iterations);
		for (int k = 0; k < passes; k++) {
			for (int i = 0; i < segs; i++) {
				float dx = px[i + 1] - px[i];
				float dy = py[i + 1] - py[i];
				float d = (float) Math.sqrt(dx * dx + dy * dy);
				if (d < 1e-5f) {
					d = 1e-5f;
				}
				float diff = (d - length) / d;
				boolean pinA = (i == 0);
				boolean pinB = tailPinned && (i + 1 == count - 1);
				if (pinA && pinB) {
					continue;
				}
				if (pinA) {
					px[i + 1] -= dx * diff;
					py[i + 1] -= dy * diff;
				} else if (pinB) {
					px[i] += dx * diff;
					py[i] += dy * diff;
				} else {
					float half = diff * 0.5f;
					px[i] += dx * half;
					py[i] += dy * half;
					px[i + 1] -= dx * half;
					py[i + 1] -= dy * half;
				}
			}
		}
		endX = px[count - 1];
		endY = py[count - 1];
	}

	/** New point chain, hanging straight down from the head. */
	private void rebuild(int count, float headX, float headY)
	{
		px = new float[count];
		py = new float[count];
		prevX = new float[count];
		prevY = new float[count];
		float length = Math.max(1f, segmentLength);
		for (int i = 0; i < count; i++) {
			px[i] = headX;
			py[i] = headY + i * length;
			prevX[i] = px[i];
			prevY[i] = py[i];
		}
		pointCount = count;
	}

	/** Draws all segments through the shared batcher. GL thread. */
	public void draw(SpriteBatch batch)
	{
		SpriteSheet sh = sheet;
		if (!visible || pointCount < 2 || sh == null || !sh.isReady()) {
			return;
		}
		SpriteSheet.Frame f = sh.frame(frame);
		if (f == null) {
			return;
		}
		float half = thickness * 0.5f;
		float overlap = half * 0.6f; // extend ends so bent joints don't gap
		int texture = sh.textureId();
		for (int i = 0; i < pointCount - 1; i++) {
			float dx = px[i + 1] - px[i];
			float dy = py[i + 1] - py[i];
			float d = (float) Math.sqrt(dx * dx + dy * dy);
			if (d < 1e-5f) {
				continue;
			}
			float ux = dx / d * overlap;
			float uy = dy / d * overlap;
			batch.drawSegment(texture, f,
				px[i] - ux, py[i] - uy,
				px[i + 1] + ux, py[i + 1] + uy,
				half, 1f);
		}
	}
}
