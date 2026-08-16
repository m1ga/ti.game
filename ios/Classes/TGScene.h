//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Scene.java)
//
#import <Foundation/Foundation.h>

@class TGParticleEmitter;
@class TGRope;
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

// Camera: world-space offset of the view's top-left corner (at scale 1).
@property (atomic, assign) float cameraX;
@property (atomic, assign) float cameraY;

// Zoom, anchored on the view center.
@property (atomic, assign) float cameraScale;

// Native dead-zone follow. Vertical is always active while a target is
// set; horizontal only when followLeftFraction >= 0. followSmoothing
// 0 = snap, else fraction of remaining distance covered per 1/60 s.
@property (atomic, strong) TGSprite *followTarget;
@property (atomic, assign) float followTopFraction;
@property (atomic, assign) float followBottomFraction;
@property (atomic, assign) float followLeftFraction;
@property (atomic, assign) float followRightFraction;
@property (atomic, assign) float followSmoothing;
@property (atomic, assign) float cameraMaxY;

// Camera bounds: clamp the visible rect into this world rect.
@property (atomic, assign) BOOL cameraBoundsEnabled;
@property (atomic, assign) float boundsMinX;
@property (atomic, assign) float boundsMinY;
@property (atomic, assign) float boundsMaxX;
@property (atomic, assign) float boundsMaxY;

// Shake offsets for the renderer — render thread only.
@property (nonatomic, assign) float shakeOffsetX;
@property (nonatomic, assign) float shakeOffsetY;

/** Kicks off (or restarts) a camera shake. strength px, duration s. */
- (void)shakeWithStrength:(float)strength duration:(float)duration;

/** World position of the visible rect's left/top edge (accounts for zoom). */
- (float)viewOriginX;
- (float)viewOriginY;

/** Maps a surface touch position into world space (camera + zoom). */
- (float)screenToWorldX:(float)sx;
- (float)screenToWorldY:(float)sy;

// Fullscreen camera effect (main thread writes, render thread reads):
// the scene renders into an offscreen texture and TGPostEffect draws it
// to the screen through the effect shader. TGPostEffectNone renders
// directly. Values mirror engine/PostEffect constants.
@property (atomic, assign) int cameraEffect;
@property (atomic, assign) float effectTintR;
@property (atomic, assign) float effectTintG;
@property (atomic, assign) float effectTintB;
@property (atomic, assign) float effectIntensity; // 0..1 mix/strength

@property (atomic, assign) float bgRed;
@property (atomic, assign) float bgGreen;
@property (atomic, assign) float bgBlue;
@property (atomic, assign) float bgAlpha;

- (void)add:(TGSprite *)sprite;
- (void)remove:(TGSprite *)sprite;
- (void)clear;
- (void)markZOrderDirty;

- (void)addEmitter:(TGParticleEmitter *)emitter;
- (void)removeEmitter:(TGParticleEmitter *)emitter;
/** Snapshot sorted by zIndex (emitters are few; sorted every call). */
- (NSArray<TGParticleEmitter *> *)emittersSnapshot;

- (void)addRope:(TGRope *)rope;
- (void)removeRope:(TGRope *)rope;
/** Snapshot sorted by zIndex (ropes are few; sorted every call). */
- (NSArray<TGRope *> *)ropesSnapshot;

/** Re-scan for ySort sprites; while any exist, draw order re-sorts every frame. */
- (void)recomputeYSort;

/** Snapshot in draw order (back to front). Caller holds no lock. */
- (NSArray<TGSprite *> *)snapshot;

/**
 * Captures the three scene collections once, advances the native simulation,
 * and returns the same snapshots the renderer must draw. ySort is applied
 * after positions advance so draw order reflects the current frame.
 */
- (NSArray<TGSprite *> *)prepareFrame:(float)dt
							 emitters:(NSArray<TGParticleEmitter *> **)emitters
								ropes:(NSArray<TGRope *> **)ropes;

/** Ticks physics, animations and tweens, then checks collisions. Render thread. */
- (void)update:(float)dt;

/** Topmost sprite under the point (front to back), or nil. */
- (TGSprite *)hitTestX:(float)x y:(float)y;

@end
