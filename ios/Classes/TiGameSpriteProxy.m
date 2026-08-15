#import "TiGameSpriteProxy.h"
#import "TGAnimation.h"
#import "TGScene.h"
#import "TGTween.h"
#import "TiGameSpriteSheetProxy.h"

@implementation TiGameSpriteProxy {
	TiGameSpriteSheetProxy *_sheetProxy;
	NSString *_glowColor;
}

- (instancetype)init
{
	if (self = [super init]) {
		_sprite = [[TGSprite alloc] init];
		_sprite.proxy = self;
		_sprite.eventListener = self;
	}
	return self;
}

- (NSString *)apiName
{
	return @"ti.game.Sprite";
}

static NSSet<NSString *> *toGroupSet(id value)
{
	if (![value isKindOfClass:[NSArray class]]) {
		return nil;
	}
	NSMutableSet<NSString *> *set = [NSMutableSet set];
	for (id group in (NSArray *)value) {
		NSString *name = [TiUtils stringValue:group];
		if (name != nil) {
			[set addObject:name];
		}
	}
	return set;
}

#pragma mark Sheet

- (void)setSheet:(id)value
{
	TiGameSpriteSheetProxy *newSheet =
		[value isKindOfClass:[TiGameSpriteSheetProxy class]] ? value : nil;
	if (_sheetProxy != nil) {
		[self forgetProxy:_sheetProxy];
	}
	_sheetProxy = newSheet;
	if (newSheet != nil) {
		[self rememberProxy:newSheet];
	}
	self.sprite.sheet = newSheet.sheet;
}

- (id)sheet
{
	return _sheetProxy;
}

#pragma mark Transform properties (live values, updated by drags/tweens)

- (void)setX:(id)value
{
	self.sprite.x = [TiUtils floatValue:value def:0];
}

- (NSNumber *)x
{
	return @(self.sprite.x);
}

- (void)setY:(id)value
{
	self.sprite.y = [TiUtils floatValue:value def:0];
}

- (NSNumber *)y
{
	return @(self.sprite.y);
}

- (void)setWidth:(id)value
{
	self.sprite.width = [TiUtils floatValue:value def:0];
}

- (NSNumber *)width
{
	return @([self.sprite drawWidth]);
}

- (void)setHeight:(id)value
{
	self.sprite.height = [TiUtils floatValue:value def:0];
}

- (NSNumber *)height
{
	return @([self.sprite drawHeight]);
}

- (void)setScale:(id)value
{
	float s = [TiUtils floatValue:value def:1];
	self.sprite.scaleX = s;
	self.sprite.scaleY = s;
}

- (NSNumber *)scale
{
	return @(self.sprite.scaleX);
}

- (void)setScaleX:(id)value
{
	self.sprite.scaleX = [TiUtils floatValue:value def:1];
}

- (NSNumber *)scaleX
{
	return @(self.sprite.scaleX);
}

- (void)setScaleY:(id)value
{
	self.sprite.scaleY = [TiUtils floatValue:value def:1];
}

- (NSNumber *)scaleY
{
	return @(self.sprite.scaleY);
}

- (void)setRotation:(id)value
{
	self.sprite.rotation = [TiUtils floatValue:value def:0];
}

- (NSNumber *)rotation
{
	return @(self.sprite.rotation);
}

- (void)setAnchorX:(id)value
{
	self.sprite.anchorX = [TiUtils floatValue:value def:0.5f];
}

- (NSNumber *)anchorX
{
	return @(self.sprite.anchorX);
}

- (void)setAnchorY:(id)value
{
	self.sprite.anchorY = [TiUtils floatValue:value def:0.5f];
}

- (NSNumber *)anchorY
{
	return @(self.sprite.anchorY);
}

- (void)setOpacity:(id)value
{
	self.sprite.opacity = [TiUtils floatValue:value def:1];
}

- (NSNumber *)opacity
{
	return @(self.sprite.opacity);
}

/** Glow tint, e.g. '#ffd54a'; visible once glowBlur > 0. */
- (void)setGlowColor:(id)value
{
	_glowColor = [TiUtils stringValue:value];
	TiColor *tiColor = [TiUtils colorValue:value];
	if (tiColor == nil) {
		self.sprite.glowR = 1.0f;
		self.sprite.glowG = 1.0f;
		self.sprite.glowB = 1.0f;
		return;
	}
	CGFloat r = 1, g = 1, b = 1, a = 1;
	[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
	self.sprite.glowR = (float)r;
	self.sprite.glowG = (float)g;
	self.sprite.glowB = (float)b;
}

- (NSString *)glowColor
{
	return _glowColor;
}

/** Glow blur radius in px; 0 = no glow. */
- (void)setGlowBlur:(id)value
{
	self.sprite.glowBlur = [TiUtils floatValue:value def:0];
}

- (NSNumber *)glowBlur
{
	return @(self.sprite.glowBlur);
}

/** Halo strength 0..1 (fade the glow without touching the blur). */
- (void)setGlowOpacity:(id)value
{
	self.sprite.glowOpacity = [TiUtils floatValue:value def:1];
}

- (NSNumber *)glowOpacity
{
	return @(self.sprite.glowOpacity);
}

- (void)setVisible:(id)value
{
	self.sprite.visible = [TiUtils boolValue:value def:YES];
}

- (NSNumber *)visible
{
	return @(self.sprite.visible);
}

- (void)setZIndex:(id)value
{
	self.sprite.zIndex = [TiUtils intValue:value def:0];
	[self.sprite.scene markZOrderDirty];
}

- (NSNumber *)zIndex
{
	return @(self.sprite.zIndex);
}

- (void)setYSort:(id)value
{
	self.sprite.ySort = [TiUtils boolValue:value def:NO];
	[self.sprite.scene recomputeYSort];
}

- (NSNumber *)ySort
{
	return @(self.sprite.ySort);
}

- (void)setFrame:(id)value
{
	[self.sprite stopAnimation];
	self.sprite.frame = [TiUtils intValue:value def:0];
}

- (NSNumber *)frame
{
	return @(self.sprite.frame);
}

#pragma mark Interaction flags

- (void)setDraggable:(id)value
{
	self.sprite.draggable = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)draggable
{
	return @(self.sprite.draggable);
}

- (void)setPinchable:(id)value
{
	self.sprite.pinchable = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)pinchable
{
	return @(self.sprite.pinchable);
}

- (void)setRotatable:(id)value
{
	self.sprite.rotatable = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)rotatable
{
	return @(self.sprite.rotatable);
}

/** NO = touches pass through to sprites underneath. */
- (void)setTouchEnabled:(id)value
{
	self.sprite.touchEnabled = [TiUtils boolValue:value def:YES];
}

- (NSNumber *)touchEnabled
{
	return @(self.sprite.touchEnabled);
}

/** Tile the frame instead of stretching: true = both axes, 'x'/'y' = one. */
- (void)setTileRepeat:(id)value
{
	if ([value isKindOfClass:[NSString class]]) {
		self.sprite.tileRepeatX = [value isEqualToString:@"x"];
		self.sprite.tileRepeatY = [value isEqualToString:@"y"];
	} else {
		BOOL both = [TiUtils boolValue:value def:NO];
		self.sprite.tileRepeatX = both;
		self.sprite.tileRepeatY = both;
	}
}

- (id)tileRepeat
{
	if (self.sprite.tileRepeatX && self.sprite.tileRepeatY) {
		return @YES;
	}
	if (self.sprite.tileRepeatX) {
		return @"x";
	}
	if (self.sprite.tileRepeatY) {
		return @"y";
	}
	return @NO;
}

#pragma mark Physics

- (void)setVelocityX:(id)value
{
	self.sprite.velocityX = [TiUtils floatValue:value def:0];
}

- (NSNumber *)velocityX
{
	return @(self.sprite.velocityX);
}

- (void)setVelocityY:(id)value
{
	self.sprite.velocityY = [TiUtils floatValue:value def:0];
}

- (NSNumber *)velocityY
{
	return @(self.sprite.velocityY);
}

- (void)setGravity:(id)value
{
	self.sprite.gravity = [TiUtils floatValue:value def:0];
}

- (NSNumber *)gravity
{
	return @(self.sprite.gravity);
}

- (void)setWrapX:(id)value
{
	self.sprite.wrapX = [TiUtils floatValue:value def:0];
}

- (NSNumber *)wrapX
{
	return @(self.sprite.wrapX);
}

- (void)setWrapShift:(id)value
{
	self.sprite.wrapShift = [TiUtils floatValue:value def:0];
}

- (NSNumber *)wrapShift
{
	return @(self.sprite.wrapShift);
}

#pragma mark Newtonian flight (Asteroids-style)

- (void)setAngularVelocity:(id)value
{
	self.sprite.angularVelocity = [TiUtils floatValue:value def:0];
}

- (NSNumber *)angularVelocity
{
	return @(self.sprite.angularVelocity);
}

- (void)setThrust:(id)value
{
	self.sprite.thrust = [TiUtils floatValue:value def:0];
}

- (NSNumber *)thrust
{
	return @(self.sprite.thrust);
}

- (void)setWrapAround:(id)value
{
	self.sprite.wrapAround = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)wrapAround
{
	return @(self.sprite.wrapAround);
}

#pragma mark Car physics (top-down driving)

- (void)setCarMode:(id)value
{
	self.sprite.carMode = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)carMode
{
	return @(self.sprite.carMode);
}

- (void)setThrottle:(id)value
{
	self.sprite.throttle = [TiUtils floatValue:value def:0];
}

- (NSNumber *)throttle
{
	return @(self.sprite.throttle);
}

- (void)setSteering:(id)value
{
	self.sprite.steering = [TiUtils floatValue:value def:0];
}

- (NSNumber *)steering
{
	return @(self.sprite.steering);
}

- (void)setEnginePower:(id)value
{
	self.sprite.enginePower = [TiUtils floatValue:value def:600];
}

- (NSNumber *)enginePower
{
	return @(self.sprite.enginePower);
}

- (void)setMaxSpeed:(id)value
{
	self.sprite.maxSpeed = [TiUtils floatValue:value def:500];
}

- (NSNumber *)maxSpeed
{
	return @(self.sprite.maxSpeed);
}

- (void)setTurnRate:(id)value
{
	self.sprite.turnRate = [TiUtils floatValue:value def:200];
}

- (NSNumber *)turnRate
{
	return @(self.sprite.turnRate);
}

- (void)setGrip:(id)value
{
	self.sprite.grip = [TiUtils floatValue:value def:4];
}

- (NSNumber *)grip
{
	return @(self.sprite.grip);
}

- (void)setDrag:(id)value
{
	self.sprite.drag = [TiUtils floatValue:value def:0.6f];
}

- (NSNumber *)drag
{
	return @(self.sprite.drag);
}

- (void)setSkidMarks:(id)value
{
	self.sprite.skidMarks = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)skidMarks
{
	return @(self.sprite.skidMarks);
}

- (void)setSkidThreshold:(id)value
{
	self.sprite.skidThreshold = [TiUtils floatValue:value def:0];
}

- (NSNumber *)skidThreshold
{
	return @(self.sprite.skidThreshold);
}

/** True while lateral speed exceeds the skid threshold (read-only). */
- (NSNumber *)drifting
{
	return @(self.sprite.drifting);
}

#pragma mark Collision

- (void)setHitboxScale:(id)value
{
	self.sprite.hitboxScale = [TiUtils floatValue:value def:1];
}

- (NSNumber *)hitboxScale
{
	return @(self.sprite.hitboxScale);
}

/** 'rect' (default) or 'circle' — balls and asteroids want circles. */
- (void)setHitboxShape:(id)value
{
	self.sprite.circleHitbox = [@"circle" isEqualToString:[TiUtils stringValue:value]];
}

- (NSString *)hitboxShape
{
	return self.sprite.circleHitbox ? @"circle" : @"rect";
}

- (void)setDebug:(id)value
{
	self.sprite.debug = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)debug
{
	return @(self.sprite.debug);
}

- (void)setCollisionGroup:(id)value
{
	self.sprite.collisionGroup = [TiUtils stringValue:value];
}

- (NSString *)collisionGroup
{
	return self.sprite.collisionGroup;
}

- (void)setCollidesWith:(id)value
{
	self.sprite.collidesWith = toGroupSet(value);
}

- (NSArray<NSString *> *)collidesWith
{
	NSSet<NSString *> *groups = self.sprite.collidesWith;
	return (groups != nil) ? groups.allObjects : @[];
}

#pragma mark Solid collision (platformer)

- (void)setSolidWith:(id)value
{
	self.sprite.solidWith = toGroupSet(value);
}

- (NSArray<NSString *> *)solidWith
{
	NSSet<NSString *> *groups = self.sprite.solidWith;
	return (groups != nil) ? groups.allObjects : @[];
}

/** True while standing on a solid (read-only; e.g. gate jumping on it). */
- (NSNumber *)onGround
{
	return @(self.sprite.onGround);
}

- (void)setRestitution:(id)value
{
	self.sprite.restitution = [TiUtils floatValue:value def:0];
}

- (NSNumber *)restitution
{
	return @(self.sprite.restitution);
}

#pragma mark Idle animation

- (void)setIdleAnimation:(id)value
{
	self.sprite.idleAnimation = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)idleAnimation
{
	return @(self.sprite.idleAnimation);
}

- (void)setIdleRotation:(id)value
{
	self.sprite.idleRotation = [TiUtils floatValue:value def:3];
}

- (NSNumber *)idleRotation
{
	return @(self.sprite.idleRotation);
}

- (void)setIdleMovement:(id)value
{
	self.sprite.idleMovement = [TiUtils floatValue:value def:4];
}

- (NSNumber *)idleMovement
{
	return @(self.sprite.idleMovement);
}

- (void)setIdleSpeed:(id)value
{
	self.sprite.idleSpeed = [TiUtils floatValue:value def:1];
}

- (NSNumber *)idleSpeed
{
	return @(self.sprite.idleSpeed);
}

#pragma mark Sheet animation

- (void)setAnimations:(id)value
{
	if (![value isKindOfClass:[NSDictionary class]]) {
		return;
	}
	[(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:
		^(NSString *name, id definition, BOOL *stop) {
			if (![definition isKindOfClass:[NSDictionary class]]) {
				return;
			}
			NSDictionary *def = definition;
			if (![def[@"frames"] isKindOfClass:[NSArray class]]) {
				NSLog(@"[WARN] Animation '%@' has no frames array; skipped", name);
				return;
			}
			NSMutableArray<NSNumber *> *frames = [NSMutableArray array];
			for (id frame in (NSArray *)def[@"frames"]) {
				[frames addObject:@([TiUtils intValue:frame def:0])];
			}
			float fps = [TiUtils floatValue:def[@"fps"] def:12];
			BOOL loop = [TiUtils boolValue:def[@"loop"] def:NO];
			[self.sprite addAnimation:[[TGAnimation alloc] initWithName:name
																 frames:frames
																	fps:fps
																   loop:loop]
								named:name];
		}];
}

- (NSNumber *)play:(id)args
{
	ENSURE_SINGLE_ARG(args, NSString);
	if (![self.sprite play:args]) {
		NSLog(@"[WARN] Unknown animation: %@", args);
		return @NO;
	}
	return @YES;
}

- (void)stop:(id)unused
{
	[self.sprite stopAnimation];
}

- (NSString *)animation
{
	return [self.sprite currentAnimationName];
}

#pragma mark Tweens

/**
 * Native tween: sprite.animate({ x: 300, rotation: 90, duration: 500,
 * easing: 'easeOut' }). Fires 'complete' when done. Duration/delay in ms.
 */
- (void)animate:(id)args
{
	ENSURE_SINGLE_ARG(args, NSDictionary);
	NSDictionary *options = args;
	TGTween *tween = [[TGTween alloc] init];
	if (options[@"x"] != nil) {
		tween.toX = @([TiUtils floatValue:options[@"x"] def:0]);
	}
	if (options[@"y"] != nil) {
		tween.toY = @([TiUtils floatValue:options[@"y"] def:0]);
	}
	if (options[@"scale"] != nil) {
		float s = [TiUtils floatValue:options[@"scale"] def:1];
		tween.toScaleX = @(s);
		tween.toScaleY = @(s);
	}
	if (options[@"scaleX"] != nil) {
		tween.toScaleX = @([TiUtils floatValue:options[@"scaleX"] def:1]);
	}
	if (options[@"scaleY"] != nil) {
		tween.toScaleY = @([TiUtils floatValue:options[@"scaleY"] def:1]);
	}
	if (options[@"rotation"] != nil) {
		tween.toRotation = @([TiUtils floatValue:options[@"rotation"] def:0]);
	}
	if (options[@"opacity"] != nil) {
		tween.toOpacity = @([TiUtils floatValue:options[@"opacity"] def:1]);
	}
	if (options[@"glowOpacity"] != nil) {
		tween.toGlowOpacity = @([TiUtils floatValue:options[@"glowOpacity"] def:1]);
	}
	if (options[@"duration"] != nil) {
		tween.duration = [TiUtils floatValue:options[@"duration"] def:300] / 1000.0f;
	}
	if (options[@"delay"] != nil) {
		tween.delay = [TiUtils floatValue:options[@"delay"] def:0] / 1000.0f;
	}
	if (options[@"easing"] != nil) {
		tween.easing = [TiUtils stringValue:options[@"easing"]];
	}
	[self.sprite addTween:tween];
}

- (void)clearTweens:(id)unused
{
	[self.sprite clearTweens];
}

#pragma mark Native engine callbacks (render thread; fireEvent is thread-safe)

- (void)spriteAnimationComplete:(TGSprite *)s animationName:(NSString *)animationName
{
	if ([self _hasListeners:@"animationcomplete"]) {
		[self fireEvent:@"animationcomplete" withObject:@{
			@"animation": (animationName != nil) ? animationName : [NSNull null]
		}];
	}
}

- (void)spriteTweenComplete:(TGSprite *)s
{
	if ([self _hasListeners:@"complete"]) {
		[self fireEvent:@"complete" withObject:@{
			@"x": @(s.x),
			@"y": @(s.y),
			@"rotation": @(s.rotation),
			@"scaleX": @(s.scaleX),
			@"scaleY": @(s.scaleY),
			@"opacity": @(s.opacity)
		}];
	}
}

- (void)sprite:(TGSprite *)s collidedWith:(TGSprite *)other
{
	if ([self _hasListeners:@"collision"]) {
		NSMutableDictionary *data = [NSMutableDictionary dictionary];
		data[@"group"] = other.collisionGroup;
		data[@"other"] = other.proxy;
		data[@"x"] = @(s.x);
		data[@"y"] = @(s.y);
		[self fireEvent:@"collision" withObject:data];
	}
}

- (void)sprite:(TGSprite *)s landedOn:(TGSprite *)solid
{
	if ([self _hasListeners:@"land"]) {
		NSMutableDictionary *data = [NSMutableDictionary dictionary];
		data[@"x"] = @(s.x);
		data[@"y"] = @(s.y);
		if (solid != nil) {
			data[@"other"] = solid.proxy;
			data[@"group"] = solid.collisionGroup;
		}
		[self fireEvent:@"land" withObject:data];
	}
}

@end
