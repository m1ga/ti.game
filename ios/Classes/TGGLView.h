//
//  ti.game — the GLSurfaceView equivalent: a CAEAGLLayer-backed view whose
//  rendering runs continuously on a dedicated render thread, driven by a
//  CADisplayLink scheduled on that thread's run loop.
//
#import <UIKit/UIKit.h>

@class TGSceneRenderer;

@interface TGGLView : UIView

- (instancetype)initWithFrame:(CGRect)frame renderer:(TGSceneRenderer *)renderer;

/** Spawns the render thread; safe to call once. */
- (void)startRendering;

/** Stops the render thread and tears down the GL context. */
- (void)stopRendering;

/** Pause/resume the loop (app lifecycle does this automatically). */
- (void)pauseRendering;
- (void)resumeRendering;

@end
