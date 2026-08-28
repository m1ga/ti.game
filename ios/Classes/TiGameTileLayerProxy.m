#import "TiGameTileLayerProxy.h"
#import "TiGameSpriteSheetProxy.h"
#import "TGValues.h"

@implementation TiGameTileLayerProxy {
	TiGameSpriteSheetProxy *_sheetProxy;
	// Raw grid inputs. Creation-dict keys arrive in no particular order on
	// iOS, so every input is kept and the grid is rebuilt from all of them
	// whenever one changes (the Android twin orders them explicitly).
	id _data;
	NSDictionary *_legend;
	NSArray *_solidIds;
	NSArray *_oneWayIds;
	int _firstGid;
	int _cols;
	int _rows;
	NSString *_tintColor;
}

- (instancetype)init
{
	if (self = [super init]) {
		_layer = [[TGTileLayer alloc] init];
	}
	return self;
}

- (NSString *)apiName
{
	return @"ti.game.TileLayer";
}

#pragma mark Grid data

/** A raw cell value → frame index: legend characters, gid offset, flip bits, empties. */
- (int)toId:(id)value
{
	if ([value isKindOfClass:[NSString class]]) {
		id mapped = _legend[value];
		return (mapped != nil) ? [self toId:mapped] : TGTileEmpty;
	}
	if (![value isKindOfClass:[NSNumber class]]) {
		return TGTileEmpty;
	}
	long long raw = [value longLongValue];
	if (raw < 0 || (raw == 0 && _firstGid > 0)) {
		return TGTileEmpty; // negative = empty; Tiled: gid 0 = no tile
	}
	int tile = (int)(raw & 0x0FFFFFFFLL) - _firstGid; // strip Tiled's flip flags
	return (tile < 0) ? TGTileEmpty : tile;
}

- (int)idOfRow:(id)row col:(int)col
{
	if ([row isKindOfClass:[NSArray class]]) {
		NSArray *cells = row;
		return (col < (int)cells.count) ? [self toId:cells[col]] : TGTileEmpty;
	}
	if ([row isKindOfClass:[NSString class]]) {
		NSString *text = row;
		return (col < (int)text.length)
			? [self toId:[text substringWithRange:NSMakeRange(col, 1)]] : TGTileEmpty;
	}
	return TGTileEmpty;
}

- (NSSet<NSNumber *> *)idSet:(NSArray *)values
{
	if (values == nil) {
		return nil;
	}
	NSMutableSet<NSNumber *> *set = [NSMutableSet set];
	for (id value in values) {
		int tile = [self toId:value];
		if (tile >= 0) {
			[set addObject:@(tile)];
		}
	}
	return set;
}

/** Re-parses the stored inputs into the engine grid. */
- (void)rebuild
{
	[self.layer setSolidIds:[self idSet:_solidIds] oneWayIds:[self idSet:_oneWayIds]];
	if (![_data isKindOfClass:[NSArray class]]) {
		if (_data == nil && _cols > 0 && _rows > 0) {
			[self.layer setGridCols:_cols rows:_rows tiles:NULL count:0]; // all empty
		}
		return;
	}
	NSArray *items = _data;
	if (items.count == 0) {
		[self.layer setGridCols:0 rows:0 tiles:NULL count:0];
		return;
	}
	id first = items[0];
	int cols = _cols;
	int rows = _rows;
	int32_t *ids = NULL;
	if ([first isKindOfClass:[NSArray class]] || [first isKindOfClass:[NSString class]]) {
		cols = 0;
		for (id row in items) {
			int length = [row isKindOfClass:[NSArray class]] ? (int)[row count]
				: ([row isKindOfClass:[NSString class]] ? (int)[row length] : 0);
			cols = MAX(cols, length);
		}
		rows = (int)items.count;
		if (cols == 0) {
			[self.layer setGridCols:0 rows:0 tiles:NULL count:0];
			return;
		}
		ids = malloc(sizeof(int32_t) * cols * rows);
		for (int r = 0; r < rows; r++) {
			for (int c = 0; c < cols; c++) {
				ids[r * cols + c] = [self idOfRow:items[r] col:c];
			}
		}
	} else {
		if (cols <= 0) {
			cols = (int)items.count; // a single row
		}
		if (rows <= 0) {
			rows = ((int)items.count + cols - 1) / cols;
		}
		ids = malloc(sizeof(int32_t) * cols * rows);
		for (int i = 0; i < cols * rows; i++) {
			ids[i] = (i < (int)items.count) ? [self toId:items[i]] : TGTileEmpty;
		}
	}
	[self.layer setGridCols:cols rows:rows tiles:ids count:cols * rows];
	free(ids);
}

- (void)setData:(id)value
{
	_data = [value isKindOfClass:[NSArray class]] ? value : nil;
	[self rebuild];
}

- (void)setLegend:(id)value
{
	_legend = [value isKindOfClass:[NSDictionary class]] ? value : nil;
	[self rebuild];
}

- (id)legend
{
	return _legend;
}

- (void)setFirstGid:(id)value
{
	_firstGid = [TiUtils intValue:value def:0];
	[self rebuild];
}

- (NSNumber *)firstGid
{
	return @(_firstGid);
}

- (void)setCols:(id)value
{
	_cols = [TiUtils intValue:value def:0];
	[self rebuild];
}

- (NSNumber *)cols
{
	return @([self.layer cols]);
}

- (void)setRows:(id)value
{
	_rows = [TiUtils intValue:value def:0];
	[self rebuild];
}

- (NSNumber *)rows
{
	return @([self.layer rows]);
}

/** Tile ids (or legend characters) that block from every side. */
- (void)setSolid:(id)value
{
	_solidIds = [value isKindOfClass:[NSArray class]] ? value : nil;
	[self.layer setSolidIds:[self idSet:_solidIds] oneWayIds:[self idSet:_oneWayIds]];
}

- (id)solid
{
	return _solidIds;
}

/** Tile ids (or legend characters) that only catch riders falling onto them. */
- (void)setOneWay:(id)value
{
	_oneWayIds = [value isKindOfClass:[NSArray class]] ? value : nil;
	[self.layer setSolidIds:[self idSet:_solidIds] oneWayIds:[self idSet:_oneWayIds]];
}

- (id)oneWay
{
	return _oneWayIds;
}

/** World size of the whole layer (read-only). */
- (NSNumber *)width
{
	return @([self.layer width]);
}

- (NSNumber *)height
{
	return @([self.layer height]);
}

#pragma mark Cell access

- (NSNumber *)getTile:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	int col = (list.count > 0) ? [TiUtils intValue:list[0] def:-1] : -1;
	int row = (list.count > 1) ? [TiUtils intValue:list[1] def:-1] : -1;
	return @([self.layer tileAtCol:col row:row]);
}

- (void)setTile:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	if (list.count < 3) {
		return;
	}
	[self.layer setTile:[self toId:list[2]]
				  atCol:[TiUtils intValue:list[0] def:-1]
					row:[TiUtils intValue:list[1] def:-1]];
}

- (NSNumber *)isBlocked:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	int col = (list.count > 0) ? [TiUtils intValue:list[0] def:-1] : -1;
	int row = (list.count > 1) ? [TiUtils intValue:list[1] def:-1] : -1;
	return @([self.layer isSolidCol:col row:row]);
}

- (void)setBlocked:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	if (list.count < 3) {
		return;
	}
	BOOL blocked = [TiUtils boolValue:list[2] def:NO];
	[self.layer setFlag:(blocked ? TGTileFlagSolid : 0)
				  atCol:[TiUtils intValue:list[0] def:-1]
					row:[TiUtils intValue:list[1] def:-1]];
}

- (NSDictionary *)cellInfoCol:(int)col row:(int)row
{
	return @{
		@"col": @(col),
		@"row": @(row),
		@"tile": @([self.layer tileAtCol:col row:row]),
		@"solid": @([self.layer isSolidCol:col row:row]),
		@"x": @(self.layer.x + (col + 0.5f) * [self.layer cellWidth]),
		@"y": @(self.layer.y + (row + 0.5f) * [self.layer cellHeight])
	};
}

- (id)tileAt:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	float x = (list.count > 0) ? [TiUtils floatValue:list[0] def:0.0f] : 0.0f;
	float y = (list.count > 1) ? [TiUtils floatValue:list[1] def:0.0f] : 0.0f;
	int col = [self.layer colAt:x];
	int row = [self.layer rowAt:y];
	if (![self.layer inGridCol:col row:row]) {
		return [NSNull null];
	}
	return [self cellInfoCol:col row:row];
}

- (id)cellAt:(id)args
{
	NSArray *list = [args isKindOfClass:[NSArray class]] ? args : @[];
	int col = (list.count > 0) ? [TiUtils intValue:list[0] def:-1] : -1;
	int row = (list.count > 1) ? [TiUtils intValue:list[1] def:-1] : -1;
	if (![self.layer inGridCol:col row:row]) {
		return [NSNull null];
	}
	return [self cellInfoCol:col row:row];
}

#pragma mark Look & placement

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
	self.layer.sheet = newSheet.sheet;
}

- (id)sheet
{
	return _sheetProxy;
}

- (void)setTileWidth:(id)value
{
	self.layer.tileWidth = [TiUtils floatValue:value def:0];
}

- (NSNumber *)tileWidth
{
	return @([self.layer cellWidth]);
}

- (void)setTileHeight:(id)value
{
	self.layer.tileHeight = [TiUtils floatValue:value def:0];
}

- (NSNumber *)tileHeight
{
	return @([self.layer cellHeight]);
}

- (void)setX:(id)value
{
	self.layer.x = [TiUtils floatValue:value def:0];
}

- (NSNumber *)x
{
	return @(self.layer.x);
}

- (void)setY:(id)value
{
	self.layer.y = [TiUtils floatValue:value def:0];
}

- (NSNumber *)y
{
	return @(self.layer.y);
}

- (void)setZIndex:(id)value
{
	self.layer.zIndex = [TiUtils intValue:value def:0];
}

- (NSNumber *)zIndex
{
	return @(self.layer.zIndex);
}

- (void)setVisible:(id)value
{
	self.layer.visible = [TiUtils boolValue:value def:YES];
}

- (NSNumber *)visible
{
	return @(self.layer.visible);
}

- (void)setOpacity:(id)value
{
	self.layer.opacity = [TGValues ratio:value fallback:1.0f];
}

- (NSNumber *)opacity
{
	return @(self.layer.opacity);
}

- (void)setScrollFactor:(id)value
{
	self.layer.scrollFactor = [TGValues ratio:value fallback:1.0f];
}

- (NSNumber *)scrollFactor
{
	return @(self.layer.scrollFactor);
}

/** Multiplies every tile's colors, e.g. '#8af' for a night look; null = unchanged. */
- (void)setTintColor:(id)value
{
	_tintColor = [TiUtils stringValue:value];
	TiColor *tiColor = [TiUtils colorValue:value];
	if (tiColor == nil) {
		self.layer.tintR = 1.0f;
		self.layer.tintG = 1.0f;
		self.layer.tintB = 1.0f;
		return;
	}
	CGFloat r = 1, g = 1, b = 1, a = 1;
	[[tiColor color] getRed:&r green:&g blue:&b alpha:&a];
	self.layer.tintR = (float)r;
	self.layer.tintG = (float)g;
	self.layer.tintB = (float)b;
}

- (NSString *)tintColor
{
	return _tintColor;
}

#pragma mark Collision

- (void)setCollisionGroup:(id)value
{
	self.layer.collisionGroup = [TiUtils stringValue:value];
}

- (NSString *)collisionGroup
{
	return self.layer.collisionGroup;
}

- (void)setRestitution:(id)value
{
	self.layer.restitution = [TGValues ratio:value fallback:0.0f];
}

- (NSNumber *)restitution
{
	return @(self.layer.restitution);
}

- (void)setDebug:(id)value
{
	self.layer.debug = [TiUtils boolValue:value def:NO];
}

- (NSNumber *)debug
{
	return @(self.layer.debug);
}

@end
