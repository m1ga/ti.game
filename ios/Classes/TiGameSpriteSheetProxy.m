#import "TiGameSpriteSheetProxy.h"

@implementation TiGameSpriteSheetProxy {
	NSString *_imagePath;
	NSString *_atlasPath;
	NSMutableArray<NSString *> *_frameNames;
}

- (NSString *)apiName
{
	return @"ti.game.SpriteSheet";
}

- (void)_initWithProperties:(NSDictionary *)properties
{
	_frameNames = [NSMutableArray array];
	_imagePath = [TiUtils stringValue:properties[@"image"]];
	_atlasPath = [TiUtils stringValue:properties[@"atlas"]];
	int frameWidth = [TiUtils intValue:properties[@"frameWidth"] def:0];
	int frameHeight = [TiUtils intValue:properties[@"frameHeight"] def:0];
	_sheet = [[TGSpriteSheet alloc] initWithLoader:self
									gridFrameWidth:frameWidth
								   gridFrameHeight:frameHeight];
	_sheet.smoothing = [TiUtils boolValue:properties[@"smoothing"] def:YES];
	if (_imagePath == nil) {
		NSLog(@"[ERROR] createSpriteSheet requires an 'image' property");
	}
	[super _initWithProperties:properties];
}

#pragma mark TGSpriteSheetLoader — called from the render thread on first use

- (UIImage *)loadSpriteSheet:(TGSpriteSheet *)sheet
{
	if (_imagePath == nil) {
		return nil;
	}
	UIImage *image = [TiUtils image:_imagePath proxy:self];
	if (image == nil) {
		NSLog(@"[ERROR] Could not load sheet image: %@", _imagePath);
		return nil;
	}
	if (_atlasPath != nil) {
		[self parseAtlasWithImageWidth:(int)CGImageGetWidth(image.CGImage)
						   imageHeight:(int)CGImageGetHeight(image.CGImage)];
	}
	return image;
}

/** Parses a TexturePacker JSON atlas (hash or array format) into UV frames. */
- (void)parseAtlasWithImageWidth:(int)imageWidth imageHeight:(int)imageHeight
{
	NSURL *url = [TiUtils toURL:_atlasPath proxy:self];
	NSData *jsonData = (url != nil) ? [NSData dataWithContentsOfURL:url] : nil;
	NSDictionary *root = (jsonData != nil)
		? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:nil] : nil;
	id framesNode = [root isKindOfClass:[NSDictionary class]] ? root[@"frames"] : nil;
	if (framesNode == nil) {
		NSLog(@"[ERROR] Could not parse atlas '%@'", _atlasPath);
		return;
	}

	NSMutableData *frameData = [NSMutableData data];
	[_frameNames removeAllObjects];

	if ([framesNode isKindOfClass:[NSArray class]]) {
		NSUInteger i = 0;
		for (NSDictionary *entry in (NSArray *)framesNode) {
			NSString *filename = [TiUtils stringValue:entry[@"filename"]];
			[_frameNames addObject:(filename != nil) ? filename : [@(i) stringValue]];
			[self appendFrame:entry[@"frame"] to:frameData
				   imageWidth:imageWidth imageHeight:imageHeight];
			i++;
		}
	} else if ([framesNode isKindOfClass:[NSDictionary class]]) {
		NSDictionary *hash = framesNode;
		NSArray<NSString *> *names =
			[hash.allKeys sortedArrayUsingSelector:@selector(compare:)];
		for (NSString *name in names) {
			[_frameNames addObject:name];
			[self appendFrame:hash[name][@"frame"] to:frameData
				   imageWidth:imageWidth imageHeight:imageHeight];
		}
	}
	[self.sheet setFrameData:frameData];
}

- (void)appendFrame:(NSDictionary *)f to:(NSMutableData *)data
		 imageWidth:(int)imageWidth imageHeight:(int)imageHeight
{
	int x = [TiUtils intValue:f[@"x"] def:0];
	int y = [TiUtils intValue:f[@"y"] def:0];
	int w = [TiUtils intValue:f[@"w"] def:0];
	int h = [TiUtils intValue:f[@"h"] def:0];
	TGFrame frame;
	frame.u0 = x / (float)imageWidth;
	frame.v0 = y / (float)imageHeight;
	frame.u1 = (x + w) / (float)imageWidth;
	frame.v1 = (y + h) / (float)imageHeight;
	frame.width = w;
	frame.height = h;
	[data appendBytes:&frame length:sizeof(TGFrame)];
}

#pragma mark JS surface

/** Frame index for an atlas frame name, or -1. Lets JS build animations by name. */
- (NSNumber *)frameIndex:(id)args
{
	ENSURE_SINGLE_ARG(args, NSString);
	NSUInteger index = [_frameNames indexOfObject:args];
	return @(index == NSNotFound ? -1 : (NSInteger)index);
}

- (NSNumber *)frameCount
{
	return @([self.sheet frameCount]);
}

- (NSArray<NSString *> *)frameNames
{
	return [_frameNames copy];
}

@end
