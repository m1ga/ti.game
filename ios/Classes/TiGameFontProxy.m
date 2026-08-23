#import "TiGameFontProxy.h"
#import "TGBitmapFont.h"
#import "TGDefaultFont.h"

@implementation TiGameFontProxy {
	NSString *_imagePath;
}

- (NSString *)apiName
{
	return @"ti.game.Font";
}

static NSString *defaultCharacters(void)
{
	NSMutableString *characters = [NSMutableString string];
	for (unichar c = 32; c < 127; c++) {
		[characters appendFormat:@"%C", c];
	}
	return characters;
}

- (void)_initWithProperties:(NSDictionary *)properties
{
	NSString *fontPath = [TiUtils stringValue:properties[@"font"]];
	_imagePath = [TiUtils stringValue:properties[@"image"]];

	if (fontPath != nil) {
		[self parseBmfont:fontPath];
	} else if (_imagePath != nil) {
		float charWidth = [TiUtils floatValue:properties[@"charWidth"] def:0];
		float charHeight = [TiUtils floatValue:properties[@"charHeight"] def:0];
		if (charWidth <= 0 || charHeight <= 0) {
			NSLog(@"[ERROR] Grid fonts need charWidth and charHeight");
			_font = [TGDefaultFont makeFont];
		} else {
			NSString *characters = [TiUtils stringValue:properties[@"characters"]]
				?: defaultCharacters();
			TGSpriteSheet *sheet = [[TGSpriteSheet alloc] initWithLoader:self
															gridFrameWidth:(int)charWidth
														   gridFrameHeight:(int)charHeight];
			_font = [TGBitmapFont gridFontWithSheet:sheet
										 characters:characters
										  charWidth:charWidth
										 charHeight:charHeight];
		}
	} else {
		// Built-in pixel font — always crisp, no options to apply
		_font = [TGDefaultFont makeFont];
		[super _initWithProperties:properties];
		return;
	}
	if (properties[@"smoothing"] != nil) {
		_font.sheet.smoothing = [TiUtils boolValue:properties[@"smoothing"] def:YES];
	}
	[super _initWithProperties:properties];
}

/** Parses a BMFont descriptor — the AngelCode text format or its JSON export. */
- (void)parseBmfont:(NSString *)fontPath
{
	NSURL *url = [TiUtils toURL:fontPath proxy:self];
	NSData *data = (url != nil) ? [NSData dataWithContentsOfURL:url] : nil;
	NSString *source = (data != nil)
		? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
	if (source == nil) {
		NSLog(@"[ERROR] Could not read font '%@'", fontPath);
		_font = [TGDefaultFont makeFont];
		return;
	}
	TGSpriteSheet *sheet = [[TGSpriteSheet alloc] initWithLoader:self
												  gridFrameWidth:0
												 gridFrameHeight:0];
	_font = [[TGBitmapFont alloc] initWithSheet:sheet];
	NSString *trimmed = [source stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *pageFile = [trimmed hasPrefix:@"{"]
		? [self parseJson:data] : [self parseText:source];
	if (_imagePath == nil && pageFile != nil) {
		// page images live next to the descriptor
		NSRange slash = [fontPath rangeOfString:@"/" options:NSBackwardsSearch];
		_imagePath = (slash.location != NSNotFound)
			? [[fontPath substringToIndex:slash.location + 1] stringByAppendingString:pageFile]
			: pageFile;
	}
}

/** AngelCode text format: one `tag key=value ...` line per entry. */
- (NSString *)parseText:(NSString *)source
{
	float scaleW = 1.0f;
	float scaleH = 1.0f;
	NSString *pageFile = nil;
	NSMutableDictionary<NSNumber *, NSValue *> *glyphs = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSNumber *, NSNumber *> *kerning = [NSMutableDictionary dictionary];
	NSMutableData *frameData = [NSMutableData data];
	int frameCount = 0;
	for (NSString *line in [source componentsSeparatedByString:@"\n"]) {
		NSDictionary<NSString *, NSString *> *fields = parseFields(line);
		if ([line hasPrefix:@"common "]) {
			_font.lineHeight = intField(fields, @"lineHeight", 0);
			scaleW = MAX(1, intField(fields, @"scaleW", 1));
			scaleH = MAX(1, intField(fields, @"scaleH", 1));
		} else if ([line hasPrefix:@"page "] && pageFile == nil) {
			pageFile = fields[@"file"];
		} else if ([line hasPrefix:@"char "]) {
			int x = intField(fields, @"x", 0);
			int y = intField(fields, @"y", 0);
			int w = intField(fields, @"width", 0);
			int h = intField(fields, @"height", 0);
			appendFontFrame(frameData, x, y, w, h, scaleW, scaleH);
			TGGlyph g;
			g.frameIndex = frameCount++;
			g.width = w;
			g.height = h;
			g.xOffset = intField(fields, @"xoffset", 0);
			g.yOffset = intField(fields, @"yoffset", 0);
			g.xAdvance = intField(fields, @"xadvance", 0);
			glyphs[@(intField(fields, @"id", 0))] =
				[NSValue valueWithBytes:&g objCType:@encode(TGGlyph)];
		} else if ([line hasPrefix:@"kerning "]) {
			int first = intField(fields, @"first", 0);
			int second = intField(fields, @"second", 0);
			if (first <= 0xffff && second <= 0xffff) {
				kerning[@((first << 16) | second)] = @(intField(fields, @"amount", 0));
			}
		}
	}
	[_font.sheet setFrameData:frameData];
	[_font setGlyphs:glyphs];
	[_font setKerning:kerning];
	return pageFile;
}

static NSDictionary<NSString *, NSString *> *parseFields(NSString *line)
{
	NSMutableDictionary<NSString *, NSString *> *fields = [NSMutableDictionary dictionary];
	NSUInteger i = 0;
	NSUInteger length = line.length;
	while (i < length) {
		NSRange eq = [line rangeOfString:@"=" options:0 range:NSMakeRange(i, length - i)];
		if (eq.location == NSNotFound) {
			break;
		}
		NSRange keySpace = [line rangeOfString:@" " options:NSBackwardsSearch
										 range:NSMakeRange(0, eq.location)];
		NSUInteger keyStart = (keySpace.location == NSNotFound) ? 0 : keySpace.location + 1;
		NSString *key = [line substringWithRange:NSMakeRange(keyStart, eq.location - keyStart)];
		NSUInteger valueStart = eq.location + 1;
		NSUInteger valueEnd;
		NSString *value;
		if (valueStart < length && [line characterAtIndex:valueStart] == '"') {
			NSRange quote = [line rangeOfString:@"\"" options:0
										  range:NSMakeRange(valueStart + 1, length - valueStart - 1)];
			valueEnd = (quote.location == NSNotFound) ? length : quote.location;
			value = [line substringWithRange:NSMakeRange(valueStart + 1, valueEnd - valueStart - 1)];
			valueEnd = (quote.location == NSNotFound) ? length : quote.location + 1;
		} else {
			NSRange space = [line rangeOfString:@" " options:0
										  range:NSMakeRange(valueStart, length - valueStart)];
			valueEnd = (space.location == NSNotFound) ? length : space.location;
			value = [line substringWithRange:NSMakeRange(valueStart, valueEnd - valueStart)];
		}
		fields[key] = [value stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		i = valueEnd;
	}
	return fields;
}

static int intField(NSDictionary<NSString *, NSString *> *fields, NSString *key, int fallback)
{
	NSString *value = fields[key];
	return (value.length > 0) ? (int)lroundf(value.floatValue) : fallback;
}

static void appendFontFrame(NSMutableData *frameData, int x, int y, int w, int h,
							float scaleW, float scaleH)
{
	TGFrame f;
	f.u0 = x / scaleW;
	f.v0 = y / scaleH;
	f.u1 = (x + w) / scaleW;
	f.v1 = (y + h) / scaleH;
	f.width = w;
	f.height = h;
	[frameData appendBytes:&f length:sizeof(TGFrame)];
}

/** BMFont JSON export: { common, pages, chars, kernings }. */
- (NSString *)parseJson:(NSData *)data
{
	NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![root isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSDictionary *common = root[@"common"];
	_font.lineHeight = [TiUtils floatValue:common[@"lineHeight"] def:0];
	float scaleW = MAX(1, [TiUtils floatValue:common[@"scaleW"] def:1]);
	float scaleH = MAX(1, [TiUtils floatValue:common[@"scaleH"] def:1]);

	NSMutableDictionary<NSNumber *, NSValue *> *glyphs = [NSMutableDictionary dictionary];
	NSMutableData *frameData = [NSMutableData data];
	int frameCount = 0;
	for (NSDictionary *c in root[@"chars"]) {
		int x = [TiUtils intValue:c[@"x"] def:0];
		int y = [TiUtils intValue:c[@"y"] def:0];
		int w = [TiUtils intValue:c[@"width"] def:0];
		int h = [TiUtils intValue:c[@"height"] def:0];
		appendFontFrame(frameData, x, y, w, h, scaleW, scaleH);
		TGGlyph g;
		g.frameIndex = frameCount++;
		g.width = w;
		g.height = h;
		g.xOffset = [TiUtils intValue:c[@"xoffset"] def:0];
		g.yOffset = [TiUtils intValue:c[@"yoffset"] def:0];
		g.xAdvance = [TiUtils intValue:c[@"xadvance"] def:0];
		glyphs[@([TiUtils intValue:c[@"id"] def:0])] =
			[NSValue valueWithBytes:&g objCType:@encode(TGGlyph)];
	}

	NSMutableDictionary<NSNumber *, NSNumber *> *kerning = [NSMutableDictionary dictionary];
	for (NSDictionary *k in root[@"kernings"]) {
		int first = [TiUtils intValue:k[@"first"] def:0];
		int second = [TiUtils intValue:k[@"second"] def:0];
		if (first <= 0xffff && second <= 0xffff) {
			kerning[@((first << 16) | second)] = @([TiUtils intValue:k[@"amount"] def:0]);
		}
	}
	[_font.sheet setFrameData:frameData];
	[_font setGlyphs:glyphs];
	[_font setKerning:kerning];

	NSArray *pages = root[@"pages"];
	return ([pages isKindOfClass:[NSArray class]] && pages.count > 0)
		? [TiUtils stringValue:pages.firstObject] : nil;
}

#pragma mark TGSpriteSheetLoader — called from the render thread on first use

- (UIImage *)loadSpriteSheet:(TGSpriteSheet *)sheet
{
	if (_imagePath == nil) {
		return nil;
	}
	UIImage *image = [TiUtils image:_imagePath proxy:self];
	if (image == nil) {
		NSLog(@"[ERROR] Could not load font image: %@", _imagePath);
	}
	return image;
}

#pragma mark JS surface

- (NSNumber *)lineHeight
{
	return @(_font.lineHeight);
}

/** Frees the glyph texture on the next rendered frame. Permanent —
 *  text sprites still using this font stop drawing. */
- (void)unload:(id)unused
{
	[_font.sheet dispose];
}

- (void)dealloc
{
	[_font.sheet dispose];
}

@end
