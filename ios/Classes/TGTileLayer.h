//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/TileLayer.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

@class TGSpriteBatch;
@class TGSpriteSheet;

enum {
	TGTileEmpty = -1,
	TGTileFlagSolid = 1,
	TGTileFlagOneWay = 2,
};

/** One published grid: replaced as a whole on resize (atomic property on
 *  the layer), cells written in place — an int/byte store is atomic, so
 *  the render thread sees the old or the new tile, never a torn one. */
@interface TGTileGrid : NSObject
@property (nonatomic, readonly) int cols;
@property (nonatomic, readonly) int rows;
@property (nonatomic, readonly) int32_t *tiles;   // cols * rows, TGTileEmpty for none
@property (nonatomic, readonly) uint8_t *flags;   // cols * rows, TGTileFlag* bits
- (instancetype)initWithCols:(int)cols rows:(int)rows;
@end

/**
 * Native tile map layer: a cols x rows grid of sheet frame indices drawn
 * as axis-aligned quads, plus a per-cell flag grid that feeds the solid
 * resolver and the pathfinder. Only the cells inside the visible rect are
 * touched per frame, and a mover only tests the cells under its own
 * hitbox — any map size costs the same. See the Android twin.
 */
@interface TGTileLayer : NSObject

@property (atomic, strong) TGSpriteSheet *sheet;
@property (atomic, assign) float x;            // world position of cell (0, 0)'s top-left
@property (atomic, assign) float y;
@property (atomic, assign) float tileWidth;    // world size per cell; 0 = the sheet's frame size
@property (atomic, assign) float tileHeight;
@property (atomic, assign) int zIndex;
@property (atomic, assign) BOOL visible;
@property (atomic, assign) float opacity;
@property (atomic, assign) float tintR;
@property (atomic, assign) float tintG;
@property (atomic, assign) float tintB;
@property (atomic, assign) float scrollFactor;
@property (atomic, copy) NSString *collisionGroup;
@property (atomic, assign) float restitution;
@property (atomic, assign) BOOL debug;

/** The live grid (may be nil before any data is set). */
@property (atomic, strong, readonly) TGTileGrid *grid;

/** Replaces the whole grid; `tiles` is row-major (count entries, missing = empty). */
- (void)setGridCols:(int)cols rows:(int)rows tiles:(const int32_t *)tiles count:(int)count;
/** Sets the solid / one-way tile id sets and re-derives every cell flag. */
- (void)setSolidIds:(NSSet<NSNumber *> *)solid oneWayIds:(NSSet<NSNumber *> *)oneWay;

- (int)cols;
- (int)rows;
- (BOOL)inGridCol:(int)col row:(int)row;
- (int)tileAtCol:(int)col row:(int)row;
- (void)setTile:(int)tile atCol:(int)col row:(int)row;
- (uint8_t)flagAtCol:(int)col row:(int)row;
- (void)setFlag:(uint8_t)flag atCol:(int)col row:(int)row;
/** Fully blocking cell? (one-way platforms are not walls) */
- (BOOL)isSolidCol:(int)col row:(int)row;

- (float)cellWidth;
- (float)cellHeight;
- (float)width;
- (float)height;
- (int)colAt:(float)worldX;
- (int)rowAt:(float)worldY;

/** True when this layer's solid cells apply to a mover's `solidWith`. */
- (BOOL)blocks:(NSSet<NSString *> *)groups;
/** Same filter raycast/findPath use for sprites: nil/empty = any tagged layer. */
- (BOOL)matches:(NSSet<NSString *> *)groups;

/** Draws the cells inside the visible world rect. Render thread. */
- (void)draw:(TGSpriteBatch *)batch
	viewLeft:(float)viewLeft viewTop:(float)viewTop
   viewRight:(float)viewRight viewBottom:(float)viewBottom;
/** Debug overlay: green outline on solid cells, yellow on one-way ones. */
- (void)drawDebug:(TGSpriteBatch *)batch whiteTexture:(GLuint)whiteTexture
		 viewLeft:(float)viewLeft viewTop:(float)viewTop
		viewRight:(float)viewRight viewBottom:(float)viewBottom;

@end
