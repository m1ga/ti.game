#import "TGDebugHud.h"
#import "TGScreenOverlay.h"
#import "TGBitmapFont.h"
#import "TGSpriteSheet.h"
#import "TGSpriteBatch.h"

static const NSUInteger kColumns = 3;
static const NSUInteger kMaxRows = 6;

// Layout in points, multiplied by the screen scale — except the glyphs,
// which step in whole multiples of the font's native size. A pixel font at
// a fractional scale is a blurry pixel font.
static const float kRowGap = 5.0f;
static const float kColumnGap = 9.0f;
static const float kPadding = 5.0f;
static const float kMargin = 8.0f;

/**
 * Cross-thread state, atomic for the same reason the Android twin marks
 * these fields volatile: the render thread lays the panel out, the main
 * thread hit-tests it, the JS thread flips it open.
 */
@interface TGDebugHud ()
@property (atomic, assign) BOOL expanded;
@property (atomic, assign) float rectX;
@property (atomic, assign) float rectY;
@property (atomic, assign) float rectWidth;
@property (atomic, assign) float rectHeight;
@end

@implementation TGDebugHud {
	// --- Render thread only ---------------------------------------------
	NSMutableArray<NSMutableArray<NSString *> *> *_columns;
	float _columnWidths[kColumns];
	float _origin[2];
	TGFrameStatsSnapshot _latest;
	BOOL _hasData;
	BOOL _builtExpanded;
}

- (instancetype)init
{
	if (self = [super init]) {
		_corner = TGOverlayCornerTopLeft;
		_columns = [NSMutableArray arrayWithCapacity:kColumns];
		for (NSUInteger c = 0; c < kColumns; c++) {
			[_columns addObject:[NSMutableArray arrayWithCapacity:kMaxRows]];
		}
	}
	return self;
}

- (BOOL)isExpanded
{
	return self.expanded;
}

- (void)toggleExpanded
{
	self.expanded = !self.expanded;
}

- (BOOL)hitTestX:(float)surfaceX y:(float)surfaceY
{
	if (!self.enabled) {
		return NO;
	}
	float w = self.rectWidth;
	float h = self.rectHeight;
	if (w <= 0.0f || h <= 0.0f) {
		return NO;
	}
	float x = self.rectX;
	float y = self.rectY;
	return surfaceX >= x && surfaceX <= x + w && surfaceY >= y && surfaceY <= y + h;
}

- (void)update:(TGFrameStatsSnapshot)snapshot
{
	_latest = snapshot;
	_hasData = YES;
	[self buildText];
}

- (void)draw:(TGSpriteBatch *)batch
	 texture:(GLuint)whiteTexture
		font:(TGBitmapFont *)hudFont
surfaceWidth:(float)surfaceWidth
surfaceHeight:(float)surfaceHeight
 screenScale:(float)screenScale
{
	if (!_hasData || hudFont == nil || hudFont.sheet == nil || ![hudFont.sheet isReady]) {
		return;
	}
	if ([self isExpanded] != _builtExpanded) {
		[self buildText];
	}

	float scale = MAX(0.5f, screenScale);
	// Whole steps only: a pixel font drawn at 1.7x is a blurry mess, and at
	// 2x it is exactly twice as crisp.
	int glyphScale = MAX(1, (int)lroundf(scale));
	float glyphHeight = hudFont.lineHeight * glyphScale;
	float rowGap = kRowGap * scale;
	float columnGap = kColumnGap * scale;
	float padding = kPadding * scale;
	float margin = kMargin * scale;

	NSUInteger usedColumns = 0;
	NSUInteger maxRows = 0;
	float contentWidth = 0.0f;
	for (NSUInteger c = 0; c < kColumns; c++) {
		NSArray<NSString *> *rows = _columns[c];
		if (rows.count == 0) {
			continue;
		}
		float width = 0.0f;
		for (NSString *row in rows) {
			width = MAX(width, measureText(hudFont, row, glyphScale));
		}
		_columnWidths[c] = width;
		contentWidth += width;
		maxRows = MAX(maxRows, rows.count);
		usedColumns++;
	}
	if (usedColumns == 0 || maxRows == 0) {
		return;
	}
	contentWidth += columnGap * (usedColumns - 1);
	float contentHeight = maxRows * glyphHeight + (maxRows - 1) * rowGap;
	float panelWidth = contentWidth + padding * 2.0f;
	float panelHeight = contentHeight + padding * 2.0f;

	[TGScreenOverlay resolveOrigin:self.corner
					  contentWidth:panelWidth
					 contentHeight:panelHeight
					  surfaceWidth:surfaceWidth
					 surfaceHeight:surfaceHeight
							margin:margin
							   out:_origin];
	self.rectX = _origin[0];
	self.rectY = _origin[1];
	self.rectWidth = panelWidth;
	self.rectHeight = panelHeight;

	// Backdrop: one horizontal line whose half-thickness is half the
	// panel — a filled rect without teaching the batcher a new shape
	float centerY = _origin[1] + panelHeight * 0.5f;
	[batch drawLine:whiteTexture
			  fromX:_origin[0] y:centerY
				toX:_origin[0] + panelWidth y:centerY
	  halfThickness:panelHeight * 0.5f
				  r:0.0f g:0.0f b:0.0f a:0.55f];

	float x = _origin[0] + padding;
	for (NSUInteger c = 0; c < kColumns; c++) {
		NSArray<NSString *> *rows = _columns[c];
		if (rows.count == 0) {
			continue;
		}
		float y = _origin[1] + padding;
		for (NSString *row in rows) {
			drawText(batch, hudFont, row, x, y, glyphScale, 0.75f, 1.0f, 0.8f, 1.0f);
			y += glyphHeight + rowGap;
		}
		x += _columnWidths[c] + columnGap;
	}
}

/** Pen width of `text` at the given whole-number scale. */
static float measureText(TGBitmapFont *font, NSString *text, int scale)
{
	float width = 0.0f;
	for (NSUInteger i = 0; i < text.length; i++) {
		unichar c = [text characterAtIndex:i];
		TGGlyph glyph;
		width += [font glyphForCharacter:c into:&glyph] ? glyph.xAdvance : [font missingAdvance];
		if (i + 1 < text.length) {
			width += [font kernFirst:c second:[text characterAtIndex:i + 1]];
		}
	}
	return width * scale;
}

/** Lays glyph quads straight into the batch — no TGTextSprite, no scene. */
static void drawText(TGSpriteBatch *batch, TGBitmapFont *font, NSString *text,
					 float x, float y, int scale,
					 float r, float g, float b, float a)
{
	GLuint texture = (GLuint)[font.sheet textureId];
	float pen = x;
	for (NSUInteger i = 0; i < text.length; i++) {
		unichar c = [text characterAtIndex:i];
		TGGlyph glyph;
		if (![font glyphForCharacter:c into:&glyph]) {
			pen += [font missingAdvance] * scale;
			continue;
		}
		TGFrame frame;
		if ([font.sheet frame:glyph.frameIndex into:&frame]
				&& glyph.width > 0.0f && glyph.height > 0.0f) {
			float halfW = glyph.width * scale * 0.5f;
			float halfH = glyph.height * scale * 0.5f;
			[batch drawFrame:texture frame:frame
						  cx:pen + glyph.xOffset * scale + halfW
						  cy:y + glyph.yOffset * scale + halfH
					   halfW:halfW halfH:halfH
						   r:r g:g b:b a:a];
		}
		pen += glyph.xAdvance * scale;
		if (i + 1 < text.length) {
			pen += [font kernFirst:c second:[text characterAtIndex:i + 1]] * scale;
		}
	}
}

/** The README explains every label. */
- (void)buildText
{
	BOOL full = [self isExpanded];
	_builtExpanded = full;
	for (NSUInteger c = 0; c < kColumns; c++) {
		[_columns[c] removeAllObjects];
	}

	if (!full) {
		[self put:0 text:[NSString stringWithFormat:@"FPS %ld", lround(_latest.fps)]];
		[self put:1 text:[NSString stringWithFormat:@"MS %.1f", _latest.averageCpuMs]];
		[self put:2 text:[NSString stringWithFormat:@"DC %d", _latest.drawCalls]];
		return;
	}

	[self put:0 text:[NSString stringWithFormat:@"FPS %ld", lround(_latest.fps)]];
	[self put:0 text:[NSString stringWithFormat:@"MS %.1f", _latest.averageCpuMs]];
	[self put:0 text:[NSString stringWithFormat:@"P95 %.1f", _latest.p95CpuMs]];
	[self put:0 text:[NSString stringWithFormat:@"MAX %.1f", _latest.maxCpuMs]];
	[self put:0 text:[NSString stringWithFormat:@"DROP %d", _latest.droppedFrames]];

	[self put:1 text:[NSString stringWithFormat:@"SPRITES %d/%d", _latest.visibleSprites, _latest.sprites]];
	[self put:1 text:[NSString stringWithFormat:@"EMITTERS %d", _latest.emitters]];
	[self put:1 text:[NSString stringWithFormat:@"PARTICLES %d", _latest.particles]];
	[self put:1 text:[NSString stringWithFormat:@"DRAWCALLS %d", _latest.drawCalls]];
	[self put:1 text:[NSString stringWithFormat:@"TEXSWITCH %d", _latest.textureSwitches]];

	[self put:2 text:[NSString stringWithFormat:@"UPDATE %.1f", _latest.averageUpdateMs]];
	[self put:2 text:[NSString stringWithFormat:@"TEXTURE %.1f", _latest.averageTexturePrepareMs]];
	[self put:2 text:[NSString stringWithFormat:@"BATCH %.1f", _latest.averageBatchMs]];
	// Only this platform can time the swap — the Android twin has no
	// equivalent rows rather than two zeros that mean nothing
	[self put:2 text:[NSString stringWithFormat:@"PRESENT %.1f", _latest.averagePresentMs]];
	[self put:2 text:[NSString stringWithFormat:@"PRESENTFAIL %d", _latest.presentFailures]];
}

- (void)put:(NSUInteger)column text:(NSString *)text
{
	NSMutableArray<NSString *> *rows = _columns[column];
	if (rows.count >= kMaxRows) {
		return;
	}
	[rows addObject:text];
}

@end
