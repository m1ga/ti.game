//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SpriteBatch.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>
#import "TGSpriteSheet.h"

@class TGSprite;

/**
 * ES 2.0 sprite batcher: accumulates quads and issues one draw call per
 * texture change (or when full). Vertices are (x, y, u, v, r, g, b, a) with
 * the color premultiplied; textures are uploaded premultiplied, so blending
 * is (ONE, ONE_MINUS_SRC_ALPHA) and the fragment color is
 * texture * vertexColor. Untextured shapes (debug overlays) draw with the
 * TGTextureManager's 1x1 white texture. Render thread only.
 */
@interface TGSpriteBatch : NSObject

/** (Re)creates shaders; call once the GL context is current. */
- (void)createGLResources;

- (void)begin:(const float *)projectionMatrix
	screenProjection:(const float *)screenProjectionMatrix
	 originX:(float)originX
	 originY:(float)originY
	screenScale:(float)screenScale; // float[16] each, column-major
- (void)draw:(TGSprite *)sprite;

/** Screen space = the identity projection in surface pixels: screenFixed
 *  sprites (HUDs) ignore camera position, zoom and shake. Flushes the
 *  pending batch on change, like a texture or blend switch. */
- (void)setScreenSpace:(BOOL)fixed;

/** Additive = (ONE, ONE) on premultiplied colors: quads brighten the
 *  backdrop instead of covering it (glows, fire, lasers). Flushes the
 *  pending batch on change, so mode switches cost one draw call. */
- (void)setAdditiveBlend:(BOOL)additive;

/** Axis-aligned textured quad with a straight-alpha tint color —
 *  the particle path (premultiplied internally, like drawLine). */
- (void)drawFrame:(GLuint)texture frame:(TGFrame)f
			   cx:(float)cx cy:(float)cy
			halfW:(float)halfW halfH:(float)halfH
				r:(float)r g:(float)g b:(float)b a:(float)a;

/** Textured quad oriented along a segment (rope links): u runs across
 *  the width, v along the segment. */
- (void)drawSegment:(GLuint)texture frame:(TGFrame)f
			  fromX:(float)x0 y:(float)y0
				toX:(float)x1 y:(float)y1
		  halfWidth:(float)halfWidth alpha:(float)alpha;

/** Debug/shape helper: a solid line segment of the given half-thickness,
 *  drawn with `texture` (normally the white texture). Color is
 *  straight-alpha; premultiplied internally. */
- (void)drawLine:(GLuint)texture
		   fromX:(float)x0 y:(float)y0
			 toX:(float)x1 y:(float)y1
   halfThickness:(float)halfThickness
			   r:(float)r g:(float)g b:(float)b a:(float)a;

- (void)end;

@end
