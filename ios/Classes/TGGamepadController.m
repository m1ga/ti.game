//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/GamepadController.java)
//
#import "TGGamepadController.h"
#import <GameController/GameController.h>
#import <TitaniumKit/TitaniumKit.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static const NSTimeInterval TGAxisEventInterval = 0.05; // ~20 Hz 'stick'/'trigger' events
static const float TGDefaultStickPress = 0.5f;   // left stick → digital direction
static const float TGDefaultStickRelease = 0.4f; // hysteresis
static const float TGTriggerPress = 0.5f;
static const float TGTriggerRelease = 0.35f;
static const float TGAxisEpsilon = 0.01f;

static NSString *const TGDirectionNames[4] = { @"up", @"down", @"left", @"right" };

static inline int TGSign(float v)
{
	return (v > 0.0f) ? 1 : (v < 0.0f) ? -1 : 0;
}

// Stable integer ids per GCController (like Android's device ids) so JS can
// tell pads apart across connect/disconnect.
// Reached from the main thread (input) and the JS thread (`gamepads`),
// hence the lock.
static NSMapTable<GCController *, NSNumber *> *TGGamepadIds;
static NSInteger TGNextGamepadId = 1;

static NSInteger TGGamepadIdFor(GCController *controller)
{
	static NSObject *lock;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		lock = [[NSObject alloc] init];
		TGGamepadIds = [NSMapTable weakToStrongObjectsMapTable];
	});
	@synchronized(lock) {
		NSNumber *existing = [TGGamepadIds objectForKey:controller];
		if (existing != nil) {
			return existing.integerValue;
		}
		NSInteger gamepadId = TGNextGamepadId++;
		[TGGamepadIds setObject:@(gamepadId) forKey:controller];
		return gamepadId;
	}
}

static NSString *TGGamepadName(GCController *controller)
{
	NSString *name = controller.vendorName;
	return name.length > 0 ? name : @"gamepad";
}

#pragma mark - Channel

/** One throttled analog channel (a stick or a trigger). */
@interface TGGamepadChannel : NSObject
@property (nonatomic, weak) TiProxy *viewProxy;
@property (nonatomic, copy) NSString *event; // 'stick' | 'trigger' (also the payload key)
@property (nonatomic, copy) NSString *name;  // 'left' | 'right' | 'l2' | 'r2'
@property (nonatomic, assign) BOOL twoAxes;
@property (nonatomic, assign) NSInteger gamepadId;
@property (nonatomic, assign) float x, y; // last reported
@property (nonatomic, assign) float pendingX, pendingY;
@property (nonatomic, assign) BOOL pending;
@property (nonatomic, assign) NSTimeInterval lastEventTime;
- (void)update:(float)nx y:(float)ny;
- (void)reset;
@end

@implementation TGGamepadChannel

- (void)update:(float)nx y:(float)ny
{
	float curX = _pending ? _pendingX : _x;
	float curY = _pending ? _pendingY : _y;
	if (fabsf(nx - curX) < TGAxisEpsilon && fabsf(ny - curY) < TGAxisEpsilon) {
		return;
	}
	_pendingX = nx;
	_pendingY = ny;
	NSTimeInterval now = CACurrentMediaTime();
	NSTimeInterval wait = _lastEventTime + TGAxisEventInterval - now;
	// Transitions skip the throttle: leaving rest, returning to rest and
	// crossing zero are what a game reacts to, and a 50 ms wait there is a
	// felt delay (a stick let go stops the hero late). See the Android twin.
	BOOL transition = TGSign(nx) != TGSign(_x) || TGSign(ny) != TGSign(_y);
	if (wait <= 0 || transition) {
		_pending = NO; // a scheduled flush finds pending == NO and does nothing
		[self flush:now];
	} else if (!_pending) {
		_pending = YES;
		__weak TGGamepadChannel *weakSelf = self;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)),
					   dispatch_get_main_queue(), ^{
			TGGamepadChannel *channel = weakSelf;
			if (channel != nil && channel.pending) {
				channel.pending = NO;
				[channel flush:CACurrentMediaTime()];
			}
		});
	}
}

- (void)flush:(NSTimeInterval)now
{
	_x = _pendingX;
	_y = _pendingY;
	_lastEventTime = now;
	TiProxy *proxy = _viewProxy;
	if (proxy != nil && [proxy _hasListeners:_event]) {
		NSMutableDictionary *data = [NSMutableDictionary dictionary];
		data[_event] = _name;
		if (_twoAxes) {
			data[@"x"] = @(_x);
			data[@"y"] = @(_y);
		} else {
			data[@"value"] = @(_x);
		}
		data[@"gamepad"] = @(_gamepadId);
		[proxy fireEvent:_event withObject:data];
	}
}

/** Back to rest, reported to JS if the last value was not rest — a stick
 *  still held when the app resigns active or the pad disconnects ends
 *  with 0, 0 in JS. */
- (void)reset
{
	_pending = NO; // a scheduled flush finds pending == NO and does nothing
	_pendingX = _pendingY = 0;
	if (_x != 0 || _y != 0) {
		[self flush:CACurrentMediaTime()];
	}
}

@end

#pragma mark - Device state

@interface TGGamepadDevice : NSObject
@property (nonatomic, weak) GCController *controller;
@property (nonatomic, assign) NSInteger gamepadId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) TGGamepadChannel *leftStick, *rightStick, *leftTrigger, *rightTrigger;
@property (nonatomic, strong) NSMutableArray<NSString *> *pressed; // guarded by @synchronized(pressed)
@property (nonatomic, assign) BOOL announced; // 'gamepadconnected' fired
@property (nonatomic, assign) BOOL l2Down, r2Down;
@property (nonatomic, assign) BOOL dpadUp, dpadDown, dpadLeft, dpadRight;
@end

@implementation TGGamepadDevice {
	@public BOOL _stickDirs[4];
}
@end

#pragma mark - Controller

@implementation TGGamepadController {
	__weak TiProxy *_viewProxy;
	NSMutableArray<TGGamepadDevice *> *_devices; // main thread; @synchronized for snapshot
	NSInteger _lastActiveDevice;
	BOOL _shutdown;
}

- (instancetype)initWithViewProxy:(TiProxy *)viewProxy
{
	if (self = [super init]) {
		_viewProxy = viewProxy;
		_devices = [NSMutableArray array];
		_lastActiveDevice = -1;
		_deadzone = 0.2f;
		_stickPress = TGDefaultStickPress;
		_stickRelease = TGDefaultStickRelease;
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(controllerConnected:)
					   name:GCControllerDidConnectNotification object:nil];
		[center addObserver:self selector:@selector(controllerDisconnected:)
					   name:GCControllerDidDisconnectNotification object:nil];
		[center addObserver:self selector:@selector(applicationWillResignActive:)
					   name:UIApplicationWillResignActiveNotification object:nil];
		dispatch_block_t attachExisting = ^{
			for (GCController *controller in [GCController controllers]) {
				// A pad paired before the view existed announces itself on
				// its first input — JS always hears 'gamepadconnected'
				// before any button from that pad.
				[self attachController:controller announce:NO];
			}
		};
		if ([NSThread isMainThread]) {
			attachExisting();
		} else {
			dispatch_async(dispatch_get_main_queue(), attachExisting);
		}
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)shutdown
{
	dispatch_block_t stop = ^{
		if (_shutdown) {
			return;
		}
		_shutdown = YES;
		[[NSNotificationCenter defaultCenter] removeObserver:self];
		[self releaseAll];
		for (TGGamepadDevice *device in _devices) {
			[self detachController:device.controller];
		}
		@synchronized(_devices) {
			[_devices removeAllObjects];
		}
	};
	if ([NSThread isMainThread]) {
		stop();
	} else {
		dispatch_async(dispatch_get_main_queue(), stop);
	}
}

#pragma mark Connection

- (void)controllerConnected:(NSNotification *)note
{
	if (_shutdown) {
		return;
	}
	GCController *controller = note.object;
	if ([controller isKindOfClass:[GCController class]]) {
		[self attachController:controller announce:YES];
	}
}

- (void)controllerDisconnected:(NSNotification *)note
{
	GCController *controller = note.object;
	TGGamepadDevice *device = [self deviceForController:controller];
	if (device == nil) {
		return;
	}
	@synchronized(_devices) {
		[_devices removeObject:device];
	}
	[self releaseDevice:device];
	if (device.announced) {
		[self fireDeviceEvent:@"gamepaddisconnected" device:device];
	}
}

- (void)applicationWillResignActive:(NSNotification *)note
{
	// button-up events are lost while in the background — don't leave a
	// direction held down in JS
	[self releaseAll];
}

- (TGGamepadDevice *)deviceForController:(GCController *)controller
{
	for (TGGamepadDevice *device in _devices) {
		if (device.controller == controller) {
			return device;
		}
	}
	return nil;
}

- (void)attachController:(GCController *)controller announce:(BOOL)announce
{
	GCExtendedGamepad *gamepad = controller.extendedGamepad;
	if (gamepad == nil || [self deviceForController:controller] != nil) {
		return; // micro gamepads (Siri Remote) are not game controllers here
	}
	TGGamepadDevice *device = [[TGGamepadDevice alloc] init];
	device.controller = controller;
	device.gamepadId = TGGamepadIdFor(controller);
	device.name = TGGamepadName(controller);
	device.pressed = [NSMutableArray array];
	device.leftStick = [self channel:@"stick" name:@"left" twoAxes:YES gamepadId:device.gamepadId];
	device.rightStick = [self channel:@"stick" name:@"right" twoAxes:YES gamepadId:device.gamepadId];
	device.leftTrigger = [self channel:@"trigger" name:@"l2" twoAxes:NO gamepadId:device.gamepadId];
	device.rightTrigger = [self channel:@"trigger" name:@"r2" twoAxes:NO gamepadId:device.gamepadId];
	@synchronized(_devices) {
		[_devices addObject:device];
	}

	__weak TGGamepadController *weakSelf = self;
	__weak TGGamepadDevice *weakDevice = device;
	controller.handlerQueue = dispatch_get_main_queue();
	gamepad.valueChangedHandler = ^(GCExtendedGamepad *pad, GCControllerElement *element) {
		TGGamepadController *strongSelf = weakSelf;
		TGGamepadDevice *strongDevice = weakDevice;
		if (strongSelf != nil && strongDevice != nil) {
			[strongSelf gamepad:pad changed:element device:strongDevice];
		}
	};

	if (announce) {
		[self announceDevice:device];
	}
}

- (void)detachController:(GCController *)controller
{
	if (controller.extendedGamepad != nil) {
		controller.extendedGamepad.valueChangedHandler = nil;
	}
}

- (TGGamepadChannel *)channel:(NSString *)event name:(NSString *)name twoAxes:(BOOL)twoAxes gamepadId:(NSInteger)gamepadId
{
	TGGamepadChannel *channel = [[TGGamepadChannel alloc] init];
	channel.viewProxy = _viewProxy;
	channel.event = event;
	channel.name = name;
	channel.twoAxes = twoAxes;
	channel.gamepadId = gamepadId;
	return channel;
}

- (void)announceDevice:(TGGamepadDevice *)device
{
	if (!device.announced) {
		device.announced = YES;
		[self fireDeviceEvent:@"gamepadconnected" device:device];
	}
}

#pragma mark Input (main thread)

- (void)gamepad:(GCExtendedGamepad *)gamepad changed:(GCControllerElement *)element device:(TGGamepadDevice *)device
{
	if (_shutdown) {
		return;
	}
	[self announceDevice:device];
	_lastActiveDevice = device.gamepadId;

	if (element == gamepad.leftThumbstick) {
		// GameController y is up-positive; the engine (and Android) are y-down
		float lx = gamepad.leftThumbstick.xAxis.value;
		float ly = -gamepad.leftThumbstick.yAxis.value;
		float x, y;
		[self applyDeadzone:lx y:ly outX:&x outY:&y];
		[self updateStickDirections:device x:x y:y];
		[device.leftStick update:x y:y];
	} else if (element == gamepad.rightThumbstick) {
		float x, y;
		[self applyDeadzone:gamepad.rightThumbstick.xAxis.value y:-gamepad.rightThumbstick.yAxis.value outX:&x outY:&y];
		[device.rightStick update:x y:y];
	} else if (element == gamepad.leftTrigger) {
		float value = gamepad.leftTrigger.value;
		device.l2Down = [self updateTrigger:device name:@"l2" value:value was:device.l2Down];
		[device.leftTrigger update:value y:0];
	} else if (element == gamepad.rightTrigger) {
		float value = gamepad.rightTrigger.value;
		device.r2Down = [self updateTrigger:device name:@"r2" value:value was:device.r2Down];
		[device.rightTrigger update:value y:0];
	} else if (element == gamepad.dpad) {
		[self updateDpad:device dpad:gamepad.dpad];
	} else if (element == gamepad.buttonA) {
		[self setButton:device name:@"a" down:gamepad.buttonA.pressed source:@"button"];
	} else if (element == gamepad.buttonB) {
		[self setButton:device name:@"b" down:gamepad.buttonB.pressed source:@"button"];
	} else if (element == gamepad.buttonX) {
		[self setButton:device name:@"x" down:gamepad.buttonX.pressed source:@"button"];
	} else if (element == gamepad.buttonY) {
		[self setButton:device name:@"y" down:gamepad.buttonY.pressed source:@"button"];
	} else if (element == gamepad.leftShoulder) {
		[self setButton:device name:@"l1" down:gamepad.leftShoulder.pressed source:@"button"];
	} else if (element == gamepad.rightShoulder) {
		[self setButton:device name:@"r1" down:gamepad.rightShoulder.pressed source:@"button"];
	} else if (@available(iOS 12.1, *)) {
		if (element == gamepad.leftThumbstickButton) {
			[self setButton:device name:@"l3" down:gamepad.leftThumbstickButton.pressed source:@"button"];
			return;
		} else if (element == gamepad.rightThumbstickButton) {
			[self setButton:device name:@"r3" down:gamepad.rightThumbstickButton.pressed source:@"button"];
			return;
		}
		if (@available(iOS 13.0, *)) {
			if (element == gamepad.buttonMenu) {
				[self setButton:device name:@"start" down:gamepad.buttonMenu.pressed source:@"button"];
				return;
			} else if (element == gamepad.buttonOptions) {
				[self setButton:device name:@"select" down:gamepad.buttonOptions.pressed source:@"button"];
				return;
			}
		}
		if (@available(iOS 14.0, *)) {
			if (element == gamepad.buttonHome) {
				[self setButton:device name:@"home" down:gamepad.buttonHome.pressed source:@"button"];
			}
		}
	}
}

- (void)applyDeadzone:(float)x y:(float)y outX:(float *)outX outY:(float *)outY
{
	float dz = self.deadzone;
	float len = sqrtf(x * x + y * y);
	if (len <= dz || len == 0) {
		*outX = 0;
		*outY = 0;
		return;
	}
	float scaled = MIN(1.0f, (len - dz) / (1.0f - dz));
	*outX = x / len * scaled;
	*outY = y / len * scaled;
}

- (void)updateStickDirections:(TGGamepadDevice *)device x:(float)x y:(float)y
{
	// order matches TGDirectionNames: up, down, left, right
	float values[4] = { -y, y, -x, x };
	for (int d = 0; d < 4; d++) {
		BOOL was = device->_stickDirs[d];
		BOOL now = was ? values[d] > self.stickRelease : values[d] > self.stickPress;
		if (now != was) {
			device->_stickDirs[d] = now;
			[self setButton:device name:TGDirectionNames[d] down:now source:@"leftstick"];
		}
	}
}

- (BOOL)updateTrigger:(TGGamepadDevice *)device name:(NSString *)name value:(float)value was:(BOOL)was
{
	BOOL now = was ? value > TGTriggerRelease : value > TGTriggerPress;
	if (now != was) {
		[self setButton:device name:name down:now source:@"trigger"];
	}
	return now;
}

- (void)updateDpad:(TGGamepadDevice *)device dpad:(GCControllerDirectionPad *)dpad
{
	BOOL up = dpad.up.pressed, down = dpad.down.pressed, left = dpad.left.pressed, right = dpad.right.pressed;
	if (up != device.dpadUp) {
		device.dpadUp = up;
		[self setButton:device name:@"up" down:up source:@"dpad"];
	}
	if (down != device.dpadDown) {
		device.dpadDown = down;
		[self setButton:device name:@"down" down:down source:@"dpad"];
	}
	if (left != device.dpadLeft) {
		device.dpadLeft = left;
		[self setButton:device name:@"left" down:left source:@"dpad"];
	}
	if (right != device.dpadRight) {
		device.dpadRight = right;
		[self setButton:device name:@"right" down:right source:@"dpad"];
	}
}

/** Central edge detector: a name is reported down once, no matter how
 *  many physical controls map onto it (d-pad + stick). */
- (void)setButton:(TGGamepadDevice *)device name:(NSString *)name down:(BOOL)down source:(NSString *)source
{
	@synchronized(device.pressed) {
		BOOL was = [device.pressed containsObject:name];
		if (down == was) {
			return;
		}
		if (down) {
			[device.pressed addObject:name];
		} else {
			[device.pressed removeObject:name];
		}
	}
	NSString *event = down ? @"buttondown" : @"buttonup";
	TiProxy *proxy = _viewProxy;
	if (proxy != nil && [proxy _hasListeners:event]) {
		[proxy fireEvent:event withObject:@{
			@"button": name,
			@"gamepad": @(device.gamepadId),
			@"input": source, // not "source" — Titanium overwrites that key with the firing proxy
			@"keyCode": @0
		}];
	}
}

- (void)fireDeviceEvent:(NSString *)event device:(TGGamepadDevice *)device
{
	TiProxy *proxy = _viewProxy;
	if (proxy != nil && [proxy _hasListeners:event]) {
		[proxy fireEvent:event withObject:@{ @"gamepad": @(device.gamepadId), @"name": device.name }];
	}
}

- (void)releaseDevice:(TGGamepadDevice *)device
{
	for (;;) {
		NSString *name;
		@synchronized(device.pressed) {
			name = device.pressed.lastObject;
		}
		if (name == nil) {
			break;
		}
		[self setButton:device name:name down:NO source:@"button"];
	}
	for (int d = 0; d < 4; d++) {
		device->_stickDirs[d] = NO;
	}
	device.dpadUp = device.dpadDown = device.dpadLeft = device.dpadRight = NO;
	device.l2Down = device.r2Down = NO;
	[device.leftStick reset];
	[device.rightStick reset];
	[device.leftTrigger reset];
	[device.rightTrigger reset];
}

- (void)releaseAll
{
	for (TGGamepadDevice *device in [_devices copy]) {
		[self releaseDevice:device];
	}
}

#pragma mark Queries (any thread)

+ (NSArray<NSDictionary *> *)connectedGamepads
{
	NSMutableArray *list = [NSMutableArray array];
	for (GCController *controller in [GCController controllers]) {
		if (controller.extendedGamepad != nil) {
			[list addObject:@{ @"id": @(TGGamepadIdFor(controller)), @"name": TGGamepadName(controller) }];
		}
	}
	return list;
}

- (NSDictionary *)snapshot
{
	TGGamepadDevice *device = nil;
	@synchronized(_devices) {
		for (TGGamepadDevice *candidate in _devices) {
			if (candidate.gamepadId == _lastActiveDevice) {
				device = candidate;
				break;
			}
		}
	}
	if (device == nil) {
		return nil;
	}
	NSMutableDictionary *buttons = [NSMutableDictionary dictionary];
	@synchronized(device.pressed) {
		for (NSString *name in device.pressed) {
			buttons[name] = @YES;
		}
	}
	TGGamepadChannel *ls = device.leftStick, *rs = device.rightStick, *lt = device.leftTrigger, *rt = device.rightTrigger;
	return @{
		@"id": @(device.gamepadId),
		@"name": device.name,
		@"leftX": @(ls.pending ? ls.pendingX : ls.x),
		@"leftY": @(ls.pending ? ls.pendingY : ls.y),
		@"rightX": @(rs.pending ? rs.pendingX : rs.x),
		@"rightY": @(rs.pending ? rs.pendingY : rs.y),
		@"l2": @(lt.pending ? lt.pendingX : lt.x),
		@"r2": @(rt.pending ? rt.pendingX : rt.x),
		@"buttons": buttons
	};
}

@end
