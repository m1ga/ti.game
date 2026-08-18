package ti.game.engine;

import java.util.Locale;

/**
 * The on-screen performance HUD: a compact line that expands into the full
 * set of counters when tapped. Draws through ScreenOverlay's screen-space
 * pass, so it stays pinned to its corner whatever the camera does, and
 * through SegmentFont, so it needs no font atlas.
 *
 * Configured from JS as GameView.debug = { hud: 'topRight' }.
 *
 * The text is rebuilt once per second, when a FrameStats window closes —
 * drawing it every frame only replays cached strings.
 *
 * Threading: `enabled`, `corner` and the panel rect cross threads (the JS
 * thread configures, the GL thread lays out, the UI thread hit-tests), so
 * they are volatile. The strings are GL-thread only.
 *
 * iOS twin: ios/Classes/TGDebugHud.{h,m}.
 */
public class DebugHud
{
	private static final int COLUMNS = 3;
	private static final int MAX_ROWS = 6;

	// Layout, in density-independent units — multiplied by the screen scale.
	private static final float GLYPH_HEIGHT = 9f;
	private static final float ROW_GAP = 5f;
	private static final float COLUMN_GAP = 9f;
	private static final float PADDING = 5f;
	private static final float MARGIN = 8f;

	/** HUD visible at all. */
	public volatile boolean enabled = false;

	/** One of the ScreenOverlay corner constants. */
	public volatile int corner = ScreenOverlay.TOP_LEFT;

	private volatile boolean expanded = false;

	// Panel rect in surface pixels: laid out on the GL thread, hit-tested
	// on the UI thread.
	private volatile float rectX = 0f;
	private volatile float rectY = 0f;
	private volatile float rectWidth = 0f;
	private volatile float rectHeight = 0f;

	// --- GL thread only ---------------------------------------------------
	private final String[][] columns = new String[COLUMNS][MAX_ROWS];
	private final int[] rowCounts = new int[COLUMNS];
	private final float[] columnWidths = new float[COLUMNS];
	private final float[] origin = new float[2];
	private final FrameStats.Snapshot latest = new FrameStats.Snapshot();
	private boolean hasData = false;
	private boolean builtExpanded = false;

	public boolean isExpanded()
	{
		return expanded;
	}

	/** Tapping the panel swaps between the compact line and the full set. */
	public void toggleExpanded()
	{
		expanded = !expanded;
	}

	/** UI thread: is this surface-pixel point on the panel? */
	public boolean hitTest(float surfaceX, float surfaceY)
	{
		if (!enabled) {
			return false;
		}
		float w = rectWidth;
		float h = rectHeight;
		if (w <= 0f || h <= 0f) {
			return false;
		}
		float x = rectX;
		float y = rectY;
		return surfaceX >= x && surfaceX <= x + w && surfaceY >= y && surfaceY <= y + h;
	}

	/** Called when a FrameStats window closes — once a second. */
	public void update(FrameStats.Snapshot s)
	{
		latest.fps = s.fps;
		latest.averageCpuMs = s.averageCpuMs;
		latest.p95CpuMs = s.p95CpuMs;
		latest.maxCpuMs = s.maxCpuMs;
		latest.averageUpdateMs = s.averageUpdateMs;
		latest.averageTexturePrepareMs = s.averageTexturePrepareMs;
		latest.averageBatchMs = s.averageBatchMs;
		latest.droppedFrames = s.droppedFrames;
		latest.sprites = s.sprites;
		latest.visibleSprites = s.visibleSprites;
		latest.emitters = s.emitters;
		latest.particles = s.particles;
		latest.drawCalls = s.drawCalls;
		latest.textureSwitches = s.textureSwitches;
		hasData = true;
		buildText();
	}

	/**
	 * Draws the panel in surface pixels. Call inside the screen-space pass,
	 * after the post-effect. `screenScale` is the display density, so the
	 * HUD reads the same size on a 1x tablet and a 3x phone.
	 */
	public void draw(SpriteBatch batch, int whiteTexture,
					 float surfaceWidth, float surfaceHeight, float screenScale)
	{
		if (!hasData) {
			return;
		}
		if (expanded != builtExpanded) {
			buildText();
		}

		float scale = Math.max(0.5f, screenScale);
		float glyphHeight = GLYPH_HEIGHT * scale;
		float rowGap = ROW_GAP * scale;
		float columnGap = COLUMN_GAP * scale;
		float padding = PADDING * scale;
		float margin = MARGIN * scale;

		int usedColumns = 0;
		int maxRows = 0;
		float contentWidth = 0f;
		for (int c = 0; c < COLUMNS; c++) {
			if (rowCounts[c] == 0) {
				continue;
			}
			float width = 0f;
			for (int r = 0; r < rowCounts[c]; r++) {
				width = Math.max(width, SegmentFont.measure(columns[c][r], glyphHeight));
			}
			columnWidths[c] = width;
			contentWidth += width;
			maxRows = Math.max(maxRows, rowCounts[c]);
			usedColumns++;
		}
		if (usedColumns == 0 || maxRows == 0) {
			return;
		}
		contentWidth += columnGap * (usedColumns - 1);
		float contentHeight = maxRows * glyphHeight + (maxRows - 1) * rowGap;
		float panelWidth = contentWidth + padding * 2f;
		float panelHeight = contentHeight + padding * 2f;

		ScreenOverlay.resolveOrigin(corner, panelWidth, panelHeight,
			surfaceWidth, surfaceHeight, margin, origin);
		rectX = origin[0];
		rectY = origin[1];
		rectWidth = panelWidth;
		rectHeight = panelHeight;

		// Backdrop: one horizontal line whose half-thickness is half the
		// panel — a filled rect without teaching the batcher a new shape
		float centerY = origin[1] + panelHeight * 0.5f;
		batch.drawLine(whiteTexture, origin[0], centerY, origin[0] + panelWidth, centerY,
			panelHeight * 0.5f, 0f, 0f, 0f, 0.55f);

		float x = origin[0] + padding;
		for (int c = 0; c < COLUMNS; c++) {
			if (rowCounts[c] == 0) {
				continue;
			}
			float y = origin[1] + padding;
			for (int r = 0; r < rowCounts[c]; r++) {
				SegmentFont.draw(batch, whiteTexture, columns[c][r], x, y, glyphHeight,
					0.75f, 1f, 0.8f, 1f);
				y += glyphHeight + rowGap;
			}
			x += columnWidths[c] + columnGap;
		}
	}

	/**
	 * Labels are limited to what seven segments can draw (no M, K, V, W,
	 * X, Z), hence CPU rather than MS and tOP rather than MAX. The README
	 * spells every one of them out.
	 */
	private void buildText()
	{
		boolean full = expanded;
		builtExpanded = full;
		for (int c = 0; c < COLUMNS; c++) {
			rowCounts[c] = 0;
		}

		if (!full) {
			put(0, "FPS " + Math.round(latest.fps));
			put(1, "CPU " + oneDecimal(latest.averageCpuMs));
			put(2, "dC " + latest.drawCalls);
			return;
		}

		put(0, "FPS " + Math.round(latest.fps));
		put(0, "CPU " + oneDecimal(latest.averageCpuMs));
		put(0, "P95 " + oneDecimal(latest.p95CpuMs));
		put(0, "tOP " + oneDecimal(latest.maxCpuMs));
		put(0, "drOP " + latest.droppedFrames);

		put(1, "SPr " + latest.visibleSprites + "/" + latest.sprites);
		put(1, "EnIt " + latest.emitters);
		put(1, "PArt " + latest.particles);
		put(1, "dC " + latest.drawCalls);
		put(1, "tS " + latest.textureSwitches);

		put(2, "UPd " + oneDecimal(latest.averageUpdateMs));
		put(2, "tPrE " + oneDecimal(latest.averageTexturePrepareMs));
		put(2, "bAt " + oneDecimal(latest.averageBatchMs));
	}

	private void put(int column, String text)
	{
		int row = rowCounts[column];
		if (row >= MAX_ROWS) {
			return;
		}
		columns[column][row] = text;
		rowCounts[column] = row + 1;
	}

	private static String oneDecimal(double value)
	{
		return String.format(Locale.US, "%.1f", value);
	}
}
