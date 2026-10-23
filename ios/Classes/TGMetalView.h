#import <UIKit/UIKit.h>
@class TGSceneRenderer;

/** CAMetalLayer surface; native display clock and simulation live on a dedicated thread. */
@interface TGMetalView : UIView
/** Main-thread drawable layout notification, independent of the render loop. */
@property(nonatomic, copy) void (^drawableScaleChanged)(CGFloat scale);
- (instancetype)initWithFrame:(CGRect)frame renderer:(TGSceneRenderer *)renderer;
- (void)startRendering;
- (void)stopRendering;
- (void)pauseRendering;
- (void)resumeRendering;
- (void)setMaxFps:(int)maxFps;
@end
