//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Path.java)
//
#import <Foundation/Foundation.h>

/**
 * Precomputed polyline a sprite walks at constant speed (followPath).
 * Built once on the main thread — including optional corner smoothing,
 * which replaces each interior corner with a sampled quadratic Bezier —
 * so the per-frame advance on the render thread is just a cursor walk
 * over cumulative segment lengths: no allocation, no bridge traffic.
 */
@interface TGPath : NSObject

@property (nonatomic, readonly) BOOL loop;
@property (nonatomic, readonly) BOOL rotate;
@property (nonatomic, readonly) float speed; // px/s
@property (nonatomic, readonly) float totalLength;

/**
 * Builds a path from raw waypoints. smoothing > 0 rounds every interior
 * corner (for loops: every corner) with that radius in px, clamped to
 * half the adjacent segment lengths. Returns nil for fewer than two
 * distinct points.
 */
+ (instancetype)buildWithPointsX:(const float *)xs y:(const float *)ys
						   count:(int)count smoothing:(float)smoothing
							loop:(BOOL)loop rotate:(BOOL)rotate speed:(float)speed;

/**
 * Advances by speed * dt and writes {x, y, headingDegrees} into out
 * (heading 0 = up, clockwise — the sprite rotation convention).
 * Returns YES once a non-looping run has reached the end.
 * Render thread only.
 */
- (BOOL)advance:(float)dt out:(float *)out;

@end
