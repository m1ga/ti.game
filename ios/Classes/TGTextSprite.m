#import "TGTextSprite.h"
#import "TGBitmapFont.h"
#import "TGSpriteSheet.h"

@implementation TGTextLayout {
	NSData *_quadData;
	NSData *_frameData;
}

- (instancetype)initWithCount:(int)count
					 quadData:(NSData *)quadData
					frameData:(NSData *)frameData
						width:(float)width
					   height:(float)height
{
	if (self = [super init]) {
		_count = count;
		_quadData = quadData;
		_frameData = frameData;
		_width = width;
		_height = height;
	}
	return self;
}

- (const float *)quads
{
	return (const float *)_quadData.bytes;
}

- (const int *)frameIndices
{
	return (const int *)_frameData.bytes;
}

@end

@implementation TGTextSprite {
	NSString *_text;             // guarded by @synchronized(self)
	TGTextAlign _align;
	float _letterSpacing;
	float _lineSpacing;
	float _maxWidth;             // wrap width in px, 0 = no wrap
	TGTextLayout *_layout;       // nil = dirty
}

- (instancetype)init
{
	if (self = [super init]) {
		_text = @"";
		_lineSpacing = 1.0f;
	}
	return self;
}

- (NSString *)text
{
	@synchronized (self) {
		return _text;
	}
}

- (void)setText:(NSString *)text
{
	@synchronized (self) {
		_text = [text copy] ?: @"";
		_layout = nil;
	}
}

- (TGTextAlign)align
{
	@synchronized (self) {
		return _align;
	}
}

- (void)setAlign:(TGTextAlign)align
{
	@synchronized (self) {
		_align = align;
		_layout = nil;
	}
}

- (float)letterSpacing
{
	@synchronized (self) {
		return _letterSpacing;
	}
}

- (void)setLetterSpacing:(float)letterSpacing
{
	@synchronized (self) {
		_letterSpacing = letterSpacing;
		_layout = nil;
	}
}

- (float)lineSpacing
{
	@synchronized (self) {
		return _lineSpacing;
	}
}

- (void)setLineSpacing:(float)lineSpacing
{
	@synchronized (self) {
		_lineSpacing = lineSpacing;
		_layout = nil;
	}
}

- (float)maxWidth
{
	@synchronized (self) {
		return _maxWidth;
	}
}

- (void)setMaxWidth:(float)maxWidth
{
	@synchronized (self) {
		_maxWidth = MAX(0.0f, maxWidth);
		_layout = nil;
	}
}

- (void)setTextFont:(TGBitmapFont *)font
{
	@synchronized (self) {
		self.font = font;
		self.sheet = font.sheet; // renderer's lazy texture upload
		_layout = nil;
	}
}

// Layout bounds drive everything TGSprite derives from its frame size:
// anchor placement, hit-testing, AABBs, ySort's bottom edge.
- (float)drawWidth
{
	return [self layout].width;
}

- (float)drawHeight
{
	return [self layout].height;
}

- (TGTextLayout *)layout
{
	@synchronized (self) {
		if (_layout == nil) {
			_layout = [self buildLayout];
		}
		return _layout;
	}
}

/** Called under @synchronized(self). */
- (TGTextLayout *)buildLayout
{
	TGBitmapFont *font = self.font;
	NSString *text = _text;
	if (font == nil || text.length == 0 || font.lineHeight <= 0.0f) {
		return [[TGTextLayout alloc] initWithCount:0
										  quadData:[NSData data]
										 frameData:[NSData data]
											 width:0.0f
											height:0.0f];
	}
	float spacing = _letterSpacing;
	float lineStep = font.lineHeight * _lineSpacing;
	NSArray<NSString *> *lines = [self wrapLines:text font:font spacing:spacing];

	// First pass: place every line at x = 0 and remember its width
	NSMutableData *quadData = [NSMutableData data];
	NSMutableData *frameData = [NSMutableData data];
	NSUInteger lineCount = lines.count;
	int *lineGlyphCount = calloc(lineCount, sizeof(int));
	float *lineWidth = calloc(lineCount, sizeof(float));
	float blockWidth = 0.0f;
	for (NSUInteger i = 0; i < lineCount; i++) {
		NSString *line = lines[i];
		float lineTop = i * lineStep;
		float pen = 0.0f;
		int prev = -1;
		int glyphCount = 0;
		for (NSUInteger c = 0; c < line.length; c++) {
			int ch = [line characterAtIndex:c];
			TGGlyph g;
			if (![font glyphForCharacter:ch into:&g]) {
				pen += [font missingAdvance] + spacing;
				prev = -1;
				continue;
			}
			if (prev >= 0) {
				pen += [font kernFirst:prev second:ch];
			}
			if (g.width > 0.0f && g.height > 0.0f) {
				float quad[4] = { pen + g.xOffset, lineTop + g.yOffset, g.width, g.height };
				[quadData appendBytes:quad length:sizeof(quad)];
				[frameData appendBytes:&g.frameIndex length:sizeof(int)];
				glyphCount++;
			}
			pen += g.xAdvance + spacing;
			prev = ch;
		}
		float width = (line.length > 0) ? pen - spacing : 0.0f;
		lineGlyphCount[i] = glyphCount;
		lineWidth[i] = MAX(0.0f, width);
		blockWidth = MAX(blockWidth, lineWidth[i]);
	}

	// Second pass: shift each line's glyphs by its alignment offset
	if (_align != TGTextAlignLeft) {
		float *quads = (float *)quadData.mutableBytes;
		int quadIndex = 0;
		for (NSUInteger i = 0; i < lineCount; i++) {
			float shift = blockWidth - lineWidth[i];
			if (_align == TGTextAlignCenter) {
				shift *= 0.5f;
			}
			for (int q = 0; q < lineGlyphCount[i]; q++) {
				quads[quadIndex * 4] += shift;
				quadIndex++;
			}
		}
	}
	free(lineGlyphCount);
	free(lineWidth);

	int count = (int)(frameData.length / sizeof(int));
	float blockHeight = (lineCount - 1) * lineStep + font.lineHeight;
	return [[TGTextLayout alloc] initWithCount:count
									  quadData:quadData
									 frameData:frameData
										 width:blockWidth
										height:blockHeight];
}

/**
 * Splits the text into layout lines: hard breaks on '\n', plus soft
 * breaks on word boundaries when maxWidth is set. Widths use the same
 * pen simulation as layout (kerning, letterSpacing, missing-glyph
 * advance), so a wrapped line never renders wider than it measured;
 * the spaces around a soft break are dropped. A single word wider
 * than maxWidth overflows rather than breaking mid-word.
 * Called under @synchronized(self).
 */
- (NSArray<NSString *> *)wrapLines:(NSString *)text font:(TGBitmapFont *)font spacing:(float)spacing
{
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	float limit = _maxWidth;
	for (NSString *hard in [text componentsSeparatedByString:@"\n"]) {
		if (limit <= 0.0f) {
			[lines addObject:hard];
			continue;
		}
		NSUInteger length = hard.length;
		NSUInteger start = 0;
		NSInteger lastSpace = -1; // break candidate: last space after a word
		BOOL wordSeen = NO;
		float pen = 0.0f;
		int prev = -1;
		for (NSUInteger c = 0; c < length; c++) {
			int ch = [hard characterAtIndex:c];
			TGGlyph g;
			if (![font glyphForCharacter:ch into:&g]) {
				pen += [font missingAdvance] + spacing;
				prev = -1;
			} else {
				if (prev >= 0) {
					pen += [font kernFirst:prev second:ch];
				}
				pen += g.xAdvance + spacing;
				prev = ch;
			}
			if (ch == ' ') {
				if (wordSeen) {
					lastSpace = (NSInteger)c;
				}
			} else {
				wordSeen = YES;
			}
			if (pen - spacing > limit && lastSpace >= 0) {
				NSUInteger end = (NSUInteger)lastSpace;
				while (end > start && [hard characterAtIndex:end - 1] == ' ') {
					end--;
				}
				[lines addObject:[hard substringWithRange:NSMakeRange(start, end - start)]];
				start = (NSUInteger)lastSpace + 1;
				while (start < length && [hard characterAtIndex:start] == ' ') {
					start++;
				}
				c = start - 1; // loop increment re-enters at the new start
				lastSpace = -1;
				wordSeen = NO;
				pen = 0.0f;
				prev = -1;
			}
		}
		if (start == 0 || start < length) {
			[lines addObject:[hard substringFromIndex:start]];
		}
	}
	return lines;
}

@end
