//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SpriteBatch.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

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

- (void)begin:(const float *)projectionMatrix; // float[16], column-major
- (void)draw:(TGSprite *)sprite;

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
