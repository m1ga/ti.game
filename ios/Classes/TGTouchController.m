#import "TGTouchController.h"
#import "TGRope.h"
#import "TGScene.h"
#import "TGSprite.h"
#import <TitaniumKit/TitaniumKit.h>
#import <math.h>

static const NSTimeInterval kDragEventInterval = 0.1; // ~10 Hz 'drag' events
static const NSTimeInterval kTapTimeout = 0.3;

@implementation TGTouchController {
	TGScene *_scene;
	__weak TiProxy *_viewProxy; // game view proxy — receives view-level press/tap/release
	CGFloat _contentScale;
	float _touchSlop;

	NSMutableArray<UITouch *> *_activeTouches; // ordered by begin
	UITouch *_primaryTouch;
	TGSprite *_activeSprite;
	float _grabOffsetX, _grabOffsetY;
	float _downX, _downY;
	NSTimeInterval _downTime;
	BOOL _dragging;
	NSTimeInterval _lastDragEventTime;

	// Two-finger gesture state
	BOOL _rotating;
	float _lastAngle;
	float _lastPinchDistance;
}

- (instancetype)initWithScene:(TGScene *)scene
					viewProxy:(TiProxy *)viewProxy
				 contentScale:(CGFloat)contentScale
{
	if (self = [super init]) {
		_scene = scene;
		_viewProxy = viewProxy;
		_contentScale = contentScale;
		_touchSlop = 8.0f * (float)contentScale; // ~Android's scaled touch slop
		_activeTouches = [NSMutableArray array];
	}
	return self;
}

// --- Geometry helpers ---------------------------------------------------

/** Touch in world space: surface pixels mapped through camera + zoom. */
- (CGPoint)worldPoint:(UITouch *)touch inView:(UIView *)view
{
	CGPoint p = [touch locationInView:view];
	return CGPointMake([_scene screenToWorldX:(float)(p.x * _contentScale)],
					   [_scene screenToWorldY:(float)(p.y * _contentScale)]);
}

static float distanceBetween(float x0, float y0, float x1, float y1)
{
	float dx = x1 - x0;
	float dy = y1 - y0;
	return sqrtf(dx * dx + dy * dy);
}

- (float)angleBetweenFirstTwoTouches:(UIView *)view
{
	CGPoint a = [_activeTouches[0] locationInView:view];
	CGPoint b = [_activeTouches[1] locationInView:view];
	return (float)(atan2(b.y - a.y, b.x - a.x) * 180.0 / M_PI);
}

- (float)distanceBetweenFirstTwoTouches:(UIView *)view
{
	CGPoint a = [_activeTouches[0] locationInView:view];
	CGPoint b = [_activeTouches[1] locationInView:view];
	return distanceBetween((float)a.x, (float)a.y, (float)b.x, (float)b.y);
}

// --- Event firing -------------------------------------------------------

- (NSMutableDictionary *)positionData:(TGSprite *)s
{
	return [NSMutableDictionary dictionaryWithDictionary:@{
		@"x": @(s.x),
		@"y": @(s.y)
	}];
}

/** View-level input: fires on the game view for every touch, whether or
 *  not it hit a sprite — e.g. tap-anywhere controls. */
- (void)fireOnView:(NSString *)event x:(float)x y:(float)y
{
	TiProxy *proxy = _viewProxy;
	if (proxy != nil && [proxy _hasListeners:event]) {
		[proxy fireEvent:event withObject:@{ @"x": @(x), @"y": @(y) }];
	}
}

static void fireOnSprite(TGSprite *sprite, NSString *event, NSDictionary *data)
{
	TiProxy *proxy = sprite.proxy;
	if (proxy != nil && [proxy _hasListeners:event]) {
		[proxy fireEvent:event withObject:data];
	}
}

// --- Touch handling -----------------------------------------------------

- (void)touchesBegan:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	for (UITouch *touch in touches) {
		[_activeTouches addObject:touch];

		if (_activeTouches.count == 1) {
			// ACTION_DOWN — world space: hit-testing and drags track the camera
			CGPoint p = [self worldPoint:touch inView:view];
			_downX = (float)p.x;
			_downY = (float)p.y;
			_downTime = touch.timestamp;
			_primaryTouch = touch;
			_dragging = NO;
			_rotating = NO;
			_lastPinchDistance = 0.0f;
			_activeSprite = [_scene hitTestX:_downX y:_downY];
			if (_activeSprite != nil) {
				_grabOffsetX = _downX - _activeSprite.x;
				_grabOffsetY = _downY - _activeSprite.y;
				NSMutableDictionary *data = [self positionData:_activeSprite];
				data[@"touchX"] = @(_downX);
				data[@"touchY"] = @(_downY);
				fireOnSprite(_activeSprite, @"press", data);
			}
			[self fireOnView:@"press" x:_downX y:_downY];
		} else if (_activeTouches.count == 2) {
			// ACTION_POINTER_DOWN
			if (_activeSprite != nil && _activeSprite.rotatable) {
				_rotating = YES;
				_lastAngle = [self angleBetweenFirstTwoTouches:view];
			}
			_lastPinchDistance = [self distanceBetweenFirstTwoTouches:view];
		}
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	TGSprite *s = _activeSprite;

	if (_activeTouches.count >= 2 && s != nil) {
		if (_rotating) {
			float angle = [self angleBetweenFirstTwoTouches:view];
			s.rotation += angle - _lastAngle;
			_lastAngle = angle;
			fireOnSprite(s, @"rotate", @{ @"rotation": @(s.rotation) });
		}
		// Pinch-to-scale (the ScaleGestureDetector equivalent): incremental
		// factor from the change in finger distance
		if (s.pinchable) {
			float dist = [self distanceBetweenFirstTwoTouches:view];
			if (_lastPinchDistance > 0.0f && dist > 0.0f) {
				float factor = dist / _lastPinchDistance;
				s.scaleX *= factor;
				s.scaleY *= factor;
				fireOnSprite(s, @"pinch", @{
					@"scaleX": @(s.scaleX),
					@"scaleY": @(s.scaleY)
				});
			}
			_lastPinchDistance = dist;
		}
	}

	// Single-finger drag
	if (s != nil && s.draggable && _activeTouches.count == 1
			&& _primaryTouch != nil && [_activeTouches containsObject:_primaryTouch]) {
		CGPoint p = [self worldPoint:_primaryTouch inView:view];
		float tx = (float)p.x;
		float ty = (float)p.y;

		if (!_dragging && distanceBetween(tx, ty, _downX, _downY) > _touchSlop) {
			_dragging = YES;
			s.dragged = YES;
			[s clearPositionTweens];
			fireOnSprite(s, @"dragstart", [self positionData:s]);
		}
		if (_dragging) {
			float nx = tx - _grabOffsetX;
			float ny = ty - _grabOffsetY;
			// Clamp against any fixed-anchor rope tethering this sprite
			// here at the source — the rope's own per-frame clamp would
			// only pull it back a frame later, which renders as a
			// visible jump past the rope end. Sprite-headed ropes are
			// skipped: those tow the head sprite behind the drag instead.
			for (TGRope *r in [_scene ropesSnapshot]) {
				if (r.tail == s && r.maxLength > 0.0f && r.head == nil) {
					float ax = r.x;
					float ay = r.y;
					float dx = nx - ax;
					float dy = ny - ay;
					float d = sqrtf(dx * dx + dy * dy);
					if (d > r.maxLength && d > 1e-5f) {
						nx = ax + dx / d * r.maxLength;
						ny = ay + dy / d * r.maxLength;
					}
				}
			}
			s.x = nx;
			s.y = ny;
			// The finger owns the sprite: keep physics from
			// accumulating velocity underneath the drag.
			s.velocityX = 0.0f;
			s.velocityY = 0.0f;
			NSTimeInterval now = _primaryTouch.timestamp;
			if (now - _lastDragEventTime >= kDragEventInterval) {
				_lastDragEventTime = now;
				fireOnSprite(s, @"drag", [self positionData:s]);
			}
		}
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	for (UITouch *touch in touches) {
		NSUInteger countBefore = _activeTouches.count;
		[_activeTouches removeObjectIdenticalTo:touch];

		if (_activeTouches.count > 0) {
			// ACTION_POINTER_UP
			if (countBefore <= 2) {
				_rotating = NO;
			}
			if (_activeTouches.count < 2) {
				_lastPinchDistance = 0.0f;
			}
			continue;
		}

		// ACTION_UP — last finger left the screen
		CGPoint p = [self worldPoint:touch inView:view];
		float upX = (float)p.x;
		float upY = (float)p.y;
		BOOL isTap = !_rotating
			&& touch.timestamp - _downTime < kTapTimeout
			&& distanceBetween(upX, upY, _downX, _downY) <= _touchSlop;
		if (isTap) {
			[self fireOnView:@"tap" x:upX y:upY];
		}
		[self fireOnView:@"release" x:upX y:upY];
		TGSprite *s = _activeSprite;
		if (s != nil) {
			if (_dragging) {
				fireOnSprite(s, @"dragend", [self positionData:s]);
			} else if (isTap) {
				NSMutableDictionary *data = [self positionData:s];
				data[@"touchX"] = @(upX);
				data[@"touchY"] = @(upY);
				fireOnSprite(s, @"tap", data);
			}
			fireOnSprite(s, @"release", [self positionData:s]);
		}
		[self resetGesture];
	}
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	for (UITouch *touch in touches) {
		[_activeTouches removeObjectIdenticalTo:touch];
	}
	if (_activeTouches.count > 0) {
		return;
	}
	// ACTION_CANCEL
	UITouch *touch = touches.anyObject;
	CGPoint p = [self worldPoint:touch inView:view];
	[self fireOnView:@"release" x:(float)p.x y:(float)p.y];
	TGSprite *s = _activeSprite;
	if (s != nil) {
		if (_dragging) {
			fireOnSprite(s, @"dragend", [self positionData:s]);
		}
		fireOnSprite(s, @"release", [self positionData:s]);
	}
	[self resetGesture];
}

- (void)resetGesture
{
	_activeSprite.dragged = NO;
	_activeSprite = nil;
	_primaryTouch = nil;
	_dragging = NO;
	_rotating = NO;
	_lastPinchDistance = 0.0f;
}

@end
