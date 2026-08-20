//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Pathfinder.java)
//
#import <Foundation/Foundation.h>

@class TGSprite;

/**
 * Grid A* over the scene's collision sprites (gameView.findPath): visible
 * sprites carrying a matching collisionGroup are rasterized into a
 * blocked/free grid, A* routes around them (diagonals never cut corners),
 * and a line-of-sight pass reduces the cell chain to the few waypoints
 * followPath actually needs. Everything is built per query on the caller's
 * thread — a discrete query like raycast, with no per-frame state and no
 * render-thread buffers.
 */
@interface TGPathfinder : NSObject

/**
 * Runs the query; world coordinates in, world coordinates out. Returns
 * flat {x0, y0, x1, y1, ...} waypoints as NSNumbers — the exact start
 * first and the exact goal last (a snapped start/goal uses its free cell
 * center instead) — or nil when the bounds are degenerate, the grid is
 * too large, or no route exists.
 */
+ (NSArray<NSNumber *> *)findInSprites:(NSArray<TGSprite *> *)sprites
								groups:(NSSet<NSString *> *)groups
								startX:(float)startX startY:(float)startY
								 goalX:(float)goalX goalY:(float)goalY
							  cellSize:(float)cellSize clearance:(float)clearance
								  minX:(float)minX minY:(float)minY
								  maxX:(float)maxX maxY:(float)maxY
							 diagonals:(BOOL)diagonals simplify:(BOOL)simplify;

@end
