#import "TGSceneRenderer.h"
#import "TGParticleEmitter.h"
#import "TGPostEffect.h"
#import "TGRope.h"
#import "TGScene.h"
#import "TGSkidTrail.h"
#import "TGSprite.h"
#import "TGSpriteBatch.h"
#import "TGSpriteSheet.h"
#import "TGTextureManager.h"
#import <OpenGLES/ES2/gl.h>
#import <QuartzCore/QuartzCore.h>
#import <TitaniumKit/TitaniumKit.h>
#import <math.h>

/** Column-major orthographic projection, like android.opengl.Matrix.orthoM. */
static void orthoM(float *m, float left, float right, float bottom, float top,
				   float near, float far)
{
	memset(m, 0, sizeof(float) * 16);
	m[0] = 2.0f / (right - left);
	m[5] = 2.0f / (top - bottom);
	m[10] = -2.0f / (far - near);
	m[12] = -(right + left) / (right - left);
	m[13] = -(top + bottom) / (top - bottom);
	m[14] = -(far + near) / (far - near);
	m[15] = 1.0f;
}

@implementation TGSceneRenderer {
	TGScene *_scene;
	__weak TiProxy *_viewProxy; // fires 'resize'
	TGSpriteBatch *_batch;
	TGTextureManager *_textures;
	TGPostEffect *_postEffect;
	float _projection[16];
	CFTimeInterval _lastFrameTime;
	float _effectTime; // drives the glitch animation
	float _debugAabb[4];
}

- (instancetype)initWithScene:(TGScene *)scene viewProxy:(TiProxy *)viewProxy
{
	if (self = [super init]) {
		_scene = scene;
		_viewProxy = viewProxy;
		_batch = [[TGSpriteBatch alloc] init];
		_textures = [[TGTextureManager alloc] init];
		_postEffect = [[TGPostEffect alloc] init];
	}
	return self;
}

- (void)surfaceCreated
{
	// A new context means every texture and shader is gone
	[_textures invalidateAll];
	[_batch createGLResources];
	[_postEffect createGLResources];
	_lastFrameTime = 0;
}

- (void)surfaceChangedWithWidth:(int)width height:(int)height
{
	_surfaceWidth = width;
	_surfaceHeight = height;
	_scene.worldWidth = width;
	_scene.worldHeight = height;
	glViewport(0, 0, width, height);
	orthoM(_projection, 0.0f, width, height, 0.0f, -1.0f, 1.0f);

	// The real scene coordinate space — build/relayout levels on this,
	// not on the display size
	TiProxy *proxy = _viewProxy;
	if (proxy != nil && [proxy _hasListeners:@"resize"]) {
		[proxy fireEvent:@"resize" withObject:@{
			@"width": @(width),
			@"height": @(height)
		}];
	}
}

- (void)resetClock
{
	_lastFrameTime = 0;
}

- (void)drawFrame:(CFTimeInterval)frameTime
{
	float dt = (_lastFrameTime == 0) ? 0.0f : (float)(frameTime - _lastFrameTime);
	_lastFrameTime = frameTime;
	// Clamp so a paused/debugged app doesn't fast-forward animations
	if (dt > 0.1f) {
		dt = 0.1f;
	}

	[_scene update:dt];
	_effectTime += dt;

	// Camera effect: render the whole scene into an offscreen texture,
	// then draw it to the screen through the effect shader at the end
	int effectMode = _scene.cameraEffect;
	BOOL effectActive = (effectMode != TGPostEffectNone)
		&& [_postEffect beginWithWidth:_surfaceWidth height:_surfaceHeight];

	// Projection follows the camera (position, zoom, shake) — sprites
	// live in world coordinates
	float scale = MAX(0.0001f, _scene.cameraScale);
	float left = [_scene viewOriginX] + _scene.shakeOffsetX;
	float top = [_scene viewOriginY] + _scene.shakeOffsetY;
	float visibleW = _surfaceWidth / scale;
	float visibleH = _surfaceHeight / scale;
	orthoM(_projection, left, left + visibleW, top + visibleH, top, -1.0f, 1.0f);

	glClearColor(_scene.bgRed, _scene.bgGreen, _scene.bgBlue, _scene.bgAlpha);
	glClear(GL_COLOR_BUFFER_BIT);

	NSArray<TGSprite *> *sprites = [_scene snapshot];
	NSArray<TGParticleEmitter *> *emitters = [_scene emittersSnapshot];
	NSArray<TGRope *> *ropes = [_scene ropesSnapshot];

	// Lazy texture upload happens here, on the render thread
	for (TGSprite *s in sprites) {
		[self ensureSheetLoaded:s.sheet];
	}
	for (TGParticleEmitter *e in emitters) {
		[self ensureSheetLoaded:e.sheet];
	}
	for (TGRope *rope in ropes) {
		[self ensureSheetLoaded:rope.sheet];
	}

	[_batch begin:_projection];
	// Skid marks slot between background (zIndex <= 0, e.g. the track)
	// and foreground sprites (the car), so they overlay the road but
	// stay under whatever drives across them. Emitters merge into the
	// sprite pass by zIndex; on equal zIndex, particles draw on top.
	BOOL trailDrawn = NO;
	NSUInteger nextEmitter = 0;
	NSUInteger nextRope = 0;
	for (TGSprite *s in sprites) {
		if (!trailDrawn && s.zIndex > 0) {
			[self drawSkidTrail];
			trailDrawn = YES;
		}
		while (nextEmitter < emitters.count && emitters[nextEmitter].zIndex < s.zIndex) {
			[emitters[nextEmitter++] draw:_batch];
		}
		while (nextRope < ropes.count && ropes[nextRope].zIndex < s.zIndex) {
			[ropes[nextRope++] draw:_batch];
		}
		if (s.visible && s.opacity > 0.0f) {
			[_batch draw:s];
		}
	}
	if (!trailDrawn) {
		[self drawSkidTrail];
	}
	while (nextEmitter < emitters.count) {
		[emitters[nextEmitter++] draw:_batch];
	}
	while (nextRope < ropes.count) {
		[ropes[nextRope++] draw:_batch];
	}
	BOOL debugAll = _scene.debugAll;
	for (TGSprite *s in sprites) {
		if (debugAll || s.debug) {
			[self drawDebugOverlay:s];
		}
	}
	[_batch end];

	if (effectActive) {
		[_postEffect finish:effectMode
					  tintR:_scene.effectTintR tintG:_scene.effectTintG tintB:_scene.effectTintB
				  intensity:_scene.effectIntensity time:_effectTime];
	}
}

- (void)ensureSheetLoaded:(TGSpriteSheet *)sheet
{
	if (sheet != nil && ![sheet isReady]) {
		[sheet ensureLoaded:_textures];
		if ([sheet isReady]) {
			[_textures track:sheet];
		}
	}
}

- (void)drawSkidTrail
{
	if (![_scene.skidTrail isEmpty]) {
		[_scene.skidTrail draw:_batch whiteTexture:[_textures whiteTexture]];
	}
}

/**
 * Debug visualization: green = collision AABB (with hitboxScale),
 * blue = sprite/touch bounds (rotated), orange dot = anchor point.
 * Drawn after all sprites so overlays sit on top.
 */
- (void)drawDebugOverlay:(TGSprite *)s
{
	GLuint white = [_textures whiteTexture];
	float t = 1.5f; // half line thickness

	// Collision shape — green (AABB, or circle for circleHitbox)
	if (s.circleHitbox) {
		float center[2];
		[s hitCenter:center];
		float r = [s hitRadius];
		int segments = 20;
		for (int i = 0; i < segments; i++) {
			float a0 = 2.0f * (float)M_PI * i / segments;
			float a1 = 2.0f * (float)M_PI * (i + 1) / segments;
			[_batch drawLine:white
					   fromX:center[0] + r * cosf(a0) y:center[1] + r * sinf(a0)
						 toX:center[0] + r * cosf(a1) y:center[1] + r * sinf(a1)
			   halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		}
	} else {
		[s computeAABB:_debugAabb];
		float minX = _debugAabb[0], minY = _debugAabb[1];
		float maxX = _debugAabb[2], maxY = _debugAabb[3];
		[_batch drawLine:white fromX:minX y:minY toX:maxX y:minY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		[_batch drawLine:white fromX:maxX y:minY toX:maxX y:maxY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		[_batch drawLine:white fromX:maxX y:maxY toX:minX y:maxY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		[_batch drawLine:white fromX:minX y:maxY toX:minX y:minY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
	}

	// Sprite/touch bounds — blue, rotated (differs from AABB when rotated
	// or when hitboxScale != 1)
	float w = [s drawWidth];
	float h = [s drawHeight];
	if (w > 0.0f && h > 0.0f) {
		float ax = s.anchorX * w;
		float ay = s.anchorY * h;
		float rad = s.rotation * (float)M_PI / 180.0f;
		float cosr = cosf(rad);
		float sinr = sinf(rad);
		float cx[4];
		float cy[4];
		for (int i = 0; i < 4; i++) {
			float lx = (((i & 1) == 0) ? -ax : w - ax) * s.scaleX;
			float ly = ((i < 2) ? -ay : h - ay) * s.scaleY;
			cx[i] = s.x + lx * cosr - ly * sinr;
			cy[i] = s.y + lx * sinr + ly * cosr;
		}
		[_batch drawLine:white fromX:cx[0] y:cy[0] toX:cx[1] y:cy[1] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
		[_batch drawLine:white fromX:cx[1] y:cy[1] toX:cx[3] y:cy[3] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
		[_batch drawLine:white fromX:cx[3] y:cy[3] toX:cx[2] y:cy[2] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
		[_batch drawLine:white fromX:cx[2] y:cy[2] toX:cx[0] y:cy[0] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
	}

	// Anchor point — orange dot
	[_batch drawLine:white fromX:s.x - 3.0f y:s.y toX:s.x + 3.0f y:s.y halfThickness:3.0f r:1.0f g:0.6f b:0.0f a:1.0f];
}

@end
