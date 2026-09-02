#import "TGPostEffect.h"
#import <math.h>

static const char *kEffectVertexShader =
	"attribute vec2 aPos;\n"
	"attribute vec2 aUV;\n"
	"varying vec2 vUV;\n"
	"void main() {\n"
	"  gl_Position = vec4(aPos, 0.0, 1.0);\n"
	"  vUV = aUV;\n"
	"}\n";

static const char *kTintFragmentShader =
	"precision mediump float;\n"
	"uniform sampler2D uTex;\n"
	"uniform vec3 uTint;\n"
	"uniform float uIntensity;\n"
	"varying vec2 vUV;\n"
	"void main() {\n"
	"  vec4 c = texture2D(uTex, vUV);\n"
	"  gl_FragColor = vec4(mix(c.rgb, c.rgb * uTint, uIntensity), c.a);\n"
	"}\n";

// Row slices jump sideways a few times a second, the RGB channels
// drift apart and scanline noise flickers — all keyed off uTime so
// the glitch re-rolls instead of animating smoothly.
static const char *kGlitchFragmentShader =
	"precision mediump float;\n"
	"uniform sampler2D uTex;\n"
	// mediump (fp16) cannot resolve uTime * 40; highp where the fragment stage has it
	"#ifdef GL_FRAGMENT_PRECISION_HIGH\n"
	"uniform highp float uTime;\n"
	"#else\n"
	"uniform float uTime;\n"
	"#endif\n"
	"uniform float uIntensity;\n"
	"varying vec2 vUV;\n"
	"float rnd(vec2 co) {\n"
	"  return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);\n"
	"}\n"
	"void main() {\n"
	"  vec2 uv = vUV;\n"
	"  float jump = floor(uTime * 12.0);\n"
	"  float band = floor(uv.y * 24.0);\n"
	"  float r = rnd(vec2(band, jump));\n"
	"  float shift = (r - 0.5) * step(1.0 - uIntensity * 0.5, r) * 0.2 * uIntensity;\n"
	"  uv.x = fract(uv.x + shift);\n"
	"  float split = 0.006 * uIntensity * (0.5 + 0.5 * sin(uTime * 40.0));\n"
	"  vec4 c;\n"
	"  c.r = texture2D(uTex, vec2(fract(uv.x + split), uv.y)).r;\n"
	"  c.g = texture2D(uTex, uv).g;\n"
	"  c.b = texture2D(uTex, vec2(fract(uv.x - split), uv.y)).b;\n"
	"  c.a = texture2D(uTex, uv).a;\n"
	"  c.rgb *= 1.0 - 0.15 * uIntensity * rnd(vec2(floor(uv.y * 120.0), jump));\n"
	"  gl_FragColor = c;\n"
	"}\n";

enum { kEffectAttrPos = 0, kEffectAttrUV = 1 };

// Fullscreen quad as a triangle strip: x, y (NDC), u, v
static const float kEffectQuad[] = {
	-1.0f, -1.0f, 0.0f, 0.0f,
	1.0f, -1.0f, 1.0f, 0.0f,
	-1.0f, 1.0f, 0.0f, 1.0f,
	1.0f, 1.0f, 1.0f, 1.0f
};

static GLuint compileEffectShader(GLenum type, const char *source)
{
	GLuint shader = glCreateShader(type);
	glShaderSource(shader, 1, &source, NULL);
	glCompileShader(shader);
	return shader;
}

static GLuint buildEffectProgram(const char *fragmentSource)
{
	GLuint vs = compileEffectShader(GL_VERTEX_SHADER, kEffectVertexShader);
	GLuint fs = compileEffectShader(GL_FRAGMENT_SHADER, fragmentSource);
	GLuint p = glCreateProgram();
	glAttachShader(p, vs);
	glAttachShader(p, fs);
	glBindAttribLocation(p, kEffectAttrPos, "aPos");
	glBindAttribLocation(p, kEffectAttrUV, "aUV");
	glLinkProgram(p);
	glDeleteShader(vs);
	glDeleteShader(fs);
	return p;
}

@implementation TGPostEffect {
	GLuint _tintProgram;
	GLuint _glitchProgram;
	GLint _uTexTint, _uTintTint, _uIntensityTint;
	GLint _uTexGlitch, _uTimeGlitch, _uIntensityGlitch;

	GLuint _fbo;
	GLuint _fboTexture;
	int _fboWidth;
	int _fboHeight;
	GLint _previousFbo;
}

- (void)createGLResources
{
	_tintProgram = buildEffectProgram(kTintFragmentShader);
	_uTexTint = glGetUniformLocation(_tintProgram, "uTex");
	_uTintTint = glGetUniformLocation(_tintProgram, "uTint");
	_uIntensityTint = glGetUniformLocation(_tintProgram, "uIntensity");
	_glitchProgram = buildEffectProgram(kGlitchFragmentShader);
	_uTexGlitch = glGetUniformLocation(_glitchProgram, "uTex");
	_uTimeGlitch = glGetUniformLocation(_glitchProgram, "uTime");
	_uIntensityGlitch = glGetUniformLocation(_glitchProgram, "uIntensity");
	// The old FBO/texture died with the context — force recreation
	_fbo = 0;
	_fboTexture = 0;
	_fboWidth = 0;
	_fboHeight = 0;
}

- (BOOL)beginWithWidth:(int)width height:(int)height
{
	if (width <= 0 || height <= 0) {
		return NO;
	}
	glGetIntegerv(GL_FRAMEBUFFER_BINDING, &_previousFbo);
	if (![self ensureFboWithWidth:width height:height]) {
		return NO;
	}
	glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
	return YES;
}

- (BOOL)ensureFboWithWidth:(int)width height:(int)height
{
	if (_fbo != 0 && width == _fboWidth && height == _fboHeight) {
		return YES;
	}
	if (_fbo == 0) {
		glGenFramebuffers(1, &_fbo);
		glGenTextures(1, &_fboTexture);
	}
	glBindTexture(GL_TEXTURE_2D, _fboTexture);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0,
		GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glBindFramebuffer(GL_FRAMEBUFFER, _fbo);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
		GL_TEXTURE_2D, _fboTexture, 0);
	BOOL complete = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
	glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)_previousFbo);
	if (complete) {
		_fboWidth = width;
		_fboHeight = height;
	}
	return complete;
}

- (void)finish:(int)mode
		 tintR:(float)tintR tintG:(float)tintG tintB:(float)tintB
	 intensity:(float)intensity time:(float)time
{
	glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)_previousFbo);

	GLuint program = (mode == TGPostEffectGlitch) ? _glitchProgram : _tintProgram;
	glUseProgram(program);
	glActiveTexture(GL_TEXTURE0);
	glBindTexture(GL_TEXTURE_2D, _fboTexture);
	float strength = MAX(0.0f, MIN(1.0f, intensity));
	if (mode == TGPostEffectGlitch) {
		glUniform1i(_uTexGlitch, 0);
		glUniform1f(_uTimeGlitch, time);
		glUniform1f(_uIntensityGlitch, strength);
	} else {
		glUniform1i(_uTexTint, 0);
		glUniform3f(_uTintTint, tintR, tintG, tintB);
		glUniform1f(_uIntensityTint, strength);
	}

	// Opaque copy — the scene already composited; the batch begin
	// re-enables blending next frame
	glDisable(GL_BLEND);
	GLsizei stride = 4 * sizeof(float);
	glVertexAttribPointer(kEffectAttrPos, 2, GL_FLOAT, GL_FALSE, stride, kEffectQuad);
	glEnableVertexAttribArray(kEffectAttrPos);
	glVertexAttribPointer(kEffectAttrUV, 2, GL_FLOAT, GL_FALSE, stride, kEffectQuad + 2);
	glEnableVertexAttribArray(kEffectAttrUV);
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

@end
