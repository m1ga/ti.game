#import "TGAnimation.h"

@implementation TGAnimation {
	int *_frameStorage;
}

- (instancetype)initWithName:(NSString *)name
					  frames:(NSArray<NSNumber *> *)frames
						 fps:(float)fps
						loop:(BOOL)loop
{
	if (self = [super init]) {
		_name = [name copy];
		_frameCount = frames.count;
		_frameStorage = malloc(sizeof(int) * MAX(_frameCount, (NSUInteger)1));
		for (NSUInteger i = 0; i < _frameCount; i++) {
			_frameStorage[i] = frames[i].intValue;
		}
		_frames = _frameStorage;
		_fps = (fps > 0.0f) ? fps : 12.0f;
		_loop = loop;
	}
	return self;
}

- (void)dealloc
{
	free(_frameStorage);
}

@end
