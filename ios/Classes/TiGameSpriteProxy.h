//
//  ti.game — iOS twin of android/src/ti/game/SpriteProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGSprite.h"

/**
 * JS-facing sprite. Setting properties writes straight into the native
 * TGSprite in the renderer's scene graph — nothing here runs per frame.
 *
 * Events fired natively: press, tap, release, dragstart, drag, dragend,
 * pinch, rotate, animationcomplete, complete (tween finished), collision,
 * land.
 */
@interface TiGameSpriteProxy : TiProxy <TGSpriteEventListener>

@property (nonatomic, readonly) TGSprite *sprite;

/** Subclasses (TiGameTextProxy) supply their own TGSprite specialization. */
- (instancetype)initWithSprite:(TGSprite *)sprite;

@end
