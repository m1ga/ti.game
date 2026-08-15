//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Animation.java)
//
#import <Foundation/Foundation.h>

/** Immutable description of a sprite-sheet animation: frame indices + timing. */
@interface TGAnimation : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) const int *frames;
@property (nonatomic, readonly) NSUInteger frameCount;
@property (nonatomic, readonly) float fps;
@property (nonatomic, readonly) BOOL loop;

- (instancetype)initWithName:(NSString *)name
					  frames:(NSArray<NSNumber *> *)frames
						 fps:(float)fps
						loop:(BOOL)loop;

@end
