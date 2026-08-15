//
//  ti.game — iOS twin of android/src/ti/game/SpriteSheetProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGSpriteSheet.h"

/**
 * JS-facing sprite sheet. Supports two formats:
 *
 *   Grid:   createSpriteSheet({ image: 'hero.png', frameWidth: 64, frameHeight: 64 })
 *   Atlas:  createSpriteSheet({ image: 'hero.png', atlas: 'hero.json' })  // TexturePacker JSON
 *
 * The image is decoded and uploaded on the render thread the first time a
 * sprite using this sheet is rendered.
 */
@interface TiGameSpriteSheetProxy : TiProxy <TGSpriteSheetLoader>

@property (nonatomic, readonly) TGSpriteSheet *sheet;

@end
