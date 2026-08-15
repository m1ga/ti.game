#import "TGSpriteSheet.h"
#import "TGTextureManager.h"

@implementation TGSpriteSheet {
	__weak id<TGSpriteSheetLoader> _loader;
	NSData *_frameData;        // TGFrame[] — atomic swap via @synchronized
	volatile GLint _textureId;
	volatile BOOL _loadFailed;
}

- (instancetype)initWithLoader:(id<TGSpriteSheetLoader>)loader
				gridFrameWidth:(int)gridFrameWidth
			   gridFrameHeight:(int)gridFrameHeight
{
	if (self = [super init]) {
		_loader = loader;
		_gridFrameWidth = gridFrameWidth;
		_gridFrameHeight = gridFrameHeight;
		_smoothing = YES;
		_textureId = -1;
	}
	return self;
}

- (void)setFrameData:(NSData *)frameData
{
	@synchronized (self) {
		_frameData = frameData;
	}
}

- (NSData *)frameData
{
	@synchronized (self) {
		return _frameData;
	}
}

- (NSUInteger)frameCount
{
	return [self frameData].length / sizeof(TGFrame);
}

- (BOOL)frame:(NSInteger)index into:(TGFrame *)out
{
	NSData *data = [self frameData];
	NSUInteger count = data.length / sizeof(TGFrame);
	if (count == 0) {
		return NO;
	}
	if (index < 0 || (NSUInteger)index >= count) {
		index = 0;
	}
	*out = ((const TGFrame *)data.bytes)[index];
	return YES;
}

- (float)frameWidth:(NSInteger)index
{
	TGFrame f;
	return [self frame:index into:&f] ? f.width : 0.0f;
}

- (float)frameHeight:(NSInteger)index
{
	TGFrame f;
	return [self frame:index into:&f] ? f.height : 0.0f;
}

- (GLint)textureId
{
	return _textureId;
}

- (BOOL)isReady
{
	return _textureId >= 0 && [self frameCount] > 0;
}

- (void)ensureLoaded:(TGTextureManager *)textures
{
	if (_textureId >= 0 || _loadFailed) {
		return;
	}
	id<TGSpriteSheetLoader> loader = _loader;
	UIImage *image = (loader != nil) ? [loader loadSpriteSheet:self] : nil;
	if (image == nil || image.CGImage == NULL) {
		_loadFailed = YES;
		return;
	}
	int imageWidth = (int)CGImageGetWidth(image.CGImage);
	int imageHeight = (int)CGImageGetHeight(image.CGImage);
	if ([self frameCount] == 0 && _gridFrameWidth > 0 && _gridFrameHeight > 0) {
		[self setFrameData:[TGSpriteSheet buildGridFramesWithImageWidth:imageWidth
															imageHeight:imageHeight
															 frameWidth:_gridFrameWidth
															frameHeight:_gridFrameHeight]];
	}
	_textureId = (GLint)[textures upload:image smoothing:self.smoothing repeat:self.repeat];
}

- (void)invalidateTexture
{
	_textureId = -1;
	_loadFailed = NO;
}

+ (NSData *)buildGridFramesWithImageWidth:(int)imageWidth
							  imageHeight:(int)imageHeight
							   frameWidth:(int)frameWidth
							  frameHeight:(int)frameHeight
{
	int cols = MAX(1, imageWidth / frameWidth);
	int rows = MAX(1, imageHeight / frameHeight);
	NSMutableData *data = [NSMutableData dataWithLength:sizeof(TGFrame) * cols * rows];
	TGFrame *frames = (TGFrame *)data.mutableBytes;
	int i = 0;
	for (int row = 0; row < rows; row++) {
		for (int col = 0; col < cols; col++) {
			TGFrame f;
			f.u0 = (col * frameWidth) / (float)imageWidth;
			f.v0 = (row * frameHeight) / (float)imageHeight;
			f.u1 = ((col + 1) * frameWidth) / (float)imageWidth;
			f.v1 = ((row + 1) * frameHeight) / (float)imageHeight;
			f.width = frameWidth;
			f.height = frameHeight;
			frames[i++] = f;
		}
	}
	return data;
}

@end
