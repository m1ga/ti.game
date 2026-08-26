#import "TiGameEmitterProxy.h"
#import "TGSprite.h"
#import "TiGameSpriteProxy.h"
#import "TiGameSpriteSheetProxy.h"
#import "TGValues.h"

@implementation TiGameEmitterProxy {
	TiGameSpriteSheetProxy *_sheetProxy;
	TiGameSpriteProxy *_targetProxy;
}

- (instancetype)init
{
	if (self = [super init]) {
		_emitter = [[TGParticleEmitter alloc] init];
	}
	return self;
}

- (NSString *)apiName
{
	return @"ti.game.Emitter";
}

#pragma mark Methods

/** One-shot burst of n particles (explosions), independent of `rate`. */
- (void)emit:(id)args
{
	ENSURE_SINGLE_ARG(args, NSNumber);
	[self.emitter emit:[TiUtils intValue:args def:0]];
}

/** Kills all live particles. */
- (void)clear:(id)unused
{
	[self.emitter clearParticles];
}

#pragma mark Sheet / target

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
	self.emitter.sheet = newSheet.sheet;
}

- (id)sheet
{
	return _sheetProxy;
}

/** Follow this sprite instead of the fixed x/y (null to detach). */
- (void)setTarget:(id)value
{
	TiGameSpriteProxy *newTarget =
		[value isKindOfClass:[TiGameSpriteProxy class]] ? value : nil;
	if (_targetProxy != nil) {
		[self forgetProxy:_targetProxy];
	}
	_targetProxy = newTarget;
	if (newTarget != nil) {
		[self rememberProxy:newTarget];
	}
	self.emitter.target = newTarget.sprite;
}

- (id)target
{
	return _targetProxy;
}

#pragma mark Configuration properties

- (void)setFrame:(id)value
{
	self.emitter.frame = [TiUtils intValue:value def:0];
}

- (NSNumber *)frame
{
	return @(self.emitter.frame);
}

- (void)setX:(id)value
{
	self.emitter.x = [TiUtils floatValue:value def:0];
}

- (NSNumber *)x
{
	return @(self.emitter.x);
}

- (void)setY:(id)value
{
	self.emitter.y = [TiUtils floatValue:value def:0];
}

- (NSNumber *)y
{
	return @(self.emitter.y);
}

- (void)setOffsetX:(id)value
{
	self.emitter.offsetX = [TiUtils floatValue:value def:0];
}

- (NSNumber *)offsetX
{
	return @(self.emitter.offsetX);
}

- (void)setOffsetY:(id)value
{
	self.emitter.offsetY = [TiUtils floatValue:value def:0];
}

- (NSNumber *)offsetY
{
	return @(self.emitter.offsetY);
}

- (void)setZIndex:(id)value
{
	self.emitter.zIndex = [TiUtils intValue:value def:0];
}

- (NSNumber *)zIndex
{
	return @(self.emitter.zIndex);
}

- (void)setRate:(id)value
{
	self.emitter.rate = [TiUtils floatValue:value def:0];
}

- (NSNumber *)rate
{
	return @(self.emitter.rate);
}

- (void)setLifetime:(id)value
{
	self.emitter.lifetime = [TiUtils floatValue:value def:800] / 1000.0f;
}

- (NSNumber *)lifetime
{
	return @(self.emitter.lifetime * 1000.0f);
}

- (void)setSpeed:(id)value
{
	self.emitter.speed = [TiUtils floatValue:value def:100];
}

- (NSNumber *)speed
{
	return @(self.emitter.speed);
}

- (void)setAngle:(id)value
{
	self.emitter.angle = [TiUtils floatValue:value def:0];
}

- (NSNumber *)angle
{
	return @(self.emitter.angle);
}

- (void)setSpread:(id)value
{
	self.emitter.spread = [TiUtils floatValue:value def:360];
}

- (NSNumber *)spread
{
	return @(self.emitter.spread);
}

- (void)setGravity:(id)value
{
	self.emitter.gravity = [TiUtils floatValue:value def:0];
}

- (NSNumber *)gravity
{
	return @(self.emitter.gravity);
}

- (void)setSize:(id)value
{
	self.emitter.size = [TiUtils floatValue:value def:0];
}

- (NSNumber *)size
{
	return @(self.emitter.size);
}

- (void)setStartScale:(id)value
{
	self.emitter.startScale = [TGValues ratio:value fallback:1];
}

- (NSNumber *)startScale
{
	return @(self.emitter.startScale);
}

- (void)setEndScale:(id)value
{
	self.emitter.endScale = [TGValues ratio:value fallback:1];
}

- (NSNumber *)endScale
{
	return @(self.emitter.endScale);
}

- (void)setStartOpacity:(id)value
{
	self.emitter.startOpacity = [TGValues ratio:value fallback:1];
}

- (NSNumber *)startOpacity
{
	return @(self.emitter.startOpacity);
}

- (void)setEndOpacity:(id)value
{
	self.emitter.endOpacity = [TGValues ratio:value fallback:0];
}

- (NSNumber *)endOpacity
{
	return @(self.emitter.endOpacity);
}

- (void)setTint:(id)value
{
	TiColor *tiColor = [TiUtils colorValue:value];
	if (tiColor == nil) {
		self.emitter.tintR = 1.0f;
		self.emitter.tintG = 1.0f;
		self.emitter.tintB = 1.0f;
		return;
	}
	CGFloat r = 1, g = 1, b = 1, a = 1;
	[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
	self.emitter.tintR = (float)r;
	self.emitter.tintG = (float)g;
	self.emitter.tintB = (float)b;
}

/** 'add' = particles brighten instead of cover (fire, sparks, magic),
 *  'multiply' darkens (smoke, dust), 'screen' lightens softly; anything
 *  else = normal alpha blending. */
- (void)setBlend:(id)value
{
	self.emitter.blendMode = TGBlendModeFromString([TiUtils stringValue:value]);
}

- (NSString *)blend
{
	return TGBlendModeName(self.emitter.blendMode);
}

- (void)setEmitting:(id)value
{
	self.emitter.emitting = [TiUtils boolValue:value def:YES];
}

- (NSNumber *)emitting
{
	return @(self.emitter.emitting);
}

- (void)setMaxParticles:(id)value
{
	self.emitter.maxParticles = [TiUtils intValue:value def:200];
}

- (NSNumber *)maxParticles
{
	return @(self.emitter.maxParticles);
}

@end
