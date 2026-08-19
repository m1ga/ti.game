#import "TGPath.h"
#import <math.h>
#import <stdlib.h>
#import <string.h>

// Sample points per rounded corner (excluding the entry/exit points)
static const int kSmoothSteps = 6;

@implementation TGPath {
	float *_xs;
	float *_ys;
	// _cumulative[i] = path length from the start to point i; for loops
	// the closing segment back to point 0 exists only in totalLength.
	float *_cumulative;
	int _count;

	// Progress cursor, render thread only
	float _distance;
	int _segment;
}

- (instancetype)initWithPointsX:(const float *)xs y:(const float *)ys count:(int)count
						   loop:(BOOL)loop rotate:(BOOL)rotate speed:(float)speed
{
	if (self = [super init]) {
		_count = count;
		_xs = malloc(sizeof(float) * count);
		_ys = malloc(sizeof(float) * count);
		_cumulative = calloc(count, sizeof(float));
		memcpy(_xs, xs, sizeof(float) * count);
		memcpy(_ys, ys, sizeof(float) * count);
		_loop = loop;
		_rotate = rotate;
		_speed = speed;
		float total = 0.0f;
		for (int i = 1; i < count; i++) {
			total += hypotf(_xs[i] - _xs[i - 1], _ys[i] - _ys[i - 1]);
			_cumulative[i] = total;
		}
		if (loop) {
			total += hypotf(_xs[0] - _xs[count - 1], _ys[0] - _ys[count - 1]);
		}
		_totalLength = total;
	}
	return self;
}

- (void)dealloc
{
	free(_xs);
	free(_ys);
	free(_cumulative);
}

+ (instancetype)buildWithPointsX:(const float *)rawX y:(const float *)rawY
						   count:(int)rawCount smoothing:(float)smoothing
							loop:(BOOL)loop rotate:(BOOL)rotate speed:(float)speed
{
	// Drop consecutive duplicates — zero-length segments break the
	// cursor walk and the heading math.
	int n = 0;
	float *px = malloc(sizeof(float) * rawCount);
	float *py = malloc(sizeof(float) * rawCount);
	for (int i = 0; i < rawCount; i++) {
		if (n > 0 && rawX[i] == px[n - 1] && rawY[i] == py[n - 1]) {
			continue;
		}
		px[n] = rawX[i];
		py[n] = rawY[i];
		n++;
	}
	// A loop closes itself; an explicitly repeated first point would
	// add a zero-length closing segment.
	if (loop && n > 1 && px[0] == px[n - 1] && py[0] == py[n - 1]) {
		n--;
	}
	if (n < 2) {
		free(px);
		free(py);
		return nil;
	}
	if (smoothing <= 0.0f || n < 3) {
		TGPath *path = [[TGPath alloc] initWithPointsX:px y:py count:n
												  loop:loop rotate:rotate speed:speed];
		free(px);
		free(py);
		return path;
	}

	// Corner rounding: cut into both adjacent segments by the radius
	// and bridge the gap with a quadratic Bezier through the corner.
	int corners = loop ? n : n - 2;
	int capacity = n + corners * (kSmoothSteps + 1);
	float *sx = malloc(sizeof(float) * capacity);
	float *sy = malloc(sizeof(float) * capacity);
	int count = 0;
	if (!loop) {
		sx[count] = px[0];
		sy[count] = py[0];
		count++;
	}
	int first = loop ? 0 : 1;
	int last = loop ? n - 1 : n - 2;
	for (int i = first; i <= last; i++) {
		float cx = px[i];
		float cy = py[i];
		int prev = (i + n - 1) % n;
		int next = (i + 1) % n;
		float d1 = hypotf(px[prev] - cx, py[prev] - cy);
		float d2 = hypotf(px[next] - cx, py[next] - cy);
		float d = MIN(smoothing, MIN(d1 / 2.0f, d2 / 2.0f));
		float ax = cx + (px[prev] - cx) / d1 * d; // entry point
		float ay = cy + (py[prev] - cy) / d1 * d;
		float bx = cx + (px[next] - cx) / d2 * d; // exit point
		float by = cy + (py[next] - cy) / d2 * d;
		for (int k = 0; k <= kSmoothSteps; k++) {
			float t = (float)k / kSmoothSteps;
			float u = 1.0f - t;
			sx[count] = u * u * ax + 2.0f * u * t * cx + t * t * bx;
			sy[count] = u * u * ay + 2.0f * u * t * cy + t * t * by;
			count++;
		}
	}
	if (!loop) {
		sx[count] = px[n - 1];
		sy[count] = py[n - 1];
		count++;
	}
	TGPath *path = [[TGPath alloc] initWithPointsX:sx y:sy count:count
											  loop:loop rotate:rotate speed:speed];
	free(px);
	free(py);
	free(sx);
	free(sy);
	return path;
}

- (BOOL)advance:(float)dt out:(float *)out
{
	BOOL finished = NO;
	_distance += _speed * dt;
	if (_distance >= _totalLength) {
		if (_loop && _totalLength > 0.0f) {
			_distance = fmodf(_distance, _totalLength);
			_segment = 0;
		} else {
			_distance = _totalLength;
			finished = YES;
		}
	}
	int segCount = _loop ? _count : _count - 1;
	while (_segment < segCount - 1 && _distance > [self segmentEnd:_segment]) {
		_segment++;
	}
	float segStart = _cumulative[_segment];
	float length = [self segmentEnd:_segment] - segStart;
	float t = (length > 0.0f) ? MIN(1.0f, (_distance - segStart) / length) : 1.0f;
	float x0 = _xs[_segment];
	float y0 = _ys[_segment];
	float x1 = _xs[(_segment + 1) % _count];
	float y1 = _ys[(_segment + 1) % _count];
	out[0] = x0 + (x1 - x0) * t;
	out[1] = y0 + (y1 - y0) * t;
	out[2] = atan2f(x1 - x0, -(y1 - y0)) * 180.0f / (float)M_PI;
	return finished;
}

- (float)segmentEnd:(int)i
{
	return (i + 1 < _count) ? _cumulative[i + 1] : _totalLength;
}

@end
