//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/DefaultFont.java)
//
#import <Foundation/Foundation.h>
#import "TGSpriteSheet.h"

@class TGBitmapFont;

/**
 * The built-in pixel font used when createFont()/createText() get no font:
 * a 9x15 monospace glyph grid (ASCII 32..126, 16 columns), embedded as a
 * ~1.2 KB PNG so it needs no asset resolution on any platform. Generated
 * from Noto Sans Mono Bold 14px by tools/genfont.py --grid.
 */
@interface TGDefaultFont : NSObject <TGSpriteSheetLoader>

/** A fresh font instance per call — GL texture names are per-context, so
 *  a shared singleton would go stale (or alias another view's texture) as
 *  soon as a second GameView creates its own GL context. Scenes and font
 *  proxies each own their instance, like any sprite sheet. */
+ (TGBitmapFont *)makeFont;

@end
