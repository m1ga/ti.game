package ti.game.engine;

import android.opengl.GLES20;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * Blurred silhouette masks for sprite glows. A glow is the sprite's alpha
 * silhouette, Gaussian-blurred by glowBlur and tinted, drawn behind the
 * sprite. Blurring per frame would be too slow, so the mask is rendered
 * once into a small offscreen texture and cached by silhouette (sheet +
 * UV rect + draw size, or a text layout) and blur radius; the batcher then
 * draws one textured quad per glow per frame.
 *
 * Build: the silhouette is drawn at 1:1 into an FBO texture padded by
 * 2.5 sigma on every side, halved (box filter) until the sigma is at most
 * 1.5 texels per axis, then blurred with a separable 9-tap Gaussian. The
 * mask is stored premultiplied white (rgb = a), so the silhouette shader
 * (color * alpha) composites it with the glow color. Bilinear upsampling
 * of the low-resolution mask is what makes the halo smooth at any radius.
 *
 * Builds happen between frames (beginFrame, before the scene renders),
 * never mid-batch, a few per frame at most; a miss draws the nearest
 * cached radius of the same silhouette for that frame, or nothing. The
 * blur is isotropic in screen px: a scaled sprite gets a sigma per axis in
 * its own units. Entries idle for a few seconds are freed. GL thread
 * only; createGLResources drops everything after context loss.
 */
public class GlowMaskCache
{
	/** Gaussian sigma per px of glowBlur: the halo fades over ~2 sigma. */
	static final float SIGMA_PER_BLUR = 0.5f;
	/** Mask padding past the sprite rect, in sigmas (tail below 1%). */
	static final float PAD_SIGMAS = 2.5f;
	// Alpha gain on the blurred coverage: a plain blur is only half opaque
	// at the sprite edge, which reads as a faint shadow instead of a halo.
	private static final float GAIN = 2.5f;
	private static final float MAX_LOW_SIGMA = 1.5f;
	private static final int MAX_FULL_RES = 2048;
	private static final int MAX_ENTRIES = 64;
	private static final int MAX_PENDING = 64;
	private static final int BUILDS_PER_FRAME = 4;
	private static final int IDLE_FRAMES = 180;
	private static final int SWEEP_INTERVAL = 60;
	// Radii are quantized in 12% steps so a scale tween builds a handful of
	// masks, not one per frame
	private static final double SIGMA_STEP = Math.log(1.12);
	private static final float MIN_SIGMA = 0.25f;
	private static final float MAX_SIGMA = 512f;

	/** What gets blurred: a sheet rect at a draw size, or a text layout. */
	static final class Silhouette
	{
		SpriteSheet sheet;
		Object layout; // TextSprite.Layout, null for a frame
		float u0, v0, u1, v1, w, h;

		void set(SpriteSheet sheet, Object layout, float u0, float v0, float u1, float v1,
				 float w, float h)
		{
			this.sheet = sheet;
			this.layout = layout;
			this.u0 = u0;
			this.v0 = v0;
			this.u1 = u1;
			this.v1 = v1;
			this.w = w;
			this.h = h;
		}

		Silhouette copy()
		{
			Silhouette c = new Silhouette();
			c.set(sheet, layout, u0, v0, u1, v1, w, h);
			return c;
		}

		@Override
		public boolean equals(Object o)
		{
			if (!(o instanceof Silhouette)) {
				return false;
			}
			Silhouette s = (Silhouette) o;
			return s.sheet == sheet && s.layout == layout
				&& s.u0 == u0 && s.v0 == v0 && s.u1 == u1 && s.v1 == v1
				&& s.w == w && s.h == h;
		}

		@Override
		public int hashCode()
		{
			int hash = System.identityHashCode(sheet);
			hash = hash * 31 + System.identityHashCode(layout);
			hash = hash * 31 + Float.floatToIntBits(u0);
			hash = hash * 31 + Float.floatToIntBits(v0);
			hash = hash * 31 + Float.floatToIntBits(u1);
			hash = hash * 31 + Float.floatToIntBits(v1);
			hash = hash * 31 + Float.floatToIntBits(w);
			hash = hash * 31 + Float.floatToIntBits(h);
			return hash;
		}
	}

	/** A built mask: texture covering the sprite rect plus padX/padY
	 *  (sprite-local units) on each side; texture < 0 = build failed. */
	static final class Entry
	{
		int texture = -1;
		float sigmaX, sigmaY;
		float padX, padY;
		int lastUsed;
	}

	static final class Job
	{
		final Silhouette key;
		final float sigmaX, sigmaY;

		Job(Silhouette key, float sigmaX, float sigmaY)
		{
			this.key = key;
			this.sigmaX = sigmaX;
			this.sigmaY = sigmaY;
		}
	}

	private static final String VERTEX_SHADER =
		"attribute vec2 aPos;\n"
		+ "attribute vec2 aUV;\n"
		+ "varying vec2 vUV;\n"
		+ "void main() {\n"
		+ "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
		+ "  vUV = aUV;\n"
		+ "}\n";

	// 2x2 box: taps half a source texel around the destination center
	// (uOff = 0 on an axis that is not halved).
	// highp where the fragment stage has it: a one-texel step on a 2048 px
	// mask is below fp16 resolution near uv = 1
	private static final String PRECISION =
		"#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
		+ "precision highp float;\n"
		+ "#else\n"
		+ "precision mediump float;\n"
		+ "#endif\n";

	private static final String DOWNSAMPLE_FRAGMENT_SHADER =
		PRECISION
		+ "uniform sampler2D uTex;\n"
		+ "uniform vec2 uOff;\n"
		+ "varying vec2 vUV;\n"
		+ "void main() {\n"
		+ "  float a = texture2D(uTex, vUV + vec2(-uOff.x, -uOff.y)).a\n"
		+ "    + texture2D(uTex, vUV + vec2(uOff.x, -uOff.y)).a\n"
		+ "    + texture2D(uTex, vUV + vec2(-uOff.x, uOff.y)).a\n"
		+ "    + texture2D(uTex, vUV + uOff).a;\n"
		+ "  gl_FragColor = vec4(a * 0.25);\n"
		+ "}\n";

	// Separable 9-tap Gaussian along uStep; the last pass applies the gain.
	private static final String BLUR_FRAGMENT_SHADER =
		PRECISION
		+ "uniform sampler2D uTex;\n"
		+ "uniform vec2 uStep;\n"
		+ "uniform float uWeights[5];\n"
		+ "uniform float uGain;\n"
		+ "varying vec2 vUV;\n"
		+ "void main() {\n"
		+ "  float a = texture2D(uTex, vUV).a * uWeights[0];\n"
		+ "  a += (texture2D(uTex, vUV + uStep).a + texture2D(uTex, vUV - uStep).a) * uWeights[1];\n"
		+ "  a += (texture2D(uTex, vUV + uStep * 2.0).a + texture2D(uTex, vUV - uStep * 2.0).a) * uWeights[2];\n"
		+ "  a += (texture2D(uTex, vUV + uStep * 3.0).a + texture2D(uTex, vUV - uStep * 3.0).a) * uWeights[3];\n"
		+ "  a += (texture2D(uTex, vUV + uStep * 4.0).a + texture2D(uTex, vUV - uStep * 4.0).a) * uWeights[4];\n"
		+ "  gl_FragColor = vec4(min(1.0, a * uGain));\n"
		+ "}\n";

	private static final int ATTR_POS = 0;
	private static final int ATTR_UV = 1;

	// Fullscreen quad as a triangle strip: x, y (NDC), u, v
	private static final float[] QUAD = {
		-1f, -1f, 0f, 0f,
		1f, -1f, 1f, 0f,
		-1f, 1f, 0f, 1f,
		1f, 1f, 1f, 1f
	};
	private final FloatBuffer quad;

	private int downsampleProgram = 0;
	private int blurProgram = 0;
	private int uTexDown, uOffDown;
	private int uTexBlur, uStepBlur, uWeightsBlur, uGainBlur;
	private int fbo = 0;

	private final Map<Silhouette, List<Entry>> entries = new HashMap<>();
	private final List<Job> pending = new ArrayList<>();
	private final Silhouette scratch = new Silhouette();
	private final float[] ortho = new float[16];
	private final float[] weights = new float[5];
	private final int[] savedFbo = new int[1];
	private final int[] savedViewport = new int[4];
	private final int[] ids = new int[1];
	private int count = 0;
	private int frame = 0;

	public GlowMaskCache()
	{
		quad = ByteBuffer.allocateDirect(QUAD.length * 4)
			.order(ByteOrder.nativeOrder())
			.asFloatBuffer();
		quad.put(QUAD).position(0);
	}

	/** (Re)creates shaders and forgets every mask (the textures died with
	 *  the context); call from onSurfaceCreated. */
	public void createGLResources()
	{
		downsampleProgram = buildProgram(DOWNSAMPLE_FRAGMENT_SHADER);
		uTexDown = GLES20.glGetUniformLocation(downsampleProgram, "uTex");
		uOffDown = GLES20.glGetUniformLocation(downsampleProgram, "uOff");
		blurProgram = buildProgram(BLUR_FRAGMENT_SHADER);
		uTexBlur = GLES20.glGetUniformLocation(blurProgram, "uTex");
		uStepBlur = GLES20.glGetUniformLocation(blurProgram, "uStep");
		uWeightsBlur = GLES20.glGetUniformLocation(blurProgram, "uWeights[0]");
		uGainBlur = GLES20.glGetUniformLocation(blurProgram, "uGain");
		fbo = 0;
		entries.clear();
		pending.clear();
		count = 0;
	}

	private static int buildProgram(String fragmentSource)
	{
		int vs = compileShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER);
		int fs = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource);
		int p = GLES20.glCreateProgram();
		GLES20.glAttachShader(p, vs);
		GLES20.glAttachShader(p, fs);
		GLES20.glBindAttribLocation(p, ATTR_POS, "aPos");
		GLES20.glBindAttribLocation(p, ATTR_UV, "aUV");
		GLES20.glLinkProgram(p);
		GLES20.glDeleteShader(vs);
		GLES20.glDeleteShader(fs);
		return p;
	}

	private static int compileShader(int type, String source)
	{
		int shader = GLES20.glCreateShader(type);
		GLES20.glShaderSource(shader, source);
		GLES20.glCompileShader(shader);
		return shader;
	}

	/** Sigma in sprite-local units for a glowBlur in px on an axis scaled
	 *  by `scale` — the blur stays isotropic on screen. */
	static float localSigma(float blur, float scale)
	{
		float s = Math.max(Math.abs(scale), 0.001f);
		return blur * SIGMA_PER_BLUR / s;
	}

	private static float quantize(float sigma)
	{
		sigma = Math.max(MIN_SIGMA, Math.min(MAX_SIGMA, sigma));
		return (float) Math.exp(Math.round(Math.log(sigma) / SIGMA_STEP) * SIGMA_STEP);
	}

	/**
	 * The mask for this silhouette at these sigmas (sprite-local units), or
	 * null to draw no glow this frame. A miss queues a build for the next
	 * beginFrame and returns the nearest cached radius of the same
	 * silhouette meanwhile, so a scale tween never drops its glow.
	 */
	Entry lookup(SpriteSheet sheet, Object layout, float u0, float v0, float u1, float v1,
				 float w, float h, float sigmaX, float sigmaY)
	{
		sigmaX = quantize(sigmaX);
		sigmaY = quantize(sigmaY);
		scratch.set(sheet, layout, u0, v0, u1, v1, w, h);
		List<Entry> list = entries.get(scratch);
		Entry nearest = null;
		double nearestDistance = Double.MAX_VALUE;
		if (list != null) {
			for (int i = 0; i < list.size(); i++) {
				Entry e = list.get(i);
				if (e.sigmaX == sigmaX && e.sigmaY == sigmaY) {
					e.lastUsed = frame;
					return (e.texture >= 0) ? e : null;
				}
				if (e.texture < 0) {
					continue;
				}
				double d = Math.abs(Math.log(e.sigmaX / sigmaX)) + Math.abs(Math.log(e.sigmaY / sigmaY));
				if (d < nearestDistance) {
					nearestDistance = d;
					nearest = e;
				}
			}
		}
		enqueue(sigmaX, sigmaY);
		if (nearest != null) {
			nearest.lastUsed = frame;
		}
		return nearest;
	}

	private void enqueue(float sigmaX, float sigmaY)
	{
		if (pending.size() >= MAX_PENDING) {
			return;
		}
		for (int i = 0; i < pending.size(); i++) {
			Job j = pending.get(i);
			if (j.sigmaX == sigmaX && j.sigmaY == sigmaY && j.key.equals(scratch)) {
				return;
			}
		}
		pending.add(new Job(scratch.copy(), sigmaX, sigmaY));
	}

	/**
	 * Builds queued masks (a few per frame) and frees idle ones. Call on
	 * the GL thread before the frame's first batch.begin — it binds its
	 * own framebuffer and viewport and restores both.
	 */
	public void beginFrame(SpriteBatch batch)
	{
		frame++;
		if (!pending.isEmpty()) {
			GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, savedFbo, 0);
			GLES20.glGetIntegerv(GLES20.GL_VIEWPORT, savedViewport, 0);
			int built = 0;
			while (!pending.isEmpty() && built < BUILDS_PER_FRAME) {
				Job job = pending.remove(0);
				build(job, batch);
				built++;
			}
			GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, savedFbo[0]);
			GLES20.glViewport(savedViewport[0], savedViewport[1], savedViewport[2], savedViewport[3]);
			GLES20.glEnable(GLES20.GL_BLEND);
			while (count > MAX_ENTRIES) {
				evictLeastRecentlyUsed();
			}
		}
		if (frame % SWEEP_INTERVAL == 0) {
			sweepIdle();
		}
	}

	private void build(Job job, SpriteBatch batch)
	{
		Entry entry = new Entry();
		entry.sigmaX = job.sigmaX;
		entry.sigmaY = job.sigmaY;
		entry.lastUsed = frame;
		List<Entry> list = entries.get(job.key);
		if (list == null) {
			list = new ArrayList<>(2);
			entries.put(job.key, list);
		}
		list.add(entry);
		count++;

		SpriteSheet sheet = job.key.sheet;
		if (sheet == null || !sheet.isReady()) {
			return; // unloaded meanwhile; the failed entry blocks retries
		}
		if (fbo == 0) {
			GLES20.glGenFramebuffers(1, ids, 0);
			fbo = ids[0];
		}
		GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo);

		float padX = (float) Math.ceil(PAD_SIGMAS * job.sigmaX);
		float padY = (float) Math.ceil(PAD_SIGMAS * job.sigmaY);
		int fullW = Math.max(1, (int) Math.ceil(job.key.w + 2f * padX));
		int fullH = Math.max(1, (int) Math.ceil(job.key.h + 2f * padY));

		// Halvings per axis until sigma fits the 9-tap kernel; oversize
		// silhouettes start below 1:1 (k0) so the first texture fits
		int kx = levels(job.sigmaX);
		int ky = levels(job.sigmaY);
		int k0 = 0;
		while ((fullW >> k0) > MAX_FULL_RES || (fullH >> k0) > MAX_FULL_RES) {
			k0++;
		}
		int curW = Math.max(1, ceilDiv(fullW, 1 << k0));
		int curH = Math.max(1, ceilDiv(fullH, 1 << k0));

		// 1. Silhouette at (near) full resolution, blended onto transparent
		int texA = allocTexture(curW, curH);
		if (!attach(texA)) {
			GLES20.glDeleteTextures(1, new int[] { texA }, 0);
			return;
		}
		GLES20.glViewport(0, 0, curW, curH);
		GLES20.glClearColor(0f, 0f, 0f, 0f);
		GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT);
		orthoLocal(padX, padY, fullW, fullH);
		batch.renderSilhouette(job.key, ortho);

		// 2. Box-halve each axis down to its target level
		GLES20.glDisable(GLES20.GL_BLEND);
		GLES20.glDisableVertexAttribArray(2);
		int remX = Math.max(0, kx - k0);
		int remY = Math.max(0, ky - k0);
		while (remX > 0 || remY > 0) {
			int nextW = (remX > 0) ? Math.max(1, ceilDiv(curW, 2)) : curW;
			int nextH = (remY > 0) ? Math.max(1, ceilDiv(curH, 2)) : curH;
			int texB = allocTexture(nextW, nextH);
			attach(texB);
			GLES20.glViewport(0, 0, nextW, nextH);
			GLES20.glUseProgram(downsampleProgram);
			GLES20.glUniform1i(uTexDown, 0);
			GLES20.glUniform2f(uOffDown, (remX > 0) ? 0.5f / curW : 0f, (remY > 0) ? 0.5f / curH : 0f);
			drawQuad(texA);
			GLES20.glDeleteTextures(1, new int[] { texA }, 0);
			texA = texB;
			curW = nextW;
			curH = nextH;
			remX = Math.max(0, remX - 1);
			remY = Math.max(0, remY - 1);
		}

		// 3. Separable Gaussian, horizontal then vertical (with gain)
		float lowSigmaX = job.sigmaX / (1 << Math.max(kx, k0));
		float lowSigmaY = job.sigmaY / (1 << Math.max(ky, k0));
		int texB = allocTexture(curW, curH);
		attach(texB);
		GLES20.glViewport(0, 0, curW, curH);
		GLES20.glUseProgram(blurProgram);
		GLES20.glUniform1i(uTexBlur, 0);
		gaussianWeights(lowSigmaX);
		GLES20.glUniform1fv(uWeightsBlur, 5, weights, 0);
		GLES20.glUniform2f(uStepBlur, 1f / curW, 0f);
		GLES20.glUniform1f(uGainBlur, 1f);
		drawQuad(texA);
		GLES20.glDeleteTextures(1, new int[] { texA }, 0);

		texA = allocTexture(curW, curH);
		attach(texA);
		gaussianWeights(lowSigmaY);
		GLES20.glUniform1fv(uWeightsBlur, 5, weights, 0);
		GLES20.glUniform2f(uStepBlur, 0f, 1f / curH);
		GLES20.glUniform1f(uGainBlur, GAIN);
		drawQuad(texB);
		GLES20.glDeleteTextures(1, new int[] { texB }, 0);

		GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
			GLES20.GL_TEXTURE_2D, 0, 0);
		entry.texture = texA;
		entry.padX = padX;
		entry.padY = padY;
	}

	private static int levels(float sigma)
	{
		if (sigma <= MAX_LOW_SIGMA) {
			return 0;
		}
		return (int) Math.ceil(Math.log(sigma / MAX_LOW_SIGMA) / Math.log(2.0));
	}

	private static int ceilDiv(int a, int b)
	{
		return (a + b - 1) / b;
	}

	/** Column-major ortho mapping sprite-local [-padX, w+padX] x
	 *  [-padY, h+padY] onto the mask texture (v = 0 at the top edge). */
	private void orthoLocal(float padX, float padY, int fullW, int fullH)
	{
		for (int i = 0; i < 16; i++) {
			ortho[i] = 0f;
		}
		ortho[0] = 2f / fullW;
		ortho[5] = 2f / fullH;
		ortho[10] = -1f;
		ortho[12] = 2f * padX / fullW - 1f;
		ortho[13] = 2f * padY / fullH - 1f;
		ortho[15] = 1f;
	}

	private void gaussianWeights(float sigma)
	{
		float twoSigmaSquared = 2f * sigma * sigma;
		float sum = 0f;
		for (int i = 0; i < 5; i++) {
			float w = (twoSigmaSquared > 0f) ? (float) Math.exp(-(i * i) / twoSigmaSquared) : (i == 0 ? 1f : 0f);
			weights[i] = w;
			sum += (i == 0) ? w : 2f * w;
		}
		for (int i = 0; i < 5; i++) {
			weights[i] /= sum;
		}
	}

	private int allocTexture(int width, int height)
	{
		GLES20.glGenTextures(1, ids, 0);
		int id = ids[0];
		GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, id);
		GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0,
			GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
		return id;
	}

	private boolean attach(int texture)
	{
		GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
			GLES20.GL_TEXTURE_2D, texture, 0);
		return GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) == GLES20.GL_FRAMEBUFFER_COMPLETE;
	}

	/** Fullscreen pass reading `source` with the current program. */
	private void drawQuad(int source)
	{
		GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
		GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, source);
		int stride = 4 * 4;
		quad.position(0);
		GLES20.glVertexAttribPointer(ATTR_POS, 2, GLES20.GL_FLOAT, false, stride, quad);
		GLES20.glEnableVertexAttribArray(ATTR_POS);
		quad.position(2);
		GLES20.glVertexAttribPointer(ATTR_UV, 2, GLES20.GL_FLOAT, false, stride, quad);
		GLES20.glEnableVertexAttribArray(ATTR_UV);
		GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
	}

	private void evictLeastRecentlyUsed()
	{
		List<Entry> oldestList = null;
		Entry oldest = null;
		for (List<Entry> list : entries.values()) {
			for (int i = 0; i < list.size(); i++) {
				Entry e = list.get(i);
				if (oldest == null || e.lastUsed < oldest.lastUsed) {
					oldest = e;
					oldestList = list;
				}
			}
		}
		if (oldest == null) {
			count = 0;
			return;
		}
		remove(oldestList, oldest);
	}

	private void sweepIdle()
	{
		Iterator<Map.Entry<Silhouette, List<Entry>>> it = entries.entrySet().iterator();
		while (it.hasNext()) {
			List<Entry> list = it.next().getValue();
			for (int i = list.size() - 1; i >= 0; i--) {
				Entry e = list.get(i);
				if (frame - e.lastUsed > IDLE_FRAMES) {
					remove(list, e);
				}
			}
			if (list.isEmpty()) {
				it.remove();
			}
		}
	}

	private void remove(List<Entry> list, Entry e)
	{
		if (e.texture >= 0) {
			GLES20.glDeleteTextures(1, new int[] { e.texture }, 0);
			e.texture = -1;
		}
		list.remove(e);
		count--;
	}
}
