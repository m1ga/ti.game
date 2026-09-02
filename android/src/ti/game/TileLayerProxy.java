package ti.game;

import android.graphics.Color;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollProxy;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.titanium.util.TiConvert;

import java.util.HashSet;
import java.util.Set;

import ti.game.engine.TileLayer;

/**
 * JS-facing tile map layer:
 *
 *   var ground = Game.createTileLayer({
 *       sheet: tileSheet,            // frame index = tile id
 *       tileWidth: 32, tileHeight: 32,
 *       data: [                      // rows of ids, a flat array, or strings + legend
 *           'WWWWWW',
 *           'W....W',
 *           'WWWWWW'
 *       ],
 *       legend: { W: 3, '.': 0 },    // char → frame; unlisted chars are empty
 *       collisionGroup: 'wall',      // what movers list in solidWith
 *       solid: [3],                  // tile ids that block
 *       oneWay: [7],                 // tile ids that only catch from above
 *       zIndex: -1
 *   });
 *   gameView.add(ground);
 *
 * Tiled JSON: pass `data: layer.data, cols: map.width, rows: map.height,
 * firstGid: tileset.firstgid` — gid 0 becomes an empty cell and the flip
 * bits are masked off. Cells are edited with setTile/getTile/setBlocked;
 * tileAt(x, y) maps a world point back to a cell.
 */
@Kroll.proxy(creatableInModule = TiGameModule.class)
public class TileLayerProxy extends KrollProxy
{
	private final TileLayer layer = new TileLayer();
	private SpriteSheetProxy sheetProxy;
	private KrollDict legend;
	private int firstGid = 0;
	private int cols = 0;
	private int rows = 0;
	private Object[] solidIds;
	private Object[] oneWayIds;
	private String tintColor;

	public TileLayer getLayer()
	{
		return layer;
	}

	@Override
	public void handleCreationDict(KrollDict options)
	{
		super.handleCreationDict(options);
		if (options.containsKey("sheet") && options.get("sheet") instanceof SpriteSheetProxy) {
			setSheet((SpriteSheetProxy) options.get("sheet"));
		}
		if (options.containsKey("tileWidth")) {
			layer.tileWidth = TiConvert.toFloat(options.get("tileWidth"), 0f);
		}
		if (options.containsKey("tileHeight")) {
			layer.tileHeight = TiConvert.toFloat(options.get("tileHeight"), 0f);
		}
		if (options.containsKey("x")) {
			layer.x = TiConvert.toFloat(options.get("x"), 0f);
		}
		if (options.containsKey("y")) {
			layer.y = TiConvert.toFloat(options.get("y"), 0f);
		}
		if (options.containsKey("zIndex")) {
			layer.zIndex = TiConvert.toInt(options.get("zIndex"), 0);
		}
		if (options.containsKey("visible")) {
			layer.visible = TiConvert.toBoolean(options.get("visible"), true);
		}
		if (options.containsKey("opacity")) {
			layer.opacity = Values.ratio(options.get("opacity"), 1f);
		}
		if (options.containsKey("scrollFactor")) {
			layer.scrollFactor = Values.ratio(options.get("scrollFactor"), 1f);
		}
		if (options.containsKey("tintColor")) {
			setTintColor(TiConvert.toString(options.get("tintColor")));
		}
		if (options.containsKey("collisionGroup")) {
			layer.collisionGroup = TiConvert.toString(options.get("collisionGroup"));
		}
		if (options.containsKey("restitution")) {
			layer.restitution = Values.ratio(options.get("restitution"), 0f);
		}
		if (options.containsKey("debug")) {
			layer.debug = TiConvert.toBoolean(options.get("debug"), false);
		}
		// Grid inputs, in dependency order: the legend and gid offset shape
		// the ids, the id sets shape the flags, the data needs all of them
		if (options.containsKey("legend")) {
			// nested JS objects arrive as plain HashMaps, not KrollDicts
			legend = options.getKrollDict("legend");
		}
		if (options.containsKey("firstGid")) {
			firstGid = TiConvert.toInt(options.get("firstGid"), 0);
		}
		if (options.containsKey("cols")) {
			cols = TiConvert.toInt(options.get("cols"), 0);
		}
		if (options.containsKey("rows")) {
			rows = TiConvert.toInt(options.get("rows"), 0);
		}
		if (options.containsKey("solid")) {
			solidIds = toArray(options.get("solid"));
		}
		if (options.containsKey("oneWay")) {
			oneWayIds = toArray(options.get("oneWay"));
		}
		applySolidIds();
		if (options.containsKey("data")) {
			setData(options.get("data"));
		} else if (cols > 0 && rows > 0) {
			layer.setGrid(cols, rows, new int[0]); // all empty, fill from JS
		}
	}

	private static Object[] toArray(Object value)
	{
		return (value instanceof Object[]) ? (Object[]) value : null;
	}

	// --- Grid data ------------------------------------------------------------

	/**
	 * Replaces the whole map. Accepts an array of rows (arrays of ids or
	 * strings decoded through `legend`), or a flat row-major array sized
	 * by `cols`/`rows` (rows is inferred from the length when omitted).
	 */
	@Kroll.setProperty
	public void setData(Object value)
	{
		if (!(value instanceof Object[])) {
			layer.setGrid(0, 0, null);
			return;
		}
		Object[] items = (Object[]) value;
		if (items.length == 0) {
			layer.setGrid(0, 0, null);
			return;
		}
		boolean nested = items[0] instanceof Object[] || items[0] instanceof String;
		if (nested) {
			int width = 0;
			for (Object row : items) {
				width = Math.max(width, rowLength(row));
			}
			cols = width;
			rows = items.length;
			int[] ids = new int[cols * rows];
			for (int r = 0; r < rows; r++) {
				Object row = items[r];
				for (int c = 0; c < cols; c++) {
					ids[r * cols + c] = cellId(row, c);
				}
			}
			layer.setGrid(cols, rows, ids);
			return;
		}
		if (cols <= 0) {
			cols = items.length; // a single row
		}
		if (rows <= 0) {
			rows = (items.length + cols - 1) / cols;
		}
		int[] ids = new int[cols * rows];
		for (int i = 0; i < ids.length; i++) {
			ids[i] = (i < items.length) ? toId(items[i]) : TileLayer.EMPTY;
		}
		layer.setGrid(cols, rows, ids);
	}

	private static int rowLength(Object row)
	{
		if (row instanceof Object[]) {
			return ((Object[]) row).length;
		}
		if (row instanceof String) {
			return ((String) row).length();
		}
		return 0;
	}

	private int cellId(Object row, int col)
	{
		if (row instanceof Object[]) {
			Object[] cells = (Object[]) row;
			return (col < cells.length) ? toId(cells[col]) : TileLayer.EMPTY;
		}
		if (row instanceof String) {
			String text = (String) row;
			return (col < text.length()) ? legendId(text.substring(col, col + 1)) : TileLayer.EMPTY;
		}
		return TileLayer.EMPTY;
	}

	/** A legend character → id; unlisted characters are empty cells. */
	private int legendId(String key)
	{
		KrollDict map = legend;
		if (map == null || !map.containsKey(key)) {
			return TileLayer.EMPTY;
		}
		return toId(map.get(key));
	}

	/** A raw cell value → frame index: gid offset, flip bits, empties. */
	private int toId(Object value)
	{
		if (value == null) {
			return TileLayer.EMPTY;
		}
		if (value instanceof String) {
			return legendId((String) value);
		}
		if (!(value instanceof Number)) {
			return TileLayer.EMPTY;
		}
		long raw = ((Number) value).longValue();
		if (raw < 0 || (raw == 0 && firstGid > 0)) {
			return TileLayer.EMPTY; // negative = empty; Tiled: gid 0 = no tile
		}
		int id = (int) (raw & 0x0FFFFFFFL) - firstGid; // strip Tiled's flip flags
		return (id < 0) ? TileLayer.EMPTY : id;
	}

	private void applySolidIds()
	{
		layer.setSolidIds(toIdSet(solidIds), toIdSet(oneWayIds));
	}

	private Set<Integer> toIdSet(Object[] values)
	{
		if (values == null) {
			return null;
		}
		Set<Integer> set = new HashSet<>();
		for (Object value : values) {
			int id = toId(value);
			if (id >= 0) {
				set.add(id);
			}
		}
		return set;
	}

	/** Tile ids (or legend characters) that block from every side. */
	@Kroll.setProperty
	public void setSolid(Object value)
	{
		solidIds = toArray(value);
		applySolidIds();
	}

	@Kroll.getProperty
	public Object[] getSolid()
	{
		return solidIds;
	}

	/** Tile ids (or legend characters) that only catch riders falling onto them. */
	@Kroll.setProperty
	public void setOneWay(Object value)
	{
		oneWayIds = toArray(value);
		applySolidIds();
	}

	@Kroll.getProperty
	public Object[] getOneWay()
	{
		return oneWayIds;
	}

	@Kroll.getProperty
	public int getCols()
	{
		return layer.cols();
	}

	@Kroll.getProperty
	public int getRows()
	{
		return layer.rows();
	}

	/** World size of the whole layer (read-only). */
	@Kroll.getProperty
	public float getWidth()
	{
		return layer.width();
	}

	@Kroll.getProperty
	public float getHeight()
	{
		return layer.height();
	}

	// --- Cell access ----------------------------------------------------------

	/** Frame index at the cell, -1 when empty or outside the grid. */
	@Kroll.method
	public int getTile(int col, int row)
	{
		return layer.tile(col, row);
	}

	/** Writes one cell (-1 clears it); solid/one-way follows the id lists. */
	@Kroll.method
	public void setTile(int col, int row, Object id)
	{
		layer.setTile(col, row, toId(id));
	}

	/** Blocking cell? (one-way platforms answer false) */
	@Kroll.method
	public boolean isBlocked(int col, int row)
	{
		return layer.isSolid(col, row);
	}

	/** Overrides one cell's blocking flag, whatever tile it shows — an
	 *  invisible wall, or a door that opens without changing its art. */
	@Kroll.method
	public void setBlocked(int col, int row, boolean blocked)
	{
		layer.setFlag(col, row, blocked ? TileLayer.FLAG_SOLID : 0);
	}

	/** The cell under a world point: { col, row, tile, solid }, or null outside the grid. */
	@Kroll.method
	public KrollDict tileAt(float x, float y)
	{
		int col = layer.colAt(x);
		int row = layer.rowAt(y);
		if (!layer.inGrid(col, row)) {
			return null;
		}
		return cellInfo(col, row);
	}

	/** World center of a cell: { x, y }, plus its tile and solid flag. */
	@Kroll.method
	public KrollDict cellAt(int col, int row)
	{
		if (!layer.inGrid(col, row)) {
			return null;
		}
		return cellInfo(col, row);
	}

	private KrollDict cellInfo(int col, int row)
	{
		KrollDict info = new KrollDict();
		info.put("col", col);
		info.put("row", row);
		info.put("tile", layer.tile(col, row));
		info.put("solid", layer.isSolid(col, row));
		info.put("x", layer.x + (col + 0.5f) * layer.cellWidth());
		info.put("y", layer.y + (row + 0.5f) * layer.cellHeight());
		return info;
	}

	// --- Look & placement -------------------------------------------------------

	@Kroll.setProperty
	public void setSheet(Object value)
	{
		// Object + instanceof: a mistyped JS value must not reach a typed JNI slot
		SpriteSheetProxy proxy = (value instanceof SpriteSheetProxy) ? (SpriteSheetProxy) value : null;
		sheetProxy = proxy;
		layer.sheet = (proxy != null) ? proxy.getSheet() : null;
	}

	@Kroll.getProperty
	public SpriteSheetProxy getSheet()
	{
		return sheetProxy;
	}

	@Kroll.getProperty
	public float getTileWidth()
	{
		return layer.cellWidth();
	}

	@Kroll.setProperty
	public void setTileWidth(float value)
	{
		layer.tileWidth = value;
	}

	@Kroll.getProperty
	public float getTileHeight()
	{
		return layer.cellHeight();
	}

	@Kroll.setProperty
	public void setTileHeight(float value)
	{
		layer.tileHeight = value;
	}

	@Kroll.getProperty
	public float getX()
	{
		return layer.x;
	}

	@Kroll.setProperty
	public void setX(float value)
	{
		layer.x = value;
	}

	@Kroll.getProperty
	public float getY()
	{
		return layer.y;
	}

	@Kroll.setProperty
	public void setY(float value)
	{
		layer.y = value;
	}

	@Kroll.getProperty
	public int getZIndex()
	{
		return layer.zIndex;
	}

	@Kroll.setProperty
	public void setZIndex(int value)
	{
		layer.zIndex = value;
	}

	@Kroll.getProperty
	public boolean getVisible()
	{
		return layer.visible;
	}

	@Kroll.setProperty
	public void setVisible(boolean value)
	{
		layer.visible = value;
	}

	@Kroll.getProperty
	public float getOpacity()
	{
		return layer.opacity;
	}

	@Kroll.setProperty
	public void setOpacity(Object value)
	{
		layer.opacity = Values.ratio(value, layer.opacity);
	}

	@Kroll.getProperty
	public float getScrollFactor()
	{
		return layer.scrollFactor;
	}

	@Kroll.setProperty
	public void setScrollFactor(Object value)
	{
		layer.scrollFactor = Values.ratio(value, layer.scrollFactor);
	}

	/** Multiplies every tile's colors, e.g. '#8af' for a night look; null = unchanged. */
	@Kroll.setProperty
	public void setTintColor(String value)
	{
		tintColor = value;
		if (value == null) {
			layer.tintR = 1f;
			layer.tintG = 1f;
			layer.tintB = 1f;
			return;
		}
		try {
			int color = Color.parseColor(expandShortHex(value));
			layer.tintR = Color.red(color) / 255f;
			layer.tintG = Color.green(color) / 255f;
			layer.tintB = Color.blue(color) / 255f;
		} catch (IllegalArgumentException e) {
			// keep previous color
		}
	}

	@Kroll.getProperty
	public String getTintColor()
	{
		return tintColor;
	}

	private static String expandShortHex(String value)
	{
		if (value.length() == 4 && value.charAt(0) == '#') {
			return new String(new char[] {
				'#',
				value.charAt(1), value.charAt(1),
				value.charAt(2), value.charAt(2),
				value.charAt(3), value.charAt(3)
			});
		}
		return value;
	}

	// --- Collision ----------------------------------------------------------------

	@Kroll.getProperty
	public String getCollisionGroup()
	{
		return layer.collisionGroup;
	}

	@Kroll.setProperty
	public void setCollisionGroup(String value)
	{
		layer.collisionGroup = value;
	}

	@Kroll.getProperty
	public float getRestitution()
	{
		return layer.restitution;
	}

	@Kroll.setProperty
	public void setRestitution(Object value)
	{
		layer.restitution = Values.ratio(value, layer.restitution);
	}

	@Kroll.getProperty
	public boolean getDebug()
	{
		return layer.debug;
	}

	@Kroll.setProperty
	public void setDebug(boolean value)
	{
		layer.debug = value;
	}

	@Override
	public String getApiName()
	{
		return "ti.game.TileLayer";
	}
}
