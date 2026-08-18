package ti.game.engine;

import java.util.Locale;

/**
 * The on-screen performance HUD: a compact line that expands into the full
 * set of counters when tapped. Drawn in the batcher's screen-space mode —
 * the same one screenFixed sprites use — so it stays pinned to its corner
 * whatever the camera does, and laid out straight into the batch as glyph
 * quads, without a TextSprite or a place in the scene.
 *
 * Configured from JS as GameView.debug = { hud: 'topRight' }, optionally
 * with { hudFont: myFont } to print it in the game's own typeface. With no
 * font of its own it borrows the scene's built-in pixel font — the same
 * one createText() falls back to — so the HUD costs no extra texture.
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

	// Layout in density-independent units, multiplied by the screen scale —
	// except the glyphs, which step in whole multiples of the font's native
	// size. A pixel font at a fractional scale is a blurry pixel font.
	private static final float ROW_GAP = 5f;
	private static final float COLUMN_GAP = 9f;
	private static final float PADDING = 5f;
	private static final float MARGIN = 8f;

	/** HUD visible at all. */
	public volatile boolean enabled = false;

	/** One of the ScreenOverlay corner constants. */
	public volatile int corner = ScreenOverlay.TOP_LEFT;

	private volatile boolean expanded = false;

	/** Set from JS via debug: { hudFont: ... }; null borrows the scene's. */
	public volatile BitmapFont font;

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
	public void draw(SpriteBatch batch, int whiteTexture, BitmapFont hudFont,
					 float surfaceWidth, float surfaceHeight, float screenScale)
	{
		if (!hasData || hudFont == null || hudFont.sheet == null || !hudFont.sheet.isReady()) {
			return;
		}
		if (expanded != builtExpanded) {
			buildText();
		}

		float scale = Math.max(0.5f, screenScale);
		// Whole steps only: a pixel font drawn at 1.7x is a blurry mess,
		// and at 2x it is exactly twice as crisp.
		int glyphScale = Math.max(1, Math.round(scale));
		float glyphHeight = hudFont.lineHeight * glyphScale;
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
				width = Math.max(width, measure(hudFont, columns[c][r], glyphScale));
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
				drawText(batch, hudFont, columns[c][r], x, y, glyphScale,
					0.75f, 1f, 0.8f, 1f);
				y += glyphHeight + rowGap;
			}
			x += columnWidths[c] + columnGap;
		}
	}

	/** Pen width of `text` at the given whole-number scale. */
	private static float measure(BitmapFont font, String text, int scale)
	{
		float width = 0f;
		for (int i = 0; i < text.length(); i++) {
			BitmapFont.Glyph glyph = font.glyph(text.charAt(i));
			width += (glyph != null) ? glyph.xAdvance : font.missingAdvance();
			if (i + 1 < text.length()) {
				width += font.kern(text.charAt(i), text.charAt(i + 1));
			}
		}
		return width * scale;
	}

	/** Lays glyph quads straight into the batch — no TextSprite, no scene. */
	private static void drawText(SpriteBatch batch, BitmapFont font, String text,
								 float x, float y, int scale,
								 float r, float g, float b, float a)
	{
		int texture = font.sheet.textureId();
		float pen = x;
		for (int i = 0; i < text.length(); i++) {
			char c = text.charAt(i);
			BitmapFont.Glyph glyph = font.glyph(c);
			if (glyph == null) {
				pen += font.missingAdvance() * scale;
				continue;
			}
			SpriteSheet.Frame frame = font.sheet.frame(glyph.frameIndex);
			if (frame != null && glyph.width > 0f && glyph.height > 0f) {
				float halfW = glyph.width * scale * 0.5f;
				float halfH = glyph.height * scale * 0.5f;
				batch.drawFrame(texture, frame,
					pen + glyph.xOffset * scale + halfW,
					y + glyph.yOffset * scale + halfH,
					halfW, halfH, r, g, b, a);
			}
			pen += glyph.xAdvance * scale;
			if (i + 1 < text.length()) {
				pen += font.kern(c, text.charAt(i + 1)) * scale;
			}
		}
	}

	/** The README explains every label. */
	private void buildText()
	{
		boolean full = expanded;
		builtExpanded = full;
		for (int c = 0; c < COLUMNS; c++) {
			rowCounts[c] = 0;
		}

		if (!full) {
			put(0, "FPS " + Math.round(latest.fps));
			put(1, "MS " + oneDecimal(latest.averageCpuMs));
			put(2, "DC " + latest.drawCalls);
			return;
		}

		put(0, "FPS " + Math.round(latest.fps));
		put(0, "MS " + oneDecimal(latest.averageCpuMs));
		put(0, "P95 " + oneDecimal(latest.p95CpuMs));
		put(0, "MAX " + oneDecimal(latest.maxCpuMs));
		put(0, "DROP " + latest.droppedFrames);

		put(1, "SPRITES " + latest.visibleSprites + "/" + latest.sprites);
		put(1, "EMITTERS " + latest.emitters);
		put(1, "PARTICLES " + latest.particles);
		put(1, "DRAWCALLS " + latest.drawCalls);
		put(1, "TEXSWITCH " + latest.textureSwitches);

		put(2, "UPDATE " + oneDecimal(latest.averageUpdateMs));
		put(2, "TEXTURE " + oneDecimal(latest.averageTexturePrepareMs));
		put(2, "BATCH " + oneDecimal(latest.averageBatchMs));
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
