//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SkidTrail.java)
//
#import <Foundation/Foundation.h>
#import <OpenGLES/ES2/gl.h>

@class TGSpriteBatch;

/**
 * Ring buffer of fading skid-mark segments, emitted by carMode sprites with
 * skidMarks enabled. Appended, aged and drawn on the render thread only — no
 * synchronization needed. When full, the oldest segments are overwritten;
 * faded-out segments drop off the tail, so memory stays bounded and old
 * marks fade away instead of accumulating forever.
 */
@interface TGSkidTrail : NSObject

- (void)addFromX:(float)x0 y:(float)y0 toX:(float)x1 y:(float)y1
	   halfWidth:(float)halfWidth alpha:(float)alpha;
- (BOOL)isEmpty;

/** Ages all segments and drops fully faded ones from the tail. */
- (void)update:(float)dt;

- (void)draw:(TGSpriteBatch *)batch whiteTexture:(GLuint)whiteTexture;
- (void)clear;

@end
