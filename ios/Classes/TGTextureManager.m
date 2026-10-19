#import "TGTextureManager.h"
#import "TGSpriteSheet.h"

@implementation TGTextureManager {
	TGMetalContext *_context;
	TGMetalTexture *_whiteTexture;
	NSMutableArray<TGSpriteSheet *> *_uploadedSheets;
}
- (instancetype)initWithContext:(TGMetalContext *)context
{
	if (self = [super init]) { _context = context; _uploadedSheets = [NSMutableArray array]; }
	return self;
}
- (TGMetalTexture *)whiteTexture
{
	if (!_whiteTexture) {
		MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:1 height:1 mipmapped:NO];
		d.usage = MTLTextureUsageShaderRead;
		id<MTLTexture> texture = [_context.device newTextureWithDescriptor:d];
		if (!texture) return nil;
		const uint8_t pixel[4] = {255,255,255,255};
		[texture replaceRegion:MTLRegionMake2D(0,0,1,1) mipmapLevel:0 withBytes:pixel bytesPerRow:4];
		_whiteTexture = [[TGMetalTexture alloc] initWithTexture:texture sampler:[_context samplerWithSmoothing:NO repeat:NO]];
	}
	return _whiteTexture;
}
- (TGMetalTexture *)upload:(UIImage *)image smoothing:(BOOL)smoothing repeat:(BOOL)repeat
{
	CGImageRef cgImage = image.CGImage;
	if (!cgImage) return nil;
	size_t width = CGImageGetWidth(cgImage), height = CGImageGetHeight(cgImage);
	if (!width || !height || width > SIZE_MAX / 4 / height) return nil;
	void *pixels = calloc(width * height, 4);
	if (!pixels) return nil;
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	CGContextRef bitmap = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
		colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	CGColorSpaceRelease(colorSpace);
	if (!bitmap) { free(pixels); return nil; }
	CGContextDrawImage(bitmap, CGRectMake(0,0,width,height), cgImage);
	CGContextRelease(bitmap);
	MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
	d.usage = MTLTextureUsageShaderRead;
	id<MTLTexture> texture = [_context.device newTextureWithDescriptor:d];
	if (texture) [texture replaceRegion:MTLRegionMake2D(0,0,width,height) mipmapLevel:0 withBytes:pixels bytesPerRow:width*4];
	free(pixels);
	return texture ? [[TGMetalTexture alloc] initWithTexture:texture sampler:[_context samplerWithSmoothing:smoothing repeat:repeat]] : nil;
}
- (void)track:(TGSpriteSheet *)sheet
{
	if (sheet && ![_uploadedSheets containsObject:sheet]) [_uploadedSheets addObject:sheet];
}
- (void)deleteDisposed
{
	for (NSInteger i = (NSInteger)_uploadedSheets.count - 1; i >= 0; i--) {
		TGSpriteSheet *sheet = _uploadedSheets[i];
		if ([sheet isDisposed]) { [sheet invalidateTexture]; [_uploadedSheets removeObjectAtIndex:i]; }
	}
}
@end
