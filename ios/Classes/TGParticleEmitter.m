#import "TGParticleEmitter.h"
#import "TGSprite.h"
#import "TGSpriteBatch.h"
#import "TGSpriteSheet.h"
#import <math.h>
#import <stdatomic.h>
#import <stdlib.h>

static const int kHardCap = 1000;

@implementation TGParticleEmitter {
	// Cross-thread requests, consumed by update on the render thread
	atomic_int _pendingBurst;
	atomic_bool _clearRequested;

	// Particle pool — render thread only
	float *_px, *_py, *_vx, *_vy, *_age, *_life;
	int _capacity;
	int _count;
	float _emitAccumulator;
	unsigned int _seed;
}

// both maxParticles accessors are hand-written, so synthesize manually
@synthesize maxParticles = _maxParticles;

- (instancetype)init
{
	if (self = [super init]) {
		_lifetime = 0.8f;
		_speed = 100.0f;
		_spread = 360.0f;
		_startScale = 1.0f;
		_endScale = 1.0f;
		_startOpacity = 1.0f;
		_endOpacity = 0.0f;
		_tintR = 1.0f;
		_tintG = 1.0f;
		_tintB = 1.0f;
		_emitting = YES;
		_maxParticles = 200;
		_seed = arc4random();
	}
	return self;
}

- (void)dealloc
{
	free(_px);
	free(_py);
	free(_vx);
	free(_vy);
	free(_age);
	free(_life);
}

- (void)setMaxParticles:(int)value
{
	@synchronized (self) {
		_maxParticles = MAX(1, MIN(kHardCap, value));
	}
}

- (int)maxParticles
{
	@synchronized (self) {
		return _maxParticles;
	}
}

- (int)activeParticleCount
{
	return _count;
}

- (void)emit:(int)n
{
	if (n > 0) {
		atomic_fetch_add(&_pendingBurst, n);
	}
}

- (void)clearParticles
{
	atomic_store(&_clearRequested, true);
}

- (float)nextRandom // 0..1, render thread only
{
	return (float)rand_r(&_seed) / (float)RAND_MAX;
}

- (void)update:(float)dt
{
	if (atomic_exchange(&_clearRequested, false)) {
		_count = 0;
	}
	int cap = self.maxParticles;
	[self ensureCapacity:cap];

	// Emitter position: followed sprite or own x/y, plus offset
	TGSprite *t = self.target;
	float ex = ((t != nil) ? t.x : self.x) + self.offsetX;
	float ey = ((t != nil) ? t.y : self.y) + self.offsetY;

	int toSpawn = atomic_exchange(&_pendingBurst, 0);
	float rate = self.rate;
	if (self.emitting && rate > 0.0f) {
		_emitAccumulator += rate * dt;
		int continuous = (int)_emitAccumulator;
		_emitAccumulator -= continuous;
		toSpawn += continuous;
	}
	while (toSpawn-- > 0 && _count < cap) {
		[self spawnAtX:ex y:ey];
	}

	float g = self.gravity;
	for (int i = 0; i < _count; ) {
		_age[i] += dt;
		if (_age[i] >= _life[i]) {
			// swap-remove: order doesn't matter for particles
			_count--;
			_px[i] = _px[_count];
			_py[i] = _py[_count];
			_vx[i] = _vx[_count];
			_vy[i] = _vy[_count];
			_age[i] = _age[_count];
			_life[i] = _life[_count];
			continue;
		}
		_vy[i] += g * dt;
		_px[i] += _vx[i] * dt;
		_py[i] += _vy[i] * dt;
		i++;
	}
}

- (void)spawnAtX:(float)ex y:(float)ey
{
	float rad = (self.angle + ([self nextRandom] - 0.5f) * self.spread) * (float)M_PI / 180.0f;
	float s = self.speed * (0.5f + 0.5f * [self nextRandom]);
	_px[_count] = ex;
	_py[_count] = ey;
	_vx[_count] = sinf(rad) * s;
	_vy[_count] = -cosf(rad) * s;
	_age[_count] = 0.0f;
	_life[_count] = MAX(0.01f, self.lifetime);
	_count++;
}

- (void)ensureCapacity:(int)cap
{
	if (cap <= _capacity) {
		if (_count > cap) {
			_count = cap; // maxParticles was lowered — drop the tail
		}
		return;
	}
	_px = realloc(_px, sizeof(float) * cap);
	_py = realloc(_py, sizeof(float) * cap);
	_vx = realloc(_vx, sizeof(float) * cap);
	_vy = realloc(_vy, sizeof(float) * cap);
	_age = realloc(_age, sizeof(float) * cap);
	_life = realloc(_life, sizeof(float) * cap);
	_capacity = cap;
}

- (void)draw:(TGSpriteBatch *)batch
{
	[batch setScreenSpace:NO]; // particles and ropes live in world space
	TGSpriteSheet *sh = self.sheet;
	if (_count == 0 || sh == nil || ![sh isReady]) {
		return;
	}
	TGFrame f;
	if (![sh frame:self.frame into:&f] || f.width <= 0.0f) {
		return;
	}
	[batch setBlendMode:self.blendMode];
	float size = self.size;
	float baseWidth = (size > 0.0f) ? size : f.width;
	float aspect = f.height / f.width;
	float r = self.tintR;
	float g = self.tintG;
	float b = self.tintB;
	float startScale = self.startScale;
	float scaleDelta = self.endScale - startScale;
	float startOpacity = self.startOpacity;
	float opacityDelta = self.endOpacity - startOpacity;
	GLint texture = [sh textureId];
	for (int i = 0; i < _count; i++) {
		float t = _age[i] / _life[i];
		float scale = startScale + scaleDelta * t;
		float alpha = startOpacity + opacityDelta * t;
		if (alpha <= 0.0f || scale <= 0.0f) {
			continue;
		}
		float halfW = baseWidth * scale * 0.5f;
		[batch drawFrame:(GLuint)texture frame:f
					  cx:_px[i] cy:_py[i]
				   halfW:halfW halfH:halfW * aspect
					   r:r g:g b:b a:MIN(1.0f, alpha)];
	}
}

@end
