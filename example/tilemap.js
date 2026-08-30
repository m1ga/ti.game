// ti.game tile map demo — a 120x90 island drawn by one native layer.
//
// - `Game.createTileLayer` holds the whole map (10,800 cells) as one
//   grid of frame indices; only the cells inside the camera are drawn,
//   so the map could be 1000x1000 without costing a frame more. Compare
//   topdown.js, which builds a sprite per tile
// - water is `solid`: the walker lists the layer's `collisionGroup` in
//   `solidWith` like any solid sprite — no per-tile collision sprites
// - tap the ground and `findPath` routes around the lakes; the layer's
//   solid cells feed the same grid A* the maze demo uses. `bounds`
//   keeps the search to the neighbourhood of the walker
// - BUILD mode: tapping a water cell calls `setTile(col, row, ...)`
//   and lays a plank — the art and the collision flag change together,
//   live, in the running scene
// - DEBUG outlines the solid cells in view; the performance HUD (top
//   right) shows the draw calls and frame time staying flat while the
//   camera scrolls across the island
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		title: 'Tile map (120x90)',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#1c2430',
		debug: { hud: 'topRight' }   // draw calls / frame time: watch them stay flat while scrolling
	});

	// 16px art, chunky pixels
	var tileSheet = Game.createSpriteSheet({ image: 'assets/tiles.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var walkerSheet = Game.createSpriteSheet({ image: 'assets/walker.png', frameWidth: 16, frameHeight: 16, smoothing: false });

	var GRASS = 0, FLOWERS = 1, PATH = 2, WATER = 3;
	var COLS = 120;
	var ROWS = 90;

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	// Deterministic random, so the island is the same on every run
	function rng(seed) {
		return function () {
			seed |= 0;
			seed = seed + 0x6D2B79F5 | 0;
			var t = Math.imul(seed ^ seed >>> 15, 1 | seed);
			t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
			return ((t ^ t >>> 14) >>> 0) / 4294967296;
		};
	}

	// Rows of frame indices: a water border, blobby lakes, flower
	// patches and a few wandering paths — the shape createTileLayer
	// takes directly (a flat array or strings + legend work too)
	function generateMap() {
		var random = rng(20260828);
		var map = [];
		var r, c;
		for (r = 0; r < ROWS; r++) {
			var row = [];
			for (c = 0; c < COLS; c++) {
				var border = c < 2 || r < 2 || c >= COLS - 2 || r >= ROWS - 2;
				row.push(border ? WATER : GRASS);
			}
			map.push(row);
		}
		// lakes
		for (var lake = 0; lake < 70; lake++) {
			var cx = 4 + random() * (COLS - 8);
			var cy = 4 + random() * (ROWS - 8);
			var rx = 1.5 + random() * 5;
			var ry = 1.5 + random() * 4;
			for (r = Math.floor(cy - ry); r <= cy + ry; r++) {
				for (c = Math.floor(cx - rx); c <= cx + rx; c++) {
					var dx = (c - cx) / rx;
					var dy = (r - cy) / ry;
					if (dx * dx + dy * dy < 1 - random() * 0.35 && r >= 0 && r < ROWS && c >= 0 && c < COLS) {
						map[r][c] = WATER;
					}
				}
			}
		}
		// flower patches
		for (r = 2; r < ROWS - 2; r++) {
			for (c = 2; c < COLS - 2; c++) {
				if (map[r][c] === GRASS && random() < 0.06) {
					map[r][c] = FLOWERS;
				}
			}
		}
		// wandering paths
		for (var trail = 0; trail < 6; trail++) {
			c = Math.floor(10 + random() * (COLS - 20));
			r = Math.floor(10 + random() * (ROWS - 20));
			var dirX = random() < 0.5 ? -1 : 1;
			var dirY = 0;
			for (var step = 0; step < 90; step++) {
				if (map[r][c] !== WATER) {
					map[r][c] = PATH;
				}
				if (random() < 0.2) {
					var turn = random() < 0.5;
					dirX = turn ? 0 : (random() < 0.5 ? -1 : 1);
					dirY = turn ? (random() < 0.5 ? -1 : 1) : 0;
				}
				c = Math.min(Math.max(c + dirX, 2), COLS - 3);
				r = Math.min(Math.max(r + dirY, 2), ROWS - 3);
			}
		}
		return map;
	}

	function init(W, H) {

		var density = Ti.Platform.osname === 'android'
			? Ti.Platform.displayCaps.logicalDensityFactor
			: H / Ti.Platform.displayCaps.platformHeight;
		var TILE = Math.round(16 * density);   // world px per cell
		var UNIT = Math.max(1, Math.round(TILE / 14));

		// --- The map: one layer, one texture, only visible cells drawn --

		var map = generateMap();
		var ground = Game.createTileLayer({
			sheet: tileSheet,
			tileWidth: TILE,
			tileHeight: TILE,
			data: map,
			collisionGroup: 'water',
			solid: [WATER],
			zIndex: 0
		});
		gameView.add(ground);
		var WORLD_W = ground.width;
		var WORLD_H = ground.height;

		// --- The walker: blocked by water like by any solid --------------

		// Start on the first dry cell out from the middle
		var startCol = COLS / 2;
		var startRow = ROWS / 2;
		while (ground.isBlocked(startCol, startRow)) {
			startCol++;
		}
		var start = ground.cellAt(startCol, startRow);
		var SPEED = TILE * 4;
		var player = Game.createSprite({
			sheet: walkerSheet,
			x: start.x,
			y: start.y,
			width: TILE,
			height: TILE,
			zIndex: 5,
			hitboxScale: 0.6,
			solidWith: ['water'],
			animations: {
				down: { frames: [0, 1], fps: 6, loop: true },
				up: { frames: [2, 3], fps: 6, loop: true },
				side: { frames: [4, 5], fps: 6, loop: true }
			}
		});
		gameView.add(player);

		gameView.follow(player, {
			leftMargin: 0.4, rightMargin: 0.6,
			topMargin: 0.4, bottomMargin: 0.6,
			smoothing: 0.15,
			maxY: WORLD_H
		});
		gameView.cameraBounds = { minX: 0, minY: 0, maxX: WORLD_W, maxY: WORLD_H };

		function faceAlong(from, to) {
			var dx = to.x - from.x;
			var dy = to.y - from.y;
			if (Math.abs(dx) > Math.abs(dy)) {
				player.scaleX = dx < 0 ? -1 : 1;
				return 'side';
			}
			return dy < 0 ? 'up' : 'down';
		}

		player.addEventListener('pathcomplete', function () {
			player.stop();
			player.frame = 0;
		});

		// --- Modes -------------------------------------------------------

		var building = false;

		function walkTo(x, y) {
			var from = { x: player.x, y: player.y };
			// Search a window around the walker, not the whole island —
			// the grid A* is per query, and 40x40 cells is plenty
			var reach = TILE * 20;
			var path = gameView.findPath(from, { x: x, y: y }, {
				cellSize: TILE,
				groups: ['water'],
				clearance: TILE * 0.2,
				bounds: {
					minX: Math.max(0, from.x - reach), minY: Math.max(0, from.y - reach),
					maxX: Math.min(WORLD_W, from.x + reach), maxY: Math.min(WORLD_H, from.y + reach)
				}
			});
			if (!path || path.length < 2) {
				player.flash('#ff5252', 200); // out of reach or no route
				return;
			}
			player.play(faceAlong(from, path[1]));
			player.followPath(path, { speed: SPEED });
		}

		function buildAt(x, y) {
			var cell = ground.tileAt(x, y);
			if (!cell) {
				return;
			}
			if (cell.tile === WATER) {
				ground.setTile(cell.col, cell.row, PATH); // plank: art + collision flag
			} else if (cell.tile === PATH) {
				ground.setTile(cell.col, cell.row, WATER); // and back again
			}
		}

		gameView.addEventListener('tap', function (e) {
			if (building) {
				buildAt(e.x, e.y);
			} else {
				walkTo(e.x, e.y);
			}
		});

		// --- HUD (screenFixed text, tap buttons) -------------------------

		var margin = Math.round(H * 0.06);
		gameView.add(Game.createText({
			text: COLS + ' x ' + ROWS + ' TILES - ONE LAYER',
			screenFixed: true,
			x: W / 2,
			y: margin,
			scale: UNIT,
			tintColor: '#ffd54a',
			zIndex: 20
		}));
		var hint = Game.createText({
			text: 'TAP TO WALK',
			screenFixed: true,
			x: W / 2,
			y: margin + 18 * UNIT,
			scale: UNIT,
			tintColor: '#dfe6ee',
			zIndex: 20
		});
		gameView.add(hint);

		var buildButton = Game.createText({
			text: '[ BUILD: OFF ]',
			screenFixed: true,
			x: W * 0.3,
			y: H - margin,
			scale: UNIT,
			tintColor: '#7ec8ff',
			zIndex: 20
		});
		buildButton.addEventListener('tap', function () {
			building = !building;
			buildButton.text = building ? '[ BUILD: ON ]' : '[ BUILD: OFF ]';
			hint.text = building ? 'TAP WATER TO LAY A PLANK' : 'TAP TO WALK';
		});
		gameView.add(buildButton);

		var debugButton = Game.createText({
			text: '[ DEBUG ]',
			screenFixed: true,
			x: W * 0.72,
			y: H - margin,
			scale: UNIT,
			tintColor: '#7ec8ff',
			zIndex: 20
		});
		var hitboxes = false;
		debugButton.addEventListener('tap', function () {
			hitboxes = !hitboxes;
			gameView.debug = { hitbox: hitboxes, hud: 'topRight' };
		});
		gameView.add(debugButton);
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win);

	win.open();
};
