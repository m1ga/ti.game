#import "TGSpriteBatch.h"
#import "TGSprite.h"
#import "TGSpriteSheet.h"
#import <math.h>

static const int kMaxQuads = 1000;
static const int kFloatsPerVertex = 8; // x, y, u, v, r, g, b, a
static const int kVerticesPerQuad = 6; // two triangles

static const char *kVertexShader =
	"uniform mat4 uProj;\n"
	"attribute vec2 aPos;\n"
	"attribute vec2 aUV;\n"
	"attribute vec4 aColor;\n"
	"varying vec2 vUV;\n"
	"varying vec4 vColor;\n"
	"void main() {\n"
	"  gl_Position = uProj * vec4(aPos, 0.0, 1.0);\n"
	"  vUV = aUV;\n"
	"  vColor = aColor;\n"
	"}\n";

static const char *kFragmentShader =
	"precision mediump float;\n"
	"uniform sampler2D uTex;\n"
	"varying vec2 vUV;\n"
	"varying vec4 vColor;\n"
	"void main() {\n"
	"  gl_FragColor = texture2D(uTex, vUV) * vColor;\n"
	"}\n";

// Silhouette shader for glows: the frame's alpha tinted with the
// vertex color, ignoring the art's own colors — stamped in soft
// rings behind the sprite it reads as a blurred halo.
static const char *kGlowFragmentShader =
	"precision mediump float;\n"
	"uniform sampler2D uTex;\n"
	"varying vec2 vUV;\n"
	"varying vec4 vColor;\n"
	"void main() {\n"
	"  gl_FragColor = vColor * texture2D(uTex, vUV).a;\n"
	"}\n";

// Attribute locations are bound identically for both programs so
// flush never cares which one is active.
enum { kAttrPos = 0, kAttrUV = 1, kAttrColor = 2 };

// Glow stamp pattern: unit (x, y, alpha) triples — an outer ring of 8
// at the full blur radius and an inner ring of 8 at 0.55r, rotated
// half a step. Overlaps build a solid core with soft edges.
static float kGlowRing[16 * 3];
static void buildGlowRing(void)
{
	for (int i = 0; i < 8; i++) {
		float outer = (float)(M_PI * 2.0 * i / 8.0);
		float inner = outer + (float)(M_PI / 8.0);
		int o = i * 3;
		kGlowRing[o] = cosf(outer);
		kGlowRing[o + 1] = sinf(outer);
		kGlowRing[o + 2] = 0.20f;
		int n = (8 + i) * 3;
		kGlowRing[n] = cosf(inner) * 0.55f;
		kGlowRing[n + 1] = sinf(inner) * 0.55f;
		kGlowRing[n + 2] = 0.30f;
	}
}

static GLuint compileShader(GLenum type, const char *source)
{
	GLuint shader = glCreateShader(type);
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);
	return shader;
}

static GLuint buildProgram(const char *fragmentSource)
{
	GLuint vs = compileShader(GL_VERTEX_SHADER, kVertexShader);
	GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragmentSource);
	GLuint p = glCreateProgram();
	glAttachShader(p, vs);
	glAttachShader(p, fs);
	glBindAttribLocation(p, kAttrPos, "aPos");
	glBindAttribLocation(p, kAttrUV, "aUV");
	glBindAttribLocation(p, kAttrColor, "aColor");
	glLinkProgram(p);
	glDeleteShader(vs);
	glDeleteShader(fs);
	return p;
}

static inline float snapToPixel(float value, float origin, float screenScale)
{
	float screenCoordinate = (value - origin) * screenScale;
	return origin + floorf(screenCoordinate + 0.5f) / screenScale;
}

@implementation TGSpriteBatch {
	float *_vertices;
	int _quadCount;
	GLint _currentTexture;

	GLuint _program;
	GLuint _glowProgram;
	GLuint _activeProgram;
	GLuint _vbo; // vertex upload buffer; client-side arrays stall the driver
	GLint _uProj, _uTex;         // main program
	GLint _uProjGlow, _uTexGlow; // glow program
	const float *_projection;
	float _pixelOriginX;
	float _pixelOriginY;
	float _pixelScale;
}

- (instancetype)init
{
	if (self = [super init]) {
		_vertices = malloc(sizeof(float) * kMaxQuads * kVerticesPerQuad * kFloatsPerVertex);
		_currentTexture = -1;
		_pixelScale = 1.0f;
	}
	return self;
}

- (void)dealloc
{
	free(_vertices);
}

- (void)createGLResources
{
	static dispatch_once_t once;
	dispatch_once(&once, ^{ buildGlowRing(); });
	_program = buildProgram(kFragmentShader);
	_uProj = glGetUniformLocation(_program, "uProj");
	_uTex = glGetUniformLocation(_program, "uTex");
	_glowProgram = buildProgram(kGlowFragmentShader);
	_uProjGlow = glGetUniformLocation(_glowProgram, "uProj");
	_uTexGlow = glGetUniformLocation(_glowProgram, "uTex");
	glGenBuffers(1, &_vbo);
}

- (void)begin:(const float *)projectionMatrix
	 originX:(float)originX
	 originY:(float)originY
	screenScale:(float)screenScale
{
	_projection = projectionMatrix;
	_pixelOriginX = originX;
	_pixelOriginY = originY;
	_pixelScale = MAX(0.0001f, screenScale);
	_quadCount = 0;
	_currentTexture = -1;
	_activeProgram = 0;
	[self useProgram:_program];
	glActiveTexture(GL_TEXTURE0);
	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
}

/** Flush and switch programs; both share attribute locations. */
- (void)useProgram:(GLuint)p
{
	if (p == _activeProgram) {
		return;
	}
	[self flush];
	glUseProgram(p);
	glUniformMatrix4fv((p == _program) ? _uProj : _uProjGlow, 1, GL_FALSE, _projection);
	glUniform1i((p == _program) ? _uTex : _uTexGlow, 0);
	_activeProgram = p;
}

- (void)ensureCapacity:(GLint)texture
{
	if (texture != _currentTexture) {
		[self flush];
		_currentTexture = texture;
	}
	if (_quadCount >= kMaxQuads) {
		[self flush];
	}
}

- (void)draw:(TGSprite *)s
{
	TGSpriteSheet *sheet = s.sheet;
	if (sheet == nil || ![sheet isReady]) {
		return;
	}
	TGFrame f;
	if (![sheet frame:s.frame into:&f]) {
		return;
	}
	[self ensureCapacity:[sheet textureId]];

	float w = [s drawWidth];
	float h = [s drawHeight];
	float ax = s.anchorX * w;
	float ay = s.anchorY * h;
	float rad = s.rotation * (float)M_PI / 180.0f;
	float cosr = cosf(rad);
	float sinr = sinf(rad);
	float sx = s.scaleX;
	float sy = s.scaleY;
	float alpha = MAX(0.0f, MIN(1.0f, s.opacity));
	float x = s.x;
	float y = s.y;
	if (s.pixelSnap) {
		x = snapToPixel(x, _pixelOriginX, _pixelScale);
		y = snapToPixel(y, _pixelOriginY, _pixelScale);
	}

	// tileRepeat: run the UVs past 1 so GL_REPEAT tiles the texture at
	// its native pixel size instead of stretching it across the sprite
	float u0 = f.u0;
	float v0 = f.v0;
	float u1 = f.u1;
	float v1 = f.v1;
	if (s.tileRepeatX && f.width > 0.0f) {
		u1 = f.u0 + (f.u1 - f.u0) * (w / f.width);
	}
	if (s.tileRepeatY && f.height > 0.0f) {
		v1 = f.v0 + (f.v1 - f.v0) * (h / f.height);
	}

	// flip: mirror the texture by swapping the UV range end-for-end
	if (s.flipX) {
		float t = u0;
		u0 = u1;
		u1 = t;
	}
	if (s.flipY) {
		float t = v0;
		v0 = v1;
		v1 = t;
	}

	// Corners in local space relative to the anchor, scaled then rotated
	float lx0 = -ax * sx, ly0 = -ay * sy;             // top-left
	float lx1 = (w - ax) * sx, ly1 = -ay * sy;        // top-right
	float lx2 = -ax * sx, ly2 = (h - ay) * sy;        // bottom-left
	float lx3 = (w - ax) * sx, ly3 = (h - ay) * sy;   // bottom-right

	float x0 = x + lx0 * cosr - ly0 * sinr, y0 = y + lx0 * sinr + ly0 * cosr;
	float x1 = x + lx1 * cosr - ly1 * sinr, y1 = y + lx1 * sinr + ly1 * cosr;
	float x2 = x + lx2 * cosr - ly2 * sinr, y2 = y + lx2 * sinr + ly2 * cosr;
	float x3 = x + lx3 * cosr - ly3 * sinr, y3 = y + lx3 * sinr + ly3 * cosr;

	float blur = s.glowBlur;
	float glow = MAX(0.0f, MIN(1.0f, s.glowOpacity)) * alpha;
	if (blur > 0.0f && glow > 0.0f) {
		[self useProgram:_glowProgram];
		float gr = s.glowR;
		float gg = s.glowG;
		float gb = s.glowB;
		GLint texture = [sheet textureId];
		for (int k = 0; k < 16 * 3; k += 3) {
			float ox = kGlowRing[k] * blur;
			float oy = kGlowRing[k + 1] * blur;
			float ga = kGlowRing[k + 2] * glow;
			[self ensureCapacity:texture];
			[self putQuadX0:x0 + ox y0:y0 + oy u0:u0 v0:v0
						 x1:x1 + ox y1:y1 + oy u1:u1 v1:v0
						 x2:x2 + ox y2:y2 + oy u2:u0 v2:v1
						 x3:x3 + ox y3:y3 + oy u3:u1 v3:v1
						  r:gr * ga g:gg * ga b:gb * ga a:ga];
		}
		[self useProgram:_program];
		[self ensureCapacity:texture];
	}

	[self putQuadX0:x0 y0:y0 u0:u0 v0:v0
				 x1:x1 y1:y1 u1:u1 v1:v0
				 x2:x2 y2:y2 u2:u0 v2:v1
				 x3:x3 y3:y3 u3:u1 v3:v1
				  r:s.tintR * alpha g:s.tintG * alpha b:s.tintB * alpha a:alpha];
}

- (void)drawFrame:(GLuint)texture frame:(TGFrame)f
			   cx:(float)cx cy:(float)cy
			halfW:(float)halfW halfH:(float)halfH
				r:(float)r g:(float)g b:(float)b a:(float)a
{
	[self ensureCapacity:(GLint)texture];
	[self putQuadX0:cx - halfW y0:cy - halfH u0:f.u0 v0:f.v0
				 x1:cx + halfW y1:cy - halfH u1:f.u1 v1:f.v0
				 x2:cx - halfW y2:cy + halfH u2:f.u0 v2:f.v1
				 x3:cx + halfW y3:cy + halfH u3:f.u1 v3:f.v1
				  r:r * a g:g * a b:b * a a:a];
}

- (void)drawSegment:(GLuint)texture frame:(TGFrame)f
			  fromX:(float)x0 y:(float)y0
				toX:(float)x1 y:(float)y1
		  halfWidth:(float)halfWidth alpha:(float)alpha
{
	float dx = x1 - x0;
	float dy = y1 - y0;
	float len = sqrtf(dx * dx + dy * dy);
	if (len < 1e-6f) {
		return;
	}
	float nx = -dy / len * halfWidth;
	float ny = dx / len * halfWidth;
	[self ensureCapacity:(GLint)texture];
	[self putQuadX0:x0 - nx y0:y0 - ny u0:f.u0 v0:f.v0
				 x1:x0 + nx y1:y0 + ny u1:f.u1 v1:f.v0
				 x2:x1 - nx y2:y1 - ny u2:f.u0 v2:f.v1
				 x3:x1 + nx y3:y1 + ny u3:f.u1 v3:f.v1
				  r:alpha g:alpha b:alpha a:alpha];
}

- (void)drawLine:(GLuint)texture
		   fromX:(float)x0 y:(float)y0
			 toX:(float)x1 y:(float)y1
   halfThickness:(float)halfThickness
			   r:(float)r g:(float)g b:(float)b a:(float)a
{
	float dx = x1 - x0;
	float dy = y1 - y0;
	float len = sqrtf(dx * dx + dy * dy);
	if (len < 1e-6f) {
		dx = 1.0f;
		dy = 0.0f;
		len = 1.0f;
	}
	float nx = -dy / len * halfThickness;
	float ny = dx / len * halfThickness;

	[self ensureCapacity:(GLint)texture];
	[self putQuadX0:x0 + nx y0:y0 + ny u0:0.5f v0:0.5f
				 x1:x1 + nx y1:y1 + ny u1:0.5f v1:0.5f
				 x2:x0 - nx y2:y0 - ny u2:0.5f v2:0.5f
				 x3:x1 - nx y3:y1 - ny u3:0.5f v3:0.5f
				  r:r * a g:g * a b:b * a a:a];
}

static inline float *putVertex(float *v, float x, float y, float u, float uv,
							   float r, float g, float b, float a)
{
	v[0] = x;
	v[1] = y;
	v[2] = u;
	v[3] = uv;
	v[4] = r;
	v[5] = g;
	v[6] = b;
	v[7] = a;
	return v + 8;
}

/** Corners: top-left, top-right, bottom-left, bottom-right. */
- (void)putQuadX0:(float)x0 y0:(float)y0 u0:(float)u0 v0:(float)v0
			   x1:(float)x1 y1:(float)y1 u1:(float)u1 v1:(float)v1
			   x2:(float)x2 y2:(float)y2 u2:(float)u2 v2:(float)v2
			   x3:(float)x3 y3:(float)y3 u3:(float)u3 v3:(float)v3
				r:(float)r g:(float)g b:(float)b a:(float)a
{
	float *v = _vertices + _quadCount * kVerticesPerQuad * kFloatsPerVertex;
	v = putVertex(v, x0, y0, u0, v0, r, g, b, a);
	v = putVertex(v, x1, y1, u1, v1, r, g, b, a);
	v = putVertex(v, x2, y2, u2, v2, r, g, b, a);
	v = putVertex(v, x1, y1, u1, v1, r, g, b, a);
	v = putVertex(v, x3, y3, u3, v3, r, g, b, a);
	putVertex(v, x2, y2, u2, v2, r, g, b, a);
	_quadCount++;
}

- (void)end
{
	[self flush];
}

- (void)flush
{
	if (_quadCount == 0 || _currentTexture < 0) {
		_quadCount = 0;
		return;
	}
	int vertexCount = _quadCount * kVerticesPerQuad;

	glBindTexture(GL_TEXTURE_2D, (GLuint)_currentTexture);

	GLsizei stride = kFloatsPerVertex * sizeof(float);
	// Fresh glBufferData each flush orphans the old storage, so the GPU can
	// keep reading the previous frame while we upload the next one
	glBindBuffer(GL_ARRAY_BUFFER, _vbo);
	glBufferData(GL_ARRAY_BUFFER, vertexCount * stride, _vertices, GL_STREAM_DRAW);
	glVertexAttribPointer(kAttrPos, 2, GL_FLOAT, GL_FALSE, stride, (const void *)0);
	glEnableVertexAttribArray(kAttrPos);
	glVertexAttribPointer(kAttrUV, 2, GL_FLOAT, GL_FALSE, stride, (const void *)(2 * sizeof(float)));
	glEnableVertexAttribArray(kAttrUV);
	glVertexAttribPointer(kAttrColor, 4, GL_FLOAT, GL_FALSE, stride, (const void *)(4 * sizeof(float)));
	glEnableVertexAttribArray(kAttrColor);

	glDrawArrays(GL_TRIANGLES, 0, vertexCount);
	// TGPostEffect draws with client-side pointers — leave no buffer bound
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	_quadCount = 0;
}

@end
