package ti.game.engine;

import java.util.Arrays;
import java.util.List;
import java.util.PriorityQueue;
import java.util.Set;

/**
 * Grid A* over the scene's collision sprites (gameView.findPath): visible
 * sprites carrying a matching collisionGroup are rasterized into a
 * blocked/free grid, A* routes around them (diagonals never cut corners),
 * and a line-of-sight pass reduces the cell chain to the few waypoints
 * followPath actually needs. Everything is built per query on the caller's
 * thread — a discrete query like raycast, with no per-frame state and no
 * GL-thread buffers.
 */
public class Pathfinder
{
	// Hard cap on the grid (cols * rows) — a runaway bounds/cellSize combo
	// fails the query instead of allocating without limit.
	private static final int MAX_CELLS = 1 << 20;

	// How many rings of cells a blocked start/goal may snap outward to the
	// nearest free cell (tapping on an obstacle walks to its edge).
	private static final int SNAP_RINGS = 4;

	private static final float SQRT2 = 1.41421356f;

	// Tolerance (in cell units) when mapping box edges to cell indices, so
	// float noise on an exactly grid-aligned edge can't flip the cell.
	private static final float EDGE_EPS = 1e-4f;

	private Pathfinder()
	{
	}

	/**
	 * Runs the query; world coordinates in, world coordinates out. Returns
	 * flat {x0, y0, x1, y1, ...} waypoints — the exact start first and the
	 * exact goal last (a snapped start/goal uses its free cell center
	 * instead) — or null when the bounds are degenerate, the grid would
	 * exceed MAX_CELLS, or no route exists.
	 */
	public static float[] find(List<Sprite> sprites, List<TileLayer> layers, Set<String> groups,
							   float startX, float startY, float goalX, float goalY,
							   float cellSize, float clearance,
							   float minX, float minY, float maxX, float maxY,
							   boolean diagonals, boolean simplify)
	{
		if (cellSize <= 0f || maxX <= minX || maxY <= minY) {
			return null;
		}
		int cols = (int) Math.ceil((maxX - minX) / cellSize);
		int rows = (int) Math.ceil((maxY - minY) / cellSize);
		if ((long) cols * rows > MAX_CELLS) {
			return null;
		}
		boolean[] blocked = new boolean[cols * rows];
		rasterize(sprites, groups, blocked, cols, rows, cellSize, clearance, minX, minY);
		rasterizeTiles(layers, groups, blocked, cols, rows, cellSize, clearance, minX, minY);

		int rawStart = cellFor(startY, minY, cellSize, rows) * cols
			+ cellFor(startX, minX, cellSize, cols);
		int rawGoal = cellFor(goalY, minY, cellSize, rows) * cols
			+ cellFor(goalX, minX, cellSize, cols);
		int startCell = snapToFree(blocked, cols, rows, rawStart % cols, rawStart / cols);
		int goalCell = snapToFree(blocked, cols, rows, rawGoal % cols, rawGoal / cols);
		if (startCell < 0 || goalCell < 0) {
			return null;
		}
		boolean startSnapped = startCell != rawStart;
		boolean goalSnapped = goalCell != rawGoal;

		int[] cells = aStar(blocked, cols, rows, startCell, goalCell, diagonals);
		if (cells == null) {
			return null;
		}

		int n = cells.length;
		float[] xs = new float[n];
		float[] ys = new float[n];
		for (int i = 0; i < n; i++) {
			xs[i] = minX + (cells[i] % cols + 0.5f) * cellSize;
			ys[i] = minY + (cells[i] / cols + 0.5f) * cellSize;
		}
		if (n == 1) {
			// start and goal share a cell — walk the straight line
			return new float[] {
				startSnapped ? xs[0] : startX, startSnapped ? ys[0] : startY,
				goalSnapped ? xs[0] : goalX, goalSnapped ? ys[0] : goalY
			};
		}
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
			return interleave(xs, ys, null, n);
		}
		// Greedy string pulling: from each kept waypoint, jump to the
		// farthest later point still in line of sight.
		int[] keep = new int[n];
		int count = 0;
		keep[count++] = 0;
		int anchor = 0;
		while (anchor < n - 1) {
			int next = anchor + 1;
			for (int j = n - 1; j > anchor + 1; j--) {
				if (lineOfSight(blocked, cols, rows, cellSize, minX, minY,
						xs[anchor], ys[anchor], xs[j], ys[j])) {
					next = j;
					break;
				}
			}
			keep[count++] = next;
			anchor = next;
		}
		return interleave(xs, ys, keep, count);
	}

	/** Packs the (optionally index-filtered) points into {x, y, x, y, ...}. */
	private static float[] interleave(float[] xs, float[] ys, int[] keep, int count)
	{
		float[] out = new float[count * 2];
		for (int i = 0; i < count; i++) {
			int index = (keep != null) ? keep[i] : i;
			out[i * 2] = xs[index];
			out[i * 2 + 1] = ys[index];
		}
		return out;
	}

	/** Grid column/row of a world coordinate, clamped into the grid. */
	private static int cellFor(float v, float min, float cellSize, int limit)
	{
		int c = (int) Math.floor((v - min) / cellSize);
		return Math.min(Math.max(c, 0), limit - 1);
	}

	/**
	 * Marks every cell a matching sprite's clearance-inflated hitbox
	 * touches. Same sprite filter as raycast: visible, tagged with a
	 * collisionGroup in `groups` (null/empty = any), not screenFixed.
	 */
	private static void rasterize(List<Sprite> sprites, Set<String> groups,
								  boolean[] blocked, int cols, int rows,
								  float cellSize, float clearance, float minX, float minY)
	{
		float[] box = new float[4];
		float[] center = new float[2];
		for (Sprite s : sprites) {
			String group = s.collisionGroup;
			if (group == null || !s.visible || s.screenFixed
					|| (groups != null && !groups.isEmpty() && !groups.contains(group))) {
				continue;
			}
			if (s.circleHitbox) {
				s.hitCenter(center);
				float r = s.hitRadius() + clearance;
				int cx0 = Math.max(0, (int) Math.floor((center[0] - r - minX) / cellSize));
				int cy0 = Math.max(0, (int) Math.floor((center[1] - r - minY) / cellSize));
				int cx1 = Math.min(cols - 1, (int) Math.floor((center[0] + r - minX) / cellSize));
				int cy1 = Math.min(rows - 1, (int) Math.floor((center[1] + r - minY) / cellSize));
				for (int cy = cy0; cy <= cy1; cy++) {
					for (int cx = cx0; cx <= cx1; cx++) {
						// circle vs cell rect: closest point on the cell
						float cellMinX = minX + cx * cellSize;
						float cellMinY = minY + cy * cellSize;
						float qx = Math.min(Math.max(center[0], cellMinX), cellMinX + cellSize);
						float qy = Math.min(Math.max(center[1], cellMinY), cellMinY + cellSize);
						float dx = center[0] - qx;
						float dy = center[1] - qy;
						if (dx * dx + dy * dy < r * r) {
							blocked[cy * cols + cx] = true;
						}
					}
				}
			} else {
				s.computeAABB(box);
				// Half-open on the max side: a box ending exactly on a cell
				// boundary overlaps zero of the next cell — grid-aligned
				// walls (tile mazes) must not bleed into the corridor
				// beside them.
				int cx0 = (int) Math.floor((box[0] - clearance - minX) / cellSize + EDGE_EPS);
				int cy0 = (int) Math.floor((box[1] - clearance - minY) / cellSize + EDGE_EPS);
				int cx1 = (int) Math.ceil((box[2] + clearance - minX) / cellSize - EDGE_EPS) - 1;
				int cy1 = (int) Math.ceil((box[3] + clearance - minY) / cellSize - EDGE_EPS) - 1;
				if (cx1 < 0 || cy1 < 0 || cx0 >= cols || cy0 >= rows) {
					continue;
				}
				cx0 = Math.max(cx0, 0);
				cy0 = Math.max(cy0, 0);
				cx1 = Math.min(cx1, cols - 1);
				cy1 = Math.min(cy1, rows - 1);
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
	 * search bounds are visited, so a huge map with a small query stays
	 * cheap.
	 */
	private static void rasterizeTiles(List<TileLayer> layers, Set<String> groups,
									   boolean[] blocked, int cols, int rows,
									   float cellSize, float clearance, float minX, float minY)
	{
		if (layers == null) {
			return;
		}
		float maxX = minX + cols * cellSize;
		float maxY = minY + rows * cellSize;
		for (TileLayer layer : layers) {
			if (!layer.matches(groups)) {
				continue;
			}
			float tw = layer.cellWidth();
			float th = layer.cellHeight();
			if (tw <= 0f || th <= 0f) {
				continue;
			}
			int tc0 = Math.max(0, (int) Math.floor((minX - clearance - layer.x) / tw));
			int tc1 = Math.min(layer.cols() - 1, (int) Math.floor((maxX + clearance - layer.x) / tw));
			int tr0 = Math.max(0, (int) Math.floor((minY - clearance - layer.y) / th));
			int tr1 = Math.min(layer.rows() - 1, (int) Math.floor((maxY + clearance - layer.y) / th));
			for (int row = tr0; row <= tr1; row++) {
				for (int col = tc0; col <= tc1; col++) {
					if (!layer.isSolid(col, row)) {
						continue;
					}
					float bx0 = layer.x + col * tw;
					float by0 = layer.y + row * th;
					// same half-open edge rule as sprite boxes
					int cx0 = (int) Math.floor((bx0 - clearance - minX) / cellSize + EDGE_EPS);
					int cy0 = (int) Math.floor((by0 - clearance - minY) / cellSize + EDGE_EPS);
					int cx1 = (int) Math.ceil((bx0 + tw + clearance - minX) / cellSize - EDGE_EPS) - 1;
					int cy1 = (int) Math.ceil((by0 + th + clearance - minY) / cellSize - EDGE_EPS) - 1;
					if (cx1 < 0 || cy1 < 0 || cx0 >= cols || cy0 >= rows) {
						continue;
					}
					cx0 = Math.max(cx0, 0);
					cy0 = Math.max(cy0, 0);
					cx1 = Math.min(cx1, cols - 1);
					cy1 = Math.min(cy1, rows - 1);
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

	/** The cell itself if free, else the nearest free cell within
	 *  SNAP_RINGS rings of it, else -1. */
	private static int snapToFree(boolean[] blocked, int cols, int rows, int cx, int cy)
	{
		if (!blocked[cy * cols + cx]) {
			return cy * cols + cx;
		}
		for (int r = 1; r <= SNAP_RINGS; r++) {
			int best = -1;
			int bestD2 = Integer.MAX_VALUE;
			for (int dy = -r; dy <= r; dy++) {
				for (int dx = -r; dx <= r; dx++) {
					if (Math.max(Math.abs(dx), Math.abs(dy)) != r) {
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

	/**
	 * Plain A* on the grid: octile heuristic, unit/√2 step costs, and
	 * diagonals only when both adjacent orthogonal cells are free (no
	 * corner cutting). Returns the cell chain start..goal, or null when
	 * the goal is unreachable.
	 */
	private static int[] aStar(boolean[] blocked, int cols, int rows,
							   int start, int goal, boolean diagonals)
	{
		if (start == goal) {
			return new int[] { start };
		}
		int n = cols * rows;
		float[] g = new float[n];
		Arrays.fill(g, Float.MAX_VALUE);
		int[] cameFrom = new int[n];
		boolean[] closed = new boolean[n];
		int goalX = goal % cols;
		int goalY = goal / cols;
		// Entries encode {f, cell} in one long: the raw bits of a
		// non-negative float sort like the float itself, so natural long
		// order pops the lowest f. Stale duplicates skip via `closed`.
		PriorityQueue<Long> open = new PriorityQueue<>();
		g[start] = 0f;
		open.add(encode(heuristic(start % cols, start / cols, goalX, goalY, diagonals), start));
		while (!open.isEmpty()) {
			int cell = (int) (open.poll() & 0xffffffffL);
			if (closed[cell]) {
				continue;
			}
			if (cell == goal) {
				return reconstruct(cameFrom, start, goal);
			}
			closed[cell] = true;
			int cx = cell % cols;
			int cy = cell / cols;
			for (int dy = -1; dy <= 1; dy++) {
				for (int dx = -1; dx <= 1; dx++) {
					if (dx == 0 && dy == 0) {
						continue;
					}
					boolean diagonal = dx != 0 && dy != 0;
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
					float cost = g[cell] + (diagonal ? SQRT2 : 1f);
					if (cost >= g[next]) {
						continue;
					}
					g[next] = cost;
					cameFrom[next] = cell;
					open.add(encode(cost + heuristic(nx, ny, goalX, goalY, diagonals), next));
				}
			}
		}
		return null;
	}

	private static long encode(float f, int cell)
	{
		return ((long) Float.floatToIntBits(f) << 32) | (cell & 0xffffffffL);
	}

	private static float heuristic(int x, int y, int gx, int gy, boolean diagonals)
	{
		int dx = Math.abs(x - gx);
		int dy = Math.abs(y - gy);
		return diagonals ? dx + dy + (SQRT2 - 2f) * Math.min(dx, dy) : dx + dy;
	}

	private static int[] reconstruct(int[] cameFrom, int start, int goal)
	{
		int length = 1;
		for (int cell = goal; cell != start; cell = cameFrom[cell]) {
			length++;
		}
		int[] cells = new int[length];
		int i = length - 1;
		for (int cell = goal; ; cell = cameFrom[cell]) {
			cells[i--] = cell;
			if (cell == start) {
				break;
			}
		}
		return cells;
	}

	/**
	 * Does the world-space segment cross only free cells? Amanatides & Woo
	 * voxel traversal — visits exactly the cells the segment passes
	 * through, so waypoint simplification can't cut through a wall the
	 * way point sampling could.
	 */
	private static boolean lineOfSight(boolean[] blocked, int cols, int rows,
									   float cellSize, float minX, float minY,
									   float x0, float y0, float x1, float y1)
	{
		int cx = cellFor(x0, minX, cellSize, cols);
		int cy = cellFor(y0, minY, cellSize, rows);
		int ex = cellFor(x1, minX, cellSize, cols);
		int ey = cellFor(y1, minY, cellSize, rows);
		float dx = x1 - x0;
		float dy = y1 - y0;
		int stepX = (dx > 0f) ? 1 : -1;
		int stepY = (dy > 0f) ? 1 : -1;
		float tMaxX = Float.MAX_VALUE;
		float tDeltaX = Float.MAX_VALUE;
		if (dx != 0f) {
			float edge = minX + (cx + ((stepX > 0) ? 1 : 0)) * cellSize;
			tMaxX = (edge - x0) / dx;
			tDeltaX = cellSize / Math.abs(dx);
		}
		float tMaxY = Float.MAX_VALUE;
		float tDeltaY = Float.MAX_VALUE;
		if (dy != 0f) {
			float edge = minY + (cy + ((stepY > 0) ? 1 : 0)) * cellSize;
			tMaxY = (edge - y0) / dy;
			tDeltaY = cellSize / Math.abs(dy);
		}
		int guard = cols + rows + 2; // a segment can't visit more cells
		while (guard-- > 0) {
			if (blocked[cy * cols + cx]) {
				return false;
			}
			if (cx == ex && cy == ey) {
				return true;
			}
			if (tMaxX < tMaxY) {
				cx += stepX;
				tMaxX += tDeltaX;
			} else {
				cy += stepY;
				tMaxY += tDeltaY;
			}
			if (cx < 0 || cy < 0 || cx >= cols || cy >= rows) {
				return false;
			}
		}
		return false;
	}
}
