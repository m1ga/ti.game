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
	private final PostEffect postEffect = new PostEffect();
	private final float[] projection = new float[16];
	private final float[] screenProjection = new float[16]; // screenFixed sprites

	private long lastFrameNanos = 0;
	private float effectTime = 0f; // drives the glitch animation
	private volatile int surfaceWidth = 0;
	private volatile int surfaceHeight = 0;
	private volatile int maxFps = 0; // 0 = display refresh rate

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

	/** Frame rate cap (e.g. 60 on a 120 Hz display); 0 = display refresh rate. */
	public void setMaxFps(int fps)
	{
		maxFps = Math.max(0, fps);
	}

	@Override
	public void onSurfaceCreated(GL10 unused, EGLConfig config)
	{
		// A new context means every texture and shader is gone
		textures.invalidateAll();
		batch.createGLResources();
		postEffect.createGLResources();
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
		// GLSurfaceView has no frame rate API — delaying the swap makes the
		// next frame land on a later vsync slot (~fps on faster displays).
		// The 1 ms margin leaves the final alignment to vsync.
		int fps = maxFps;
		if (fps > 0 && lastFrameNanos != 0) {
			long sleepNanos = 1_000_000_000L / fps - (System.nanoTime() - lastFrameNanos) - 1_000_000L;
			if (sleepNanos > 0) {
				try {
					Thread.sleep(sleepNanos / 1_000_000L, (int) (sleepNanos % 1_000_000L));
				} catch (InterruptedException e) {
					Thread.currentThread().interrupt();
				}
			}
		}

		long now = System.nanoTime();
		float dt = (lastFrameNanos == 0) ? 0f : (now - lastFrameNanos) / 1_000_000_000f;
		lastFrameNanos = now;
		// Clamp so a paused/debugged app doesn't fast-forward animations
		if (dt > 0.1f) {
			dt = 0.1f;
		}

		scene.update(dt);
		effectTime += dt;

		// Camera effect: render the whole scene into an offscreen texture,
		// then draw it to the screen through the effect shader at the end
		int effectMode = scene.cameraEffect;
		boolean effectActive = (effectMode != PostEffect.NONE)
			&& postEffect.begin(surfaceWidth, surfaceHeight);

		// Projection follows the camera (position, zoom, shake) — sprites
		// live in world coordinates
		float scale = Math.max(0.0001f, scene.cameraScale);
		float left = scene.viewOriginX() + scene.shakeOffsetX;
		float top = scene.viewOriginY() + scene.shakeOffsetY;
		float visibleW = surfaceWidth / scale;
		float visibleH = surfaceHeight / scale;
		Matrix.orthoM(projection, 0, left, left + visibleW, top + visibleH, top, -1f, 1f);
		Matrix.orthoM(screenProjection, 0, 0f, surfaceWidth, surfaceHeight, 0f, -1f, 1f);

		GLES20.glClearColor(scene.bgRed, scene.bgGreen, scene.bgBlue, scene.bgAlpha);
		GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);

		List<Sprite> sprites = scene.snapshot();
		List<ParticleEmitter> emitters = scene.emittersSnapshot();
		List<Rope> ropes = scene.ropesSnapshot();

		// Sheets unloaded from JS free their texture here, on the GL thread
		textures.deleteDisposed();

		// Lazy texture upload happens here, on the GL thread
		for (Sprite s : sprites) {
			ensureSheetLoaded(s.sheet);
		}
		for (ParticleEmitter e : emitters) {
			ensureSheetLoaded(e.sheet);
		}
		for (Rope rope : ropes) {
			ensureSheetLoaded(rope.sheet);
		}

		// Camera travel (position + shake, without the zoom-centering term)
		// — the share of it that parallax sprites give back at draw time
		batch.begin(projection, screenProjection, left, top, scale,
			scene.cameraX + scene.shakeOffsetX, scene.cameraY + scene.shakeOffsetY);
		// Skid marks slot between background (zIndex <= 0, e.g. the track)
		// and foreground sprites (the car), so they overlay the road but
		// stay under whatever drives across them. Emitters merge into the
		// sprite pass by zIndex; on equal zIndex, particles draw on top.
		boolean trailDrawn = false;
		int nextEmitter = 0;
		int nextRope = 0;
		for (Sprite s : sprites) {
			if (!trailDrawn && s.zIndex > 0) {
				drawSkidTrail();
				trailDrawn = true;
			}
			while (nextEmitter < emitters.size() && emitters.get(nextEmitter).zIndex < s.zIndex) {
				emitters.get(nextEmitter++).draw(batch);
			}
			while (nextRope < ropes.size() && ropes.get(nextRope).zIndex < s.zIndex) {
				ropes.get(nextRope++).draw(batch);
			}
			if (s.visible && s.effectiveOpacity() > 0f) {
				batch.draw(s);
			}
		}
		if (!trailDrawn) {
			drawSkidTrail();
		}
		while (nextEmitter < emitters.size()) {
			emitters.get(nextEmitter++).draw(batch);
		}
		while (nextRope < ropes.size()) {
			ropes.get(nextRope++).draw(batch);
		}
		boolean debugAll = scene.debugAll;
		for (Sprite s : sprites) {
			if (debugAll || s.debug) {
				drawDebugOverlay(s);
			}
		}
		batch.end();

		if (effectActive) {
			postEffect.finish(effectMode,
				scene.effectTintR, scene.effectTintG, scene.effectTintB,
				scene.effectIntensity, effectTime);
		}
	}

	private void ensureSheetLoaded(SpriteSheet sheet)
	{
		if (sheet != null && !sheet.isReady()) {
			sheet.ensureLoaded(textures);
			if (sheet.isReady()) {
				textures.track(sheet);
			}
		}
	}

	private void drawSkidTrail()
	{
		if (!scene.skidTrail.isEmpty()) {
			batch.setScreenSpace(false);
			scene.skidTrail.draw(batch, textures.whiteTexture());
		}
	}

	private final float[] debugAabb = new float[4];
	private final float[] debugCenter = new float[2];
	private final float[] debugBox = new float[5];
	private final float[] debugCorners = new float[8];

	/**
	 * Debug visualization: green = collision AABB (with hitboxScale and the
	 * per-axis corrections),
	 * blue = sprite/touch bounds (rotated), orange dot = anchor point.
	 * Drawn after all sprites so overlays sit on top.
	 */
	private void drawDebugOverlay(Sprite s)
	{
		batch.setScreenSpace(s.screenFixed); // overlay in the sprite's own space
		int white = textures.whiteTexture();
		float t = 1.5f; // half line thickness
		// Parallax sprites render shifted — shift the overlay with the art
		float ox = batch.parallaxX(s) - s.x;
		float oy = batch.parallaxY(s) - s.y;

		// Collision shape — green (AABB, or circle for circleHitbox)
		if (s.circleHitbox) {
			s.hitCenter(debugCenter);
			debugCenter[0] += ox;
			debugCenter[1] += oy;
			float r = s.hitRadius();
			int segments = 20;
			for (int i = 0; i < segments; i++) {
				double a0 = 2.0 * Math.PI * i / segments;
				double a1 = 2.0 * Math.PI * (i + 1) / segments;
				batch.drawLine(white,
					debugCenter[0] + r * (float) Math.cos(a0), debugCenter[1] + r * (float) Math.sin(a0),
					debugCenter[0] + r * (float) Math.cos(a1), debugCenter[1] + r * (float) Math.sin(a1),
					t, 0.2f, 1f, 0.4f, 0.9f);
			}
		} else if (s.obbHitbox) {
			// The collision rect as it really sits: turned with the sprite,
			// so the green shape and the blue bounds agree instead of the
			// green one being an oversized square around the art
			s.hitBox(debugBox);
			float bc = (float) Math.cos(debugBox[4]);
			float bs = (float) Math.sin(debugBox[4]);
			float hx = debugBox[2];
			float hy = debugBox[3];
			for (int i = 0; i < 4; i++) {
				float lx = ((i == 0 || i == 3) ? -hx : hx);
				float ly = ((i < 2) ? -hy : hy);
				debugCorners[i * 2] = debugBox[0] + ox + lx * bc - ly * bs;
				debugCorners[i * 2 + 1] = debugBox[1] + oy + lx * bs + ly * bc;
			}
			for (int i = 0; i < 4; i++) {
				int j = (i + 1) % 4;
				batch.drawLine(white,
					debugCorners[i * 2], debugCorners[i * 2 + 1],
					debugCorners[j * 2], debugCorners[j * 2 + 1],
					t, 0.2f, 1f, 0.4f, 0.9f);
			}
		} else {
			s.computeAABB(debugAabb);
			float minX = debugAabb[0] + ox, minY = debugAabb[1] + oy;
			float maxX = debugAabb[2] + ox, maxY = debugAabb[3] + oy;
			batch.drawLine(white, minX, minY, maxX, minY, t, 0.2f, 1f, 0.4f, 0.9f);
			batch.drawLine(white, maxX, minY, maxX, maxY, t, 0.2f, 1f, 0.4f, 0.9f);
			batch.drawLine(white, maxX, maxY, minX, maxY, t, 0.2f, 1f, 0.4f, 0.9f);
			batch.drawLine(white, minX, maxY, minX, minY, t, 0.2f, 1f, 0.4f, 0.9f);
		}

		// Sprite/touch bounds — blue, rotated (differs from AABB when rotated,
		// or when any of hitboxScale/hitboxScaleX/hitboxScaleY != 1)
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
				cx[i] = s.x + ox + lx * cos - ly * sin;
				cy[i] = s.y + oy + lx * sin + ly * cos;
			}
			batch.drawLine(white, cx[0], cy[0], cx[1], cy[1], t, 0.35f, 0.6f, 1f, 0.9f);
			batch.drawLine(white, cx[1], cy[1], cx[3], cy[3], t, 0.35f, 0.6f, 1f, 0.9f);
			batch.drawLine(white, cx[3], cy[3], cx[2], cy[2], t, 0.35f, 0.6f, 1f, 0.9f);
			batch.drawLine(white, cx[2], cy[2], cx[0], cy[0], t, 0.35f, 0.6f, 1f, 0.9f);
		}

		// Anchor point — orange dot
		batch.drawLine(white, s.x + ox - 3f, s.y + oy, s.x + ox + 3f, s.y + oy, 3f, 1f, 0.6f, 0f, 1f);
	}
}
