#import "TGSegmentFont.h"
#import "TGSpriteBatch.h"

// Segment bits, in the conventional order:
//   0 = a (top)           3 = d (bottom)        6 = g (middle)
//   1 = b (top right)     4 = e (bottom left)
//   2 = c (bottom right)  5 = f (top left)
static const uint8_t kSegA = 0x01;
static const uint8_t kSegB = 0x02;
static const uint8_t kSegC = 0x04;
static const uint8_t kSegD = 0x08;
static const uint8_t kSegE = 0x10;
static const uint8_t kSegF = 0x20;
static const uint8_t kSegG = 0x40;

static const uint8_t kDigits[10] = {
	0x3F, // 0
	0x06, // 1
	0x5B, // 2
	0x4F, // 3
	0x66, // 4
	0x6D, // 5
	0x7D, // 6
	0x07, // 7
	0x7F, // 8
	0x6F  // 9
};

// Glyph geometry as fractions of the glyph height.
static const float kWidthRatio = 0.60f;
static const float kGapRatio = 0.28f;
static const float kThicknessRatio = 0.16f;

/** Segment mask for one character; 0 (blank) for anything undrawable. */
static uint8_t maskFor(unichar c)
{
	if (c >= '0' && c <= '9') {
		return kDigits[c - '0'];
	}
	switch (c) {
		case 'A': return 0x77;
		case 'b': return 0x7C;
		case 'C': return 0x39;
		case 'c': return 0x58;
		case 'd': return 0x5E;
		case 'E': return 0x79;
		case 'F': return 0x71;
		case 'G': return 0x3D;
		case 'H': return 0x76;
		case 'h': return 0x74;
		case 'I': return 0x30;
		case 'J': return 0x1E;
		case 'L': return 0x38;
		case 'n': return 0x54;
		case 'O': return 0x3F;
		case 'o': return 0x5C;
		case 'P': return 0x73;
		case 'r': return 0x50;
		case 'S': return 0x6D;
		case 't': return 0x78;
		case 'U': return 0x3E;
		case 'u': return 0x1C;
		case 'y': return 0x6E;
		case '-': return kSegG;
		default:  return 0;
	}
}

@implementation TGSegmentFont

+ (float)advance:(float)glyphHeight
{
	return glyphHeight * (kWidthRatio + kGapRatio);
}

+ (float)measure:(NSString *)text glyphHeight:(float)glyphHeight
{
	if (text.length == 0) {
		return 0.0f;
	}
	return text.length * [self advance:glyphHeight] - glyphHeight * kGapRatio;
}

+ (void)draw:(TGSpriteBatch *)batch
	 texture:(GLuint)whiteTexture
		text:(NSString *)text
		   x:(float)x
		   y:(float)y
 glyphHeight:(float)glyphHeight
		   r:(float)r g:(float)g b:(float)b a:(float)a
{
	if (text.length == 0) {
		return;
	}
	float w = glyphHeight * kWidthRatio;
	float t = glyphHeight * kThicknessRatio * 0.5f; // half thickness
	float step = [self advance:glyphHeight];
	float cursor = x;

	for (NSUInteger i = 0; i < text.length; i++, cursor += step) {
		unichar c = [text characterAtIndex:i];
		if (c == ' ') {
			continue;
		}
		float left = cursor + t;
		float right = cursor + w - t;
		float top = y + t;
		float middle = y + glyphHeight * 0.5f;
		float bottom = y + glyphHeight - t;

		// Two shapes the segment table can't express
		if (c == '.') {
			float dot = cursor + w * 0.5f;
			[batch drawLine:whiteTexture fromX:dot - t y:bottom toX:dot + t y:bottom
			  halfThickness:t r:r g:g b:b a:a];
			continue;
		}
		if (c == '/') {
			[batch drawLine:whiteTexture fromX:left y:bottom toX:right y:top
			  halfThickness:t r:r g:g b:b a:a];
			continue;
		}

		// Verticals run corner to corner with no inset at the middle: a gap
		// there splits '1' into two stubs that read as a colon. Overlapping
		// the middle bar is invisible at full alpha.
		uint8_t mask = maskFor(c);
		if (mask & kSegA) {
			[batch drawLine:whiteTexture fromX:left y:top toX:right y:top
			  halfThickness:t r:r g:g b:b a:a];
		}
		if (mask & kSegB) {
			[batch drawLine:whiteTexture fromX:right y:top toX:right y:middle
			  halfThickness:t r:r g:g b:b a:a];
		}
		if (mask & kSegC) {
			[batch drawLine:whiteTexture fromX:right y:middle toX:right y:bottom
			  halfThickness:t r:r g:g b:b a:a];
		}
		if (mask & kSegD) {
			[batch drawLine:whiteTexture fromX:left y:bottom toX:right y:bottom
			  halfThickness:t r:r g:g b:b a:a];
		}
		if (mask & kSegE) {
			[batch drawLine:whiteTexture fromX:left y:middle toX:left y:bottom
			  halfThickness:t r:r g:g b:b a:a];
		}
		if (mask & kSegF) {
			[batch drawLine:whiteTexture fromX:left y:top toX:left y:middle
			  halfThickness:t r:r g:g b:b a:a];
		}
		if (mask & kSegG) {
			[batch drawLine:whiteTexture fromX:left y:middle toX:right y:middle
			  halfThickness:t r:r g:g b:b a:a];
		}
	}
}

@end
