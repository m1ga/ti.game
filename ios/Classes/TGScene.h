//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Scene.java)
//
#import <Foundation/Foundation.h>

@class TGBitmapFont;
@class TGDebugHud;
@class TGFrameStats;
@class TGParticleEmitter;
@class TGRope;
@class TGSkidTrail;
@class TGTileLayer;
@class TGSprite;

/** Receives expired game-clock timer ids on the render thread. */
@protocol TGSceneTimerListener <NSObject>
- (void)onTimer:(int)timerId repeats:(BOOL)repeats;
@end

/**
 * The native scene graph: an ordered list of sprites plus background color.
 * Shared between the main thread (add/remove, property writes, touch
 * hit-testing) and the render thread (update + draw), so all list access
 * is internally synchronized.
 */
@interface TGScene : NSObject

/** Renders debug overlays for every sprite (GameView.debug = { hitbox: true }). */
@property (atomic, assign) BOOL debugAll;

/** On-screen performance HUD (GameView.debug = { hud: 'topRight' }).
 *  Lives here because three threads reach it: the JS thread configures
 *  it, the render thread lays it out, the main thread hit-tests it. */
@property (nonatomic, readonly) TGDebugHud *hud;

/** Render telemetry behind the HUD and the 'performance' event. Off
 *  until one of the two asks for it; see TGFrameStats. */
@property (nonatomic, readonly) TGFrameStats *stats;

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

// Global time multiplier: 1 = normal, 0.5 = slow motion, 0 = frozen.
// Scales the dt fed to sprites, emitters, ropes, camera and shake —
// rendering and touch input keep running, so 0 works as a pause that
// still draws (menus, hit-stop juice).
@property (atomic, assign) float timeScale;

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

// --- Game-clock timers --------------------------------------------------
// Ticked with the timeScale-scaled dt, so they slow down with the scene
// and freeze at timeScale 0 — unlike JS setTimeout. Added from the main
// thread, fired from the render thread through the listener (discrete,
// never per frame).

@property (atomic, weak) id<TGSceneTimerListener> timerListener;

/** Schedules a timer on the game clock; returns its cancel id. */
- (int)addTimer:(float)seconds repeats:(BOOL)repeats;
- (void)cancelTimer:(int)timerId;

/** World position of the visible rect's left/top edge (accounts for zoom). */
- (float)viewOriginX;
- (float)viewOriginY;

/** Maps a surface touch position into world space (camera + zoom). */
- (float)screenToWorldX:(float)sx;
- (float)screenToWorldY:(float)sy;

/** Maps a world position back to surface coordinates (screenFixed sprites). */
- (float)worldToScreenX:(float)wx;
- (float)worldToScreenY:(float)wy;

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
/** Points default-font text at this scene's own font instance (called
 *  automatically on add; public so a proxy can re-resolve after clearing
 *  an explicit font). */
/** This scene's built-in pixel font, created on first use. Also used by
 *  the debug HUD, which shares this one texture rather than uploading a
 *  second copy of the same 1.2 KB atlas. */
- (TGBitmapFont *)defaultFont;

- (void)resolveTextFont:(TGSprite *)sprite;
/** Adds a group in one protected scene mutation. */
- (void)addSprites:(NSArray<TGSprite *> *)sprites
		  emitters:(NSArray<TGParticleEmitter *> *)emitters
			 ropes:(NSArray<TGRope *> *)ropes
			layers:(NSArray<TGTileLayer *> *)layers;
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

- (void)addTileLayer:(TGTileLayer *)layer;
- (void)removeTileLayer:(TGTileLayer *)layer;
/** Snapshot sorted by zIndex (layers are few; sorted every call). */
- (NSArray<TGTileLayer *> *)tileLayersSnapshot;

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
								ropes:(NSArray<TGRope *> **)ropes
							   layers:(NSArray<TGTileLayer *> **)layers;

/** Ticks physics, animations and tweens, then checks collisions. Render thread. */
- (void)update:(float)dt;

/** Topmost sprite under the point (front to back), or nil. */
- (TGSprite *)hitTestX:(float)x y:(float)y;

/**
 * One-shot segment query from (x0, y0) to (x1, y1) against every visible
 * sprite carrying a collisionGroup in `groups` (nil or empty = any tagged
 * sprite). Returns the nearest hit sprite with {x, y, distance, normalX,
 * normalY} written into `out` (5 floats), or nil for a clear ray. Rect
 * hitboxes use the slab test on their AABB, circle hitboxes an exact
 * ray/circle intersection; screenFixed sprites are skipped. A ray that
 * starts inside a hitbox reports that sprite at distance 0.
 *
 * Safe from any thread — meant for discrete JS-initiated checks (line of
 * sight on an AI timer, ground probes, hitscan weapons), not per-frame
 * polling; it uses its own scratch, never the render thread's buffers.
 */
- (TGSprite *)raycastFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1
					groups:(NSSet<NSString *> *)groups out:(float *)out;

/**
 * Grid A* path query (gameView.findPath): rasterizes the visible sprites
 * whose collisionGroup is in `groups` (nil/empty = any tagged sprite)
 * into a blocked/free grid inside the bounds rect, inflated by
 * `clearance` px, and returns simplified waypoints as a flat
 * {x0, y0, x1, y1, ...} NSNumber array, or nil when no route exists.
 * Like raycast, a discrete JS-initiated query, safe from any thread.
 */
- (NSArray<NSNumber *> *)findPathFromX:(float)startX y:(float)startY
								   toX:(float)goalX y:(float)goalY
								groups:(NSSet<NSString *> *)groups
							  cellSize:(float)cellSize clearance:(float)clearance
								  minX:(float)minX minY:(float)minY
								  maxX:(float)maxX maxY:(float)maxY
							 diagonals:(BOOL)diagonals simplify:(BOOL)simplify;

@end
