package ti.game.engine;

import java.util.Arrays;

/**
 * Precomputed polyline a sprite walks at constant speed (followPath).
 * Built once on the JS thread — including optional corner smoothing,
 * which replaces each interior corner with a sampled quadratic Bezier —
 * so the per-frame advance on the GL thread is just a cursor walk over
 * cumulative segment lengths: no allocation, no bridge traffic.
 */
public class Path
{
	// Sample points per rounded corner (excluding the entry/exit points)
	private static final int SMOOTH_STEPS = 6;

	public final float[] xs;
	public final float[] ys;
	public final boolean loop;
	public final boolean rotate;
	public final float speed; // px/s

	// cumulative[i] = path length from the start to point i; for loops the
	// closing segment back to point 0 exists only in totalLength.
	private final float[] cumulative;
	public final float totalLength;

	// Progress cursor, GL thread only
	private float distance = 0f;
	private int segment = 0;

	private Path(float[] xs, float[] ys, boolean loop, boolean rotate, float speed)
	{
		this.xs = xs;
		this.ys = ys;
		this.loop = loop;
		this.rotate = rotate;
		this.speed = speed;
		cumulative = new float[xs.length];
		float total = 0f;
		for (int i = 1; i < xs.length; i++) {
			total += (float) Math.hypot(xs[i] - xs[i - 1], ys[i] - ys[i - 1]);
			cumulative[i] = total;
		}
		if (loop) {
			total += (float) Math.hypot(xs[0] - xs[xs.length - 1], ys[0] - ys[xs.length - 1]);
		}
		totalLength = total;
	}

	/**
	 * Builds a path from raw waypoints. smoothing > 0 rounds every interior
	 * corner (for loops: every corner) with that radius in px, clamped to
	 * half the adjacent segment lengths. Returns null for fewer than two
	 * distinct points.
	 */
	public static Path build(float[] rawX, float[] rawY, float smoothing,
							 boolean loop, boolean rotate, float speed)
	{
		// Drop consecutive duplicates — zero-length segments break the
		// cursor walk and the heading math.
		int n = 0;
		float[] px = new float[rawX.length];
		float[] py = new float[rawY.length];
		for (int i = 0; i < rawX.length; i++) {
			if (n > 0 && rawX[i] == px[n - 1] && rawY[i] == py[n - 1]) {
				continue;
			}
			px[n] = rawX[i];
			py[n] = rawY[i];
			n++;
		}
		// A loop closes itself; an explicitly repeated first point would
		// add a zero-length closing segment.
		if (loop && n > 1 && px[0] == px[n - 1] && py[0] == py[n - 1]) {
			n--;
		}
		if (n < 2) {
			return null;
		}
		if (smoothing <= 0f || n < 3) {
			return new Path(Arrays.copyOf(px, n), Arrays.copyOf(py, n), loop, rotate, speed);
		}

		// Corner rounding: cut into both adjacent segments by the radius
		// and bridge the gap with a quadratic Bezier through the corner.
		int corners = loop ? n : n - 2;
		int capacity = n + corners * (SMOOTH_STEPS + 1);
		float[] sx = new float[capacity];
		float[] sy = new float[capacity];
		int count = 0;
		if (!loop) {
			sx[count] = px[0];
			sy[count] = py[0];
			count++;
		}
		int first = loop ? 0 : 1;
		int last = loop ? n - 1 : n - 2;
		for (int i = first; i <= last; i++) {
			float cx = px[i];
			float cy = py[i];
			int prev = (i + n - 1) % n;
			int next = (i + 1) % n;
			float d1 = (float) Math.hypot(px[prev] - cx, py[prev] - cy);
			float d2 = (float) Math.hypot(px[next] - cx, py[next] - cy);
			float d = Math.min(smoothing, Math.min(d1 / 2f, d2 / 2f));
			float ax = cx + (px[prev] - cx) / d1 * d; // entry point
			float ay = cy + (py[prev] - cy) / d1 * d;
			float bx = cx + (px[next] - cx) / d2 * d; // exit point
			float by = cy + (py[next] - cy) / d2 * d;
			for (int k = 0; k <= SMOOTH_STEPS; k++) {
				float t = (float) k / SMOOTH_STEPS;
				float u = 1f - t;
				sx[count] = u * u * ax + 2f * u * t * cx + t * t * bx;
				sy[count] = u * u * ay + 2f * u * t * cy + t * t * by;
				count++;
			}
		}
		if (!loop) {
			sx[count] = px[n - 1];
			sy[count] = py[n - 1];
			count++;
		}
		return new Path(Arrays.copyOf(sx, count), Arrays.copyOf(sy, count), loop, rotate, speed);
	}

	/**
	 * Advances by speed * dt and writes {x, y, headingDegrees} into out
	 * (heading 0 = up, clockwise — the sprite rotation convention).
	 * Returns true once a non-looping run has reached the end.
	 * GL thread only.
	 */
	public boolean advance(float dt, float[] out)
	{
		boolean finished = false;
		distance += speed * dt;
		if (distance >= totalLength) {
			if (loop && totalLength > 0f) {
				distance %= totalLength;
				segment = 0;
			} else {
				distance = totalLength;
				finished = true;
			}
		}
		int n = xs.length;
		int segCount = loop ? n : n - 1;
		while (segment < segCount - 1 && distance > segmentEnd(segment)) {
			segment++;
		}
		float segStart = cumulative[segment];
		float length = segmentEnd(segment) - segStart;
		float t = (length > 0f) ? Math.min(1f, (distance - segStart) / length) : 1f;
		float x0 = xs[segment];
		float y0 = ys[segment];
		float x1 = xs[(segment + 1) % n];
		float y1 = ys[(segment + 1) % n];
		out[0] = x0 + (x1 - x0) * t;
		out[1] = y0 + (y1 - y0) * t;
		out[2] = (float) Math.toDegrees(Math.atan2(x1 - x0, -(y1 - y0)));
		return finished;
	}

	private float segmentEnd(int i)
	{
		return (i + 1 < cumulative.length) ? cumulative[i + 1] : totalLength;
	}
}
