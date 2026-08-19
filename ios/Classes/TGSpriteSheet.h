//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/SpriteSheet.java)
//
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>

@class TGSpriteSheet;
@class TGTextureManager;

/** One frame: UV rect in the texture plus its pixel size. */
typedef struct {
	float u0, v0, u1, v1;
	float width, height;
} TGFrame;

@protocol TGSpriteSheetLoader <NSObject>
/** Decode the sheet image and (for atlas sheets) parse frames. May run on the render thread. */
- (UIImage *)loadSpriteSheet:(TGSpriteSheet *)sheet;
@end

/**
 * Native sprite sheet: one texture plus a frame table of UV rects. Built
 * either from a simple grid (frameWidth/frameHeight) or a TexturePacker-style
 * JSON atlas. The image is decoded lazily and uploaded to GL on first use
 * by the render loop.
 */
@interface TGSpriteSheet : NSObject

/** NO = GL_NEAREST filtering — crisp pixels for pixel-art sheets. */
@property (atomic, assign) BOOL smoothing;

/** YES = GL_REPEAT wrap so sprites with tileRepeat tile the texture.
 *  ES 2.0 requires power-of-two texture dimensions for this. */
@property (atomic, assign) BOOL repeat;

// Grid parameters; 0 means "atlas sheet", frames come from JSON
@property (nonatomic, readonly) int gridFrameWidth;
@property (nonatomic, readonly) int gridFrameHeight;

- (instancetype)initWithLoader:(id<TGSpriteSheetLoader>)loader
				gridFrameWidth:(int)gridFrameWidth
			   gridFrameHeight:(int)gridFrameHeight;

/** frames: contiguous TGFrame array wrapped in NSData (atomic publication). */
- (void)setFrameData:(NSData *)frameData;
- (NSUInteger)frameCount;
- (BOOL)frame:(NSInteger)index into:(TGFrame *)out;
- (float)frameWidth:(NSInteger)index;
- (float)frameHeight:(NSInteger)index;

- (GLint)textureId;
- (BOOL)isReady;

/**
 * Called from the render thread each frame until the texture exists. Decodes
 * the image via the loader, builds grid frames if needed, and uploads.
 */
- (void)ensureLoaded:(TGTextureManager *)textures;

/** Drops the GL texture reference after context loss so it reloads. */
- (void)invalidateTexture;

/** Grid frame UVs; `inset` pulls interior edges in by half a texel
 *  (linear-filtered sheets) so magnified edges don't bleed neighbors. */
+ (NSData *)buildGridFramesWithImageWidth:(int)imageWidth
							  imageHeight:(int)imageHeight
							   frameWidth:(int)frameWidth
							  frameHeight:(int)frameHeight
									inset:(BOOL)inset;

@end
