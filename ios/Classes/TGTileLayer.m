#import "TGTileLayer.h"
#import "TGSpriteBatch.h"
#import "TGSpriteSheet.h"
#import <math.h>
#import <stdlib.h>

@implementation TGTileGrid

- (instancetype)initWithCols:(int)cols rows:(int)rows
{
	if (self = [super init]) {
		_cols = cols;
		_rows = rows;
		size_t n = (size_t)cols * (size_t)rows;
		_tiles = malloc(n * sizeof(int32_t));
		_flags = calloc(n, sizeof(uint8_t));
		for (size_t i = 0; i < n; i++) {
			_tiles[i] = TGTileEmpty;
		}
	}
	return self;
}

- (void)dealloc
{
	free(_tiles);
	free(_flags);
}

@end

@implementation TGTileLayer {
	NSSet<NSNumber *> *_solidIds;   // guarded by @synchronized(self)
	NSSet<NSNumber *> *_oneWayIds;
}

- (instancetype)init
{
	if (self = [super init]) {
		_visible = YES;
		_opacity = 1.0f;
		_tintR = 1.0f;
		_tintG = 1.0f;
		_tintB = 1.0f;
		_scrollFactor = 1.0f;
	}
	return self;
}

#pragma mark Grid

- (uint8_t)flagFor:(int32_t)tile
{
	if (tile < 0) {
		return 0;
	}
	NSNumber *key = @(tile);
	if ([_solidIds containsObject:key]) {
		return TGTileFlagSolid;
	}
	if ([_oneWayIds containsObject:key]) {
		return TGTileFlagOneWay;
	}
	return 0;
}

- (void)setGridCols:(int)cols rows:(int)rows tiles:(const int32_t *)tiles count:(int)count
{
	@synchronized (self) {
		if (cols <= 0 || rows <= 0) {
			_grid = nil;
			return;
		}
		TGTileGrid *grid = [[TGTileGrid alloc] initWithCols:cols rows:rows];
		int n = cols * rows;
		for (int i = 0; i < n; i++) {
			int32_t tile = (tiles != NULL && i < count) ? tiles[i] : TGTileEmpty;
			grid.tiles[i] = tile;
			grid.flags[i] = [self flagFor:tile];
		}
		_grid = grid;
	}
}

- (void)setSolidIds:(NSSet<NSNumber *> *)solid oneWayIds:(NSSet<NSNumber *> *)oneWay
{
	@synchronized (self) {
		_solidIds = solid;
		_oneWayIds = oneWay;
		TGTileGrid *grid = _grid;
		if (grid == nil) {
			return;
		}
		int n = grid.cols * grid.rows;
		for (int i = 0; i < n; i++) {
			grid.flags[i] = [self flagFor:grid.tiles[i]];
		}
	}
}

- (int)cols
{
	TGTileGrid *grid = self.grid;
	return (grid != nil) ? grid.cols : 0;
}

- (int)rows
{
	TGTileGrid *grid = self.grid;
	return (grid != nil) ? grid.rows : 0;
}

- (BOOL)inGridCol:(int)col row:(int)row
{
	TGTileGrid *grid = self.grid;
	return grid != nil && col >= 0 && row >= 0 && col < grid.cols && row < grid.rows;
}

- (int)tileAtCol:(int)col row:(int)row
{
	TGTileGrid *grid = self.grid;
	if (grid == nil || col < 0 || row < 0 || col >= grid.cols || row >= grid.rows) {
		return TGTileEmpty;
	}
	return grid.tiles[row * grid.cols + col];
}

- (void)setTile:(int)tile atCol:(int)col row:(int)row
{
	@synchronized (self) {
		TGTileGrid *grid = _grid;
		if (grid == nil || col < 0 || row < 0 || col >= grid.cols || row >= grid.rows) {
			return;
		}
		int i = row * grid.cols + col;
		grid.tiles[i] = (tile < 0) ? TGTileEmpty : tile;
		grid.flags[i] = [self flagFor:grid.tiles[i]];
	}
}

- (uint8_t)flagAtCol:(int)col row:(int)row
{
	TGTileGrid *grid = self.grid;
	if (grid == nil || col < 0 || row < 0 || col >= grid.cols || row >= grid.rows) {
		return 0;
	}
	return grid.flags[row * grid.cols + col];
}

- (void)setFlag:(uint8_t)flag atCol:(int)col row:(int)row
{
	TGTileGrid *grid = self.grid;
	if (grid == nil || col < 0 || row < 0 || col >= grid.cols || row >= grid.rows) {
		return;
	}
	grid.flags[row * grid.cols + col] = flag;
}

- (BOOL)isSolidCol:(int)col row:(int)row
{
	return ([self flagAtCol:col row:row] & TGTileFlagSolid) != 0;
}

#pragma mark Geometry

- (float)cellWidth
{
	float w = self.tileWidth;
	if (w > 0.0f) {
		return w;
	}
	TGSpriteSheet *sh = self.sheet;
	return (sh != nil) ? [sh frameWidth:0] : 0.0f;
}

- (float)cellHeight
{
	float h = self.tileHeight;
	if (h > 0.0f) {
		return h;
	}
	TGSpriteSheet *sh = self.sheet;
	return (sh != nil) ? [sh frameHeight:0] : 0.0f;
}

- (float)width
{
	return [self cols] * [self cellWidth];
}

- (float)height
{
	return [self rows] * [self cellHeight];
}

- (BOOL)spansWorldXFrom:(float)minX width:(float)width
{
	return fabsf(self.x - minX) < 0.001f && fabsf([self width] - width) < 0.001f;
}

- (int)colAt:(float)worldX
{
	float w = [self cellWidth];
	return (w > 0.0f) ? (int)floorf((worldX - self.x) / w) : -1;
}

- (int)rowAt:(float)worldY
{
	float h = [self cellHeight];
	return (h > 0.0f) ? (int)floorf((worldY - self.y) / h) : -1;
}

- (BOOL)blocks:(NSSet<NSString *> *)groups
{
	NSString *group = self.collisionGroup;
	return group != nil && self.visible && self.grid != nil && [groups containsObject:group];
}

- (BOOL)matches:(NSSet<NSString *> *)groups
{
	NSString *group = self.collisionGroup;
	return group != nil && self.visible && self.grid != nil
		&& (groups == nil || groups.count == 0 || [groups containsObject:group]);
}

#pragma mark Drawing

- (BOOL)wrapsWorldX:(TGSpriteBatch *)batch
{
	return [batch worldWrapXEnabled]
		&& [self spansWorldXFrom:[batch worldWrapMinX] width:[batch worldWrapWidth]];
}

- (void)draw:(TGSpriteBatch *)batch
	viewLeft:(float)viewLeft viewTop:(float)viewTop
   viewRight:(float)viewRight viewBottom:(float)viewBottom
{
	TGSpriteSheet *sh = self.sheet;
	TGTileGrid *grid = self.grid;
	float alpha = MAX(0.0f, MIN(1.0f, self.opacity));
	if (!self.visible || alpha <= 0.0f || sh == nil || ![sh isReady] || grid == nil) {
		return;
	}
	float tw = [self cellWidth];
	float th = [self cellHeight];
	if (tw <= 0.0f || th <= 0.0f) {
		return;
	}
	int c = grid.cols;
	int r = grid.rows;
	float ox = self.x + [batch parallaxOffsetX:self.scrollFactor];
	float oy = self.y + [batch parallaxOffsetY:self.scrollFactor];
	BOOL wrapsWorld = [self wrapsWorldX:batch];
	int c0 = (int)floorf((viewLeft - ox) / tw);
	int c1 = (int)floorf((viewRight - ox) / tw);
	if (!wrapsWorld) {
		c0 = MAX(0, c0);
		c1 = MIN(c - 1, c1);
	}
	int r0 = MAX(0, (int)floorf((viewTop - oy) / th));
	int r1 = MIN(r - 1, (int)floorf((viewBottom - oy) / th));
	if (c1 < c0 || r1 < r0) {
		return; // entirely off-screen
	}
	[batch setScreenSpace:NO];
	[batch setBlendMode:TGBlendModeNormal];
	GLuint texture = (GLuint)[sh textureId];
	NSInteger frameCount = (NSInteger)[sh frameCount];
	float hw = tw / 2.0f;
	float hh = th / 2.0f;
	float tr = self.tintR;
	float tg = self.tintG;
	float tb = self.tintB;
	const int32_t *tiles = grid.tiles;
	TGFrame f;
	for (int row = r0; row <= r1; row++) {
		int base = row * c;
		float cy = oy + (row + 0.5f) * th;
		for (int col = c0; col <= c1; col++) {
			int sourceCol = wrapsWorld ? ((col % c) + c) % c : col;
			int32_t tile = tiles[base + sourceCol];
			if (tile < 0 || tile >= frameCount || ![sh frame:tile into:&f]) {
				continue;
			}
			[batch drawFrame:texture frame:f
						  cx:ox + (col + 0.5f) * tw cy:cy
					   halfW:hw halfH:hh
						   r:tr g:tg b:tb a:alpha];
		}
	}
}

- (void)drawDebug:(TGSpriteBatch *)batch whiteTexture:(GLuint)whiteTexture
		 viewLeft:(float)viewLeft viewTop:(float)viewTop
		viewRight:(float)viewRight viewBottom:(float)viewBottom
{
	TGTileGrid *grid = self.grid;
	float tw = [self cellWidth];
	float th = [self cellHeight];
	if (grid == nil || tw <= 0.0f || th <= 0.0f) {
		return;
	}
	int c = grid.cols;
	int r = grid.rows;
	float ox = self.x + [batch parallaxOffsetX:self.scrollFactor];
	float oy = self.y + [batch parallaxOffsetY:self.scrollFactor];
	BOOL wrapsWorld = [self wrapsWorldX:batch];
	int c0 = (int)floorf((viewLeft - ox) / tw);
	int c1 = (int)floorf((viewRight - ox) / tw);
	if (!wrapsWorld) {
		c0 = MAX(0, c0);
		c1 = MIN(c - 1, c1);
	}
	int r0 = MAX(0, (int)floorf((viewTop - oy) / th));
	int r1 = MIN(r - 1, (int)floorf((viewBottom - oy) / th));
	if (c1 < c0 || r1 < r0) {
		return;
	}
	[batch setScreenSpace:NO];
	float t = 1.0f;
	const uint8_t *flags = grid.flags;
	for (int row = r0; row <= r1; row++) {
		for (int col = c0; col <= c1; col++) {
			int sourceCol = wrapsWorld ? ((col % c) + c) % c : col;
			uint8_t flag = flags[row * c + sourceCol];
			if (flag == 0) {
				continue;
			}
			BOOL oneWay = (flag & TGTileFlagSolid) == 0;
			float cr = oneWay ? 1.0f : 0.2f;
			float cg = oneWay ? 0.85f : 1.0f;
			float cb = oneWay ? 0.2f : 0.4f;
			float x0 = ox + col * tw + t;
			float y0 = oy + row * th + t;
			float x1 = x0 + tw - 2.0f * t;
			float y1 = y0 + th - 2.0f * t;
			[batch drawLine:whiteTexture fromX:x0 y:y0 toX:x1 y:y0 halfThickness:t r:cr g:cg b:cb a:0.9f];
			if (!oneWay) {
				[batch drawLine:whiteTexture fromX:x1 y:y0 toX:x1 y:y1 halfThickness:t r:cr g:cg b:cb a:0.9f];
				[batch drawLine:whiteTexture fromX:x1 y:y1 toX:x0 y:y1 halfThickness:t r:cr g:cg b:cb a:0.9f];
				[batch drawLine:whiteTexture fromX:x0 y:y1 toX:x0 y:y0 halfThickness:t r:cr g:cg b:cb a:0.9f];
			}
		}
	}
}

@end
