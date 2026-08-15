//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Scene.java)
//
#import <Foundation/Foundation.h>

@class TGSkidTrail;
@class TGSprite;

/**
 * The native scene graph: an ordered list of sprites plus background color.
 * Shared between the main thread (add/remove, property writes, touch
 * hit-testing) and the render thread (update + draw), so all list access
 * is internally synchronized.
 */
@interface TGScene : NSObject

/** Renders debug overlays for every sprite (GameView.debug = true). */
@property (atomic, assign) BOOL debugAll;

/** Fading skid-mark segments emitted by carMode sprites (skidMarks).
 *  Drawn above sprites with zIndex <= 0 and below everything else. */
@property (nonatomic, readonly) TGSkidTrail *skidTrail;

// Surface size in pixels, kept current by the renderer — the world
// bounds used for wrapAround sprites.
@property (atomic, assign) float worldWidth;
@property (atomic, assign) float worldHeight;

// Camera: world-space offset of the view's top-left corner.
@property (atomic, assign) float cameraX;
@property (atomic, assign) float cameraY;

// Native vertical follow with a dead-zone.
@property (atomic, strong) TGSprite *followTarget;
@property (atomic, assign) float followTopFraction;
@property (atomic, assign) float followBottomFraction;
@property (atomic, assign) float cameraMaxY;

@property (atomic, assign) float bgRed;
@property (atomic, assign) float bgGreen;
@property (atomic, assign) float bgBlue;
@property (atomic, assign) float bgAlpha;

- (void)add:(TGSprite *)sprite;
- (void)remove:(TGSprite *)sprite;
- (void)clear;
- (void)markZOrderDirty;

/** Re-scan for ySort sprites; while any exist, draw order re-sorts every frame. */
- (void)recomputeYSort;

/** Snapshot in draw order (back to front). Caller holds no lock. */
- (NSArray<TGSprite *> *)snapshot;

/** Ticks physics, animations and tweens, then checks collisions. Render thread. */
- (void)update:(float)dt;

/** Topmost sprite under the point (front to back), or nil. */
- (TGSprite *)hitTestX:(float)x y:(float)y;

@end
