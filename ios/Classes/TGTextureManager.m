#import "TGTextureManager.h"
#import "TGSpriteSheet.h"

@implementation TGTextureManager {
	NSMutableArray<TGSpriteSheet *> *_uploadedSheets;
	GLint _whiteTextureId;
}

- (instancetype)init
{
	if (self = [super init]) {
		_uploadedSheets = [NSMutableArray array];
		_whiteTextureId = -1;
	}
	return self;
}

- (GLuint)whiteTexture
{
	if (_whiteTextureId < 0) {
		GLuint textureId = 0;
		glGenTextures(1, &textureId);
		glBindTexture(GL_TEXTURE_2D, textureId);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		const uint8_t pixel[4] = { 255, 255, 255, 255 };
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
		_whiteTextureId = (GLint)textureId;
	}
	return (GLuint)_whiteTextureId;
}

- (GLuint)upload:(UIImage *)image smoothing:(BOOL)smoothing repeat:(BOOL)repeat
{
	// Decode into premultiplied RGBA — matches the (ONE, ONE_MINUS_SRC_ALPHA)
	// blend mode used by the batcher (same as Android's GLUtils upload).
	CGImageRef cgImage = image.CGImage;
	size_t width = CGImageGetWidth(cgImage);
	size_t height = CGImageGetHeight(cgImage);
	void *pixels = calloc(width * height * 4, 1);
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
		colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(colorSpace);
	if (context == NULL) {
		free(pixels);
		return 0;
	}
	CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
	CGContextRelease(context);

	GLint filter = smoothing ? GL_LINEAR : GL_NEAREST;
	GLint wrap = repeat ? GL_REPEAT : GL_CLAMP_TO_EDGE;
	GLuint textureId = 0;
	glGenTextures(1, &textureId);
	glBindTexture(GL_TEXTURE_2D, textureId);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, filter);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, filter);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)width, (GLsizei)height, 0,
		GL_RGBA, GL_UNSIGNED_BYTE, pixels);
	free(pixels);
	return textureId;
}

- (void)track:(TGSpriteSheet *)sheet
{
	if (sheet != nil && ![_uploadedSheets containsObject:sheet]) {
		[_uploadedSheets addObject:sheet];
	}
}

- (void)invalidateAll
{
	for (TGSpriteSheet *sheet in _uploadedSheets) {
		[sheet invalidateTexture];
	}
	[_uploadedSheets removeAllObjects];
	_whiteTextureId = -1;
}

@end
