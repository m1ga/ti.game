package ti.game.engine;

import android.graphics.Bitmap;
import android.opengl.GLES20;
import android.opengl.GLUtils;

import java.util.ArrayList;
import java.util.List;

/**
 * Owns GL texture objects. All methods must be called from the GL thread.
 * Tracks the sheets it has uploaded so they can be invalidated together
 * when the EGL context is lost and recreated.
 */
public class TextureManager
{
	private final List<SpriteSheet> uploadedSheets = new ArrayList<>();
	private int whiteTextureId = -1;

	/** Lazily-created 1x1 white texture for untextured shapes (debug overlays). */
	public int whiteTexture()
	{
		if (whiteTextureId < 0) {
			int[] ids = new int[1];
			GLES20.glGenTextures(1, ids, 0);
			GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0]);
			GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST);
			GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST);
			java.nio.ByteBuffer pixel = java.nio.ByteBuffer.allocateDirect(4);
			pixel.put(new byte[] { (byte) 255, (byte) 255, (byte) 255, (byte) 255 }).position(0);
			GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, 1, 1, 0,
				GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixel);
			whiteTextureId = ids[0];
		}
		return whiteTextureId;
	}

	/** Uploads a bitmap and returns the GL texture id. GL thread only.
	 *  smoothing=false uses GL_NEAREST for crisp pixel-art scaling;
	 *  repeat=true uses GL_REPEAT wrap (needs power-of-two dimensions
	 *  on ES 2.0) so tileRepeat sprites can tile the texture. */
	public int upload(Bitmap bitmap, boolean smoothing, boolean repeat)
	{
		int filter = smoothing ? GLES20.GL_LINEAR : GLES20.GL_NEAREST;
		int wrap = repeat ? GLES20.GL_REPEAT : GLES20.GL_CLAMP_TO_EDGE;
		int[] ids = new int[1];
		GLES20.glGenTextures(1, ids, 0);
		GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, ids[0]);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, filter);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, filter);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, wrap);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, wrap);
		GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0);
		return ids[0];
	}

	public void track(SpriteSheet sheet)
	{
		if (!uploadedSheets.contains(sheet)) {
			uploadedSheets.add(sheet);
		}
	}

	/** After context loss: forget every texture so sheets re-upload lazily. */
	public void invalidateAll()
	{
		for (SpriteSheet sheet : uploadedSheets) {
			sheet.invalidateTexture();
		}
		uploadedSheets.clear();
		whiteTextureId = -1;
	}
}
