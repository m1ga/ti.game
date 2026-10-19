//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SceneRenderer.java)
//
#import "TGMetalContext.h"
#import <QuartzCore/QuartzCore.h>

@class TGScene;
@class TiProxy;

/**
 * The native game loop. Driven by the TGMetalView's CADisplayLink on the
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

/** Drawable content scale, so the HUD reads the same size at 1x and on a
 *  3x Retina drawable (the surface is in drawable pixels, not points). */
@property (atomic, assign) float screenScale;

- (instancetype)initWithScene:(TGScene *)scene viewProxy:(TiProxy *)viewProxy;

/** Start a fresh clock and telemetry window. Shared device resources stay valid. */
- (void)surfaceCreated;

/** Drawable resized: viewport, projection, 'resize' event to JS. */
- (void)surfaceChangedWithWidth:(int)width height:(int)height;

/**
 * One frame: tick + encode on the view’s command buffer and available frame slot.
 *
 * frameTime must be the CADisplayLink's targetTimestamp (vsync-aligned),
 * not the wall clock at callback time — callback dispatch latency jitters
 * by milliseconds, and a jittery dt on a fixed presentation cadence is
 * visible as tween/motion stutter.
 */
- (BOOL)drawFrame:(CFTimeInterval)frameTime commandBuffer:(id<MTLCommandBuffer>)command
           target:(id<MTLTexture>)target slot:(NSUInteger)slot;

/** Forget the last frame time; the next frame ticks with dt = 0 (use after a pause). */
- (void)resetClock;

/**
 * Whether this frame is worth measuring — the HUD is on, or JS is
 * listening for 'performance'. TGMetalView reads it once per tick so it can
 * skip its own clock calls too.
 */
- (BOOL)isMeasuring;

/**
 * Closes per-frame CPU telemetry after drawable acquisition and command submission.
 * This does not measure GPU execution or confirm a physical presentation. Call only when isMeasuring
 * said yes.
 */
- (void)recordFrameCpuMs:(double)cpuMs
			   presentMs:(double)presentMs
			   presented:(BOOL)presented
	 commandFailures:(NSUInteger)commandFailures
				interval:(CFTimeInterval)interval
				  target:(CFTimeInterval)target;

@end
