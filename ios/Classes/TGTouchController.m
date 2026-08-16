#import "TGTouchController.h"
#import "TGRope.h"
#import "TGScene.h"
#import "TGSprite.h"
#import <TitaniumKit/TitaniumKit.h>
#import <math.h>

static const NSTimeInterval kDragEventInterval = 0.1; // ~10 Hz 'drag' events
static const NSTimeInterval kTapTimeout = 0.3;

/** One finger's interaction with one sprite (Gesture on Android). */
@interface TGGesture : NSObject
@property (nonatomic, strong) UITouch *touch;
@property (nonatomic, strong) TGSprite *sprite;
@property (nonatomic, assign) float downX;
@property (nonatomic, assign) float downY;
@property (nonatomic, assign) NSTimeInterval downTime;
@property (nonatomic, assign) float grabOffsetX;
@property (nonatomic, assign) float grabOffsetY;
@property (nonatomic, assign) BOOL dragging;
@property (nonatomic, assign) NSTimeInterval lastDragEventTime;
@end

@implementation TGGesture
@end

@implementation TGTouchController {
	TGScene *_scene;
	__weak TiProxy *_viewProxy; // game view proxy — receives view-level press/tap/release
	CGFloat _contentScale;
	float _touchSlop;

	NSMutableArray<UITouch *> *_activeTouches; // ordered by begin
	NSMutableArray<TGGesture *> *_gestures;    // one per sprite-holding touch

	// View-level (first finger) state for the view tap
	float _downX, _downY;
	NSTimeInterval _downTime;

	// Two-finger pinch/rotate state: set while a modifier finger is down
	TGSprite *_modifierTarget;
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
		_gestures = [NSMutableArray array];
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

// --- Gesture bookkeeping ------------------------------------------------

- (TGGesture *)gestureForTouch:(UITouch *)touch
{
	for (TGGesture *g in _gestures) {
		if (g.touch == touch) {
			return g;
		}
	}
	return nil;
}

- (TGGesture *)gestureForSprite:(TGSprite *)sprite
{
	for (TGGesture *g in _gestures) {
		if (g.sprite == sprite) {
			return g;
		}
	}
	return nil;
}

/** The sprite held by the earliest still-active finger, if any. */
- (TGSprite *)heldSprite
{
	return _gestures.firstObject.sprite;
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
		CGPoint p = [self worldPoint:touch inView:view];
		float wx = (float)p.x;
		float wy = (float)p.y;

		if (_activeTouches.count == 1) {
			// ACTION_DOWN — world space: hit-testing and drags track the camera
			[self resetAll];
			_downX = wx;
			_downY = wy;
			_downTime = touch.timestamp;
			[self pointerDown:touch x:wx y:wy];
			[self fireOnView:@"press" x:wx y:wy];
		} else {
			// ACTION_POINTER_DOWN
			BOOL claimed = [self pointerDown:touch x:wx y:wy];
			if (!claimed && _activeTouches.count == 2) {
				// second finger on empty space (or the held sprite
				// itself) modifies the held sprite: pinch / rotate
				_modifierTarget = [self heldSprite];
				if (_modifierTarget != nil && _modifierTarget.rotatable) {
					_rotating = YES;
					_lastAngle = [self angleBetweenFirstTwoTouches:view];
				}
				_lastPinchDistance = [self distanceBetweenFirstTwoTouches:view];
			}
		}
	}
}

/** Hit-tests a new finger and claims the sprite (a new TGGesture) if no
 *  other finger holds it yet. Returns whether a sprite was claimed. */
- (BOOL)pointerDown:(UITouch *)touch x:(float)wx y:(float)wy
{
	TGSprite *hit = [_scene hitTestX:wx y:wy];
	if (hit == nil || [self gestureForSprite:hit] != nil) {
		return NO;
	}
	TGGesture *g = [TGGesture new];
	g.touch = touch;
	g.sprite = hit;
	g.downX = wx;
	g.downY = wy;
	g.downTime = touch.timestamp;
	g.grabOffsetX = wx - hit.x;
	g.grabOffsetY = wy - hit.y;
	[_gestures addObject:g];
	NSMutableDictionary *data = [self positionData:hit];
	data[@"touchX"] = @(wx);
	data[@"touchY"] = @(wy);
	fireOnSprite(hit, @"press", data);
	return YES;
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	TGSprite *target = _modifierTarget;

	if (_activeTouches.count >= 2 && target != nil) {
		if (_rotating) {
			float angle = [self angleBetweenFirstTwoTouches:view];
			target.rotation += angle - _lastAngle;
			_lastAngle = angle;
			fireOnSprite(target, @"rotate", @{ @"rotation": @(target.rotation) });
		}
		// Pinch-to-scale (the ScaleGestureDetector equivalent): incremental
		// factor from the change in finger distance
		if (target.pinchable) {
			float dist = [self distanceBetweenFirstTwoTouches:view];
			if (_lastPinchDistance > 0.0f && dist > 0.0f) {
				float factor = dist / _lastPinchDistance;
				target.scaleX *= factor;
				target.scaleY *= factor;
				fireOnSprite(target, @"pinch", @{
					@"scaleX": @(target.scaleX),
					@"scaleY": @(target.scaleY)
				});
			}
			_lastPinchDistance = dist;
		}
	}

	for (UITouch *touch in touches) {
		TGGesture *g = [self gestureForTouch:touch];
		if (g == nil || !g.sprite.draggable) {
			continue;
		}
		if (g.sprite == target) {
			continue; // two-finger gesture owns this sprite
		}
		CGPoint p = [self worldPoint:touch inView:view];
		[self drag:g toX:(float)p.x y:(float)p.y time:touch.timestamp];
	}
}

- (void)drag:(TGGesture *)g toX:(float)tx y:(float)ty time:(NSTimeInterval)now
{
	TGSprite *s = g.sprite;
	if (!g.dragging && distanceBetween(tx, ty, g.downX, g.downY) > _touchSlop) {
		g.dragging = YES;
		s.dragged = YES;
		[s clearPositionTweens];
		fireOnSprite(s, @"dragstart", [self positionData:s]);
	}
	if (!g.dragging) {
		return;
	}
	float nx = tx - g.grabOffsetX;
	float ny = ty - g.grabOffsetY;
	// Clamp against any rope tethering this sprite here at the
	// source — the rope's own per-frame clamp would only pull it
	// back a frame later, which renders as a visible jump past the
	// rope end. The anchor is the fixed x/y, or the sprite at the
	// other end when a finger owns that one too (multi-touch: both
	// ends held, neither yields — see TGRope update). A free other
	// end is skipped: the rope tows it behind the drag instead.
	for (TGRope *r in [_scene ropesSnapshot]) {
		if (r.maxLength <= 0.0f) {
			continue;
		}
		float ax, ay;
		if (r.tail == s && r.head == nil) {
			ax = r.x;
			ay = r.y;
		} else if (r.tail == s && r.head != nil && r.head.dragged) {
			ax = r.head.x;
			ay = r.head.y;
		} else if (r.head == s && r.tail != nil && r.tail.dragged) {
			ax = r.tail.x;
			ay = r.tail.y;
		} else {
			continue;
		}
		float dx = nx - ax;
		float dy = ny - ay;
		float d = sqrtf(dx * dx + dy * dy);
		if (d > r.maxLength && d > 1e-5f) {
			nx = ax + dx / d * r.maxLength;
			ny = ay + dy / d * r.maxLength;
		}
	}
	s.x = nx;
	s.y = ny;
	// The finger owns the sprite: keep physics from
	// accumulating velocity underneath the drag.
	s.velocityX = 0.0f;
	s.velocityY = 0.0f;
	if (now - g.lastDragEventTime >= kDragEventInterval) {
		g.lastDragEventTime = now;
		fireOnSprite(s, @"drag", [self positionData:s]);
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	for (UITouch *touch in touches) {
		CGPoint p = [self worldPoint:touch inView:view];
		float upX = (float)p.x;
		float upY = (float)p.y;
		[_activeTouches removeObjectIdenticalTo:touch];

		if (_activeTouches.count > 0) {
			// ACTION_POINTER_UP
			[self finishGestureForTouch:touch x:upX y:upY time:touch.timestamp allowTap:YES];
			if (_activeTouches.count < 2) {
				_rotating = NO;
				_modifierTarget = nil;
				_lastPinchDistance = 0.0f;
			}
			continue;
		}

		// ACTION_UP — last finger left the screen
		if (touch.timestamp - _downTime < kTapTimeout
				&& distanceBetween(upX, upY, _downX, _downY) <= _touchSlop) {
			[self fireOnView:@"tap" x:upX y:upY];
		}
		[self fireOnView:@"release" x:upX y:upY];
		[self finishGestureForTouch:touch x:upX y:upY time:touch.timestamp allowTap:YES];
		[self resetAll];
	}
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches inView:(UIView *)view
{
	for (UITouch *touch in touches) {
		[_activeTouches removeObjectIdenticalTo:touch];
	}
	if (_activeTouches.count == 0) {
		// ACTION_CANCEL
		UITouch *touch = touches.anyObject;
		CGPoint p = [self worldPoint:touch inView:view];
		[self fireOnView:@"release" x:(float)p.x y:(float)p.y];
	}
	for (UITouch *touch in touches) {
		[self finishGestureForTouch:touch x:0 y:0 time:0 allowTap:NO];
	}
	if (_activeTouches.count == 0) {
		[self resetAll];
	} else if (_activeTouches.count < 2) {
		_rotating = NO;
		_modifierTarget = nil;
		_lastPinchDistance = 0.0f;
	}
}

- (void)finishGestureForTouch:(UITouch *)touch
							x:(float)upX
							y:(float)upY
						 time:(NSTimeInterval)time
					 allowTap:(BOOL)allowTap
{
	TGGesture *g = [self gestureForTouch:touch];
	if (g == nil) {
		return;
	}
	[_gestures removeObjectIdenticalTo:g];
	TGSprite *s = g.sprite;
	s.dragged = NO;
	if (g.dragging) {
		fireOnSprite(s, @"dragend", [self positionData:s]);
	} else if (allowTap && time - g.downTime < kTapTimeout
			&& distanceBetween(upX, upY, g.downX, g.downY) <= _touchSlop) {
		NSMutableDictionary *data = [self positionData:s];
		data[@"touchX"] = @(upX);
		data[@"touchY"] = @(upY);
		fireOnSprite(s, @"tap", data);
	}
	fireOnSprite(s, @"release", [self positionData:s]);
}

- (void)resetAll
{
	for (TGGesture *g in _gestures) {
		g.sprite.dragged = NO;
	}
	[_gestures removeAllObjects];
	_modifierTarget = nil;
	_rotating = NO;
	_lastPinchDistance = 0.0f;
}

@end
