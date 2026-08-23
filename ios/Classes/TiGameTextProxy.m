#import "TiGameTextProxy.h"
#import "TGBitmapFont.h"
#import "TGScene.h"
#import "TGTextSprite.h"
#import "TiGameFontProxy.h"

@implementation TiGameTextProxy {
	TiGameFontProxy *_fontProxy;
}

- (instancetype)init
{
	if (self = [super initWithSprite:[[TGTextSprite alloc] init]]) {
		// No explicit font: the scene assigns its own default-font
		// instance when the sprite is added to a game view.
		((TGTextSprite *)self.sprite).usesDefaultFont = YES;
	}
	return self;
}

- (NSString *)apiName
{
	return @"ti.game.Text";
}

- (TGTextSprite *)textSprite
{
	return (TGTextSprite *)self.sprite;
}

- (void)setFont:(id)value
{
	TiGameFontProxy *newFont =
		[value isKindOfClass:[TiGameFontProxy class]] ? value : nil;
	if (_fontProxy != nil) {
		[self forgetProxy:_fontProxy];
	}
	_fontProxy = newFont;
	if (newFont != nil) {
		[self rememberProxy:newFont];
	}
	TGTextSprite *text = [self textSprite];
	BOOL explicitFont = (newFont.font != nil);
	text.usesDefaultFont = !explicitFont;
	[text setTextFont:explicitFont ? newFont.font : nil];
	if (!explicitFont && text.scene != nil) {
		[text.scene resolveTextFont:text]; // back to the scene's default font
	}
}

- (id)font
{
	return _fontProxy;
}

- (void)setText:(id)value
{
	[[self textSprite] setText:[TiUtils stringValue:value] ?: @""];
}

- (NSString *)text
{
	return [[self textSprite] text];
}

/** 'left' (default), 'center' or 'right' — how multi-line text lines up. */
- (void)setAlign:(id)value
{
	NSString *align = [TiUtils stringValue:value];
	if ([@"center" isEqualToString:align]) {
		[[self textSprite] setAlign:TGTextAlignCenter];
	} else if ([@"right" isEqualToString:align]) {
		[[self textSprite] setAlign:TGTextAlignRight];
	} else {
		[[self textSprite] setAlign:TGTextAlignLeft];
	}
}

- (NSString *)align
{
	switch ([[self textSprite] align]) {
		case TGTextAlignCenter:
			return @"center";
		case TGTextAlignRight:
			return @"right";
		default:
			return @"left";
	}
}

/** Extra px between glyphs (negative tightens). */
- (void)setLetterSpacing:(id)value
{
	[[self textSprite] setLetterSpacing:[TiUtils floatValue:value def:0]];
}

- (NSNumber *)letterSpacing
{
	return @([[self textSprite] letterSpacing]);
}

/** Multiplier on the font's line height (1 = default leading). */
- (void)setLineSpacing:(id)value
{
	[[self textSprite] setLineSpacing:[TiUtils floatValue:value def:1]];
}

- (NSNumber *)lineSpacing
{
	return @([[self textSprite] lineSpacing]);
}

/** Wrap width in px — lines break on word boundaries (0 = no wrap). */
- (void)setMaxWidth:(id)value
{
	[[self textSprite] setMaxWidth:[TiUtils floatValue:value def:0]];
}

- (NSNumber *)maxWidth
{
	return @([[self textSprite] maxWidth]);
}

@end
