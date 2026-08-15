//
//  ti.game — iOS twin of android/src/ti/game/GameViewProxy.java
//
#import <TitaniumKit/TitaniumKit.h>

@class TGScene;
@class TGSceneRenderer;

/**
 * The game canvas: createGameView({ backgroundColor: '#202030' }).
 *
 * Owns the native TGScene, so sprites can be added before (or after) the
 * view is realized. Rendering runs continuously once the view is on screen.
 */
@interface TiGameGameViewProxy : TiViewProxy

@property (nonatomic, readonly) TGScene *scene;

@end
