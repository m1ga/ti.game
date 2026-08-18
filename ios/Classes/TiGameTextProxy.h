//
//  ti.game — iOS twin of android/src/ti/game/TextProxy.java
//
#import "TiGameSpriteProxy.h"

/**
 * JS-facing text sprite: createText({ font: font, text: 'SCORE 0' }).
 *
 * Extends TiGameSpriteProxy, so text carries the whole sprite API —
 * position, anchor, scale, tint, zIndex/ySort, tweens, idle wobble, flash,
 * touch events, screenFixed — and renders inside the GL scene (one quad
 * per glyph, a single batch run). Setting `text` re-lays out natively;
 * omit `font` to use the built-in pixel font.
 */
@interface TiGameTextProxy : TiGameSpriteProxy

@end
