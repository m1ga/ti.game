package ti.game.engine;

import android.opengl.Matrix;

/**
 * The screen-space drawing pass. The scene's projection follows the camera
 * (position, zoom, shake), so anything pinned to a corner would drift with
 * the world; this holds the second projection — plain surface pixels,
 * top-left origin — plus the corner anchoring every screen-space element
 * needs.
 *
 * The pass runs after the post-effect, not inside it: the glitch shader
 * would otherwise smear exactly the numbers you turned the HUD on to read.
 *
 * Nothing here owns GL resources, so there is nothing to recreate after
 * context loss. The debug HUD is its first client; bitmap text pinned to
 * the screen and the virtual joystick want the same two halves (draw in
 * surface pixels, hit-test in surface pixels) and should hang here too.
 *
 * iOS twin: ios/Classes/TGScreenOverlay.{h,m}.
 */
public class ScreenOverlay
{
	public static final int TOP_LEFT = 0;
	public static final int TOP_RIGHT = 1;
	public static final int BOTTOM_LEFT = 2;
	public static final int BOTTOM_RIGHT = 3;

	private final float[] projection = new float[16];

	/** Recomputed whenever the drawable resizes. */
	public void surfaceChanged(int width, int height)
	{
		Matrix.orthoM(projection, 0, 0f, width, height, 0f, -1f, 1f);
	}

	/** Orthographic surface-pixel projection; feed it to SpriteBatch.begin. */
	public float[] projection()
	{
		return projection;
	}

	public static int cornerFromName(String name, int fallback)
	{
		if ("topLeft".equals(name)) {
			return TOP_LEFT;
		}
		if ("topRight".equals(name)) {
			return TOP_RIGHT;
		}
		if ("bottomLeft".equals(name)) {
			return BOTTOM_LEFT;
		}
		if ("bottomRight".equals(name)) {
			return BOTTOM_RIGHT;
		}
		return fallback;
	}

	public static String cornerName(int corner)
	{
		switch (corner) {
			case TOP_RIGHT:
				return "topRight";
			case BOTTOM_LEFT:
				return "bottomLeft";
			case BOTTOM_RIGHT:
				return "bottomRight";
			default:
				return "topLeft";
		}
	}

	/**
	 * Top-left corner of a content box of the given size, anchored in
	 * `corner` with `margin` px of breathing room. Result goes into
	 * out[0] = x, out[1] = y.
	 */
	public static void resolveOrigin(int corner, float contentWidth, float contentHeight,
									 float surfaceWidth, float surfaceHeight,
									 float margin, float[] out)
	{
		boolean right = (corner == TOP_RIGHT || corner == BOTTOM_RIGHT);
		boolean bottom = (corner == BOTTOM_LEFT || corner == BOTTOM_RIGHT);
		out[0] = right ? surfaceWidth - margin - contentWidth : margin;
		out[1] = bottom ? surfaceHeight - margin - contentHeight : margin;
	}
}
