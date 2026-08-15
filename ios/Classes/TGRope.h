//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Rope.java)
//
#import <Foundation/Foundation.h>

@class TGSprite;
@class TGSpriteBatch;
@class TGSpriteSheet;

/**
 * Native Verlet rope: a chain of distance-constrained points, integrated
 * and drawn entirely in the game loop — zero bridge traffic while it
 * swings. The head pins to a sprite (drag it natively and the rope
 * follows) or to a fixed x/y; an optional tail sprite pins the other
 * end. Segments render as textured quads oriented along the rope, all
 * from one sheet frame — one batch run.
 */
@interface TGRope : NSObject

@property (atomic, strong) TGSpriteSheet *sheet;
@property (atomic, assign) int frame;
@property (atomic, assign) int segments;
@property (atomic, assign) float segmentLength;  // px
@property (atomic, assign) float thickness;      // drawn width, px
@property (atomic, assign) float gravity;        // px/s^2
@property (atomic, assign) float damping;        // velocity kept per step
@property (atomic, assign) int iterations;       // constraint passes
@property (atomic, assign) int zIndex;
@property (atomic, assign) BOOL visible;
@property (atomic, assign) float x;              // head anchor when no head sprite
@property (atomic, assign) float y;
@property (atomic, strong) TGSprite *head;
@property (atomic, strong) TGSprite *tail;

// Live tail-end position, mirrored for JS reads
@property (atomic, assign) float endX;
@property (atomic, assign) float endY;

/** Integrate + relax constraints. Render thread, once per frame. */
- (void)update:(float)dt;

/** Draws all segments through the shared batcher. Render thread. */
- (void)draw:(TGSpriteBatch *)batch;

@end
