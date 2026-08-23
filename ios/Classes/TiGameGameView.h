//
//  ti.game — iOS twin of android/src/ti/game/TiGameView.java
//
#import <TitaniumKit/TitaniumKit.h>

@class TGSceneRenderer;

/**
 * TiUIView wrapping the GL surface. The renderer runs continuously on the
 * render thread (the native game loop); the TGTouchController handles all
 * interaction on the main thread. App lifecycle pauses/resumes the loop.
 */
@interface TiGameGameView : TiUIView

@property (nonatomic, readonly) TGSceneRenderer *renderer;

+ (void)installLiveViewRestartHook;
+ (void)activateRuntimeContext:(id<TiEvaluator>)context;
+ (void)shutdownAllViews;
+ (void)shutdownViewsForRuntimeContext:(id<TiEvaluator>)context;

- (void)pauseRendering;
- (void)resumeRendering;
- (void)shutdownRendering;

@end
