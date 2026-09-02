package ti.game.engine;

import android.opengl.GLES20;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

/**
 * Fullscreen camera effects. When active, the renderer redirects the
 * whole scene into an offscreen framebuffer texture (begin), then this
 * class draws that texture to the screen through an effect shader
 * (finish) — one extra fullscreen pass, nothing else changes.
 *
 * Effects: TINT multiplies the scene with a color, GLITCH displaces
 * horizontal slices, splits RGB channels and flickers, driven by a time
 * uniform. Both scale with an intensity (0..1). GL thread only; all GL
 * resources are recreated after context loss via createGLResources.
 */
public class PostEffect
{
	public static final int NONE = 0;
	public static final int TINT = 1;
	public static final int GLITCH = 2;

	private static final String VERTEX_SHADER =
		"attribute vec2 aPos;\n"
		+ "attribute vec2 aUV;\n"
		+ "varying vec2 vUV;\n"
		+ "void main() {\n"
		+ "  gl_Position = vec4(aPos, 0.0, 1.0);\n"
		+ "  vUV = aUV;\n"
		+ "}\n";

	private static final String TINT_FRAGMENT_SHADER =
		"precision mediump float;\n"
		+ "uniform sampler2D uTex;\n"
		+ "uniform vec3 uTint;\n"
		+ "uniform float uIntensity;\n"
		+ "varying vec2 vUV;\n"
		+ "void main() {\n"
		+ "  vec4 c = texture2D(uTex, vUV);\n"
		+ "  gl_FragColor = vec4(mix(c.rgb, c.rgb * uTint, uIntensity), c.a);\n"
		+ "}\n";

	// Row slices jump sideways a few times a second, the RGB channels
	// drift apart and scanline noise flickers — all keyed off uTime so
	// the glitch re-rolls instead of animating smoothly.
	private static final String GLITCH_FRAGMENT_SHADER =
		"precision mediump float;\n"
		+ "uniform sampler2D uTex;\n"
		// mediump (fp16) cannot resolve uTime * 40; highp where the fragment stage has it
		+ "#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
		+ "uniform highp float uTime;\n"
		+ "#else\n"
		+ "uniform float uTime;\n"
		+ "#endif\n"
		+ "uniform float uIntensity;\n"
		+ "varying vec2 vUV;\n"
		+ "float rnd(vec2 co) {\n"
		+ "  return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);\n"
		+ "}\n"
		+ "void main() {\n"
		+ "  vec2 uv = vUV;\n"
		+ "  float jump = floor(uTime * 12.0);\n"
		+ "  float band = floor(uv.y * 24.0);\n"
		+ "  float r = rnd(vec2(band, jump));\n"
		+ "  float shift = (r - 0.5) * step(1.0 - uIntensity * 0.5, r) * 0.2 * uIntensity;\n"
		+ "  uv.x = fract(uv.x + shift);\n"
		+ "  float split = 0.006 * uIntensity * (0.5 + 0.5 * sin(uTime * 40.0));\n"
		+ "  vec4 c;\n"
		+ "  c.r = texture2D(uTex, vec2(fract(uv.x + split), uv.y)).r;\n"
		+ "  c.g = texture2D(uTex, uv).g;\n"
		+ "  c.b = texture2D(uTex, vec2(fract(uv.x - split), uv.y)).b;\n"
		+ "  c.a = texture2D(uTex, uv).a;\n"
		+ "  c.rgb *= 1.0 - 0.15 * uIntensity * rnd(vec2(floor(uv.y * 120.0), jump));\n"
		+ "  gl_FragColor = c;\n"
		+ "}\n";

	private static final int ATTR_POS = 0;
	private static final int ATTR_UV = 1;

	private int tintProgram = 0;
	private int glitchProgram = 0;
	private int uTexTint, uTintTint, uIntensityTint;
	private int uTexGlitch, uTimeGlitch, uIntensityGlitch;

	private int fbo = 0;
	private int fboTexture = 0;
	private int fboWidth = 0;
	private int fboHeight = 0;
	private int previousFbo = 0;

	// Fullscreen quad as a triangle strip: x, y (NDC), u, v
	private final FloatBuffer quad;
	private static final float[] QUAD = {
		-1f, -1f, 0f, 0f,
		1f, -1f, 1f, 0f,
		-1f, 1f, 0f, 1f,
		1f, 1f, 1f, 1f
	};

	public PostEffect()
	{
		quad = ByteBuffer.allocateDirect(QUAD.length * 4)
			.order(ByteOrder.nativeOrder())
			.asFloatBuffer();
		quad.put(QUAD).position(0);
	}

	/** (Re)creates shaders and invalidates the FBO; call from onSurfaceCreated. */
	public void createGLResources()
	{
		tintProgram = buildProgram(TINT_FRAGMENT_SHADER);
		uTexTint = GLES20.glGetUniformLocation(tintProgram, "uTex");
		uTintTint = GLES20.glGetUniformLocation(tintProgram, "uTint");
		uIntensityTint = GLES20.glGetUniformLocation(tintProgram, "uIntensity");
		glitchProgram = buildProgram(GLITCH_FRAGMENT_SHADER);
		uTexGlitch = GLES20.glGetUniformLocation(glitchProgram, "uTex");
		uTimeGlitch = GLES20.glGetUniformLocation(glitchProgram, "uTime");
		uIntensityGlitch = GLES20.glGetUniformLocation(glitchProgram, "uIntensity");
		// The old FBO/texture died with the context — force recreation
		fbo = 0;
		fboTexture = 0;
		fboWidth = 0;
		fboHeight = 0;
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

	/**
	 * Redirect rendering into the offscreen texture. Returns false (and
	 * leaves the screen framebuffer bound) if the FBO can't be set up —
	 * the caller then renders directly, skipping the effect.
	 */
	private final int[] prevFbo = new int[1]; // glGetIntegerv scratch

	public boolean begin(int width, int height)
	{
		if (width <= 0 || height <= 0) {
			return false;
		}
		GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, prevFbo, 0);
		previousFbo = prevFbo[0];
		if (!ensureFbo(width, height)) {
			return false;
		}
		GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo);
		return true;
	}

	private boolean ensureFbo(int width, int height)
	{
		if (fbo != 0 && width == fboWidth && height == fboHeight) {
			return true;
		}
		if (fbo == 0) {
			int[] id = new int[1];
			GLES20.glGenFramebuffers(1, id, 0);
			fbo = id[0];
			GLES20.glGenTextures(1, id, 0);
			fboTexture = id[0];
		}
		GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, fboTexture);
		GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, width, height, 0,
			GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE);
		GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE);
		GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, fbo);
		GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
			GLES20.GL_TEXTURE_2D, fboTexture, 0);
		boolean complete =
			GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER) == GLES20.GL_FRAMEBUFFER_COMPLETE;
		GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, previousFbo);
		if (complete) {
			fboWidth = width;
			fboHeight = height;
		}
		return complete;
	}

	/** Draw the captured scene to the screen through the effect shader. */
	public void finish(int mode, float tintR, float tintG, float tintB,
					   float intensity, float time)
	{
		GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, previousFbo);

		int program = (mode == GLITCH) ? glitchProgram : tintProgram;
		GLES20.glUseProgram(program);
		GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
		GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, fboTexture);
		float strength = Math.max(0f, Math.min(1f, intensity));
		if (mode == GLITCH) {
			GLES20.glUniform1i(uTexGlitch, 0);
			GLES20.glUniform1f(uTimeGlitch, time);
			GLES20.glUniform1f(uIntensityGlitch, strength);
		} else {
			GLES20.glUniform1i(uTexTint, 0);
			GLES20.glUniform3f(uTintTint, tintR, tintG, tintB);
			GLES20.glUniform1f(uIntensityTint, strength);
		}

		// Opaque copy — the scene already composited; SpriteBatch.begin
		// re-enables blending next frame
		GLES20.glDisable(GLES20.GL_BLEND);
		int stride = 4 * 4;
		quad.position(0);
		GLES20.glVertexAttribPointer(ATTR_POS, 2, GLES20.GL_FLOAT, false, stride, quad);
		GLES20.glEnableVertexAttribArray(ATTR_POS);
		quad.position(2);
		GLES20.glVertexAttribPointer(ATTR_UV, 2, GLES20.GL_FLOAT, false, stride, quad);
		GLES20.glEnableVertexAttribArray(ATTR_UV);
		GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
	}
}
