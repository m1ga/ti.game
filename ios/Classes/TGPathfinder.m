//
//  ti.game — engine (iOS twin of android/src/ti/game/engine/Pathfinder.java)
//
#import "TGPathfinder.h"
#import "TGSprite.h"
#import "TGTileLayer.h"
#import <float.h>
#import <limits.h>
#import <math.h>
#import <stdlib.h>
#import <string.h>

// Hard cap on the grid (cols * rows) — a runaway bounds/cellSize combo
// fails the query instead of allocating without limit.
static const int kMaxCells = 1 << 20;

// How many rings of cells a blocked start/goal may snap outward to the
// nearest free cell (tapping on an obstacle walks to its edge).
static const int kSnapRings = 4;

static const float kSqrt2 = 1.41421356f;

// Tolerance (in cell units) when mapping box edges to cell indices, so
// float noise on an exactly grid-aligned edge can't flip the cell.
static const float kEdgeEps = 1e-4f;

/** Grid column/row of a world coordinate, clamped into the grid. */
static int TGCellFor(float v, float min, float cellSize, int limit)
{
	int c = (int)floorf((v - min) / cellSize);
	return MIN(MAX(c, 0), limit - 1);
}

/**
 * Marks every cell a matching sprite's clearance-inflated hitbox touches.
 * Same sprite filter as raycast: visible, tagged with a collisionGroup in
 * `groups` (nil/empty = any), not screenFixed.
 */
static void TGRasterize(NSArray<TGSprite *> *sprites, NSSet<NSString *> *groups,
						bool *blocked, int cols, int rows,
						float cellSize, float clearance, float minX, float minY)
{
	float box[4];
	float center[2];
	for (TGSprite *s in sprites) {
		NSString *group = s.collisionGroup;
		if (group == nil || !s.visible || s.screenFixed
				|| (groups != nil && groups.count > 0 && ![groups containsObject:group])) {
			continue;
		}
		if (s.circleHitbox) {
			[s hitCenter:center];
			float r = [s hitRadius] + clearance;
			int cx0 = MAX(0, (int)floorf((center[0] - r - minX) / cellSize));
			int cy0 = MAX(0, (int)floorf((center[1] - r - minY) / cellSize));
			int cx1 = MIN(cols - 1, (int)floorf((center[0] + r - minX) / cellSize));
			int cy1 = MIN(rows - 1, (int)floorf((center[1] + r - minY) / cellSize));
			for (int cy = cy0; cy <= cy1; cy++) {
				for (int cx = cx0; cx <= cx1; cx++) {
					// circle vs cell rect: closest point on the cell
					float cellMinX = minX + cx * cellSize;
					float cellMinY = minY + cy * cellSize;
					float qx = MIN(MAX(center[0], cellMinX), cellMinX + cellSize);
					float qy = MIN(MAX(center[1], cellMinY), cellMinY + cellSize);
					float dx = center[0] - qx;
					float dy = center[1] - qy;
					if (dx * dx + dy * dy < r * r) {
						blocked[cy * cols + cx] = true;
					}
				}
			}
		} else {
			[s computeAABB:box];
			// Half-open on the max side: a box ending exactly on a cell
			// boundary overlaps zero of the next cell — grid-aligned
			// walls (tile mazes) must not bleed into the corridor
			// beside them.
			int cx0 = (int)floorf((box[0] - clearance - minX) / cellSize + kEdgeEps);
			int cy0 = (int)floorf((box[1] - clearance - minY) / cellSize + kEdgeEps);
			int cx1 = (int)ceilf((box[2] + clearance - minX) / cellSize - kEdgeEps) - 1;
			int cy1 = (int)ceilf((box[3] + clearance - minY) / cellSize - kEdgeEps) - 1;
			if (cx1 < 0 || cy1 < 0 || cx0 >= cols || cy0 >= rows) {
				continue;
			}
			cx0 = MAX(cx0, 0);
			cy0 = MAX(cy0, 0);
			cx1 = MIN(cx1, cols - 1);
			cy1 = MIN(cy1, rows - 1);
			for (int cy = cy0; cy <= cy1; cy++) {
				int base = cy * cols;
				for (int cx = cx0; cx <= cx1; cx++) {
					blocked[base + cx] = true;
				}
			}
		}
	}
}

/**
 * Marks every grid cell a solid tile (inflated by `clearance`) touches,
 * for the layers whose collisionGroup matches. One-way platforms are
 * left open — a walker passes through them. Only the tiles inside the
 * search bounds are visited, so a huge map with a small query stays cheap.
 */
static void TGRasterizeTiles(NSArray<TGTileLayer *> *layers, NSSet<NSString *> *groups,
							 bool *blocked, int cols, int rows,
							 float cellSize, float clearance, float minX, float minY)
{
	float maxX = minX + cols * cellSize;
	float maxY = minY + rows * cellSize;
	for (TGTileLayer *layer in layers) {
		if (![layer matches:groups]) {
			continue;
		}
		float tw = [layer cellWidth];
		float th = [layer cellHeight];
		if (tw <= 0.0f || th <= 0.0f) {
			continue;
		}
		float lx = layer.x;
		float ly = layer.y;
		int tc0 = MAX(0, (int)floorf((minX - clearance - lx) / tw));
		int tc1 = MIN([layer cols] - 1, (int)floorf((maxX + clearance - lx) / tw));
		int tr0 = MAX(0, (int)floorf((minY - clearance - ly) / th));
		int tr1 = MIN([layer rows] - 1, (int)floorf((maxY + clearance - ly) / th));
		for (int row = tr0; row <= tr1; row++) {
			for (int col = tc0; col <= tc1; col++) {
				if (![layer isSolidCol:col row:row]) {
					continue;
				}
				float bx0 = lx + col * tw;
				float by0 = ly + row * th;
				// same half-open edge rule as sprite boxes
				int cx0 = (int)floorf((bx0 - clearance - minX) / cellSize + kEdgeEps);
				int cy0 = (int)floorf((by0 - clearance - minY) / cellSize + kEdgeEps);
				int cx1 = (int)ceilf((bx0 + tw + clearance - minX) / cellSize - kEdgeEps) - 1;
				int cy1 = (int)ceilf((by0 + th + clearance - minY) / cellSize - kEdgeEps) - 1;
				if (cx1 < 0 || cy1 < 0 || cx0 >= cols || cy0 >= rows) {
					continue;
				}
				cx0 = MAX(cx0, 0);
				cy0 = MAX(cy0, 0);
				cx1 = MIN(cx1, cols - 1);
				cy1 = MIN(cy1, rows - 1);
				for (int cy = cy0; cy <= cy1; cy++) {
					int base = cy * cols;
					for (int cx = cx0; cx <= cx1; cx++) {
						blocked[base + cx] = true;
					}
				}
			}
		}
	}
}

/** The cell itself if free, else the nearest free cell within kSnapRings
 *  rings of it, else -1. */
static int TGSnapToFree(const bool *blocked, int cols, int rows, int cx, int cy)
{
	if (!blocked[cy * cols + cx]) {
		return cy * cols + cx;
	}
	for (int r = 1; r <= kSnapRings; r++) {
		int best = -1;
		int bestD2 = INT_MAX;
		for (int dy = -r; dy <= r; dy++) {
			for (int dx = -r; dx <= r; dx++) {
				if (MAX(abs(dx), abs(dy)) != r) {
					continue; // perimeter of the ring only
				}
				int nx = cx + dx;
				int ny = cy + dy;
				if (nx < 0 || ny < 0 || nx >= cols || ny >= rows
						|| blocked[ny * cols + nx]) {
					continue;
				}
				int d2 = dx * dx + dy * dy;
				if (d2 < bestD2) {
					bestD2 = d2;
					best = ny * cols + nx;
				}
			}
		}
		if (best >= 0) {
			return best;
		}
	}
	return -1;
}

static float TGHeuristic(int x, int y, int gx, int gy, BOOL diagonals)
{
	int dx = abs(x - gx);
	int dy = abs(y - gy);
	return diagonals ? dx + dy + (kSqrt2 - 2.0f) * MIN(dx, dy) : dx + dy;
}

// Min-heap of {f, cell} entries encoded in one uint64: the raw bits of a
// non-negative float sort like the float itself, so plain integer order
// pops the lowest f. Stale duplicates skip via the closed set.
typedef struct {
	uint64_t *items;
	int size;
	int capacity;
} TGHeap;

static uint64_t TGEncode(float f, int cell)
{
	uint32_t bits;
	memcpy(&bits, &f, sizeof(bits));
	return ((uint64_t)bits << 32) | (uint32_t)cell;
}

static void TGHeapPush(TGHeap *heap, uint64_t value)
{
	if (heap->size == heap->capacity) {
		heap->capacity *= 2;
		heap->items = realloc(heap->items, heap->capacity * sizeof(uint64_t));
	}
	int i = heap->size++;
	heap->items[i] = value;
	while (i > 0) {
		int parent = (i - 1) / 2;
		if (heap->items[parent] <= heap->items[i]) {
			break;
		}
		uint64_t t = heap->items[parent];
		heap->items[parent] = heap->items[i];
		heap->items[i] = t;
		i = parent;
	}
}

static uint64_t TGHeapPop(TGHeap *heap)
{
	uint64_t top = heap->items[0];
	heap->items[0] = heap->items[--heap->size];
	int i = 0;
	for (;;) {
		int left = i * 2 + 1;
		int right = left + 1;
		int smallest = i;
		if (left < heap->size && heap->items[left] < heap->items[smallest]) {
			smallest = left;
		}
		if (right < heap->size && heap->items[right] < heap->items[smallest]) {
			smallest = right;
		}
		if (smallest == i) {
			break;
		}
		uint64_t t = heap->items[smallest];
		heap->items[smallest] = heap->items[i];
		heap->items[i] = t;
		i = smallest;
	}
	return top;
}

/**
 * Plain A* on the grid: octile heuristic, unit/√2 step costs, and
 * diagonals only when both adjacent orthogonal cells are free (no corner
 * cutting). Writes the cell chain start..goal into *outCells (malloc'd,
 * caller frees) and returns its length, or 0 when unreachable.
 */
static int TGAStar(const bool *blocked, int cols, int rows,
				   int start, int goal, BOOL diagonals, int **outCells)
{
	if (start == goal) {
		int *cells = malloc(sizeof(int));
		cells[0] = start;
		*outCells = cells;
		return 1;
	}
	int n = cols * rows;
	float *g = malloc(n * sizeof(float));
	int *cameFrom = malloc(n * sizeof(int));
	bool *closed = calloc(n, sizeof(bool));
	for (int i = 0; i < n; i++) {
		g[i] = FLT_MAX;
	}
	TGHeap open = { malloc(64 * sizeof(uint64_t)), 0, 64 };
	int goalX = goal % cols;
	int goalY = goal / cols;
	g[start] = 0.0f;
	TGHeapPush(&open, TGEncode(TGHeuristic(start % cols, start / cols, goalX, goalY, diagonals), start));
	int length = 0;
	while (open.size > 0) {
		int cell = (int)(TGHeapPop(&open) & 0xffffffffu);
		if (closed[cell]) {
			continue;
		}
		if (cell == goal) {
			length = 1;
			for (int c = goal; c != start; c = cameFrom[c]) {
				length++;
			}
			int *cells = malloc(length * sizeof(int));
			int i = length - 1;
			for (int c = goal; ; c = cameFrom[c]) {
				cells[i--] = c;
				if (c == start) {
					break;
				}
			}
			*outCells = cells;
			break;
		}
		closed[cell] = true;
		int cx = cell % cols;
		int cy = cell / cols;
		for (int dy = -1; dy <= 1; dy++) {
			for (int dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) {
					continue;
				}
				BOOL diagonal = dx != 0 && dy != 0;
				if (diagonal && !diagonals) {
					continue;
				}
				int nx = cx + dx;
				int ny = cy + dy;
				if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) {
					continue;
				}
				int next = ny * cols + nx;
				if (blocked[next] || closed[next]) {
					continue;
				}
				if (diagonal && (blocked[cy * cols + nx] || blocked[ny * cols + cx])) {
					continue;
				}
				float cost = g[cell] + (diagonal ? kSqrt2 : 1.0f);
				if (cost >= g[next]) {
					continue;
				}
				g[next] = cost;
				cameFrom[next] = cell;
				TGHeapPush(&open, TGEncode(cost + TGHeuristic(nx, ny, goalX, goalY, diagonals), next));
			}
		}
	}
	free(open.items);
	free(g);
	free(cameFrom);
	free(closed);
	return length;
}

/**
 * Does the world-space segment cross only free cells? Amanatides & Woo
 * voxel traversal — visits exactly the cells the segment passes through,
 * so waypoint simplification can't cut through a wall the way point
 * sampling could.
 */
static BOOL TGLineOfSight(const bool *blocked, int cols, int rows,
						  float cellSize, float minX, float minY,
						  float x0, float y0, float x1, float y1)
{
	int cx = TGCellFor(x0, minX, cellSize, cols);
	int cy = TGCellFor(y0, minY, cellSize, rows);
	int ex = TGCellFor(x1, minX, cellSize, cols);
	int ey = TGCellFor(y1, minY, cellSize, rows);
	float dx = x1 - x0;
	float dy = y1 - y0;
	int stepX = (dx > 0.0f) ? 1 : -1;
	int stepY = (dy > 0.0f) ? 1 : -1;
	float tMaxX = FLT_MAX;
	float tDeltaX = FLT_MAX;
	if (dx != 0.0f) {
		float edge = minX + (cx + ((stepX > 0) ? 1 : 0)) * cellSize;
		tMaxX = (edge - x0) / dx;
		tDeltaX = cellSize / fabsf(dx);
	}
	float tMaxY = FLT_MAX;
	float tDeltaY = FLT_MAX;
	if (dy != 0.0f) {
		float edge = minY + (cy + ((stepY > 0) ? 1 : 0)) * cellSize;
		tMaxY = (edge - y0) / dy;
		tDeltaY = cellSize / fabsf(dy);
	}
	int guard = cols + rows + 2; // a segment can't visit more cells
	while (guard-- > 0) {
		if (blocked[cy * cols + cx]) {
			return NO;
		}
		if (cx == ex && cy == ey) {
			return YES;
		}
		if (tMaxX < tMaxY) {
			cx += stepX;
			tMaxX += tDeltaX;
		} else {
			cy += stepY;
			tMaxY += tDeltaY;
		}
		if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) {
			return NO;
		}
	}
	return NO;
}

@implementation TGPathfinder

+ (NSArray<NSNumber *> *)findInSprites:(NSArray<TGSprite *> *)sprites
								layers:(NSArray<TGTileLayer *> *)layers
								groups:(NSSet<NSString *> *)groups
								startX:(float)startX startY:(float)startY
								 goalX:(float)goalX goalY:(float)goalY
							  cellSize:(float)cellSize clearance:(float)clearance
								  minX:(float)minX minY:(float)minY
								  maxX:(float)maxX maxY:(float)maxY
							 diagonals:(BOOL)diagonals simplify:(BOOL)simplify
{
	if (cellSize <= 0.0f || maxX <= minX || maxY <= minY) {
		return nil;
	}
	int cols = (int)ceilf((maxX - minX) / cellSize);
	int rows = (int)ceilf((maxY - minY) / cellSize);
	if ((long long)cols * rows > kMaxCells) {
		return nil;
	}
	bool *blocked = calloc(cols * rows, sizeof(bool));
	TGRasterize(sprites, groups, blocked, cols, rows, cellSize, clearance, minX, minY);
	TGRasterizeTiles(layers, groups, blocked, cols, rows, cellSize, clearance, minX, minY);

	int rawStart = TGCellFor(startY, minY, cellSize, rows) * cols
		+ TGCellFor(startX, minX, cellSize, cols);
	int rawGoal = TGCellFor(goalY, minY, cellSize, rows) * cols
		+ TGCellFor(goalX, minX, cellSize, cols);
	int startCell = TGSnapToFree(blocked, cols, rows, rawStart % cols, rawStart / cols);
	int goalCell = TGSnapToFree(blocked, cols, rows, rawGoal % cols, rawGoal / cols);
	if (startCell < 0 || goalCell < 0) {
		free(blocked);
		return nil;
	}
	BOOL startSnapped = startCell != rawStart;
	BOOL goalSnapped = goalCell != rawGoal;

	int *cells = NULL;
	int n = TGAStar(blocked, cols, rows, startCell, goalCell, diagonals, &cells);
	if (n == 0) {
		free(blocked);
		return nil;
	}

	float *xs = malloc(n * sizeof(float));
	float *ys = malloc(n * sizeof(float));
	for (int i = 0; i < n; i++) {
		xs[i] = minX + (cells[i] % cols + 0.5f) * cellSize;
		ys[i] = minY + (cells[i] / cols + 0.5f) * cellSize;
	}
	free(cells);
	NSMutableArray<NSNumber *> *result = [NSMutableArray array];
	if (n == 1) {
		// start and goal share a cell — walk the straight line
		[result addObject:@(startSnapped ? xs[0] : startX)];
		[result addObject:@(startSnapped ? ys[0] : startY)];
		[result addObject:@(goalSnapped ? xs[0] : goalX)];
		[result addObject:@(goalSnapped ? ys[0] : goalY)];
	} else {
		// Exact endpoints replace their cell centers, so the walk starts
		// under the sprite's feet and ends on the tapped point.
		if (!startSnapped) {
			xs[0] = startX;
			ys[0] = startY;
		}
		if (!goalSnapped) {
			xs[n - 1] = goalX;
			ys[n - 1] = goalY;
		}
		if (!simplify || n == 2) {
			for (int i = 0; i < n; i++) {
				[result addObject:@(xs[i])];
				[result addObject:@(ys[i])];
			}
		} else {
			// Greedy string pulling: from each kept waypoint, jump to the
			// farthest later point still in line of sight.
			[result addObject:@(xs[0])];
			[result addObject:@(ys[0])];
			int anchor = 0;
			while (anchor < n - 1) {
				int next = anchor + 1;
				for (int j = n - 1; j > anchor + 1; j--) {
					if (TGLineOfSight(blocked, cols, rows, cellSize, minX, minY,
							xs[anchor], ys[anchor], xs[j], ys[j])) {
						next = j;
						break;
					}
				}
				[result addObject:@(xs[next])];
				[result addObject:@(ys[next])];
				anchor = next;
			}
		}
	}
	free(xs);
	free(ys);
	free(blocked);
	return result;
}

@end
