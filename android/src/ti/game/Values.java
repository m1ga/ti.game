package ti.game;

import org.appcelerator.kroll.common.Log;
import org.appcelerator.titanium.util.TiConvert;

/**
 * Names and percentages for properties whose bare number reads like a riddle.
 *
 * The engine already does this where it matters: `blend`, `hitboxShape`,
 * `tintColor` and `glowColor` all take strings. The numeric properties are
 * simply the ones that never got the same treatment, and some of them are
 * unreadable without the docs open — `anchorY: 1` says nothing about the fact
 * that it pins the sprite by its feet.
 *
 * Everything here is additive: a number keeps working exactly as before, and a
 * value that cannot be understood falls back to the number the caller passed
 * rather than throwing, so a typo degrades to the default instead of taking the
 * app down mid-frame.
 */
public final class Values
{
	private static final String LCAT = "TiGame";

	private Values() {}

	/**
	 * A ratio, as a number or as a percentage string: 0.5 and "50%" are the
	 * same thing. Percentages above 100 are fine — `scaleX: "200%"` is twice
	 * as wide, which is what a percentage means everywhere else.
	 */
	public static float ratio(Object value, float fallback)
	{
		if (value == null) {
			return fallback;
		}
		if (value instanceof Number) {
			return ((Number) value).floatValue();
		}

		String text = TiConvert.toString(value);
		if (text == null) {
			return fallback;
		}
		text = text.trim();
		if (text.endsWith("%")) {
			text = text.substring(0, text.length() - 1).trim();
			try {
				return Float.parseFloat(text) / 100f;
			} catch (NumberFormatException e) {
				Log.w(LCAT, "not a percentage: " + value);
				return fallback;
			}
		}

		try {
			return Float.parseFloat(text);
		} catch (NumberFormatException e) {
			Log.w(LCAT, "not a ratio: " + value);
			return fallback;
		}
	}

	/**
	 * The horizontal anchor, as a number or as one of `left`, `center` and
	 * `right`. The anchor is the point the sprite is positioned by and the
	 * point `hitboxScale` shrinks around, so naming it is the difference
	 * between "1" and "pinned by its right edge".
	 */
	public static float anchorX(Object value, float fallback)
	{
		String name = name(value);
		if (name == null) {
			return ratio(value, fallback);
		}
		switch (name) {
			case "left":
				return 0f;
			case "center":
			case "centre":
			case "middle":
				return 0.5f;
			case "right":
				return 1f;
			default:
				return unknownAnchor(value, fallback);
		}
	}

	/** The vertical anchor: `top`, `middle` or `bottom`. */
	public static float anchorY(Object value, float fallback)
	{
		String name = name(value);
		if (name == null) {
			return ratio(value, fallback);
		}
		switch (name) {
			case "top":
				return 0f;
			case "center":
			case "centre":
			case "middle":
				return 0.5f;
			case "bottom":
				return 1f;
			default:
				return unknownAnchor(value, fallback);
		}
	}

	/**
	 * Both axes at once: `anchor: "bottom-left"`. Accepts the nine corners and
	 * edges, in either order, so `bottom-left` and `left-bottom` both work.
	 * Returns null when the value is not a recognised preset, which is the
	 * caller's cue to leave the anchors alone.
	 */
	public static float[] anchor(Object value)
	{
		String name = name(value);
		if (name == null) {
			return null;
		}

		float x = -1f;
		float y = -1f;
		for (String part : name.split("[-_ ]+")) {
			switch (part) {
				case "left":
					x = 0f;
					break;
				case "right":
					x = 1f;
					break;
				case "top":
					y = 0f;
					break;
				case "bottom":
					y = 1f;
					break;
				case "center":
				case "centre":
				case "middle":
					// `center` on its own means both axes; paired with an edge
					// it only fills in the axis that edge left open.
					break;
				default:
					Log.w(LCAT, "unknown anchor: " + value);
					return null;
			}
		}

		return new float[] { x < 0f ? 0.5f : x, y < 0f ? 0.5f : y };
	}

	/**
	 * The preset a pair of anchors sits on, or `custom`. Exists so reading the
	 * property back gives something you could pass in again.
	 */
	public static String anchorName(float x, float y)
	{
		String horizontal = x == 0f ? "left" : (x == 1f ? "right" : (x == 0.5f ? "center" : null));
		String vertical = y == 0f ? "top" : (y == 1f ? "bottom" : (y == 0.5f ? "middle" : null));
		if (horizontal == null || vertical == null) {
			return "custom";
		}
		if (horizontal.equals("center") && vertical.equals("middle")) {
			return "center";
		}
		return vertical + "-" + horizontal;
	}

	/** The lower-cased string behind a value, or null if it is not one. */
	private static String name(Object value)
	{
		if (!(value instanceof String)) {
			return null;
		}
		String text = ((String) value).trim();
		// A percentage is a ratio wearing a string, not a name.
		return text.isEmpty() || text.endsWith("%") ? null : text.toLowerCase();
	}

	private static float unknownAnchor(Object value, float fallback)
	{
		Log.w(LCAT, "unknown anchor: " + value);
		return fallback;
	}
}
