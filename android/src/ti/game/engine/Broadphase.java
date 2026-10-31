package ti.game.engine;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Uniform-grid broadphase over the scene's per-frame `tagged` list (the
 * visible sprites that carry a collisionGroup). Without it every mover
 * scans the whole tagged list, so cost grows with the square of tagged
 * sprites; with it a query walks only the grid cells its box covers.
 *
 * Rebuilt by Scene.update once before solid resolution and once before
 * collision events (attachments and wrap normalization teleport sprites
 * in between). Entry boxes are inflated by the sprite's own frame delta
 * plus a small slack, so a solid that is itself pushed out after the
 * build is still found by later movers — a push-out never exceeds the
 * penetration, which never exceeds the frame's movement plus slack in
 * practice. The result is conservative: a candidate still has to pass
 * the exact shape test, a false candidate only costs that test.
 *
 * Sprites covering more than LARGE_CELLS cells (a huge floor) go to a
 * `large` list that every query includes, which bounds entry counts; a
 * query covering more than QUERY_CELLS falls back to the full list.
 * World wrap: a wrapping query sprite also looks one period to either
 * side, mirroring Scene.periodicOffsetX. Dedupe uses a per-query stamp
 * on the sprite (Sprite.broadphaseStamp). GL thread only.
 */
final class Broadphase
{
	private static final float MARGIN = 4f;
	private static final int LARGE_CELLS = 64;
	private static final int QUERY_CELLS = 256;
	private static final float MIN_CELL = 32f;
	private static final float MAX_CELL = 512f;
	private static final float SIZE_CAP = 256f; // clamp per sprite when averaging cell size

	private final List<Sprite> candidates = new ArrayList<>();
	private final List<Sprite> large = new ArrayList<>();
	private List<Sprite> tagged = new ArrayList<>();
	private float[] bounds = new float[0];        // 4 per tagged sprite, inflated
	private int[] bucketHead = new int[0];
	private int bucketMask = 0;
	private Sprite[] entrySprite = new Sprite[64];
	private int[] entryNext = new int[64];
	private long[] entryKey = new long[64];
	private int entryCount = 0;
	private float invCell = 1f / 64f;
	private float wrapWidth = 0f;
	private float entriesMinX, entriesMaxX;
	private int stamp = 0;
	private final float[] box = new float[4];
	private final float[] center = new float[2];

	/** Index the tagged list at its current positions. wrapWidth 0 = no world wrap. */
	void rebuild(List<Sprite> tagged, float wrapWidth)
	{
		this.tagged = tagged;
		this.wrapWidth = wrapWidth;
		int n = tagged.size();
		stamp = 0;
		large.clear();
		entryCount = 0;
		entriesMinX = Float.MAX_VALUE;
		entriesMaxX = -Float.MAX_VALUE;
		if (bounds.length < n * 4) {
			bounds = new float[Math.max(n * 4, bounds.length * 2)];
		}
		float sizeSum = 0f;
		for (int i = 0; i < n; i++) {
			Sprite s = tagged.get(i);
			s.taggedIndex = i;
			s.broadphaseStamp = 0;
			shapeBounds(s, box);
			sizeSum += Math.min(Math.max(box[2] - box[0], box[3] - box[1]), SIZE_CAP);
			inflate(s, box);
			int o = i * 4;
			bounds[o] = box[0];
			bounds[o + 1] = box[1];
			bounds[o + 2] = box[2];
			bounds[o + 3] = box[3];
			entriesMinX = Math.min(entriesMinX, box[0]);
			entriesMaxX = Math.max(entriesMaxX, box[2]);
		}
		if (n == 0) {
			return;
		}
		float cell = Math.max(MIN_CELL, Math.min(MAX_CELL, (sizeSum / n) * 2f));
		invCell = 1f / cell;
		int buckets = 64;
		while (buckets < n * 2 && buckets < (1 << 16)) {
			buckets <<= 1;
		}
		if (bucketHead.length != buckets) {
			bucketHead = new int[buckets];
		}
		bucketMask = buckets - 1;
		Arrays.fill(bucketHead, -1);
		for (int i = 0; i < n; i++) {
			int o = i * 4;
			int cx0 = cellOf(bounds[o]);
			int cy0 = cellOf(bounds[o + 1]);
			int cx1 = cellOf(bounds[o + 2]);
			int cy1 = cellOf(bounds[o + 3]);
			long spanX = (long) cx1 - cx0 + 1;
			long spanY = (long) cy1 - cy0 + 1;
			Sprite s = tagged.get(i);
			if (spanX <= 0 || spanY <= 0 || spanX * spanY > LARGE_CELLS) {
				large.add(s); // also catches NaN/infinite positions
				continue;
			}
			for (int cy = cy0; cy <= cy1; cy++) {
				for (int cx = cx0; cx <= cx1; cx++) {
					insert(s, cx, cy);
				}
			}
		}
	}

	/** Candidates near the sprite's own hit shape (rect AABB or circle). */
	List<Sprite> queryShape(Sprite s)
	{
		shapeBounds(s, box);
		return query(s, box[0], box[1], box[2], box[3]);
	}

	/** Like queryShape, extended back over the frame's movement (swept tests). */
	List<Sprite> querySwept(Sprite s)
	{
		shapeBounds(s, box);
		float dx = s.frameDeltaX;
		float dy = s.frameDeltaY;
		return query(s, Math.min(box[0], box[0] - dx), Math.min(box[1], box[1] - dy),
			Math.max(box[2], box[2] - dx), Math.max(box[3], box[3] - dy));
	}

	/**
	 * Tagged sprites whose inflated entry box may touch the given box (the
	 * query sprite itself included when tagged). The returned list is
	 * reused by the next query — consume it before querying again. Every
	 * sprite in it carries the current stamp().
	 */
	List<Sprite> query(Sprite s, float minX, float minY, float maxX, float maxY)
	{
		candidates.clear();
		stamp++;
		if (tagged.isEmpty()) {
			return candidates;
		}
		float pad = MARGIN + Math.max(Math.abs(s.frameDeltaX), Math.abs(s.frameDeltaY));
		minX -= pad;
		minY -= pad;
		maxX += pad;
		maxY += pad;
		for (int i = 0, n = large.size(); i < n; i++) {
			mark(large.get(i));
		}
		collect(minX, minY, maxX, maxY);
		float w = wrapWidth;
		if (w > 0f && s.wrapWorldX && !s.screenFixed) {
			// The periodic images one world to either side, when any entry
			// lies there at all
			if (maxX + w >= entriesMinX && minX + w <= entriesMaxX) {
				collect(minX + w, minY, maxX + w, maxY);
			}
			if (maxX - w >= entriesMinX && minX - w <= entriesMaxX) {
				collect(minX - w, minY, maxX - w, maxY);
			}
		}
		return candidates;
	}

	/** Stamp written on every sprite the latest query returned. */
	int stamp()
	{
		return stamp;
	}

	private void collect(float minX, float minY, float maxX, float maxY)
	{
		int cx0 = cellOf(minX);
		int cy0 = cellOf(minY);
		int cx1 = cellOf(maxX);
		int cy1 = cellOf(maxY);
		long spanX = (long) cx1 - cx0 + 1;
		long spanY = (long) cy1 - cy0 + 1;
		if (spanX <= 0 || spanY <= 0 || spanX * spanY > QUERY_CELLS) {
			for (int i = 0, n = tagged.size(); i < n; i++) {
				mark(tagged.get(i));
			}
			return;
		}
		for (int cy = cy0; cy <= cy1; cy++) {
			for (int cx = cx0; cx <= cx1; cx++) {
				long key = key(cx, cy);
				for (int e = bucketHead[hash(cx, cy) & bucketMask]; e >= 0; e = entryNext[e]) {
					if (entryKey[e] == key) {
						mark(entrySprite[e]);
					}
				}
			}
		}
	}

	private void mark(Sprite s)
	{
		if (s.broadphaseStamp != stamp) {
			s.broadphaseStamp = stamp;
			candidates.add(s);
		}
	}

	private void insert(Sprite s, int cx, int cy)
	{
		if (entryCount == entrySprite.length) {
			int cap = entryCount * 2;
			entrySprite = Arrays.copyOf(entrySprite, cap);
			entryNext = Arrays.copyOf(entryNext, cap);
			entryKey = Arrays.copyOf(entryKey, cap);
		}
		int b = hash(cx, cy) & bucketMask;
		entrySprite[entryCount] = s;
		entryKey[entryCount] = key(cx, cy);
		entryNext[entryCount] = bucketHead[b];
		bucketHead[b] = entryCount++;
	}

	private int cellOf(float v)
	{
		return (int) Math.floor(v * invCell);
	}

	private static int hash(int cx, int cy)
	{
		return (cx * 73856093) ^ (cy * 19349663);
	}

	private static long key(int cx, int cy)
	{
		return ((long) cx << 32) | (cy & 0xffffffffL);
	}

	/** World box of the hit shape the narrow tests use: circle or (rotated) rect. */
	private void shapeBounds(Sprite s, float[] out)
	{
		if (s.circleHitbox) {
			s.hitCenter(center);
			float r = s.hitRadius();
			out[0] = center[0] - r;
			out[1] = center[1] - r;
			out[2] = center[0] + r;
			out[3] = center[1] + r;
		} else {
			s.computeAABB(out);
		}
	}

	private static void inflate(Sprite s, float[] b)
	{
		float px = MARGIN + Math.abs(s.frameDeltaX);
		float py = MARGIN + Math.abs(s.frameDeltaY);
		b[0] -= px;
		b[1] -= py;
		b[2] += px;
		b[3] += py;
	}
}
