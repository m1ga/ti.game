package ti.game.engine;

import android.graphics.Bitmap;

/**
 * Native sprite sheet: one texture plus a frame table of UV rects. Built
 * either from a simple grid (frameWidth/frameHeight) or a TexturePacker-style
 * JSON atlas. The bitmap is decoded lazily and uploaded to GL on first use
 * by the render loop; on EGL context loss it is re-uploaded from source.
 */
public class SpriteSheet
{
	/** One frame: UV rect in the texture plus its pixel size. */
	public static class Frame
	{
		public final float u0, v0, u1, v1;
		public final float width, height;

		public Frame(float u0, float v0, float u1, float v1, float width, float height)
		{
			this.u0 = u0;
			this.v0 = v0;
			this.u1 = u1;
			this.v1 = v1;
			this.width = width;
			this.height = height;
		}
	}

	public interface Loader
	{
		/** Decode the sheet image and (for atlas sheets) parse frames. May run on the GL thread. */
		Bitmap load(SpriteSheet sheet);
	}

	/** false = GL_NEAREST filtering — crisp pixels for pixel-art sheets. */
	public volatile boolean smoothing = true;

	/** true = GL_REPEAT wrap so sprites with tileRepeat tile the texture.
	 *  ES 2.0 requires power-of-two texture dimensions for this. */
	public volatile boolean repeat = false;

	private volatile Frame[] frames = new Frame[0];
	private volatile int textureId = -1;
	private volatile boolean loadFailed = false;
	private volatile boolean disposed = false;
	private final Loader loader;

	// Grid parameters; 0 means "atlas sheet", frames come from JSON
	public final int gridFrameWidth;
	public final int gridFrameHeight;

	public SpriteSheet(Loader loader, int gridFrameWidth, int gridFrameHeight)
	{
		this.loader = loader;
		this.gridFrameWidth = gridFrameWidth;
		this.gridFrameHeight = gridFrameHeight;
	}

	public void setFrames(Frame[] frames)
	{
		this.frames = (frames != null) ? frames : new Frame[0];
	}

	public int frameCount()
	{
		return frames.length;
	}

	public Frame frame(int index)
	{
		Frame[] f = frames;
		if (f.length == 0) {
			return null;
		}
		if (index < 0 || index >= f.length) {
			index = 0;
		}
		return f[index];
	}

	public float frameWidth(int index)
	{
		Frame f = frame(index);
		return (f != null) ? f.width : 0f;
	}

	public float frameHeight(int index)
	{
		Frame f = frame(index);
		return (f != null) ? f.height : 0f;
	}

	public int textureId()
	{
		return textureId;
	}

	public boolean isReady()
	{
		return textureId >= 0 && frames.length > 0;
	}

	/**
	 * Called from the GL thread each frame until the texture exists. Decodes
	 * the bitmap via the loader, builds grid frames if needed, and uploads.
	 */
	public void ensureLoaded(TextureManager textures)
	{
		if (textureId >= 0 || loadFailed || disposed) {
			return;
		}
		Bitmap bitmap = (loader != null) ? loader.load(this) : null;
		if (bitmap == null) {
			loadFailed = true;
			return;
		}
		if (frames.length == 0 && gridFrameWidth > 0 && gridFrameHeight > 0) {
			setFrames(buildGridFrames(bitmap.getWidth(), bitmap.getHeight(),
				gridFrameWidth, gridFrameHeight, smoothing));
		}
		textureId = textures.upload(bitmap, smoothing, repeat);
		bitmap.recycle();
	}

	/** Drops the GL texture reference after context loss so it reloads. */
	public void invalidateTexture()
	{
		textureId = -1;
		loadFailed = false;
	}

	/**
	 * Marks the sheet for texture deletion on the next rendered frame
	 * (TextureManager.deleteDisposed) and blocks any re-upload. Sprites
	 * still referencing the sheet simply stop drawing.
	 */
	public void dispose()
	{
		disposed = true;
	}

	public boolean isDisposed()
	{
		return disposed;
	}

	/**
	 * Grid frame UVs. With `inset` (linear-filtered sheets), interior frame
	 * edges pull in by half a texel so magnified edge samples can't blend
	 * in the neighboring frame (1px ghost lines, the next row's heads
	 * showing at the bottom). Exterior edges stay at the texture border —
	 * CLAMP_TO_EDGE covers them, and full-texture tileRepeat frames must
	 * keep the exact 0..1 range to wrap seamlessly. NEAREST sheets skip
	 * the inset: they can't bleed, and pixel art at 1:1 needs exact UVs.
	 */
	public static Frame[] buildGridFrames(int imageWidth, int imageHeight,
										  int frameWidth, int frameHeight, boolean inset)
	{
		int cols = Math.max(1, imageWidth / frameWidth);
		int rows = Math.max(1, imageHeight / frameHeight);
		float halfX = 0.5f / imageWidth;
		float halfY = 0.5f / imageHeight;
		Frame[] result = new Frame[cols * rows];
		int i = 0;
		for (int row = 0; row < rows; row++) {
			for (int col = 0; col < cols; col++) {
				float u0 = (col * frameWidth) / (float) imageWidth;
				float v0 = (row * frameHeight) / (float) imageHeight;
				float u1 = ((col + 1) * frameWidth) / (float) imageWidth;
				float v1 = ((row + 1) * frameHeight) / (float) imageHeight;
				if (inset) {
					if (col > 0) {
						u0 += halfX;
					}
					if (col < cols - 1) {
						u1 -= halfX;
					}
					if (row > 0) {
						v0 += halfY;
					}
					if (row < rows - 1) {
						v1 -= halfY;
					}
				}
				result[i++] = new Frame(u0, v0, u1, v1, frameWidth, frameHeight);
			}
		}
		return result;
	}
}
