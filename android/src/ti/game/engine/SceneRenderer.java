package ti.game.engine;

import android.opengl.GLES20;
import android.opengl.GLSurfaceView;
import android.opengl.Matrix;

import java.util.List;

import javax.microedition.khronos.egl.EGLConfig;
import javax.microedition.khronos.opengles.GL10;

/**
 * The native game loop. Runs on the GLSurfaceView's render thread in
 * continuous mode: computes delta time, ticks the scene (animations,
 * tweens), lazily uploads textures, then batches all sprites.
 *
 * Projection is orthographic with top-left origin, y-down, in surface
 * pixels — matching touch coordinates 1:1.
 */
public class SceneRenderer implements GLSurfaceView.Renderer
{
	private final Scene scene;
	private final org.appcelerator.kroll.KrollProxy viewProxy; // fires 'resize'
	private final SpriteBatch batch = new SpriteBatch();
	private final TextureManager textures = new TextureManager();
	private final float[] projection = new float[16];

	private long lastFrameNanos = 0;
	private volatile int surfaceWidth = 0;
	private volatile int surfaceHeight = 0;

	public SceneRenderer(Scene scene, org.appcelerator.kroll.KrollProxy viewProxy)
	{
		this.scene = scene;
		this.viewProxy = viewProxy;
	}

	public int surfaceWidth()
	{
		return surfaceWidth;
	}

	public int surfaceHeight()
	{
		return surfaceHeight;
	}

	@Override
	public void onSurfaceCreated(GL10 unused, EGLConfig config)
	{
		// A new context means every texture and shader is gone
		textures.invalidateAll();
		batch.createGLResources();
		lastFrameNanos = 0;
	}

	@Override
	public void onSurfaceChanged(GL10 unused, int width, int height)
	{
		surfaceWidth = width;
		surfaceHeight = height;
		scene.worldWidth = width;
		scene.worldHeight = height;
		GLES20.glViewport(0, 0, width, height);
		Matrix.orthoM(projection, 0, 0f, width, height, 0f, -1f, 1f);

		// The real scene coordinate space — build/relayout levels on this,
		// not on the display size (which includes system bars)
		if (viewProxy != null && viewProxy.hasListeners("resize")) {
			org.appcelerator.kroll.KrollDict data = new org.appcelerator.kroll.KrollDict();
			data.put("width", width);
			data.put("height", height);
			viewProxy.fireEvent("resize", data);
		}
	}

	@Override
	public void onDrawFrame(GL10 unused)
	{
		long now = System.nanoTime();
		float dt = (lastFrameNanos == 0) ? 0f : (now - lastFrameNanos) / 1_000_000_000f;
		lastFrameNanos = now;
		// Clamp so a paused/debugged app doesn't fast-forward animations
		if (dt > 0.1f) {
			dt = 0.1f;
		}

		scene.update(dt);

		// Projection follows the camera — sprites live in world coordinates
		float camX = scene.cameraX;
		float camY = scene.cameraY;
		Matrix.orthoM(projection, 0, camX, camX + surfaceWidth, camY + surfaceHeight, camY, -1f, 1f);

		GLES20.glClearColor(scene.bgRed, scene.bgGreen, scene.bgBlue, scene.bgAlpha);
		GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);

		List<Sprite> sprites = scene.snapshot();

		// Lazy texture upload happens here, on the GL thread
		for (Sprite s : sprites) {
			SpriteSheet sheet = s.sheet;
			if (sheet != null && !sheet.isReady()) {
				sheet.ensureLoaded(textures);
				if (sheet.isReady()) {
					textures.track(sheet);
				}
			}
		}

		batch.begin(projection);
		// Skid marks slot between background (zIndex <= 0, e.g. the track)
		// and foreground sprites (the car), so they overlay the road but
		// stay under whatever drives across them.
		boolean trailDrawn = false;
		for (Sprite s : sprites) {
			if (!trailDrawn && s.zIndex > 0) {
				drawSkidTrail();
				trailDrawn = true;
			}
			if (s.visible && s.opacity > 0f) {
				batch.draw(s);
			}
		}
		if (!trailDrawn) {
			drawSkidTrail();
		}
		boolean debugAll = scene.debugAll;
		for (Sprite s : sprites) {
			if (debugAll || s.debug) {
				drawDebugOverlay(s);
			}
		}
		batch.end();
	}

	private void drawSkidTrail()
	{
		if (!scene.skidTrail.isEmpty()) {
			scene.skidTrail.draw(batch, textures.whiteTexture());
		}
	}

	private final float[] debugAabb = new float[4];

	/**
	 * Debug visualization: green = collision AABB (with hitboxScale),
	 * blue = sprite/touch bounds (rotated), orange dot = anchor point.
	 * Drawn after all sprites so overlays sit on top.
	 */
	private void drawDebugOverlay(Sprite s)
	{
		int white = textures.whiteTexture();
		float t = 1.5f; // half line thickness

		// Collision AABB — green
		s.computeAABB(debugAabb);
		float minX = debugAabb[0], minY = debugAabb[1], maxX = debugAabb[2], maxY = debugAabb[3];
		batch.drawLine(white, minX, minY, maxX, minY, t, 0.2f, 1f, 0.4f, 0.9f);
		batch.drawLine(white, maxX, minY, maxX, maxY, t, 0.2f, 1f, 0.4f, 0.9f);
		batch.drawLine(white, maxX, maxY, minX, maxY, t, 0.2f, 1f, 0.4f, 0.9f);
		batch.drawLine(white, minX, maxY, minX, minY, t, 0.2f, 1f, 0.4f, 0.9f);

		// Sprite/touch bounds — blue, rotated (differs from AABB when rotated
		// or when hitboxScale != 1)
		float w = s.drawWidth();
		float h = s.drawHeight();
		if (w > 0f && h > 0f) {
			float ax = s.anchorX * w;
			float ay = s.anchorY * h;
			double rad = Math.toRadians(s.rotation);
			float cos = (float) Math.cos(rad);
			float sin = (float) Math.sin(rad);
			float[] cx = new float[4];
			float[] cy = new float[4];
			for (int i = 0; i < 4; i++) {
				float lx = (((i & 1) == 0) ? -ax : w - ax) * s.scaleX;
				float ly = ((i < 2) ? -ay : h - ay) * s.scaleY;
				cx[i] = s.x + lx * cos - ly * sin;
				cy[i] = s.y + lx * sin + ly * cos;
			}
			batch.drawLine(white, cx[0], cy[0], cx[1], cy[1], t, 0.35f, 0.6f, 1f, 0.9f);
			batch.drawLine(white, cx[1], cy[1], cx[3], cy[3], t, 0.35f, 0.6f, 1f, 0.9f);
			batch.drawLine(white, cx[3], cy[3], cx[2], cy[2], t, 0.35f, 0.6f, 1f, 0.9f);
			batch.drawLine(white, cx[2], cy[2], cx[0], cy[0], t, 0.35f, 0.6f, 1f, 0.9f);
		}

		// Anchor point — orange dot
		batch.drawLine(white, s.x - 3f, s.y, s.x + 3f, s.y, 3f, 1f, 0.6f, 0f, 1f);
	}
}
