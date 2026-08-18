//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/TextSprite.java)
//
#import <Foundation/Foundation.h>
#import "TGSprite.h"

@class TGBitmapFont;

typedef NS_ENUM(int, TGTextAlign) {
	TGTextAlignLeft = 0,
	TGTextAlignCenter = 1,
	TGTextAlignRight = 2
};

/** Immutable glyph layout in local space (origin = text block top-left). */
@interface TGTextLayout : NSObject
@property (nonatomic, readonly) int count;
@property (nonatomic, readonly) const float *quads;      // per glyph: x, y, w, h
@property (nonatomic, readonly) const int *frameIndices; // per glyph: frame in the font's sheet
@property (nonatomic, readonly) float width;
@property (nonatomic, readonly) float height;
@end

/**
 * A sprite whose frame is a laid-out string of bitmap-font glyphs. Because
 * it IS a TGSprite in the scene graph, everything sprites do — zIndex/ySort,
 * tweens, idle wobble, tint, flash, camera, touch, even collision — works
 * on text unchanged; only drawing differs (one quad per glyph, all from
 * the font's texture, so a label still renders as a single batch run).
 *
 * Layout runs natively whenever `text` or a layout property changed, and
 * is cached until then: setters just nil the cache, and whichever thread
 * touches the text next (render draw, touch hit-test, JS width read)
 * rebuilds it.
 */
@interface TGTextSprite : TGSprite

@property (atomic, strong) TGBitmapFont *font;

// YES = no explicit font was given: the scene assigns its own
// default-font instance when the sprite is added (fonts hold a GL
// texture, so they must belong to the view that renders them).
@property (atomic, assign) BOOL usesDefaultFont;

- (NSString *)text;
- (void)setText:(NSString *)text;
- (TGTextAlign)align;
- (void)setAlign:(TGTextAlign)align;
- (float)letterSpacing; // extra px between glyphs
- (void)setLetterSpacing:(float)letterSpacing;
- (float)lineSpacing;   // multiplier on font lineHeight
- (void)setLineSpacing:(float)lineSpacing;

/** Sets the font and points the inherited sheet at its texture. */
- (void)setTextFont:(TGBitmapFont *)font;

/** Current glyph layout, rebuilding if a setter invalidated it. */
- (TGTextLayout *)layout;

@end
