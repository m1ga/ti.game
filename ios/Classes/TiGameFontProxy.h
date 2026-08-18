//
//  ti.game — iOS twin of android/src/ti/game/FontProxy.java
//
#import <TitaniumKit/TitaniumKit.h>
#import "TGSpriteSheet.h"

@class TGBitmapFont;

/**
 * JS-facing bitmap font for createText. Three ways to build one:
 *
 *   BMFont: createFont({ font: 'assets/hud.fnt' })   // AngelCode text or JSON
 *   Grid:   createFont({ image: 'assets/mono.png', charWidth: 9, charHeight: 15 })
 *   Default: createFont({})                          // built-in pixel font
 *
 * Metrics (and BMFont kerning) parse immediately on the main thread, so
 * text lays out before the glyph texture is uploaded; the image itself
 * loads lazily on the render thread like any sprite sheet. Grid fonts map
 * the cells row-major onto `characters` (default: ASCII 32..126).
 */
@interface TiGameFontProxy : TiProxy <TGSpriteSheetLoader>

@property (nonatomic, readonly) TGBitmapFont *font;

@end
