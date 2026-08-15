#import "TGRope.h"
#import "TGSprite.h"
#import "TGSpriteBatch.h"
#import "TGSpriteSheet.h"
#import <math.h>
#import <stdlib.h>

static const int kMaxSegments = 200;

@implementation TGRope {
	// Verlet points — render thread only
	float *_px, *_py, *_prevX, *_prevY;
	int _pointCount;
}

- (instancetype)init
{
	if (self = [super init]) {
		_segments = 10;
		_segmentLength = 30.0f;
		_thickness = 10.0f;
		_gravity = 1500.0f;
		_damping = 0.98f;
		_iterations = 3;
		_visible = YES;
	}
	return self;
}

- (void)dealloc
{
	free(_px);
	free(_py);
	free(_prevX);
	free(_prevY);
}

- (void)update:(float)dt
{
	int segs = MAX(1, MIN(kMaxSegments, self.segments));
	int count = segs + 1;
	TGSprite *h = self.head;
	float headX = (h != nil) ? h.x : self.x;
	float headY = (h != nil) ? h.y : self.y;
	if (count != _pointCount) {
		[self rebuild:count headX:headX headY:headY];
	}

	TGSprite *t = self.tail;
	BOOL tailPinned = (t != nil);
	float damp = self.damping;
	float fall = self.gravity * dt * dt;
	int lastFree = tailPinned ? count - 2 : count - 1;
	for (int i = 1; i <= lastFree; i++) {
		float vx = (_px[i] - _prevX[i]) * damp;
		float vy = (_py[i] - _prevY[i]) * damp;
		_prevX[i] = _px[i];
		_prevY[i] = _py[i];
		_px[i] += vx;
		_py[i] += vy + fall;
	}
	_px[0] = headX;
	_py[0] = headY;
	_prevX[0] = headX;
	_prevY[0] = headY;
	if (tailPinned) {
		_px[count - 1] = t.x;
		_py[count - 1] = t.y;
		_prevX[count - 1] = t.x;
		_prevY[count - 1] = t.y;
	}

	float length = MAX(1.0f, self.segmentLength);
	int passes = MAX(1, self.iterations);
	for (int k = 0; k < passes; k++) {
		for (int i = 0; i < segs; i++) {
			float dx = _px[i + 1] - _px[i];
			float dy = _py[i + 1] - _py[i];
			float d = sqrtf(dx * dx + dy * dy);
			if (d < 1e-5f) {
				d = 1e-5f;
			}
			float diff = (d - length) / d;
			BOOL pinA = (i == 0);
			BOOL pinB = tailPinned && (i + 1 == count - 1);
			if (pinA && pinB) {
				continue;
			}
			if (pinA) {
				_px[i + 1] -= dx * diff;
				_py[i + 1] -= dy * diff;
			} else if (pinB) {
				_px[i] += dx * diff;
				_py[i] += dy * diff;
			} else {
				float half = diff * 0.5f;
				_px[i] += dx * half;
				_py[i] += dy * half;
				_px[i + 1] -= dx * half;
				_py[i + 1] -= dy * half;
			}
		}
	}
	self.endX = _px[count - 1];
	self.endY = _py[count - 1];
}

/** New point chain, hanging straight down from the head. */
- (void)rebuild:(int)count headX:(float)headX headY:(float)headY
{
	_px = realloc(_px, sizeof(float) * count);
	_py = realloc(_py, sizeof(float) * count);
	_prevX = realloc(_prevX, sizeof(float) * count);
	_prevY = realloc(_prevY, sizeof(float) * count);
	float length = MAX(1.0f, self.segmentLength);
	for (int i = 0; i < count; i++) {
		_px[i] = headX;
		_py[i] = headY + i * length;
		_prevX[i] = _px[i];
		_prevY[i] = _py[i];
	}
	_pointCount = count;
}

- (void)draw:(TGSpriteBatch *)batch
{
	TGSpriteSheet *sh = self.sheet;
	if (!self.visible || _pointCount < 2 || sh == nil || ![sh isReady]) {
		return;
	}
	TGFrame f;
	if (![sh frame:self.frame into:&f]) {
		return;
	}
	float half = self.thickness * 0.5f;
	float overlap = half * 0.6f; // extend ends so bent joints don't gap
	GLint texture = [sh textureId];
	for (int i = 0; i < _pointCount - 1; i++) {
		float dx = _px[i + 1] - _px[i];
		float dy = _py[i + 1] - _py[i];
		float d = sqrtf(dx * dx + dy * dy);
		if (d < 1e-5f) {
			continue;
		}
		float ux = dx / d * overlap;
		float uy = dy / d * overlap;
		[batch drawSegment:(GLuint)texture frame:f
					 fromX:_px[i] - ux y:_py[i] - uy
					   toX:_px[i + 1] + ux y:_py[i + 1] + uy
				 halfWidth:half alpha:1.0f];
	}
}

@end
