//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SceneRenderer.java)
//
#import <Foundation/Foundation.h>

@class TGScene;
@class TiProxy;

/**
 * The native game loop. Driven by the TGGLView's CADisplayLink on the
 * render thread (the GLSurfaceView continuous-mode equivalent): computes
 * delta time, ticks the scene (physics, animations, tweens), lazily
 * uploads textures, then batches all sprites.
 *
 * Projection is orthographic with top-left origin, y-down, in surface
 * pixels — matching touch coordinates 1:1.
 */
@interface TGSceneRenderer : NSObject

@property (atomic, readonly) int surfaceWidth;
@property (atomic, readonly) int surfaceHeight;

- (instancetype)initWithScene:(TGScene *)scene viewProxy:(TiProxy *)viewProxy;

/** GL context (re)created: every texture and shader is gone. */
- (void)surfaceCreated;

/** Drawable resized: viewport, projection, 'resize' event to JS. */
- (void)surfaceChangedWithWidth:(int)width height:(int)height;

/**
 * One frame: tick + draw. GL context must be current.
 *
 * frameTime must be the CADisplayLink's targetTimestamp (vsync-aligned),
 * not the wall clock at callback time — callback dispatch latency jitters
 * by milliseconds, and a jittery dt on a fixed presentation cadence is
 * visible as tween/motion stutter.
 */
- (void)drawFrame:(CFTimeInterval)frameTime;

/** Forget the last frame time; the next frame ticks with dt = 0 (use after a pause). */
- (void)resetClock;

@end
