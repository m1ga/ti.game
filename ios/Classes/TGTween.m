#import "TGTween.h"
#import "TGEasing.h"
#import "TGSprite.h"

@implementation TGTween {
	float _fromX, _fromY, _fromScaleX, _fromScaleY, _fromRotation, _fromOpacity, _fromGlowOpacity;
	float _elapsed;
	BOOL _started;
}

- (instancetype)init
{
	if (self = [super init]) {
		_duration = 0.3f;
		_easing = TGEasingLinear;
	}
	return self;
}

- (void)captureStartValues:(TGSprite *)s
{
	_fromX = s.x;
	_fromY = s.y;
	_fromScaleX = s.scaleX;
	_fromScaleY = s.scaleY;
	_fromRotation = s.rotation;
	_fromOpacity = s.opacity;
	_fromGlowOpacity = s.glowOpacity;
}

- (BOOL)update:(TGSprite *)s delta:(float)dt
{
	_elapsed += dt;
	if (_elapsed < _delay) {
		return NO;
	}
	if (!_started) {
		// Re-capture at actual start so delayed tweens pick up current values
		[self captureStartValues:s];
		_started = YES;
	}
	float t = (_duration > 0.0f) ? MIN(1.0f, (_elapsed - _delay) / _duration) : 1.0f;
	float e = TGEasingApply(_easing, t);

	if (_toX != nil) {
		s.x = _fromX + (_toX.floatValue - _fromX) * e;
	}
	if (_toY != nil) {
		s.y = _fromY + (_toY.floatValue - _fromY) * e;
	}
	if (_toScaleX != nil) {
		s.scaleX = _fromScaleX + (_toScaleX.floatValue - _fromScaleX) * e;
	}
	if (_toScaleY != nil) {
		s.scaleY = _fromScaleY + (_toScaleY.floatValue - _fromScaleY) * e;
	}
	if (_toRotation != nil) {
		s.rotation = _fromRotation + (_toRotation.floatValue - _fromRotation) * e;
	}
	if (_toOpacity != nil) {
		s.opacity = _fromOpacity + (_toOpacity.floatValue - _fromOpacity) * e;
	}
	if (_toGlowOpacity != nil) {
		s.glowOpacity = _fromGlowOpacity + (_toGlowOpacity.floatValue - _fromGlowOpacity) * e;
	}
	return t >= 1.0f;
}

@end
