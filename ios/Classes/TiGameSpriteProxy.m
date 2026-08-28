#import "TiGameSpriteProxy.h"
#import "TGAnimation.h"
#import "TGPath.h"
#import "TGScene.h"
#import "TGTween.h"
#import "TiGameSpriteSheetProxy.h"
#import "TGValues.h"

@implementation TiGameSpriteProxy {
	TiGameSpriteSheetProxy *_sheetProxy;
	NSString *_glowColor;
	NSString *_tintColor;
}

- (instancetype)init
{
	return [self initWithSprite:[[TGSprite alloc] init]];
}

- (instancetype)initWithSprite:(TGSprite *)sprite
{
	if (self = [super init]) {
		_sprite = sprite;
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
	self.sprite.scaleX = [TGValues ratio:value fallback:1];
}

- (NSNumber *)scaleX
{
	return @(self.sprite.scaleX);
}

- (void)setScaleY:(id)value
{
	self.sprite.scaleY = [TGValues ratio:value fallback:1];
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
	self.sprite.anchorX = [TGValues anchorX:value fallback:0.5f];
}

- (NSNumber *)anchorX
{
	return @(self.sprite.anchorX);
}

- (void)setAnchorY:(id)value
{
	self.sprite.anchorY = [TGValues anchorY:value fallback:0.5f];
}

- (NSNumber *)anchorY
{
	return @(self.sprite.anchorY);
}

/**
 Both anchors at once, by name: `anchor: "bottom-left"`. Accepts the nine
 corners and edges. Reading it back gives the preset the sprite is on, or
 `custom` when its anchors are somewhere else.
 */
- (void)setAnchor:(id)value
{
	float x = 0.5f;
	float y = 0.5f;
	if ([TGValues anchor:value x:&x y:&y]) {
		self.sprite.anchorX = x;
		self.sprite.anchorY = y;
	}
}

- (NSString *)anchor
{
	return [TGValues anchorNameForX:self.sprite.anchorX y:self.sprite.anchorY];
}

- (void)setOpacity:(id)value
{
	self.sprite.opacity = [TGValues ratio:value fallback:1];
}

- (NSNumber *)opacity
{
	return @(self.sprite.opacity);
}

/** Multiplies the frame's colors, e.g. '#ff5252'; nil/white = unchanged. */
- (void)setTintColor:(id)value
{
	_tintColor = [TiUtils stringValue:value];
	TiColor *tiColor = [TiUtils colorValue:value];
	if (tiColor == nil) {
		self.sprite.tintR = 1.0f;
		self.sprite.tintG = 1.0f;
		self.sprite.tintB = 1.0f;
		return;
	}
	CGFloat r = 1, g = 1, b = 1, a = 1;
	[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
	self.sprite.tintR = (float)r;
	self.sprite.tintG = (float)g;
	self.sprite.tintB = (float)b;
}

- (NSString *)tintColor
{
	return _tintColor;
}

/** 'add' brightens the backdrop instead of covering it (glows, lasers,
 *  fire), 'multiply' darkens it (shadows, stains), 'screen' lightens it
 *  softly without blowing out to white (fog, soft light); anything else
 *  = normal alpha blending. */
- (void)setBlend:(id)value
{
	self.sprite.blendMode = TGBlendModeFromString([TiUtils stringValue:value]);
}

- (NSString *)blend
{
	return TGBlendModeName(self.sprite.blendMode);
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
	self.sprite.glowOpacity = [TGValues ratio:value fallback:1];
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

- (void)setPixelSnap:(id)value
{
	self.sprite.pixelSnap = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)pixelSnap
{
	return @(self.sprite.pixelSnap);
}

/** true = (x, y) are surface coordinates and the sprite ignores camera
 *  position, zoom and shake — HUD scores, buttons, overlays. */
- (void)setScreenFixed:(id)value
{
	self.sprite.screenFixed = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)screenFixed
{
	return @(self.sprite.screenFixed);
}

/** Parallax: how much camera travel moves this sprite — 1 = normal,
 *  0.5 = half-speed background layer, 0 = pinned to the view (but
 *  still zooming, unlike screenFixed). Rendering and touch only;
 *  x/y, physics and collisions stay in world coordinates. */
- (void)setScrollFactor:(id)value
{
	self.sprite.scrollFactor = [TGValues ratio:value fallback:1.0f];
}

- (NSNumber *)scrollFactor
{
	return @(self.sprite.scrollFactor);
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

/** Mirror the frame horizontally (face left/right) — render-only, the
 *  transform, physics and hit testing are unaffected. */
- (void)setFlipX:(id)value
{
	self.sprite.flipX = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)flipX
{
	return @(self.sprite.flipX);
}

/** Mirror the frame vertically (upside down) — render-only. */
- (void)setFlipY:(id)value
{
	self.sprite.flipY = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)flipY
{
	return @(self.sprite.flipY);
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

/** Horizontal acceleration in px/s² (wind, conveyors). `gravity` stays the
 *  vertical one — this is its sibling, not half of a vector. */
- (void)setGravityX:(id)value
{
	self.sprite.gravityX = [TiUtils floatValue:value def:0];
}

- (NSNumber *)gravityX
{
	return @(self.sprite.gravityX);
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
	self.sprite.throttle = [TGValues ratio:value fallback:0];
}

- (NSNumber *)throttle
{
	return @(self.sprite.throttle);
}

- (void)setSteering:(id)value
{
	self.sprite.steering = [TGValues ratio:value fallback:0];
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
	self.sprite.hitboxScale = [TGValues ratio:value fallback:1];
}

- (NSNumber *)hitboxScale
{
	return @(self.sprite.hitboxScale);
}

/**
 Per-axis corrections multiplied on top of hitboxScale (default 1), for art
 whose useful part fills its frame by a different fraction on each axis.
 Ignored by circle hitboxes, which have no axes.
 */
- (void)setHitboxScaleX:(id)value
{
	self.sprite.hitboxScaleX = [TGValues ratio:value fallback:1];
}

- (NSNumber *)hitboxScaleX
{
	return @(self.sprite.hitboxScaleX);
}

- (void)setHitboxScaleY:(id)value
{
	self.sprite.hitboxScaleY = [TGValues ratio:value fallback:1];
}

- (NSNumber *)hitboxScaleY
{
	return @(self.sprite.hitboxScaleY);
}

/** 'rect' (default) or 'circle' — balls and asteroids want circles. */
- (void)setHitboxShape:(id)value
{
	NSString *shape = [TiUtils stringValue:value];
	self.sprite.circleHitbox = [@"circle" isEqualToString:shape];
	self.sprite.obbHitbox = [@"rotatedRect" isEqualToString:shape];
}

- (NSString *)hitboxShape
{
	if (self.sprite.circleHitbox) {
		return @"circle";
	}
	return self.sprite.obbHitbox ? @"rotatedRect" : @"rect";
}

/** Swept AABB: this sprite's movement is collision-tested as a path,
 *  so fast bullets can't tunnel through thin targets or solids. */
- (void)setSwept:(id)value
{
	self.sprite.swept = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)swept
{
	return @(self.sprite.swept);
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

/** True while pressed against a solid on the left (read-only — wall jumps). */
- (NSNumber *)onWallLeft
{
	return @(self.sprite.wallSide < 0);
}

/** True while pressed against a solid on the right (read-only — wall jumps). */
- (NSNumber *)onWallRight
{
	return @(self.sprite.wallSide > 0);
}

/** As a solid: riders only land on the top edge — they jump up
 *  through it and are never blocked sideways (pass-through floors). */
- (void)setOneWay:(id)value
{
	self.sprite.oneWay = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)oneWay
{
	return @(self.sprite.oneWay);
}

/** As a solid: 'block' (default, immovable wall), 'contain' (inward
 *  circular boundary — matched circles are kept inside it) or 'push' (a
 *  body in its own right: a matched circle and this one share the
 *  separation and exchange momentum). The last two are circle-on-circle
 *  only; anything else falls back to 'block'. */
- (void)setSolidMode:(id)value
{
	NSString *mode = [TiUtils stringValue:value];
	if ([@"contain" isEqualToString:mode]) {
		self.sprite.solidMode = TGSolidContain;
	} else if ([@"push" isEqualToString:mode]) {
		self.sprite.solidMode = TGSolidPush;
	} else {
		self.sprite.solidMode = TGSolidBlock; // unknown values behave like today
	}
}

- (NSString *)solidMode
{
	switch (self.sprite.solidMode) {
		case TGSolidContain:
			return @"contain";
		case TGSolidPush:
			return @"push";
		default:
			return @"block";
	}
}

/** Fraction of speed shed per second to the surface (0 = none, the
 *  default). Rolling friction for ordinary sprites — `drag` only ever
 *  worked inside carMode. Stopped outright below 4 px/s. */
- (void)setLinearDamping:(id)value
{
	self.sprite.linearDamping = MAX(0.0f, [TiUtils floatValue:value def:0.0f]);
}

- (NSNumber *)linearDamping
{
	return @(self.sprite.linearDamping);
}

/** As a solid: whether riders inherit this sprite's movement (moving
 *  platforms; default YES). Set false for world-scroll terrain that
 *  moves under a player who's meant to stay put (endless runners). */
- (void)setCarryRiders:(id)value
{
	self.sprite.carryRiders = [TiUtils boolValue:value def:YES];
}

- (NSNumber *)carryRiders
{
	return @(self.sprite.carryRiders);
}

- (void)setRestitution:(id)value
{
	self.sprite.restitution = [TGValues ratio:value fallback:0];
}

- (NSNumber *)restitution
{
	return @(self.sprite.restitution);
}

/** Max fall speed (px/s) while pressed against a wall; 0 = no wall slide. */
- (void)setWallSlideSpeed:(id)value
{
	self.sprite.wallSlideSpeed = MAX(0.0f, [TiUtils floatValue:value def:0]);
}

- (NSNumber *)wallSlideSpeed
{
	return @(self.sprite.wallSlideSpeed);
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

/** sprite.play('attack', { then: 'idle' }) chains natively: as each
 *  non-looping animation finishes, the next queued name plays without
 *  a round-trip through an animationcomplete handler. `then` accepts
 *  a name or an array of names; animationcomplete still fires per
 *  finished animation. */
- (NSNumber *)play:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[ args ];
	NSString *name = (list.count > 0) ? [TiUtils stringValue:list[0]] : nil;
	NSMutableArray<NSString *> *chain = nil;
	if (list.count > 1 && [list[1] isKindOfClass:[NSDictionary class]]) {
		id then = ((NSDictionary *)list[1])[@"then"];
		if ([then isKindOfClass:[NSArray class]]) {
			chain = [NSMutableArray array];
			for (id next in (NSArray *)then) {
				[chain addObject:[TiUtils stringValue:next]];
			}
		} else if (then != nil) {
			chain = [NSMutableArray arrayWithObject:[TiUtils stringValue:then]];
		}
	}
	if (name == nil || ![self.sprite play:name then:chain]) {
		NSLog(@"[WARN] Unknown animation: %@", name);
		return @NO;
	}
	return @YES;
}

- (void)stop:(id)unused
{
	[self.sprite stopAnimation];
}

/** Damage/invincibility flash: fills the sprite's silhouette with a
 *  color (default white) and fades it out over a duration in ms
 *  (default 150). sprite.flash('#f00', 300) — both args optional;
 *  runs natively, calling again restarts it. */
- (void)flash:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	float fr = 1.0f, fg = 1.0f, fb = 1.0f;
	TiColor *tiColor = (list.count > 0) ? [TiUtils colorValue:list[0]] : nil;
	if (tiColor != nil) {
		CGFloat r = 1, g = 1, b = 1, a = 1;
		[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
		fr = (float)r;
		fg = (float)g;
		fb = (float)b;
	}
	self.sprite.flashR = fr;
	self.sprite.flashG = fg;
	self.sprite.flashB = fb;
	float seconds = ((list.count > 1) ? [TiUtils floatValue:list[1] def:150] : 150.0f) / 1000.0f;
	self.sprite.flashDuration = seconds;
	self.sprite.flashRemaining = seconds;
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
	if (options[@"frame"] != nil) {
		tween.endFrame = @([TiUtils intValue:options[@"frame"] def:0]);
	}
	[self.sprite addTween:tween];
}

- (void)clearTweens:(id)unused
{
	[self.sprite clearTweens];
}

#pragma mark Path following

/**
 * sprite.followPath(points, { speed, loop, rotate, smoothing }):
 * walks the sprite along the points (array of {x, y} objects or
 * [x, y] pairs) natively at `speed` px/s (default 100). `loop` runs
 * the path as a closed circuit; `rotate` turns the sprite to face
 * along the path (0 = up); `smoothing` rounds corners with that
 * radius in px. Fires 'pathcomplete' when a non-looping run ends.
 * followPath(null) stops following in place.
 */
- (void)followPath:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	id points = (list.count > 0) ? list[0] : nil;
	if (![points isKindOfClass:[NSArray class]]) {
		self.sprite.path = nil;
		return;
	}
	NSArray *raw = points;
	float *xs = malloc(sizeof(float) * MAX(raw.count, 1));
	float *ys = malloc(sizeof(float) * MAX(raw.count, 1));
	int count = 0;
	for (id point in raw) {
		if ([point isKindOfClass:[NSDictionary class]]) {
			xs[count] = [TiUtils floatValue:((NSDictionary *)point)[@"x"] def:0];
			ys[count] = [TiUtils floatValue:((NSDictionary *)point)[@"y"] def:0];
			count++;
		} else if ([point isKindOfClass:[NSArray class]] && ((NSArray *)point).count >= 2) {
			xs[count] = [TiUtils floatValue:((NSArray *)point)[0] def:0];
			ys[count] = [TiUtils floatValue:((NSArray *)point)[1] def:0];
			count++;
		}
	}
	if (count < 2) {
		NSLog(@"[WARN] followPath needs at least two points");
		self.sprite.path = nil;
	} else {
		NSDictionary *options = (list.count > 1 && [list[1] isKindOfClass:[NSDictionary class]])
			? list[1] : nil;
		self.sprite.path = [TGPath buildWithPointsX:xs y:ys count:count
										  smoothing:[TiUtils floatValue:options[@"smoothing"] def:0]
											   loop:[TiUtils boolValue:options[@"loop"] def:NO]
											 rotate:[TiUtils boolValue:options[@"rotate"] def:NO]
											  speed:[TiUtils floatValue:options[@"speed"] def:100]];
	}
	free(xs);
	free(ys);
}

#pragma mark Attachment

/**
 * sprite.attachTo(target, { offsetX: 0, offsetY: -40, rotate: false }):
 * pins this sprite to another sprite natively — see the Android twin
 * for the full contract (offset in the sprite's own space, rotate
 * swings the offset and copies the target's rotation, drags win while
 * the finger is down, cross-space attach converts automatically).
 * attachTo(null) detaches. The target's opacity multiplies into
 * attached sprites (fades cascade). Removing the target from the scene
 * also removes every sprite attached to it (recursively).
 */
- (void)attachTo:(id)args
{
	id first = [args isKindOfClass:[NSArray class]] ? [args firstObject] : args;
	if (![first isKindOfClass:[TiGameSpriteProxy class]] || first == self) {
		self.sprite.attachTarget = nil;
		self.sprite.attachOpacity = 1.0f;
		return;
	}
	NSDictionary *options = ([args isKindOfClass:[NSArray class]] && [args count] > 1
		&& [args[1] isKindOfClass:[NSDictionary class]]) ? args[1] : nil;
	self.sprite.attachOffsetX = [TiUtils floatValue:options[@"offsetX"] def:0];
	self.sprite.attachOffsetY = [TiUtils floatValue:options[@"offsetY"] def:0];
	self.sprite.attachRotate = [TiUtils boolValue:options[@"rotate"] def:NO];
	self.sprite.attachTarget = [(TiGameSpriteProxy *)first sprite];
}

/** Releases the sprite where it is; x/y are writable again. */
- (void)detach:(id)unused
{
	self.sprite.attachTarget = nil;
	self.sprite.attachOpacity = 1.0f;
}

- (id)attachedTo
{
	TiProxy *proxy = self.sprite.attachTarget.proxy;
	return [proxy isKindOfClass:[TiGameSpriteProxy class]] ? proxy : nil;
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

- (void)spritePathComplete:(TGSprite *)s
{
	if ([self _hasListeners:@"pathcomplete"]) {
		[self fireEvent:@"pathcomplete" withObject:@{
			@"x": @(s.x),
			@"y": @(s.y)
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

- (void)sprite:(TGSprite *)s separatedFrom:(TGSprite *)other
{
	if ([self _hasListeners:@"collisionend"]) {
		NSMutableDictionary *data = [NSMutableDictionary dictionary];
		data[@"group"] = other.collisionGroup;
		data[@"other"] = other.proxy;
		data[@"x"] = @(s.x);
		data[@"y"] = @(s.y);
		[self fireEvent:@"collisionend" withObject:data];
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

- (void)sprite:(TGSprite *)s hitWall:(TGSprite *)solid side:(NSInteger)side
{
	if ([self _hasListeners:@"wallhit"]) {
		NSMutableDictionary *data = [NSMutableDictionary dictionary];
		data[@"side"] = (side < 0) ? @"left" : @"right";
		data[@"x"] = @(s.x);
		data[@"y"] = @(s.y);
		if (solid != nil) {
			data[@"other"] = solid.proxy;
			data[@"group"] = solid.collisionGroup;
		}
		[self fireEvent:@"wallhit" withObject:data];
	}
}

@end
