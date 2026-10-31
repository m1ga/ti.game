// Twin of android/src/ti/game/engine/Broadphase.java
#import <Foundation/Foundation.h>

@class TGSprite;

NS_ASSUME_NONNULL_BEGIN

/**
 * Uniform-grid broadphase over the scene's per-frame tagged list (the
 * visible sprites that carry a collisionGroup). A query walks only the grid
 * cells its box covers instead of the whole list. Entry boxes are inflated
 * by the sprite's own frame delta plus a small slack, so a solid pushed out
 * after the build is still found by later movers. Conservative: a candidate
 * still has to pass the exact shape test. Render thread only.
 */
@interface TGBroadphase : NSObject

/** Index the tagged list at its current positions. wrapWidth 0 = no world wrap. */
- (void)rebuild:(NSArray<TGSprite *> *)tagged wrapWidth:(float)wrapWidth;

/** Candidates near the sprite's own hit shape (rect AABB or circle). */
- (NSArray<TGSprite *> *)queryShape:(TGSprite *)s;

/** Like queryShape, extended back over the frame's movement (swept tests). */
- (NSArray<TGSprite *> *)querySwept:(TGSprite *)s;

/**
 * Tagged sprites whose inflated entry box may touch the given box (the query
 * sprite itself included when tagged). The returned array is reused by the
 * next query — consume it before querying again. Every sprite in it carries
 * the current stamp.
 */
- (NSArray<TGSprite *> *)query:(TGSprite *)s minX:(float)minX minY:(float)minY maxX:(float)maxX maxY:(float)maxY;

/** Stamp written on every sprite the latest query returned. */
- (int)stamp;

@end

NS_ASSUME_NONNULL_END
