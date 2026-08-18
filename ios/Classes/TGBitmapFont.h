//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/BitmapFont.java)
//
#import <Foundation/Foundation.h>

@class TGSpriteSheet;

/** One character: its frame in the sheet plus placement metrics. */
typedef struct {
	int frameIndex;
	float width, height;    // px in the atlas
	float xOffset, yOffset; // pen-relative placement
	float xAdvance;         // pen movement after this glyph
} TGGlyph;

/**
 * Native bitmap font: a glyph atlas texture plus per-character metrics.
 * Built either from a monospace grid (charWidth/charHeight + a characters
 * string) or a BMFont/AngelCode descriptor (proportional glyphs, kerning).
 *
 * Metrics are set once at parse time on the main thread; only the texture
 * upload is lazy (via the wrapped TGSpriteSheet, on the render thread), so
 * text layout never has to wait for GL.
 */
@interface TGBitmapFont : NSObject

/** Glyph texture; frames indexed by TGGlyph.frameIndex. */
@property (nonatomic, readonly) TGSpriteSheet *sheet;

@property (atomic, assign) float lineHeight;

- (instancetype)initWithSheet:(TGSpriteSheet *)sheet;

/** glyphs: TGGlyph structs boxed in NSValue, keyed by character code. */
- (void)setGlyphs:(NSDictionary<NSNumber *, NSValue *> *)glyphs;
/** kerning: amounts keyed by (first << 16) | second. */
- (void)setKerning:(NSDictionary<NSNumber *, NSNumber *> *)kerning;

- (BOOL)glyphForCharacter:(int)character into:(TGGlyph *)out;
/** Kerning adjustment between two characters (0 for most pairs). */
- (float)kernFirst:(int)first second:(int)second;
/** Pen advance for characters the font has no glyph for. */
- (float)missingAdvance;

/**
 * Monospace grid font: the image is a row-major grid of charWidth x
 * charHeight cells, one per character of `characters`. The wrapped
 * sheet builds matching grid frames when its texture loads.
 */
+ (TGBitmapFont *)gridFontWithSheet:(TGSpriteSheet *)sheet
						 characters:(NSString *)characters
						  charWidth:(float)charWidth
						 charHeight:(float)charHeight;

@end
