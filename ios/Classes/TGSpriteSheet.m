#import "TGSpriteSheet.h"
#import "TGTextureManager.h"
#import <stdatomic.h>
#import <stdint.h>

@implementation TGSpriteSheet {
	__weak id<TGSpriteSheetLoader> _loader;
	// Frame tables are immutable after publication. Old versions stay retained
	// for the sheet lifetime, so a concurrent reader can never observe freed
	// bytes while an atlas is being replaced.
	NSMutableArray<NSData *> *_frameDataHistory;
	atomic_uintptr_t _publishedFrames;
	atomic_size_t _publishedFrameCount;
	atomic_int _textureId;
	atomic_bool _loadFailed;
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
		_frameDataHistory = [NSMutableArray array];
		atomic_init(&_publishedFrames, (uintptr_t)NULL);
		atomic_init(&_publishedFrameCount, 0);
		atomic_init(&_textureId, -1);
		atomic_init(&_loadFailed, false);
	}
	return self;
}

- (void)setFrameData:(NSData *)frameData
{
	NSData *published = [frameData copy] ?: [NSData data];
	@synchronized (self) {
		[_frameDataHistory addObject:published];
		atomic_store_explicit(&_publishedFrames, (uintptr_t)published.bytes, memory_order_relaxed);
		atomic_store_explicit(&_publishedFrameCount,
			published.length / sizeof(TGFrame), memory_order_release);
	}
}

- (NSUInteger)frameCount
{
	return atomic_load_explicit(&_publishedFrameCount, memory_order_acquire);
}

- (BOOL)frame:(NSInteger)index into:(TGFrame *)out
{
	NSUInteger count = atomic_load_explicit(&_publishedFrameCount, memory_order_acquire);
	if (count == 0) {
		return NO;
	}
	if (index < 0 || (NSUInteger)index >= count) {
		index = 0;
	}
	const TGFrame *frames = (const TGFrame *)atomic_load_explicit(
		&_publishedFrames, memory_order_acquire);
	if (frames == NULL) {
		return NO;
	}
	*out = frames[index];
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
	return atomic_load_explicit(&_textureId, memory_order_acquire);
}

- (BOOL)isReady
{
	return atomic_load_explicit(&_textureId, memory_order_acquire) >= 0
		&& atomic_load_explicit(&_publishedFrameCount, memory_order_acquire) > 0;
}

- (void)ensureLoaded:(TGTextureManager *)textures
{
	if (atomic_load_explicit(&_textureId, memory_order_acquire) >= 0
		|| atomic_load_explicit(&_loadFailed, memory_order_acquire)) {
		return;
	}
	id<TGSpriteSheetLoader> loader = _loader;
	UIImage *image = (loader != nil) ? [loader loadSpriteSheet:self] : nil;
	if (image == nil || image.CGImage == NULL) {
		atomic_store_explicit(&_loadFailed, true, memory_order_release);
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
	atomic_store_explicit(&_textureId,
		(GLint)[textures upload:image smoothing:self.smoothing repeat:self.repeat],
		memory_order_release);
}

- (void)invalidateTexture
{
	atomic_store_explicit(&_textureId, -1, memory_order_release);
	atomic_store_explicit(&_loadFailed, false, memory_order_release);
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
