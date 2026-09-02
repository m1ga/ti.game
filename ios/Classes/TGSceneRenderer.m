#import "TGSceneRenderer.h"
#import "TGBitmapFont.h"
#import "TGDebugHud.h"
#import "TGFrameStats.h"
#import "TGParticleEmitter.h"
#import "TGPostEffect.h"
#import "TGRope.h"
#import "TGScene.h"
#import "TGScreenOverlay.h"
#import "TGSkidTrail.h"
#import "TGSprite.h"
#import "TGSpriteBatch.h"
#import "TGSpriteSheet.h"
#import "TGTextureManager.h"
#import "TGTileLayer.h"
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
	__weak TiProxy *_viewProxy; // fires 'resize', 'performance'
	TGSpriteBatch *_batch;
	TGTextureManager *_textures;
	TGPostEffect *_postEffect;
	TGScreenOverlay *_overlay;
	TGFrameStats *_stats; // scene.stats — the proxy toggles it
	float _projection[16];
	float _screenProjection[16]; // screenFixed sprites
	CFTimeInterval _lastFrameTime;
	float _effectTime; // drives the glitch animation
	float _debugAabb[4];
	float _debugBox[5];
	float _debugCorners[8];
	BOOL _wasMeasuring;
	NSMutableSet<TGSpriteSheet *> *_preparedSheets;
}

- (instancetype)initWithScene:(TGScene *)scene viewProxy:(TiProxy *)viewProxy
{
	if (self = [super init]) {
		_scene = scene;
		_viewProxy = viewProxy;
		_batch = [[TGSpriteBatch alloc] init];
		_textures = [[TGTextureManager alloc] init];
		_postEffect = [[TGPostEffect alloc] init];
		_overlay = [[TGScreenOverlay alloc] init];
		_stats = scene.stats;
		_preparedSheets = [NSMutableSet set];
		_screenScale = 1.0f;
	}
	return self;
}

- (BOOL)isMeasuring
{
	return _stats.enabled;
}

- (void)surfaceCreated
{
	// A new context means every texture and shader is gone
	[_textures invalidateAll];
	[_batch createGLResources];
	[_postEffect createGLResources];
	_lastFrameTime = 0;
	[_stats reset];
}

- (void)surfaceChangedWithWidth:(int)width height:(int)height
{
	_surfaceWidth = width;
	_surfaceHeight = height;
	_scene.worldWidth = width;
	_scene.worldHeight = height;
	glViewport(0, 0, width, height);
	orthoM(_projection, 0.0f, width, height, 0.0f, -1.0f, 1.0f);
	[_overlay surfaceChangedWithWidth:width height:height];

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

	// One atomic read decides whether this frame is measured at all.
	// Everything below that reads a clock sits behind it.
	const BOOL measuring = _stats.enabled;
	if (!measuring && _wasMeasuring) {
		[_stats reset];
	}
	_wasMeasuring = measuring;

	CFTimeInterval phaseStart = measuring ? CACurrentMediaTime() : 0;
	NSArray<TGParticleEmitter *> *emitters;
	NSArray<TGRope *> *ropes;
	NSArray<TGTileLayer *> *layers;
	NSArray<TGSprite *> *sprites = [_scene prepareFrame:dt emitters:&emitters ropes:&ropes layers:&layers];
	if (measuring) {
		_stats.updateMs = (CACurrentMediaTime() - phaseStart) * 1000.0;
	}
	// Wrapped: the glitch shader multiplies uTime by 40, and an unbounded
	// accumulator loses its sub-frame resolution within minutes (goes NaN
	// after ~27 min in fp16). 60 s is a whole number of every period the
	// shader uses, so the wrap itself is invisible.
	_effectTime = fmodf(_effectTime + dt, 60.0f);

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
	float right = left + visibleW;
	float bottom = top + visibleH;
	orthoM(_projection, left, right, bottom, top, -1.0f, 1.0f);
	orthoM(_screenProjection, 0.0f, _surfaceWidth, _surfaceHeight, 0.0f, -1.0f, 1.0f);

	glClearColor(_scene.bgRed, _scene.bgGreen, _scene.bgBlue, _scene.bgAlpha);
	glClear(GL_COLOR_BUFFER_BIT);

	// Sheets unloaded from JS free their texture here, on the render thread
	[_textures deleteDisposed];

	// Lazy texture upload happens here, on the render thread. A shared sheet
	// is prepared once per frame even when many sprites reference it.
	if (measuring) {
		phaseStart = CACurrentMediaTime();
	}
	[_preparedSheets removeAllObjects];
	for (TGSprite *s in sprites) {
		[self ensureSheetLoadedOnce:s.sheet];
	}
	for (TGParticleEmitter *e in emitters) {
		[self ensureSheetLoadedOnce:e.sheet];
	}
	for (TGRope *rope in ropes) {
		[self ensureSheetLoadedOnce:rope.sheet];
	}
	for (TGTileLayer *layer in layers) {
		[self ensureSheetLoadedOnce:layer.sheet];
	}
	if (measuring) {
		_stats.texturePrepareMs = (CACurrentMediaTime() - phaseStart) * 1000.0;
		phaseStart = CACurrentMediaTime();
	}

	// Camera travel (position + shake, without the zoom-centering term)
	// — the share of it that parallax sprites give back at draw time
	[_batch begin:_projection screenProjection:_screenProjection
		  originX:left originY:top screenScale:scale
		  travelX:_scene.cameraX + _scene.shakeOffsetX
		  travelY:_scene.cameraY + _scene.shakeOffsetY];
	[_batch setWorldWrapX:_scene.worldWrapXEnabled minX:_scene.worldWrapMinX
				 maxX:_scene.worldWrapMaxX referenceX:left + visibleW * 0.5f];
	// Skid marks slot between background (zIndex <= 0, e.g. the track)
	// and foreground sprites (the car), so they overlay the road but
	// stay under whatever drives across them. Emitters merge into the
	// sprite pass by zIndex; on equal zIndex, particles draw on top.
	// Tile layers merge the same way but draw UNDER sprites of equal
	// zIndex — a floor is the backdrop of whatever stands on it.
	BOOL trailDrawn = NO;
	NSUInteger nextEmitter = 0;
	NSUInteger nextRope = 0;
	NSUInteger nextLayer = 0;
	int visibleSprites = 0;
	for (TGSprite *s in sprites) {
		while (nextLayer < layers.count && layers[nextLayer].zIndex <= s.zIndex) {
			[layers[nextLayer++] draw:_batch viewLeft:left viewTop:top viewRight:right viewBottom:bottom];
		}
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
		if (s.visible && [s effectiveOpacity] > 0.0f) {
			visibleSprites++;
			[_batch draw:s];
		}
	}
	if (!trailDrawn) {
		[self drawSkidTrail];
	}
	while (nextEmitter < emitters.count) {
		[emitters[nextEmitter++] draw:_batch];
	}
	while (nextLayer < layers.count) {
		[layers[nextLayer++] draw:_batch viewLeft:left viewTop:top viewRight:right viewBottom:bottom];
	}
	while (nextRope < ropes.count) {
		[ropes[nextRope++] draw:_batch];
	}
	BOOL debugAll = _scene.debugAll;
	for (TGTileLayer *layer in layers) {
		if (debugAll || layer.debug) {
			[layer drawDebug:_batch whiteTexture:[_textures whiteTexture]
					viewLeft:left viewTop:top viewRight:right viewBottom:bottom];
		}
	}
	for (TGSprite *s in sprites) {
		if (debugAll || s.debug) {
			[self drawDebugOverlay:s];
		}
	}
	[_batch end];

	// Counters have to be read here, before the screen-space pass calls
	// begin again and resets them — otherwise the HUD would be reporting
	// its own cost back to itself.
	if (measuring) {
		_stats.batchMs = (CACurrentMediaTime() - phaseStart) * 1000.0;
		_stats.drawCalls = _batch.drawCalls + (effectActive ? 1 : 0);
		_stats.textureSwitches = _batch.textureSwitches;
		_stats.sprites = (int)sprites.count;
		_stats.visibleSprites = visibleSprites;
		_stats.emitters = (int)emitters.count;
		int particles = 0;
		for (TGParticleEmitter *emitter in emitters) {
			particles += MAX(0, emitter.activeParticleCount);
		}
		_stats.particles = particles;
	}

	if (effectActive) {
		[_postEffect finish:effectMode
					  tintR:_scene.effectTintR tintG:_scene.effectTintG tintB:_scene.effectTintB
				  intensity:_scene.effectIntensity time:_effectTime];
	}

	// Screen-space pass, last of all: drawn any earlier, the glitch shader
	// would smear exactly the numbers the HUD exists to show. A second
	// begin only re-uploads the projection uniform and re-enables
	// blending — the batcher needs no other state.
	TGDebugHud *hud = _scene.hud;
	if (hud.enabled) {
		// The HUD's own font if it was given one, else the scene's built-in
		// pixel font — the same instance createText() falls back to, so
		// there is only ever one copy of that texture.
		TGBitmapFont *hudFont = (hud.font != nil) ? hud.font : [_scene defaultFont];
		[self ensureSheetLoadedOnce:hudFont.sheet];
		// Screen space ignores camera travel, so the parallax terms are 0.
		[_batch begin:_projection screenProjection:_screenProjection
			  originX:left originY:top screenScale:scale
			  travelX:0.0f travelY:0.0f];
		[_batch setScreenSpace:YES];
		[hud draw:_batch texture:[_textures whiteTexture] font:hudFont
	   surfaceWidth:_surfaceWidth surfaceHeight:_surfaceHeight
		screenScale:self.screenScale];
		[_batch end];
	}
}

- (void)recordFrameCpuMs:(double)cpuMs
			   presentMs:(double)presentMs
			   presented:(BOOL)presented
				interval:(CFTimeInterval)interval
				  target:(CFTimeInterval)target
{
	CFTimeInterval now = CACurrentMediaTime();
	[_stats addFrameCpuMs:cpuMs presentMs:presentMs presented:presented
					  now:now interval:interval target:target];
	if ([_stats windowClosed:now]) {
		TGFrameStatsSnapshot snapshot = [_stats closeWindow:now];
		[_scene.hud update:snapshot];
		[self firePerformance:snapshot];
	}
}

/** At most one event per second, and only while JS is listening. */
- (void)firePerformance:(TGFrameStatsSnapshot)s
{
	TiProxy *proxy = _viewProxy;
	if (proxy == nil || ![proxy _hasListeners:@"performance"]) {
		return;
	}
	[proxy fireEvent:@"performance" withObject:@{
		@"fps": @(s.fps),
		@"averageCpuMs": @(s.averageCpuMs),
		@"p95CpuMs": @(s.p95CpuMs),
		@"maxCpuMs": @(s.maxCpuMs),
		@"averageUpdateMs": @(s.averageUpdateMs),
		@"averageTexturePrepareMs": @(s.averageTexturePrepareMs),
		@"averageBatchMs": @(s.averageBatchMs),
		@"averagePresentMs": @(s.averagePresentMs),
		@"droppedFrames": @(s.droppedFrames),
		@"presentFailures": @(s.presentFailures),
		@"sprites": @(s.sprites),
		@"visibleSprites": @(s.visibleSprites),
		@"emitters": @(s.emitters),
		@"particles": @(s.particles),
		@"drawCalls": @(s.drawCalls),
		@"textureSwitches": @(s.textureSwitches),
		@"surfaceWidth": @(_surfaceWidth),
		@"surfaceHeight": @(_surfaceHeight)
	}];
}

- (void)ensureSheetLoadedOnce:(TGSpriteSheet *)sheet
{
	if (sheet == nil || [_preparedSheets containsObject:sheet]) {
		return;
	}
	[_preparedSheets addObject:sheet];
	if (![sheet isReady]) {
		// Tracked as soon as a texture exists — a sheet that uploaded but
		// ended with zero frames (broken atlas) must still be deleted on
		// unload and invalidated on context loss
		if ([sheet ensureLoaded:_textures]) {
			[_textures track:sheet];
		}
	}
}

- (void)drawSkidTrail
{
	if (![_scene.skidTrail isEmpty]) {
		[_batch setScreenSpace:NO];
		[_scene.skidTrail draw:_batch whiteTexture:[_textures whiteTexture]];
	}
}

/**
 * Debug visualization: green = collision AABB (with hitboxScale and the
 * per-axis corrections),
 * blue = sprite/touch bounds (rotated), orange dot = anchor point.
 * Drawn after all sprites so overlays sit on top.
 */
- (void)drawDebugOverlay:(TGSprite *)s
{
	[_batch setScreenSpace:s.screenFixed]; // overlay in the sprite's own space
	GLuint white = [_textures whiteTexture];
	float t = 1.5f; // half line thickness
	// Parallax sprites render shifted — shift the overlay with the art
	float ox = [_batch parallaxX:s] - s.x;
	float oy = [_batch parallaxY:s] - s.y;

	// Collision shape — green (AABB, or circle for circleHitbox)
	if (s.circleHitbox) {
		float center[2];
		[s hitCenter:center];
		center[0] += ox;
		center[1] += oy;
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
	} else if (s.obbHitbox) {
		// The collision rect as it really sits: turned with the sprite, so
		// the green shape and the blue bounds agree instead of the green one
		// being an oversized square around the art
		[s hitBox:_debugBox];
		float bc = cosf(_debugBox[4]);
		float bs = sinf(_debugBox[4]);
		float hx = _debugBox[2];
		float hy = _debugBox[3];
		for (int i = 0; i < 4; i++) {
			float lx = ((i == 0 || i == 3) ? -hx : hx);
			float ly = ((i < 2) ? -hy : hy);
			_debugCorners[i * 2] = _debugBox[0] + ox + lx * bc - ly * bs;
			_debugCorners[i * 2 + 1] = _debugBox[1] + oy + lx * bs + ly * bc;
		}
		for (int i = 0; i < 4; i++) {
			int j = (i + 1) % 4;
			[_batch drawLine:white
					   fromX:_debugCorners[i * 2] y:_debugCorners[i * 2 + 1]
						 toX:_debugCorners[j * 2] y:_debugCorners[j * 2 + 1]
			   halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		}
	} else {
		[s computeAABB:_debugAabb];
		float minX = _debugAabb[0] + ox, minY = _debugAabb[1] + oy;
		float maxX = _debugAabb[2] + ox, maxY = _debugAabb[3] + oy;
		[_batch drawLine:white fromX:minX y:minY toX:maxX y:minY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		[_batch drawLine:white fromX:maxX y:minY toX:maxX y:maxY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		[_batch drawLine:white fromX:maxX y:maxY toX:minX y:maxY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
		[_batch drawLine:white fromX:minX y:maxY toX:minX y:minY halfThickness:t r:0.2f g:1.0f b:0.4f a:0.9f];
	}

	// Sprite/touch bounds — blue, rotated (differs from AABB when rotated
	// or when any of hitboxScale/hitboxScaleX/hitboxScaleY != 1)
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
			cx[i] = s.x + ox + lx * cosr - ly * sinr;
			cy[i] = s.y + oy + lx * sinr + ly * cosr;
		}
		[_batch drawLine:white fromX:cx[0] y:cy[0] toX:cx[1] y:cy[1] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
		[_batch drawLine:white fromX:cx[1] y:cy[1] toX:cx[3] y:cy[3] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
		[_batch drawLine:white fromX:cx[3] y:cy[3] toX:cx[2] y:cy[2] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
		[_batch drawLine:white fromX:cx[2] y:cy[2] toX:cx[0] y:cy[0] halfThickness:t r:0.35f g:0.6f b:1.0f a:0.9f];
	}

	// Anchor point — orange dot
	[_batch drawLine:white fromX:s.x + ox - 3.0f y:s.y + oy toX:s.x + ox + 3.0f y:s.y + oy halfThickness:3.0f r:1.0f g:0.6f b:0.0f a:1.0f];
}

@end
