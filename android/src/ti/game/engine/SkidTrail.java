package ti.game.engine;

/**
 * Ring buffer of fading skid-mark segments, emitted by carMode sprites with
 * skidMarks enabled. Appended, aged and drawn on the GL thread only — no
 * synchronization needed. When full, the oldest segments are overwritten;
 * faded-out segments drop off the tail, so memory stays bounded and old
 * marks fade away instead of accumulating forever.
 */
public class SkidTrail
{
	private static final int MAX_SEGMENTS = 1500;
	private static final int FLOATS = 6; // x0, y0, x1, y1, halfWidth, alpha
	private static final float FADE_PER_SECOND = 0.03f;
	private static final float MIN_ALPHA = 0.02f;

	private final float[] segments = new float[MAX_SEGMENTS * FLOATS];
	private int head = 0;  // next write slot
	private int count = 0;

	public void add(float x0, float y0, float x1, float y1, float halfWidth, float alpha)
	{
		int i = head * FLOATS;
		segments[i] = x0;
		segments[i + 1] = y0;
		segments[i + 2] = x1;
		segments[i + 3] = y1;
		segments[i + 4] = halfWidth;
		segments[i + 5] = alpha;
		head = (head + 1) % MAX_SEGMENTS;
		if (count < MAX_SEGMENTS) {
			count++;
		}
	}

	public boolean isEmpty()
	{
		return count == 0;
	}

	/** Ages all segments and drops fully faded ones from the tail. */
	public void update(float dt)
	{
		float fade = FADE_PER_SECOND * dt;
		int start = (head - count + MAX_SEGMENTS) % MAX_SEGMENTS;
		for (int k = 0; k < count; k++) {
			segments[((start + k) % MAX_SEGMENTS) * FLOATS + 5] -= fade;
		}
		while (count > 0) {
			int i = ((head - count + MAX_SEGMENTS) % MAX_SEGMENTS) * FLOATS;
			if (segments[i + 5] > MIN_ALPHA) {
				break;
			}
			count--;
		}
	}

	public void draw(SpriteBatch batch, int whiteTexture)
	{
		int start = (head - count + MAX_SEGMENTS) % MAX_SEGMENTS;
		for (int k = 0; k < count; k++) {
			int i = ((start + k) % MAX_SEGMENTS) * FLOATS;
			batch.drawLine(whiteTexture,
				segments[i], segments[i + 1], segments[i + 2], segments[i + 3],
				segments[i + 4], 0.07f, 0.07f, 0.08f, segments[i + 5]);
		}
	}

	public void clear()
	{
		head = 0;
		count = 0;
	}
}
