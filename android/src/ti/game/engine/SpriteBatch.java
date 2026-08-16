package ti.game.engine;

import android.opengl.GLES20;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;

/**
 * ES 2.0 sprite batcher: accumulates quads and issues one draw call per
 * texture change (or when full). Vertices are (x, y, u, v, r, g, b, a) with
 * the color premultiplied; bitmaps uploaded via GLUtils are premultiplied,
 * so blending is (ONE, ONE_MINUS_SRC_ALPHA) and the fragment color is
 * texture * vertexColor. Untextured shapes (debug overlays) draw with the
 * TextureManager's 1x1 white texture. GL thread only.
 */
public class SpriteBatch
{
	private static final int MAX_QUADS = 1000;
	private static final int FLOATS_PER_VERTEX = 8; // x, y, u, v, r, g, b, a
	private static final int VERTICES_PER_QUAD = 6; // two triangles

	private static final String VERTEX_SHADER =
		"uniform mat4 uProj;\n"
		+ "attribute vec2 aPos;\n"
		+ "attribute vec2 aUV;\n"
		+ "attribute vec4 aColor;\n"
		+ "varying vec2 vUV;\n"
		+ "varying vec4 vColor;\n"
		+ "void main() {\n"
		+ "  gl_Position = uProj * vec4(aPos, 0.0, 1.0);\n"
		+ "  vUV = aUV;\n"
		+ "  vColor = aColor;\n"
		+ "}\n";

	private static final String FRAGMENT_SHADER =
		"precision mediump float;\n"
		+ "uniform sampler2D uTex;\n"
		+ "varying vec2 vUV;\n"
		+ "varying vec4 vColor;\n"
		+ "void main() {\n"
		+ "  gl_FragColor = texture2D(uTex, vUV) * vColor;\n"
		+ "}\n";

	// Silhouette shader for glows: the frame's alpha tinted with the
	// vertex color, ignoring the art's own colors — stamped in soft
	// rings behind the sprite it reads as a blurred halo.
	private static final String GLOW_FRAGMENT_SHADER =
		"precision mediump float;\n"
		+ "uniform sampler2D uTex;\n"
		+ "varying vec2 vUV;\n"
		+ "varying vec4 vColor;\n"
		+ "void main() {\n"
		+ "  gl_FragColor = vColor * texture2D(uTex, vUV).a;\n"
		+ "}\n";

	// Attribute locations are bound identically for both programs so
	// flush() never cares which one is active.
	private static final int ATTR_POS = 0;
	private static final int ATTR_UV = 1;
	private static final int ATTR_COLOR = 2;

	// Glow stamp pattern: unit (x, y, alpha) triples — an outer ring of 8
	// at the full blur radius and an inner ring of 8 at 0.55r, rotated
	// half a step. Overlaps build a solid core with soft edges.
	private static final float[] GLOW_RING = buildGlowRing();

	private static float[] buildGlowRing()
	{
		float[] ring = new float[16 * 3];
		for (int i = 0; i < 8; i++) {
			double outer = Math.PI * 2.0 * i / 8.0;
			double inner = outer + Math.PI / 8.0;
			int o = i * 3;
			ring[o] = (float) Math.cos(outer);
			ring[o + 1] = (float) Math.sin(outer);
			ring[o + 2] = 0.20f;
			int n = (8 + i) * 3;
			ring[n] = (float) Math.cos(inner) * 0.55f;
			ring[n + 1] = (float) Math.sin(inner) * 0.55f;
			ring[n + 2] = 0.30f;
		}
		return ring;
	}

	private final float[] vertices = new float[MAX_QUADS * VERTICES_PER_QUAD * FLOATS_PER_VERTEX];
	private final FloatBuffer buffer;
	private int quadCount = 0;
	private int currentTexture = -1;

	private int program = 0;
	private int glowProgram = 0;
	private int activeProgram = 0;
	private int uProj, uTex;             // main program
	private int uProjGlow, uTexGlow;     // glow program
	private float[] projection;
	private float pixelOriginX;
	private float pixelOriginY;
	private float pixelScale = 1f;

	public SpriteBatch()
	{
		buffer = ByteBuffer.allocateDirect(vertices.length * 4)
			.order(ByteOrder.nativeOrder())
			.asFloatBuffer();
	}

	/** (Re)creates shaders; call from onSurfaceCreated. */
	public void createGLResources()
	{
		program = buildProgram(FRAGMENT_SHADER);
		uProj = GLES20.glGetUniformLocation(program, "uProj");
		uTex = GLES20.glGetUniformLocation(program, "uTex");
		glowProgram = buildProgram(GLOW_FRAGMENT_SHADER);
		uProjGlow = GLES20.glGetUniformLocation(glowProgram, "uProj");
		uTexGlow = GLES20.glGetUniformLocation(glowProgram, "uTex");
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
		GLES20.glBindAttribLocation(p, ATTR_COLOR, "aColor");
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

	public void begin(float[] projectionMatrix, float originX, float originY, float screenScale)
	{
		projection = projectionMatrix;
		pixelOriginX = originX;
		pixelOriginY = originY;
		pixelScale = Math.max(0.0001f, screenScale);
		quadCount = 0;
		currentTexture = -1;
		activeProgram = 0;
		useProgram(program);
		GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
		GLES20.glEnable(GLES20.GL_BLEND);
		GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA);
	}

	/** Flush and switch programs; both share attribute locations. */
	private void useProgram(int p)
	{
		if (p == activeProgram) {
			return;
		}
		flush();
		GLES20.glUseProgram(p);
		GLES20.glUniformMatrix4fv((p == program) ? uProj : uProjGlow, 1, false, projection, 0);
		GLES20.glUniform1i((p == program) ? uTex : uTexGlow, 0);
		activeProgram = p;
	}

	private void ensureCapacity(int texture)
	{
		if (texture != currentTexture) {
			flush();
			currentTexture = texture;
		}
		if (quadCount >= MAX_QUADS) {
			flush();
		}
	}

	public void draw(Sprite s)
	{
		SpriteSheet sheet = s.sheet;
		if (sheet == null || !sheet.isReady()) {
			return;
		}
		SpriteSheet.Frame f = sheet.frame(s.frame);
		if (f == null) {
			return;
		}
		ensureCapacity(sheet.textureId());

		float w = s.drawWidth();
		float h = s.drawHeight();
		float ax = s.anchorX * w;
		float ay = s.anchorY * h;
		double rad = Math.toRadians(s.rotation);
		float cos = (float) Math.cos(rad);
		float sin = (float) Math.sin(rad);
		float sx = s.scaleX;
		float sy = s.scaleY;
		float alpha = Math.max(0f, Math.min(1f, s.opacity));
		float x = s.x;
		float y = s.y;
		if (s.pixelSnap) {
			x = snapToPixel(x, pixelOriginX);
			y = snapToPixel(y, pixelOriginY);
		}

		// tileRepeat: run the UVs past 1 so GL_REPEAT tiles the texture at
		// its native pixel size instead of stretching it across the sprite
		float u1 = f.u1;
		float v1 = f.v1;
		if (s.tileRepeatX && f.width > 0f) {
			u1 = f.u0 + (f.u1 - f.u0) * (w / f.width);
		}
		if (s.tileRepeatY && f.height > 0f) {
			v1 = f.v0 + (f.v1 - f.v0) * (h / f.height);
		}

		// Corners in local space relative to the anchor, scaled then rotated
		float lx0 = -ax * sx, ly0 = -ay * sy;             // top-left
		float lx1 = (w - ax) * sx, ly1 = -ay * sy;        // top-right
		float lx2 = -ax * sx, ly2 = (h - ay) * sy;        // bottom-left
		float lx3 = (w - ax) * sx, ly3 = (h - ay) * sy;   // bottom-right

		float x0 = x + lx0 * cos - ly0 * sin, y0 = y + lx0 * sin + ly0 * cos;
		float x1 = x + lx1 * cos - ly1 * sin, y1 = y + lx1 * sin + ly1 * cos;
		float x2 = x + lx2 * cos - ly2 * sin, y2 = y + lx2 * sin + ly2 * cos;
		float x3 = x + lx3 * cos - ly3 * sin, y3 = y + lx3 * sin + ly3 * cos;

		float blur = s.glowBlur;
		float glow = Math.max(0f, Math.min(1f, s.glowOpacity)) * alpha;
		if (blur > 0f && glow > 0f) {
			useProgram(glowProgram);
			float gr = s.glowR;
			float gg = s.glowG;
			float gb = s.glowB;
			int texture = sheet.textureId();
			for (int k = 0; k < GLOW_RING.length; k += 3) {
				float ox = GLOW_RING[k] * blur;
				float oy = GLOW_RING[k + 1] * blur;
				float ga = GLOW_RING[k + 2] * glow;
				ensureCapacity(texture);
				putQuad(x0 + ox, y0 + oy, f.u0, f.v0,
					x1 + ox, y1 + oy, u1, f.v0,
					x2 + ox, y2 + oy, f.u0, v1,
					x3 + ox, y3 + oy, u1, v1,
					gr * ga, gg * ga, gb * ga, ga);
			}
			useProgram(program);
			ensureCapacity(texture);
		}

		putQuad(x0, y0, f.u0, f.v0,
			x1, y1, u1, f.v0,
			x2, y2, f.u0, v1,
			x3, y3, u1, v1,
			s.tintR * alpha, s.tintG * alpha, s.tintB * alpha, alpha);
	}

	private float snapToPixel(float value, float origin)
	{
		float screenCoordinate = (value - origin) * pixelScale;
		return origin + (float) Math.floor(screenCoordinate + 0.5f) / pixelScale;
	}

	/**
	 * Axis-aligned textured quad with a straight-alpha tint color —
	 * the particle path (premultiplied internally, like drawLine).
	 */
	public void drawFrame(int texture, SpriteSheet.Frame f, float cx, float cy,
						  float halfW, float halfH, float r, float g, float b, float a)
	{
		ensureCapacity(texture);
		putQuad(cx - halfW, cy - halfH, f.u0, f.v0,
			cx + halfW, cy - halfH, f.u1, f.v0,
			cx - halfW, cy + halfH, f.u0, f.v1,
			cx + halfW, cy + halfH, f.u1, f.v1,
			r * a, g * a, b * a, a);
	}

	/**
	 * Textured quad oriented along a segment (rope links): u runs across
	 * the width, v along the segment. Straight-alpha, premultiplied here.
	 */
	public void drawSegment(int texture, SpriteSheet.Frame f, float x0, float y0,
							float x1, float y1, float halfWidth, float alpha)
	{
		float dx = x1 - x0;
		float dy = y1 - y0;
		float len = (float) Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-6f) {
			return;
		}
		float nx = -dy / len * halfWidth;
		float ny = dx / len * halfWidth;
		ensureCapacity(texture);
		putQuad(x0 - nx, y0 - ny, f.u0, f.v0,
			x0 + nx, y0 + ny, f.u1, f.v0,
			x1 - nx, y1 - ny, f.u0, f.v1,
			x1 + nx, y1 + ny, f.u1, f.v1,
			alpha, alpha, alpha, alpha);
	}

	/**
	 * Debug/shape helper: a solid line segment of the given half-thickness,
	 * drawn with `texture` (normally the white texture). Color is
	 * straight-alpha; premultiplied internally.
	 */
	public void drawLine(int texture, float x0, float y0, float x1, float y1,
						 float halfThickness, float r, float g, float b, float a)
	{
		float dx = x1 - x0;
		float dy = y1 - y0;
		float len = (float) Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-6f) {
			dx = 1f;
			dy = 0f;
			len = 1f;
		}
		float nx = -dy / len * halfThickness;
		float ny = dx / len * halfThickness;

		ensureCapacity(texture);
		putQuad(x0 + nx, y0 + ny, 0.5f, 0.5f,
			x1 + nx, y1 + ny, 0.5f, 0.5f,
			x0 - nx, y0 - ny, 0.5f, 0.5f,
			x1 - nx, y1 - ny, 0.5f, 0.5f,
			r * a, g * a, b * a, a);
	}

	/** Corners: top-left, top-right, bottom-left, bottom-right. */
	private void putQuad(float x0, float y0, float u0, float v0,
						 float x1, float y1, float u1, float v1,
						 float x2, float y2, float u2, float v2,
						 float x3, float y3, float u3, float v3,
						 float r, float g, float b, float a)
	{
		int i = quadCount * VERTICES_PER_QUAD * FLOATS_PER_VERTEX;
		i = putVertex(i, x0, y0, u0, v0, r, g, b, a);
		i = putVertex(i, x1, y1, u1, v1, r, g, b, a);
		i = putVertex(i, x2, y2, u2, v2, r, g, b, a);
		i = putVertex(i, x1, y1, u1, v1, r, g, b, a);
		i = putVertex(i, x3, y3, u3, v3, r, g, b, a);
		putVertex(i, x2, y2, u2, v2, r, g, b, a);
		quadCount++;
	}

	private int putVertex(int i, float x, float y, float u, float v,
						  float r, float g, float b, float a)
	{
		vertices[i++] = x;
		vertices[i++] = y;
		vertices[i++] = u;
		vertices[i++] = v;
		vertices[i++] = r;
		vertices[i++] = g;
		vertices[i++] = b;
		vertices[i++] = a;
		return i;
	}

	public void end()
	{
		flush();
	}

	private void flush()
	{
		if (quadCount == 0 || currentTexture < 0) {
			quadCount = 0;
			return;
		}
		int vertexCount = quadCount * VERTICES_PER_QUAD;
		buffer.position(0);
		buffer.put(vertices, 0, vertexCount * FLOATS_PER_VERTEX);

		GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, currentTexture);

		int stride = FLOATS_PER_VERTEX * 4;
		buffer.position(0);
		GLES20.glVertexAttribPointer(ATTR_POS, 2, GLES20.GL_FLOAT, false, stride, buffer);
		GLES20.glEnableVertexAttribArray(ATTR_POS);
		buffer.position(2);
		GLES20.glVertexAttribPointer(ATTR_UV, 2, GLES20.GL_FLOAT, false, stride, buffer);
		GLES20.glEnableVertexAttribArray(ATTR_UV);
		buffer.position(4);
		GLES20.glVertexAttribPointer(ATTR_COLOR, 4, GLES20.GL_FLOAT, false, stride, buffer);
		GLES20.glEnableVertexAttribArray(ATTR_COLOR);

		GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount);
		quadCount = 0;
	}
}
