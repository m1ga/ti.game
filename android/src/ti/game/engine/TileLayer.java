package ti.game.engine;

import java.util.Set;

/**
 * Native tile map layer: a cols x rows grid of sheet frame indices drawn
 * as axis-aligned quads, plus a per-cell flag grid that feeds the solid
 * resolver and the pathfinder. Any map size — only the cells inside the
 * visible rect are touched per frame, and a mover only tests the handful
 * of cells under its own hitbox, so a 200x200 level costs the same as a
 * 20x20 one. No per-tile objects, no per-tile update.
 *
 * Configuration fields are volatile (JS thread writes, GL thread reads).
 * The grid arrays are replaced as a whole on resize (under `this`); a
 * single-cell write is a plain array store, atomic per element, so the
 * GL thread sees the old or the new tile, never a torn one.
 *
 * Cell flags: FLAG_SOLID blocks from every side, FLAG_ONE_WAY only
 * catches riders falling onto its top face (platforms). A layer carries
 * one `collisionGroup`; sprites list it in `solidWith` exactly like a
 * solid sprite's group.
 */
public class TileLayer
{
	public static final int EMPTY = -1;
	public static final byte FLAG_SOLID = 1;
	public static final byte FLAG_ONE_WAY = 2;

	// Configuration (JS thread writes, GL thread reads)
	public volatile SpriteSheet sheet;
	public volatile float x = 0f;          // world position of cell (0, 0)'s top-left
	public volatile float y = 0f;
	public volatile float tileWidth = 0f;  // world size per cell; 0 = the sheet's frame size
	public volatile float tileHeight = 0f;
	public volatile int zIndex = 0;
	public volatile boolean visible = true;
	public volatile float opacity = 1f;
	public volatile float tintR = 1f;
	public volatile float tintG = 1f;
	public volatile float tintB = 1f;
	public volatile float scrollFactor = 1f;
	public volatile String collisionGroup;
	public volatile float restitution = 0f;
	public volatile boolean debug = false;

	// Grid — see the class comment for the publication rules
	private volatile int cols = 0;
	private volatile int rows = 0;
	private volatile int[] tiles = new int[0];
	private volatile byte[] flags = new byte[0];

	// Which tile ids count as solid / one-way; setTile() derives a cell's
	// flag from them, setSolid() overrides a single cell until the next
	// setGrid()/setSolidIds().
	private volatile Set<Integer> solidIds;
	private volatile Set<Integer> oneWayIds;

	// --- Grid ---------------------------------------------------------------

	/** Replaces the whole grid; `newTiles` is row-major, EMPTY for no tile. */
	public synchronized void setGrid(int newCols, int newRows, int[] newTiles)
	{
		if (newCols <= 0 || newRows <= 0 || newTiles == null) {
			cols = 0;
			rows = 0;
			tiles = new int[0];
			flags = new byte[0];
			return;
		}
		int n = newCols * newRows;
		int[] t = new int[n];
		System.arraycopy(newTiles, 0, t, 0, Math.min(n, newTiles.length));
		for (int i = newTiles.length; i < n; i++) {
			t[i] = EMPTY;
		}
		byte[] f = new byte[n];
		for (int i = 0; i < n; i++) {
			f[i] = flagFor(t[i]);
		}
		tiles = t;
		flags = f;
		cols = newCols;
		rows = newRows;
	}

	/** Sets the solid / one-way tile id sets and re-derives every cell flag. */
	public synchronized void setSolidIds(Set<Integer> solid, Set<Integer> oneWay)
	{
		solidIds = solid;
		oneWayIds = oneWay;
		int[] t = tiles;
		byte[] f = flags;
		for (int i = 0; i < t.length && i < f.length; i++) {
			f[i] = flagFor(t[i]);
		}
	}

	private byte flagFor(int id)
	{
		if (id < 0) {
			return 0;
		}
		Set<Integer> solid = solidIds;
		if (solid != null && solid.contains(id)) {
			return FLAG_SOLID;
		}
		Set<Integer> oneWay = oneWayIds;
		if (oneWay != null && oneWay.contains(id)) {
			return FLAG_ONE_WAY;
		}
		return 0;
	}

	public int cols()
	{
		return cols;
	}

	public int rows()
	{
		return rows;
	}

	public boolean inGrid(int col, int row)
	{
		return col >= 0 && row >= 0 && col < cols && row < rows;
	}

	/** Frame index at the cell, EMPTY outside the grid or for an empty cell. */
	public int tile(int col, int row)
	{
		if (!inGrid(col, row)) {
			return EMPTY;
		}
		int[] t = tiles;
		int i = row * cols + col;
		return (i < t.length) ? t[i] : EMPTY;
	}

	/** Writes one cell; the flag follows the id (solid/one-way sets). */
	public void setTile(int col, int row, int id)
	{
		if (!inGrid(col, row)) {
			return;
		}
		int i = row * cols + col;
		int[] t = tiles;
		byte[] f = flags;
		if (i < t.length && i < f.length) {
			t[i] = (id < 0) ? EMPTY : id;
			f[i] = flagFor(t[i]);
		}
	}

	/** Cell flag (FLAG_*), 0 outside the grid. */
	public byte flag(int col, int row)
	{
		if (!inGrid(col, row)) {
			return 0;
		}
		byte[] f = flags;
		int i = row * cols + col;
		return (i < f.length) ? f[i] : 0;
	}

	public void setFlag(int col, int row, byte flag)
	{
		if (!inGrid(col, row)) {
			return;
		}
		byte[] f = flags;
		int i = row * cols + col;
		if (i < f.length) {
			f[i] = flag;
		}
	}

	/** Fully blocking cell? (one-way platforms are not walls) */
	public boolean isSolid(int col, int row)
	{
		return (flag(col, row) & FLAG_SOLID) != 0;
	}

	// --- Geometry -----------------------------------------------------------

	/** World width of one cell: tileWidth, else the sheet's frame width. */
	public float cellWidth()
	{
		float w = tileWidth;
		if (w > 0f) {
			return w;
		}
		SpriteSheet sh = sheet;
		SpriteSheet.Frame f = (sh != null) ? sh.frame(0) : null;
		return (f != null) ? f.width : 0f;
	}

	public float cellHeight()
	{
		float h = tileHeight;
		if (h > 0f) {
			return h;
		}
		SpriteSheet sh = sheet;
		SpriteSheet.Frame f = (sh != null) ? sh.frame(0) : null;
		return (f != null) ? f.height : 0f;
	}

	/** World size of the whole layer. */
	public float width()
	{
		return cols * cellWidth();
	}

	public float height()
	{
		return rows * cellHeight();
	}

	/** Column under a world x (may be outside the grid — check inGrid). */
	public int colAt(float worldX)
	{
		float w = cellWidth();
		return (w > 0f) ? (int) Math.floor((worldX - x) / w) : -1;
	}

	public int rowAt(float worldY)
	{
		float h = cellHeight();
		return (h > 0f) ? (int) Math.floor((worldY - y) / h) : -1;
	}

	/** True when this layer's solid cells apply to a mover's `solidWith`. */
	public boolean blocks(Set<String> groups)
	{
		String group = collisionGroup;
		return group != null && visible && cols > 0 && rows > 0 && groups.contains(group);
	}

	/** Same filter raycast/findPath use for sprites: null/empty = any tagged layer. */
	public boolean matches(Set<String> groups)
	{
		String group = collisionGroup;
		return group != null && visible && cols > 0 && rows > 0
			&& (groups == null || groups.isEmpty() || groups.contains(group));
	}

	// --- Drawing (GL thread) ---------------------------------------------

	/**
	 * Draws the cells inside the visible world rect, one quad each, all
	 * from the layer's sheet — one batch run per layer. The rect is the
	 * camera's; parallax layers shift by the unapplied share of the
	 * camera travel exactly like a sprite with the same scrollFactor.
	 */
	public void draw(SpriteBatch batch, float viewLeft, float viewTop, float viewRight, float viewBottom)
	{
		SpriteSheet sh = sheet;
		int c = cols;
		int r = rows;
		int[] t = tiles;
		float alpha = Math.max(0f, Math.min(1f, opacity));
		if (!visible || alpha <= 0f || sh == null || !sh.isReady() || c == 0 || r == 0) {
			return;
		}
		float tw = cellWidth();
		float th = cellHeight();
		if (tw <= 0f || th <= 0f) {
			return;
		}
		float ox = x + batch.parallaxOffsetX(scrollFactor);
		float oy = y + batch.parallaxOffsetY(scrollFactor);
		int c0 = Math.max(0, (int) Math.floor((viewLeft - ox) / tw));
		int c1 = Math.min(c - 1, (int) Math.floor((viewRight - ox) / tw));
		int r0 = Math.max(0, (int) Math.floor((viewTop - oy) / th));
		int r1 = Math.min(r - 1, (int) Math.floor((viewBottom - oy) / th));
		if (c1 < c0 || r1 < r0) {
			return; // entirely off-screen
		}
		batch.setScreenSpace(false);
		batch.setBlendMode(SpriteBatch.BLEND_NORMAL);
		int texture = sh.textureId();
		int frameCount = sh.frameCount();
		float hw = tw / 2f;
		float hh = th / 2f;
		float tr = tintR;
		float tg = tintG;
		float tb = tintB;
		for (int row = r0; row <= r1; row++) {
			int base = row * c;
			float cy = oy + (row + 0.5f) * th;
			for (int col = c0; col <= c1; col++) {
				int i = base + col;
				int id = (i < t.length) ? t[i] : EMPTY;
				if (id < 0 || id >= frameCount) {
					continue;
				}
				SpriteSheet.Frame f = sh.frame(id);
				if (f == null) {
					continue;
				}
				batch.drawFrame(texture, f, ox + (col + 0.5f) * tw, cy, hw, hh, tr, tg, tb, alpha);
			}
		}
	}

	/** Debug overlay: green outline on solid cells, yellow on one-way ones. */
	public void drawDebug(SpriteBatch batch, int whiteTexture,
						  float viewLeft, float viewTop, float viewRight, float viewBottom)
	{
		int c = cols;
		int r = rows;
		byte[] f = flags;
		float tw = cellWidth();
		float th = cellHeight();
		if (c == 0 || r == 0 || tw <= 0f || th <= 0f) {
			return;
		}
		float ox = x + batch.parallaxOffsetX(scrollFactor);
		float oy = y + batch.parallaxOffsetY(scrollFactor);
		int c0 = Math.max(0, (int) Math.floor((viewLeft - ox) / tw));
		int c1 = Math.min(c - 1, (int) Math.floor((viewRight - ox) / tw));
		int r0 = Math.max(0, (int) Math.floor((viewTop - oy) / th));
		int r1 = Math.min(r - 1, (int) Math.floor((viewBottom - oy) / th));
		batch.setScreenSpace(false);
		float t = 1f;
		for (int row = r0; row <= r1; row++) {
			for (int col = c0; col <= c1; col++) {
				int i = row * c + col;
				byte flag = (i < f.length) ? f[i] : 0;
				if (flag == 0) {
					continue;
				}
				boolean oneWay = (flag & FLAG_SOLID) == 0;
				float cr = oneWay ? 1f : 0.2f;
				float cg = oneWay ? 0.85f : 1f;
				float cb = oneWay ? 0.2f : 0.4f;
				float x0 = ox + col * tw + t;
				float y0 = oy + row * th + t;
				float x1 = x0 + tw - 2f * t;
				float y1 = y0 + th - 2f * t;
				batch.drawLine(whiteTexture, x0, y0, x1, y0, t, cr, cg, cb, 0.9f);
				if (!oneWay) {
					batch.drawLine(whiteTexture, x1, y0, x1, y1, t, cr, cg, cb, 0.9f);
					batch.drawLine(whiteTexture, x1, y1, x0, y1, t, cr, cg, cb, 0.9f);
					batch.drawLine(whiteTexture, x0, y1, x0, y0, t, cr, cg, cb, 0.9f);
				}
			}
		}
	}
}
