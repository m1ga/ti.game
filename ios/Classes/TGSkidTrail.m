#import "TGSkidTrail.h"
#import "TGSpriteBatch.h"

static const int kMaxSegments = 1500;
static const int kFloats = 6; // x0, y0, x1, y1, halfWidth, alpha
static const float kFadePerSecond = 0.03f;
static const float kMinAlpha = 0.02f;

@implementation TGSkidTrail {
	float _segments[kMaxSegments * kFloats];
	int _head;  // next write slot
	int _count;
}

- (void)addFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1
	   halfWidth:(float)halfWidth alpha:(float)alpha
{
	int i = _head * kFloats;
	_segments[i] = x0;
	_segments[i + 1] = y0;
	_segments[i + 2] = x1;
	_segments[i + 3] = y1;
	_segments[i + 4] = halfWidth;
	_segments[i + 5] = alpha;
	_head = (_head + 1) % kMaxSegments;
	if (_count < kMaxSegments) {
		_count++;
	}
}

- (BOOL)isEmpty
{
	return _count == 0;
}

- (void)update:(float)dt
{
	float fade = kFadePerSecond * dt;
	int start = (_head - _count + kMaxSegments) % kMaxSegments;
	for (int k = 0; k < _count; k++) {
		_segments[((start + k) % kMaxSegments) * kFloats + 5] -= fade;
	}
	while (_count > 0) {
		int i = ((_head - _count + kMaxSegments) % kMaxSegments) * kFloats;
		if (_segments[i + 5] > kMinAlpha) {
			break;
		}
		_count--;
	}
}

- (void)draw:(TGSpriteBatch *)batch whiteTexture:(GLuint)whiteTexture
{
	int start = (_head - _count + kMaxSegments) % kMaxSegments;
	for (int k = 0; k < _count; k++) {
		int i = ((start + k) % kMaxSegments) * kFloats;
		[batch drawLine:whiteTexture
				  fromX:_segments[i] y:_segments[i + 1]
					toX:_segments[i + 2] y:_segments[i + 3]
		  halfThickness:_segments[i + 4]
					  r:0.07f g:0.07f b:0.08f a:_segments[i + 5]];
	}
}

- (void)clear
{
	_head = 0;
	_count = 0;
}

@end
