// Twin of android/src/ti/game/engine/Broadphase.java
#import "TGBroadphase.h"
#import "TGSprite.h"
#import <float.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

static const float TGBroadphaseMargin = 4.0f;
static const int TGBroadphaseLargeCells = 64;
static const int TGBroadphaseQueryCells = 256;
static const float TGBroadphaseMinCell = 32.0f;
static const float TGBroadphaseMaxCell = 512.0f;
static const float TGBroadphaseSizeCap = 256.0f; // clamp per sprite when averaging cell size

static inline int TGBroadphaseHash(int cx, int cy)
{
	return (int)((unsigned)cx * 73856093u ^ (unsigned)cy * 19349663u);
}

static inline long long TGBroadphaseKey(int cx, int cy)
{
	return ((long long)cx << 32) | ((long long)cy & 0xffffffffLL);
}

@implementation TGBroadphase {
	NSMutableArray<TGSprite *> *_candidates;
	NSMutableArray<TGSprite *> *_large;
	NSArray<TGSprite *> *_tagged;
	__unsafe_unretained TGSprite **_sprites; // tagged, in order; _tagged keeps them alive
	int _spriteCap;
	float *_bounds;                          // 4 per tagged sprite, inflated
	int _boundsCap;
	int *_bucketHead;
	int _buckets;
	int _bucketMask;
	int *_entrySprite;                       // index into _sprites
	int *_entryNext;
	long long *_entryKey;
	int _entryCount;
	int _entryCap;
	float _invCell;
	float _wrapWidth;
	float _entriesMinX, _entriesMaxX;
	int _stamp;
	float _box[4];
	float _center[2];
}

- (instancetype)init
{
	if (self = [super init]) {
		_candidates = [NSMutableArray array];
		_large = [NSMutableArray array];
		_tagged = @[];
		_entryCap = 64;
		_entrySprite = malloc(sizeof(int) * _entryCap);
		_entryNext = malloc(sizeof(int) * _entryCap);
		_entryKey = malloc(sizeof(long long) * _entryCap);
		_invCell = 1.0f / 64.0f;
	}
	return self;
}

- (void)dealloc
{
	free(_sprites);
	free(_bounds);
	free(_bucketHead);
	free(_entrySprite);
	free(_entryNext);
	free(_entryKey);
}

- (void)rebuild:(NSArray<TGSprite *> *)tagged wrapWidth:(float)wrapWidth
{
	_tagged = tagged;
	_wrapWidth = wrapWidth;
	int n = (int)tagged.count;
	_stamp = 0;
	[_large removeAllObjects];
	_entryCount = 0;
	_entriesMinX = FLT_MAX;
	_entriesMaxX = -FLT_MAX;
	if (_spriteCap < n) {
		_spriteCap = MAX(n, _spriteCap * 2);
		_sprites = realloc(_sprites, sizeof(TGSprite *) * _spriteCap);
	}
	if (_boundsCap < n * 4) {
		_boundsCap = MAX(n * 4, _boundsCap * 2);
		_bounds = realloc(_bounds, sizeof(float) * _boundsCap);
	}
	float sizeSum = 0.0f;
	for (int i = 0; i < n; i++) {
		TGSprite *s = tagged[i];
		_sprites[i] = s;
		s.taggedIndex = i;
		s.broadphaseStamp = 0;
		[self shapeBounds:s out:_box];
		sizeSum += MIN(MAX(_box[2] - _box[0], _box[3] - _box[1]), TGBroadphaseSizeCap);
		[self inflate:s box:_box];
		int o = i * 4;
		_bounds[o] = _box[0];
		_bounds[o + 1] = _box[1];
		_bounds[o + 2] = _box[2];
		_bounds[o + 3] = _box[3];
		_entriesMinX = MIN(_entriesMinX, _box[0]);
		_entriesMaxX = MAX(_entriesMaxX, _box[2]);
	}
	if (n == 0) {
		return;
	}
	float cell = MAX(TGBroadphaseMinCell, MIN(TGBroadphaseMaxCell, (sizeSum / n) * 2.0f));
	_invCell = 1.0f / cell;
	int buckets = 64;
	while (buckets < n * 2 && buckets < (1 << 16)) {
		buckets <<= 1;
	}
	if (_buckets != buckets) {
		_buckets = buckets;
		_bucketHead = realloc(_bucketHead, sizeof(int) * buckets);
	}
	_bucketMask = buckets - 1;
	memset(_bucketHead, 0xff, sizeof(int) * buckets); // every head = -1
	for (int i = 0; i < n; i++) {
		int o = i * 4;
		int cx0 = [self cellOf:_bounds[o]];
		int cy0 = [self cellOf:_bounds[o + 1]];
		int cx1 = [self cellOf:_bounds[o + 2]];
		int cy1 = [self cellOf:_bounds[o + 3]];
		long long spanX = (long long)cx1 - cx0 + 1;
		long long spanY = (long long)cy1 - cy0 + 1;
		if (spanX <= 0 || spanY <= 0 || spanX * spanY > TGBroadphaseLargeCells) {
			[_large addObject:_sprites[i]]; // also catches NaN/infinite positions
			continue;
		}
		for (int cy = cy0; cy <= cy1; cy++) {
			for (int cx = cx0; cx <= cx1; cx++) {
				[self insert:i cx:cx cy:cy];
			}
		}
	}
}

- (NSArray<TGSprite *> *)queryShape:(TGSprite *)s
{
	[self shapeBounds:s out:_box];
	return [self query:s minX:_box[0] minY:_box[1] maxX:_box[2] maxY:_box[3]];
}

- (NSArray<TGSprite *> *)querySwept:(TGSprite *)s
{
	[self shapeBounds:s out:_box];
	float dx = s.frameDeltaX;
	float dy = s.frameDeltaY;
	return [self query:s minX:MIN(_box[0], _box[0] - dx) minY:MIN(_box[1], _box[1] - dy)
				  maxX:MAX(_box[2], _box[2] - dx) maxY:MAX(_box[3], _box[3] - dy)];
}

- (NSArray<TGSprite *> *)query:(TGSprite *)s minX:(float)minX minY:(float)minY maxX:(float)maxX maxY:(float)maxY
{
	[_candidates removeAllObjects];
	_stamp++;
	if (_tagged.count == 0) {
		return _candidates;
	}
	float pad = TGBroadphaseMargin + MAX(fabsf(s.frameDeltaX), fabsf(s.frameDeltaY));
	minX -= pad;
	minY -= pad;
	maxX += pad;
	maxY += pad;
	for (TGSprite *big in _large) {
		[self mark:big];
	}
	[self collectMinX:minX minY:minY maxX:maxX maxY:maxY];
	float w = _wrapWidth;
	if (w > 0.0f && s.wrapWorldX && !s.screenFixed) {
		// The periodic images one world to either side, when any entry
		// lies there at all
		if (maxX + w >= _entriesMinX && minX + w <= _entriesMaxX) {
			[self collectMinX:minX + w minY:minY maxX:maxX + w maxY:maxY];
		}
		if (maxX - w >= _entriesMinX && minX - w <= _entriesMaxX) {
			[self collectMinX:minX - w minY:minY maxX:maxX - w maxY:maxY];
		}
	}
	return _candidates;
}

- (int)stamp
{
	return _stamp;
}

- (void)collectMinX:(float)minX minY:(float)minY maxX:(float)maxX maxY:(float)maxY
{
	int cx0 = [self cellOf:minX];
	int cy0 = [self cellOf:minY];
	int cx1 = [self cellOf:maxX];
	int cy1 = [self cellOf:maxY];
	long long spanX = (long long)cx1 - cx0 + 1;
	long long spanY = (long long)cy1 - cy0 + 1;
	if (spanX <= 0 || spanY <= 0 || spanX * spanY > TGBroadphaseQueryCells) {
		int n = (int)_tagged.count;
		for (int i = 0; i < n; i++) {
			[self mark:_sprites[i]];
		}
		return;
	}
	for (int cy = cy0; cy <= cy1; cy++) {
		for (int cx = cx0; cx <= cx1; cx++) {
			long long key = TGBroadphaseKey(cx, cy);
			for (int e = _bucketHead[TGBroadphaseHash(cx, cy) & _bucketMask]; e >= 0; e = _entryNext[e]) {
				if (_entryKey[e] == key) {
					[self mark:_sprites[_entrySprite[e]]];
				}
			}
		}
	}
}

- (void)mark:(TGSprite *)s
{
	if (s.broadphaseStamp != _stamp) {
		s.broadphaseStamp = _stamp;
		[_candidates addObject:s];
	}
}

- (void)insert:(int)spriteIndex cx:(int)cx cy:(int)cy
{
	if (_entryCount == _entryCap) {
		_entryCap *= 2;
		_entrySprite = realloc(_entrySprite, sizeof(int) * _entryCap);
		_entryNext = realloc(_entryNext, sizeof(int) * _entryCap);
		_entryKey = realloc(_entryKey, sizeof(long long) * _entryCap);
	}
	int b = TGBroadphaseHash(cx, cy) & _bucketMask;
	_entrySprite[_entryCount] = spriteIndex;
	_entryKey[_entryCount] = TGBroadphaseKey(cx, cy);
	_entryNext[_entryCount] = _bucketHead[b];
	_bucketHead[b] = _entryCount++;
}

- (int)cellOf:(float)v
{
	return (int)floorf(v * _invCell);
}

/** World box of the hit shape the narrow tests use: circle or (rotated) rect. */
- (void)shapeBounds:(TGSprite *)s out:(float *)out
{
	if (s.circleHitbox) {
		[s hitCenter:_center];
		float r = [s hitRadius];
		out[0] = _center[0] - r;
		out[1] = _center[1] - r;
		out[2] = _center[0] + r;
		out[3] = _center[1] + r;
	} else {
		[s computeAABB:out];
	}
}

- (void)inflate:(TGSprite *)s box:(float *)b
{
	float px = TGBroadphaseMargin + fabsf(s.frameDeltaX);
	float py = TGBroadphaseMargin + fabsf(s.frameDeltaY);
	b[0] -= px;
	b[1] -= py;
	b[2] += px;
	b[3] += py;
}

@end
