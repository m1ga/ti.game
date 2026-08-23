package ti.game.engine;

import java.util.ArrayList;
import java.util.List;

/**
 * A sprite whose frame is a laid-out string of bitmap-font glyphs. Because
 * it IS a Sprite in the scene graph, everything sprites do — zIndex/ySort,
 * tweens, idle wobble, tint, flash, camera, touch, even collision — works
 * on text unchanged; only drawing differs (one quad per glyph, all from
 * the font's texture, so a label still renders as a single batch run).
 *
 * Layout runs natively whenever `text` or a layout property changed, and
 * is cached until then: setters just null the cache, and whichever thread
 * touches the text next (GL draw, UI hit-test, JS width read) rebuilds it.
 */
public class TextSprite extends Sprite
{
	public static final int ALIGN_LEFT = 0;
	public static final int ALIGN_CENTER = 1;
	public static final int ALIGN_RIGHT = 2;

	public volatile BitmapFont font;

	// true = no explicit font was given: the scene assigns its own
	// default-font instance when the sprite is added (fonts hold a GL
	// texture, so they must belong to the view that renders them).
	public volatile boolean usesDefaultFont = false;

	private volatile String text = "";
	private volatile int align = ALIGN_LEFT;
	private volatile float letterSpacing = 0f; // extra px between glyphs
	private volatile float lineSpacing = 1f;   // multiplier on font lineHeight
	private volatile float maxWidth = 0f;      // wrap width in px, 0 = no wrap

	/** Immutable glyph layout in local space (origin = text block top-left). */
	public static final class Layout
	{
		public final int count;
		public final float[] quads;       // per glyph: x, y, w, h
		public final int[] frameIndices;  // per glyph: frame in the font's sheet
		public final float width, height;

		Layout(int count, float[] quads, int[] frameIndices, float width, float height)
		{
			this.count = count;
			this.quads = quads;
			this.frameIndices = frameIndices;
			this.width = width;
			this.height = height;
		}
	}

	private static final Layout EMPTY = new Layout(0, new float[0], new int[0], 0f, 0f);
	private volatile Layout layout;

	public String text()
	{
		return text;
	}

	public void setText(String value)
	{
		text = (value != null) ? value : "";
		layout = null;
	}

	public int align()
	{
		return align;
	}

	public void setAlign(int value)
	{
		align = value;
		layout = null;
	}

	public float letterSpacing()
	{
		return letterSpacing;
	}

	public void setLetterSpacing(float value)
	{
		letterSpacing = value;
		layout = null;
	}

	public float lineSpacing()
	{
		return lineSpacing;
	}

	public void setLineSpacing(float value)
	{
		lineSpacing = value;
		layout = null;
	}

	public float maxWidth()
	{
		return maxWidth;
	}

	public void setMaxWidth(float value)
	{
		maxWidth = Math.max(0f, value);
		layout = null;
	}

	public void setFont(BitmapFont value)
	{
		font = value;
		sheet = (value != null) ? value.sheet : null; // renderer's lazy texture upload
		layout = null;
	}

	// Layout bounds drive everything Sprite derives from its frame size:
	// anchor placement, hit-testing, AABBs, ySort's bottom edge.
	@Override
	public float drawWidth()
	{
		return layout().width;
	}

	@Override
	public float drawHeight()
	{
		return layout().height;
	}

	/** Current glyph layout, rebuilding if a setter invalidated it. */
	public Layout layout()
	{
		Layout l = layout;
		if (l != null) {
			return l;
		}
		synchronized (this) {
			l = layout;
			if (l == null) {
				l = buildLayout();
				layout = l;
			}
			return l;
		}
	}

	private Layout buildLayout()
	{
		BitmapFont f = font;
		String t = text;
		if (f == null || t.isEmpty() || f.lineHeight <= 0f) {
			return EMPTY;
		}
		float spacing = letterSpacing;
		float lineStep = f.lineHeight * lineSpacing;
		List<String> lines = wrapLines(f, t, spacing);
		int lineCount = lines.size();

		// First pass: place every line at x = 0 and remember its width
		List<float[]> quads = new ArrayList<>();
		List<Integer> frames = new ArrayList<>();
		int[] lineGlyphCount = new int[lineCount];
		float[] lineWidth = new float[lineCount];
		float blockWidth = 0f;
		for (int i = 0; i < lineCount; i++) {
			String line = lines.get(i);
			float lineTop = i * lineStep;
			float pen = 0f;
			int prev = -1;
			int glyphCount = 0;
			for (int c = 0; c < line.length(); c++) {
				int ch = line.charAt(c);
				BitmapFont.Glyph g = f.glyph(ch);
				if (g == null) {
					pen += f.missingAdvance() + spacing;
					prev = -1;
					continue;
				}
				if (prev >= 0) {
					pen += f.kern(prev, ch);
				}
				if (g.width > 0f && g.height > 0f) {
					quads.add(new float[] { pen + g.xOffset, lineTop + g.yOffset, g.width, g.height });
					frames.add(g.frameIndex);
					glyphCount++;
				}
				pen += g.xAdvance + spacing;
				prev = ch;
			}
			float width = (line.length() > 0) ? pen - spacing : 0f;
			lineGlyphCount[i] = glyphCount;
			lineWidth[i] = Math.max(0f, width);
			blockWidth = Math.max(blockWidth, lineWidth[i]);
		}

		// Second pass: shift each line's glyphs by its alignment offset
		int alignment = align;
		if (alignment != ALIGN_LEFT) {
			int quadIndex = 0;
			for (int i = 0; i < lineCount; i++) {
				float shift = blockWidth - lineWidth[i];
				if (alignment == ALIGN_CENTER) {
					shift *= 0.5f;
				}
				for (int q = 0; q < lineGlyphCount[i]; q++) {
					quads.get(quadIndex++)[0] += shift;
				}
			}
		}

		int count = quads.size();
		float[] flat = new float[count * 4];
		int[] frameIndices = new int[count];
		for (int i = 0; i < count; i++) {
			float[] q = quads.get(i);
			flat[i * 4] = q[0];
			flat[i * 4 + 1] = q[1];
			flat[i * 4 + 2] = q[2];
			flat[i * 4 + 3] = q[3];
			frameIndices[i] = frames.get(i);
		}
		float blockHeight = (lineCount - 1) * lineStep + f.lineHeight;
		return new Layout(count, flat, frameIndices, blockWidth, blockHeight);
	}

	/**
	 * Splits the text into layout lines: hard breaks on '\n', plus soft
	 * breaks on word boundaries when maxWidth is set. Widths use the same
	 * pen simulation as layout (kerning, letterSpacing, missing-glyph
	 * advance), so a wrapped line never renders wider than it measured;
	 * the spaces around a soft break are dropped. A single word wider
	 * than maxWidth overflows rather than breaking mid-word.
	 */
	private List<String> wrapLines(BitmapFont f, String t, float spacing)
	{
		List<String> lines = new ArrayList<>();
		float limit = maxWidth;
		for (String hard : t.split("\n", -1)) {
			if (limit <= 0f) {
				lines.add(hard);
				continue;
			}
			int start = 0;
			int lastSpace = -1; // break candidate: last space after a word
			boolean wordSeen = false;
			float pen = 0f;
			int prev = -1;
			for (int c = 0; c < hard.length(); c++) {
				int ch = hard.charAt(c);
				BitmapFont.Glyph g = f.glyph(ch);
				if (g == null) {
					pen += f.missingAdvance() + spacing;
					prev = -1;
				} else {
					if (prev >= 0) {
						pen += f.kern(prev, ch);
					}
					pen += g.xAdvance + spacing;
					prev = ch;
				}
				if (ch == ' ') {
					if (wordSeen) {
						lastSpace = c;
					}
				} else {
					wordSeen = true;
				}
				if (pen - spacing > limit && lastSpace >= 0) {
					int end = lastSpace;
					while (end > start && hard.charAt(end - 1) == ' ') {
						end--;
					}
					lines.add(hard.substring(start, end));
					start = lastSpace + 1;
					while (start < hard.length() && hard.charAt(start) == ' ') {
						start++;
					}
					c = start - 1; // loop increment re-enters at the new start
					lastSpace = -1;
					wordSeen = false;
					pen = 0f;
					prev = -1;
				}
			}
			if (start == 0 || start < hard.length()) {
				lines.add(hard.substring(start));
			}
		}
		return lines;
	}
}
