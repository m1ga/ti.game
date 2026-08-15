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

static GLuint compileShader(GLenum type, const char *source)
{
	GLuint shader = glCreateShader(type);
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);
	return shader;
}

@implementation TGSpriteBatch {
	float *_vertices;
	int _quadCount;
	GLint _currentTexture;

	GLuint _program;
	GLint _aPos, _aUV, _aColor, _uProj, _uTex;
}

- (instancetype)init
{
	if (self = [super init]) {
		_vertices = malloc(sizeof(float) * kMaxQuads * kVerticesPerQuad * kFloatsPerVertex);
		_currentTexture = -1;
	}
	return self;
}

- (void)dealloc
{
	free(_vertices);
}

- (void)createGLResources
{
	GLuint vs = compileShader(GL_VERTEX_SHADER, kVertexShader);
	GLuint fs = compileShader(GL_FRAGMENT_SHADER, kFragmentShader);
	_program = glCreateProgram();
	glAttachShader(_program, vs);
	glAttachShader(_program, fs);
	glLinkProgram(_program);
	glDeleteShader(vs);
	glDeleteShader(fs);
	_aPos = glGetAttribLocation(_program, "aPos");
	_aUV = glGetAttribLocation(_program, "aUV");
	_aColor = glGetAttribLocation(_program, "aColor");
	_uProj = glGetUniformLocation(_program, "uProj");
	_uTex = glGetUniformLocation(_program, "uTex");
}

- (void)begin:(const float *)projectionMatrix
{
	_quadCount = 0;
	_currentTexture = -1;
	glUseProgram(_program);
	glUniformMatrix4fv(_uProj, 1, GL_FALSE, projectionMatrix);
	glUniform1i(_uTex, 0);
	glActiveTexture(GL_TEXTURE0);
	glEnable(GL_BLEND);
	glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
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

	// Corners in local space relative to the anchor, scaled then rotated
	float lx0 = -ax * sx, ly0 = -ay * sy;             // top-left
	float lx1 = (w - ax) * sx, ly1 = -ay * sy;        // top-right
	float lx2 = -ax * sx, ly2 = (h - ay) * sy;        // bottom-left
	float lx3 = (w - ax) * sx, ly3 = (h - ay) * sy;   // bottom-right

	float x0 = x + lx0 * cosr - ly0 * sinr, y0 = y + lx0 * sinr + ly0 * cosr;
	float x1 = x + lx1 * cosr - ly1 * sinr, y1 = y + lx1 * sinr + ly1 * cosr;
	float x2 = x + lx2 * cosr - ly2 * sinr, y2 = y + lx2 * sinr + ly2 * cosr;
	float x3 = x + lx3 * cosr - ly3 * sinr, y3 = y + lx3 * sinr + ly3 * cosr;

	[self putQuadX0:x0 y0:y0 u0:f.u0 v0:f.v0
				 x1:x1 y1:y1 u1:f.u1 v1:f.v0
				 x2:x2 y2:y2 u2:f.u0 v2:f.v1
				 x3:x3 y3:y3 u3:f.u1 v3:f.v1
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

/** Corners: top-left, top-right, bottom-left, bottom-right. */
- (void)putQuadX0:(float)x0 y0:(float)y0 u0:(float)u0 v0:(float)v0
			   x1:(float)x1 y1:(float)y1 u1:(float)u1 v1:(float)v1
			   x2:(float)x2 y2:(float)y2 u2:(float)u2 v2:(float)v2
			   x3:(float)x3 y3:(float)y3 u3:(float)u3 v3:(float)v3
				r:(float)r g:(float)g b:(float)b a:(float)a
{
	int i = _quadCount * kVerticesPerQuad * kFloatsPerVertex;
	i = [self putVertex:i x:x0 y:y0 u:u0 v:v0 r:r g:g b:b a:a];
	i = [self putVertex:i x:x1 y:y1 u:u1 v:v1 r:r g:g b:b a:a];
	i = [self putVertex:i x:x2 y:y2 u:u2 v:v2 r:r g:g b:b a:a];
	i = [self putVertex:i x:x1 y:y1 u:u1 v:v1 r:r g:g b:b a:a];
	i = [self putVertex:i x:x3 y:y3 u:u3 v:v3 r:r g:g b:b a:a];
	[self putVertex:i x:x2 y:y2 u:u2 v:v2 r:r g:g b:b a:a];
	_quadCount++;
}

- (int)putVertex:(int)i x:(float)x y:(float)y u:(float)u v:(float)v
			   r:(float)r g:(float)g b:(float)b a:(float)a
{
	_vertices[i++] = x;
	_vertices[i++] = y;
	_vertices[i++] = u;
	_vertices[i++] = v;
	_vertices[i++] = r;
	_vertices[i++] = g;
	_vertices[i++] = b;
	_vertices[i++] = a;
	return i;
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
	glVertexAttribPointer(_aPos, 2, GL_FLOAT, GL_FALSE, stride, _vertices);
	glEnableVertexAttribArray(_aPos);
	glVertexAttribPointer(_aUV, 2, GL_FLOAT, GL_FALSE, stride, _vertices + 2);
	glEnableVertexAttribArray(_aUV);
	glVertexAttribPointer(_aColor, 4, GL_FLOAT, GL_FALSE, stride, _vertices + 4);
	glEnableVertexAttribArray(_aColor);

	glDrawArrays(GL_TRIANGLES, 0, vertexCount);
	_quadCount = 0;
}

@end
