#import "TGDebugHud.h"
#import "TGScreenOverlay.h"
#import "TGSegmentFont.h"
#import "TGSpriteBatch.h"

static const NSUInteger kColumns = 3;
static const NSUInteger kMaxRows = 6;

// Layout, in points — multiplied by the screen scale.
static const float kGlyphHeight = 9.0f;
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
surfaceWidth:(float)surfaceWidth
surfaceHeight:(float)surfaceHeight
 screenScale:(float)screenScale
{
	if (!_hasData) {
		return;
	}
	if ([self isExpanded] != _builtExpanded) {
		[self buildText];
	}

	float scale = MAX(0.5f, screenScale);
	float glyphHeight = kGlyphHeight * scale;
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
			width = MAX(width, [TGSegmentFont measure:row glyphHeight:glyphHeight]);
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
			[TGSegmentFont draw:batch texture:whiteTexture text:row
							  x:x y:y glyphHeight:glyphHeight
							  r:0.75f g:1.0f b:0.8f a:1.0f];
			y += glyphHeight + rowGap;
		}
		x += _columnWidths[c] + columnGap;
	}
}

/**
 * Labels are limited to what seven segments can draw (no M, K, V, W, X,
 * Z), hence CPU rather than MS and tOP rather than MAX. The README spells
 * every one of them out.
 */
- (void)buildText
{
	BOOL full = [self isExpanded];
	_builtExpanded = full;
	for (NSUInteger c = 0; c < kColumns; c++) {
		[_columns[c] removeAllObjects];
	}

	if (!full) {
		[self put:0 text:[NSString stringWithFormat:@"FPS %ld", lround(_latest.fps)]];
		[self put:1 text:[NSString stringWithFormat:@"CPU %.1f", _latest.averageCpuMs]];
		[self put:2 text:[NSString stringWithFormat:@"dC %d", _latest.drawCalls]];
		return;
	}

	[self put:0 text:[NSString stringWithFormat:@"FPS %ld", lround(_latest.fps)]];
	[self put:0 text:[NSString stringWithFormat:@"CPU %.1f", _latest.averageCpuMs]];
	[self put:0 text:[NSString stringWithFormat:@"P95 %.1f", _latest.p95CpuMs]];
	[self put:0 text:[NSString stringWithFormat:@"tOP %.1f", _latest.maxCpuMs]];
	[self put:0 text:[NSString stringWithFormat:@"drOP %d", _latest.droppedFrames]];

	[self put:1 text:[NSString stringWithFormat:@"SPr %d/%d", _latest.visibleSprites, _latest.sprites]];
	[self put:1 text:[NSString stringWithFormat:@"EnIt %d", _latest.emitters]];
	[self put:1 text:[NSString stringWithFormat:@"PArt %d", _latest.particles]];
	[self put:1 text:[NSString stringWithFormat:@"dC %d", _latest.drawCalls]];
	[self put:1 text:[NSString stringWithFormat:@"tS %d", _latest.textureSwitches]];

	[self put:2 text:[NSString stringWithFormat:@"UPd %.1f", _latest.averageUpdateMs]];
	[self put:2 text:[NSString stringWithFormat:@"tPrE %.1f", _latest.averageTexturePrepareMs]];
	[self put:2 text:[NSString stringWithFormat:@"bAt %.1f", _latest.averageBatchMs]];
	// Only this platform can time the swap — the Android twin has no
	// equivalent rows rather than two zeros that mean nothing
	[self put:2 text:[NSString stringWithFormat:@"PrE %.1f", _latest.averagePresentMs]];
	[self put:2 text:[NSString stringWithFormat:@"PF %d", _latest.presentFailures]];
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
