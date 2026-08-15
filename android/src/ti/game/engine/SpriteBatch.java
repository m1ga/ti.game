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

	private final float[] vertices = new float[MAX_QUADS * VERTICES_PER_QUAD * FLOATS_PER_VERTEX];
	private final FloatBuffer buffer;
	private int quadCount = 0;
	private int currentTexture = -1;

	private int program = 0;
	private int aPos, aUV, aColor, uProj, uTex;
	private float[] projection;

	public SpriteBatch()
	{
		buffer = ByteBuffer.allocateDirect(vertices.length * 4)
			.order(ByteOrder.nativeOrder())
			.asFloatBuffer();
	}

	/** (Re)creates shaders; call from onSurfaceCreated. */
	public void createGLResources()
	{
		int vs = compileShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER);
		int fs = compileShader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER);
		program = GLES20.glCreateProgram();
		GLES20.glAttachShader(program, vs);
		GLES20.glAttachShader(program, fs);
		GLES20.glLinkProgram(program);
		GLES20.glDeleteShader(vs);
		GLES20.glDeleteShader(fs);
		aPos = GLES20.glGetAttribLocation(program, "aPos");
		aUV = GLES20.glGetAttribLocation(program, "aUV");
		aColor = GLES20.glGetAttribLocation(program, "aColor");
		uProj = GLES20.glGetUniformLocation(program, "uProj");
		uTex = GLES20.glGetUniformLocation(program, "uTex");
	}

	private static int compileShader(int type, String source)
	{
		int shader = GLES20.glCreateShader(type);
		GLES20.glShaderSource(shader, source);
		GLES20.glCompileShader(shader);
		return shader;
	}

	public void begin(float[] projectionMatrix)
	{
		projection = projectionMatrix;
		quadCount = 0;
		currentTexture = -1;
		GLES20.glUseProgram(program);
		GLES20.glUniformMatrix4fv(uProj, 1, false, projection, 0);
		GLES20.glUniform1i(uTex, 0);
		GLES20.glActiveTexture(GLES20.GL_TEXTURE0);
		GLES20.glEnable(GLES20.GL_BLEND);
		GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA);
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

		// Corners in local space relative to the anchor, scaled then rotated
		float lx0 = -ax * sx, ly0 = -ay * sy;             // top-left
		float lx1 = (w - ax) * sx, ly1 = -ay * sy;        // top-right
		float lx2 = -ax * sx, ly2 = (h - ay) * sy;        // bottom-left
		float lx3 = (w - ax) * sx, ly3 = (h - ay) * sy;   // bottom-right

		float x0 = s.x + lx0 * cos - ly0 * sin, y0 = s.y + lx0 * sin + ly0 * cos;
		float x1 = s.x + lx1 * cos - ly1 * sin, y1 = s.y + lx1 * sin + ly1 * cos;
		float x2 = s.x + lx2 * cos - ly2 * sin, y2 = s.y + lx2 * sin + ly2 * cos;
		float x3 = s.x + lx3 * cos - ly3 * sin, y3 = s.y + lx3 * sin + ly3 * cos;

		putQuad(x0, y0, f.u0, f.v0,
			x1, y1, f.u1, f.v0,
			x2, y2, f.u0, f.v1,
			x3, y3, f.u1, f.v1,
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
		GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, stride, buffer);
		GLES20.glEnableVertexAttribArray(aPos);
		buffer.position(2);
		GLES20.glVertexAttribPointer(aUV, 2, GLES20.GL_FLOAT, false, stride, buffer);
		GLES20.glEnableVertexAttribArray(aUV);
		buffer.position(4);
		GLES20.glVertexAttribPointer(aColor, 4, GLES20.GL_FLOAT, false, stride, buffer);
		GLES20.glEnableVertexAttribArray(aColor);

		GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount);
		quadCount = 0;
	}
}
