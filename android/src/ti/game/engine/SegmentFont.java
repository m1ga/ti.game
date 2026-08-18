package ti.game.engine;

/**
 * Seven-segment glyphs drawn with the batcher's line primitive and the
 * TextureManager's 1x1 white texture — no font atlas, no GL resources of
 * its own, nothing to recreate after context loss. Enough to label and
 * print the debug HUD's numbers until the bitmap font lands; when it does,
 * the HUD swaps its text renderer without touching the public API.
 *
 * Seven segments cannot draw every letter (no M, K, V, W, X, Z), so HUD
 * labels are picked from what this table can render. Undrawable characters
 * render blank rather than throwing.
 *
 * Monospaced on purpose: a proportional HUD makes numbers jitter sideways
 * as they change. GL thread only, like everything that touches the batch.
 *
 * iOS twin: ios/Classes/TGSegmentFont.{h,m} — keep the tables identical.
 */
public final class SegmentFont
{
	private SegmentFont()
	{
	}

	// Segment bits, in the conventional order:
	//   0 = a (top)           3 = d (bottom)        6 = g (middle)
	//   1 = b (top right)     4 = e (bottom left)
	//   2 = c (bottom right)  5 = f (top left)
	private static final int SEG_A = 0x01;
	private static final int SEG_B = 0x02;
	private static final int SEG_C = 0x04;
	private static final int SEG_D = 0x08;
	private static final int SEG_E = 0x10;
	private static final int SEG_F = 0x20;
	private static final int SEG_G = 0x40;

	private static final int[] DIGITS = {
		0x3F, // 0
		0x06, // 1
		0x5B, // 2
		0x4F, // 3
		0x66, // 4
		0x6D, // 5
		0x7D, // 6
		0x07, // 7
		0x7F, // 8
		0x6F  // 9
	};

	// Glyph geometry as fractions of the glyph height.
	private static final float WIDTH_RATIO = 0.60f;
	private static final float GAP_RATIO = 0.28f;
	private static final float THICKNESS_RATIO = 0.16f;

	/** Distance from one glyph's left edge to the next one's. */
	public static float advance(float glyphHeight)
	{
		return glyphHeight * (WIDTH_RATIO + GAP_RATIO);
	}

	/** Width of `text` without the trailing gap — for layout and hit rects. */
	public static float measure(String text, float glyphHeight)
	{
		if (text == null || text.length() == 0) {
			return 0f;
		}
		return text.length() * advance(glyphHeight) - glyphHeight * GAP_RATIO;
	}

	/**
	 * Draws `text` with its top-left corner at (x, y), in surface pixels.
	 * Color is straight-alpha, like SpriteBatch.drawLine.
	 */
	public static void draw(SpriteBatch batch, int whiteTexture, String text,
							float x, float y, float glyphHeight,
							float r, float g, float b, float a)
	{
		if (text == null || text.length() == 0) {
			return;
		}
		float w = glyphHeight * WIDTH_RATIO;
		float t = glyphHeight * THICKNESS_RATIO * 0.5f; // half thickness
		float step = advance(glyphHeight);
		float cursor = x;

		for (int i = 0; i < text.length(); i++, cursor += step) {
			char c = text.charAt(i);
			if (c == ' ') {
				continue;
			}
			float left = cursor + t;
			float right = cursor + w - t;
			float top = y + t;
			float middle = y + glyphHeight * 0.5f;
			float bottom = y + glyphHeight - t;

			// Two shapes the segment table can't express
			if (c == '.') {
				float dot = cursor + w * 0.5f;
				batch.drawLine(whiteTexture, dot - t, bottom, dot + t, bottom, t, r, g, b, a);
				continue;
			}
			if (c == '/') {
				batch.drawLine(whiteTexture, left, bottom, right, top, t, r, g, b, a);
				continue;
			}

			// Verticals run corner to corner with no inset at the middle:
			// a gap there splits '1' into two stubs that read as a colon.
			// Overlapping the middle bar is invisible at full alpha.
			int mask = maskFor(c);
			if ((mask & SEG_A) != 0) {
				batch.drawLine(whiteTexture, left, top, right, top, t, r, g, b, a);
			}
			if ((mask & SEG_B) != 0) {
				batch.drawLine(whiteTexture, right, top, right, middle, t, r, g, b, a);
			}
			if ((mask & SEG_C) != 0) {
				batch.drawLine(whiteTexture, right, middle, right, bottom, t, r, g, b, a);
			}
			if ((mask & SEG_D) != 0) {
				batch.drawLine(whiteTexture, left, bottom, right, bottom, t, r, g, b, a);
			}
			if ((mask & SEG_E) != 0) {
				batch.drawLine(whiteTexture, left, middle, left, bottom, t, r, g, b, a);
			}
			if ((mask & SEG_F) != 0) {
				batch.drawLine(whiteTexture, left, top, left, middle, t, r, g, b, a);
			}
			if ((mask & SEG_G) != 0) {
				batch.drawLine(whiteTexture, left, middle, right, middle, t, r, g, b, a);
			}
		}
	}

	/** Segment mask for one character; 0 (blank) for anything undrawable. */
	private static int maskFor(char c)
	{
		if (c >= '0' && c <= '9') {
			return DIGITS[c - '0'];
		}
		switch (c) {
			case 'A': return 0x77;
			case 'b': return 0x7C;
			case 'C': return 0x39;
			case 'c': return 0x58;
			case 'd': return 0x5E;
			case 'E': return 0x79;
			case 'F': return 0x71;
			case 'G': return 0x3D;
			case 'H': return 0x76;
			case 'h': return 0x74;
			case 'I': return 0x30;
			case 'J': return 0x1E;
			case 'L': return 0x38;
			case 'n': return 0x54;
			case 'O': return 0x3F;
			case 'o': return 0x5C;
			case 'P': return 0x73;
			case 'r': return 0x50;
			case 'S': return 0x6D;
			case 't': return 0x78;
			case 'U': return 0x3E;
			case 'u': return 0x1C;
			case 'y': return 0x6E;
			case '-': return SEG_G;
			default:  return 0;
		}
	}
}
