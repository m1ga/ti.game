#import "TiGameRopeProxy.h"
#import "TGSprite.h"
#import "TiGameSpriteProxy.h"
#import "TiGameSpriteSheetProxy.h"

@implementation TiGameRopeProxy {
	TiGameSpriteSheetProxy *_sheetProxy;
	TiGameSpriteProxy *_headProxy;
	TiGameSpriteProxy *_tailProxy;
}

- (instancetype)init
{
	if (self = [super init]) {
		_rope = [[TGRope alloc] init];
	}
	return self;
}

- (NSString *)apiName
{
	return @"ti.game.Rope";
}

#pragma mark Sheet / anchors

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
	self.rope.sheet = newSheet.sheet;
}

- (id)sheet
{
	return _sheetProxy;
}

/** Pin the head to this sprite (null = use the fixed x/y anchor). */
- (void)setHead:(id)value
{
	TiGameSpriteProxy *newHead =
		[value isKindOfClass:[TiGameSpriteProxy class]] ? value : nil;
	if (_headProxy != nil) {
		[self forgetProxy:_headProxy];
	}
	_headProxy = newHead;
	if (newHead != nil) {
		[self rememberProxy:newHead];
	}
	self.rope.head = newHead.sprite;
}

- (id)head
{
	return _headProxy;
}

/** Pin the loose end to this sprite too (bridges); null = free. */
- (void)setTail:(id)value
{
	TiGameSpriteProxy *newTail =
		[value isKindOfClass:[TiGameSpriteProxy class]] ? value : nil;
	if (_tailProxy != nil) {
		[self forgetProxy:_tailProxy];
	}
	_tailProxy = newTail;
	if (newTail != nil) {
		[self rememberProxy:newTail];
	}
	self.rope.tail = newTail.sprite;
}

- (id)tail
{
	return _tailProxy;
}

#pragma mark Configuration

- (void)setFrame:(id)value
{
	self.rope.frame = [TiUtils intValue:value def:0];
}

- (NSNumber *)frame
{
	return @(self.rope.frame);
}

- (void)setSegments:(id)value
{
	self.rope.segments = [TiUtils intValue:value def:10];
}

- (NSNumber *)segments
{
	return @(self.rope.segments);
}

- (void)setSegmentLength:(id)value
{
	self.rope.segmentLength = [TiUtils floatValue:value def:30];
}

- (NSNumber *)segmentLength
{
	return @(self.rope.segmentLength);
}

- (void)setThickness:(id)value
{
	self.rope.thickness = [TiUtils floatValue:value def:10];
}

- (NSNumber *)thickness
{
	return @(self.rope.thickness);
}

- (void)setGravity:(id)value
{
	self.rope.gravity = [TiUtils floatValue:value def:1500];
}

- (NSNumber *)gravity
{
	return @(self.rope.gravity);
}

- (void)setDamping:(id)value
{
	self.rope.damping = [TiUtils floatValue:value def:0.98f];
}

- (NSNumber *)damping
{
	return @(self.rope.damping);
}

- (void)setIterations:(id)value
{
	self.rope.iterations = [TiUtils intValue:value def:3];
}

- (NSNumber *)iterations
{
	return @(self.rope.iterations);
}

- (void)setZIndex:(id)value
{
	self.rope.zIndex = [TiUtils intValue:value def:0];
}

- (NSNumber *)zIndex
{
	return @(self.rope.zIndex);
}

- (void)setVisible:(id)value
{
	self.rope.visible = [TiUtils boolValue:value def:YES];
}

- (NSNumber *)visible
{
	return @(self.rope.visible);
}

- (void)setX:(id)value
{
	self.rope.x = [TiUtils floatValue:value def:0];
}

- (NSNumber *)x
{
	return @(self.rope.x);
}

- (void)setY:(id)value
{
	self.rope.y = [TiUtils floatValue:value def:0];
}

- (NSNumber *)y
{
	return @(self.rope.y);
}

/** Live position of the loose end (read-only). */
- (NSNumber *)endX
{
	return @(self.rope.endX);
}

- (NSNumber *)endY
{
	return @(self.rope.endY);
}

@end
