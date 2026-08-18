package ti.game.engine;

import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

/**
 * Native bitmap font: a glyph atlas texture plus per-character metrics.
 * Built either from a monospace grid (charWidth/charHeight + a characters
 * string) or a BMFont/AngelCode descriptor (proportional glyphs, kerning).
 *
 * Metrics are set once at parse time on the JS thread; only the texture
 * upload is lazy (via the wrapped SpriteSheet, on the GL thread), so text
 * layout never has to wait for GL.
 */
public class BitmapFont
{
	/** One character: its frame in the sheet plus placement metrics. */
	public static class Glyph
	{
		public final int frameIndex;
		public final float width, height;    // px in the atlas
		public final float xOffset, yOffset; // pen-relative placement
		public final float xAdvance;         // pen movement after this glyph

		public Glyph(int frameIndex, float width, float height,
					 float xOffset, float yOffset, float xAdvance)
		{
			this.frameIndex = frameIndex;
			this.width = width;
			this.height = height;
			this.xOffset = xOffset;
			this.yOffset = yOffset;
			this.xAdvance = xAdvance;
		}
	}

	/** Glyph texture; frames indexed by Glyph.frameIndex. */
	public final SpriteSheet sheet;

	public volatile float lineHeight = 0f;

	private volatile Map<Integer, Glyph> glyphs = Collections.emptyMap();
	private volatile Map<Integer, Float> kerning = null; // key: (first << 16) | second

	public BitmapFont(SpriteSheet sheet)
	{
		this.sheet = sheet;
	}

	public void setGlyphs(Map<Integer, Glyph> glyphs)
	{
		this.glyphs = (glyphs != null) ? glyphs : Collections.<Integer, Glyph>emptyMap();
	}

	public void setKerning(Map<Integer, Float> kerning)
	{
		this.kerning = (kerning != null && !kerning.isEmpty()) ? kerning : null;
	}

	public Glyph glyph(int character)
	{
		return glyphs.get(character);
	}

	/** Kerning adjustment between two characters (0 for most pairs). */
	public float kern(int first, int second)
	{
		Map<Integer, Float> k = kerning;
		if (k == null || first > 0xffff || second > 0xffff) {
			return 0f;
		}
		Float amount = k.get((first << 16) | second);
		return (amount != null) ? amount : 0f;
	}

	/** Pen advance for characters the font has no glyph for. */
	public float missingAdvance()
	{
		Glyph space = glyph(' ');
		return (space != null) ? space.xAdvance : lineHeight * 0.4f;
	}

	/**
	 * Monospace grid font: the image is a row-major grid of charWidth x
	 * charHeight cells, one per character of `characters`. The wrapped
	 * sheet builds matching grid frames when its texture loads.
	 */
	public static BitmapFont grid(SpriteSheet sheet, String characters, float charWidth, float charHeight)
	{
		BitmapFont font = new BitmapFont(sheet);
		font.lineHeight = charHeight;
		Map<Integer, Glyph> glyphs = new HashMap<>();
		for (int i = 0; i < characters.length(); i++) {
			glyphs.put((int) characters.charAt(i),
				new Glyph(i, charWidth, charHeight, 0f, 0f, charWidth));
		}
		font.setGlyphs(glyphs);
		return font;
	}
}
