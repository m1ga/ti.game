#import "TGBitmapFont.h"
#import "TGSpriteSheet.h"

@implementation TGBitmapFont {
	// Immutable after publication, replaced atomically as a whole
	NSDictionary<NSNumber *, NSValue *> *_glyphs;
	NSDictionary<NSNumber *, NSNumber *> *_kerning;
}

- (instancetype)initWithSheet:(TGSpriteSheet *)sheet
{
	if (self = [super init]) {
		_sheet = sheet;
		_glyphs = @{};
	}
	return self;
}

- (void)setGlyphs:(NSDictionary<NSNumber *, NSValue *> *)glyphs
{
	@synchronized (self) {
		_glyphs = [glyphs copy] ?: @{};
	}
}

- (void)setKerning:(NSDictionary<NSNumber *, NSNumber *> *)kerning
{
	@synchronized (self) {
		_kerning = (kerning.count > 0) ? [kerning copy] : nil;
	}
}

- (BOOL)glyphForCharacter:(int)character into:(TGGlyph *)out
{
	NSValue *value;
	@synchronized (self) {
		value = _glyphs[@(character)];
	}
	if (value == nil) {
		return NO;
	}
	[value getValue:out];
	return YES;
}

- (float)kernFirst:(int)first second:(int)second
{
	if (first > 0xffff || second > 0xffff) {
		return 0.0f;
	}
	NSNumber *amount;
	@synchronized (self) {
		amount = _kerning[@((first << 16) | second)];
	}
	return (amount != nil) ? amount.floatValue : 0.0f;
}

- (float)missingAdvance
{
	TGGlyph space;
	if ([self glyphForCharacter:' ' into:&space]) {
		return space.xAdvance;
	}
	return self.lineHeight * 0.4f;
}

+ (TGBitmapFont *)gridFontWithSheet:(TGSpriteSheet *)sheet
						 characters:(NSString *)characters
						  charWidth:(float)charWidth
						 charHeight:(float)charHeight
{
	TGBitmapFont *font = [[TGBitmapFont alloc] initWithSheet:sheet];
	font.lineHeight = charHeight;
	NSMutableDictionary<NSNumber *, NSValue *> *glyphs = [NSMutableDictionary dictionary];
	for (NSUInteger i = 0; i < characters.length; i++) {
		TGGlyph g;
		g.frameIndex = (int)i;
		g.width = charWidth;
		g.height = charHeight;
		g.xOffset = 0.0f;
		g.yOffset = 0.0f;
		g.xAdvance = charWidth;
		glyphs[@([characters characterAtIndex:i])] =
			[NSValue valueWithBytes:&g objCType:@encode(TGGlyph)];
	}
	[font setGlyphs:glyphs];
	return font;
}

@end
