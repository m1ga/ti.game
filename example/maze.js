// ti.game maze demo — A* pathfinding playground.
//
// - a tile maze; every wall block is just a sprite with
//   `collisionGroup: 'wall'` — findPath needs no other setup
// - tap any tile: `gameView.findPath` computes the route (cellSize =
//   the tile size, so the grid matches the maze exactly) and the player
//   walks it with `followPath`. The route is visualized first: faint
//   blue dots show every grid cell A* walks (`simplify: false`), gold
//   dots the line-of-sight-reduced waypoints the player actually gets
// - a hound hunts you: every 800 ms of game time it re-paths to the
//   player and follows — pathfinding on a discrete AI timer, the chase
//   itself runs natively between ticks. Getting caught shakes the
//   camera and sends the hound back to its den
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#141821'
		// debug: true  // show collision shapes for every sprite
	});

	var tileSheet = Game.createSpriteSheet({ image: 'assets/tiles.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var walkerSheet = Game.createSpriteSheet({ image: 'assets/walker.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		// '#' wall, '.' corridor — fully connected, with loops so the
		// shortest way around is rarely the obvious one
		var MAP = [
			'###########',
			'#.........#',
			'#.###.###.#',
			'#.#.....#.#',
			'#.#.###.#.#',
			'#...#...#.#',
			'###.#.###.#',
			'#...#.....#',
			'#.#####.###',
			'#.....#...#',
			'#.###.###.#',
			'#.#.#.....#',
			'#.#.#####.#',
			'#.#.......#',
			'###########'
		];
		var COLS = MAP[0].length;
		var ROWS = MAP.length;
		var TILE = Math.floor(Math.min(W / COLS, H / ROWS));
		var ox = (W - COLS * TILE) / 2;                  // center the maze
		var oy = (H - ROWS * TILE) / 2;

		function tileCenter(col, row) {
			return { x: ox + (col + 0.5) * TILE, y: oy + (row + 0.5) * TILE };
		}

		for (var row = 0; row < ROWS; row++) {
			for (var col = 0; col < COLS; col++) {
				var isWall = MAP[row].charAt(col) === '#';
				var pos = tileCenter(col, row);
				gameView.add(Game.createSprite({
					sheet: isWall ? wallSheet : tileSheet,
					frame: isWall ? 0 : 2,
					x: pos.x,
					y: pos.y,
					width: TILE,
					height: TILE,
					zIndex: isWall ? 1 : 0,
					// this one property is the whole pathfinding setup
					collisionGroup: isWall ? 'wall' : null
				}));
			}
		}

		// The exact rect and resolution of the maze grid — cell centers
		// land on tile centers, so waypoints run down the middle of the
		// corridors
		var MAZE_BOUNDS = { minX: ox, minY: oy, maxX: ox + COLS * TILE, maxY: oy + ROWS * TILE };
		var PATH_OPTIONS = { cellSize: TILE, groups: ['wall'], bounds: MAZE_BOUNDS };

		// --- Player ------------------------------------------------------

		var start = tileCenter(1, 1);
		var SPEED = TILE * 4; // px/s
		var player = Game.createSprite({
			sheet: walkerSheet,
			x: start.x,
			y: start.y,
			width: TILE * 0.9,
			height: TILE * 0.9,
			zIndex: 5,
			hitboxScale: 0.6,
			collisionGroup: 'player',   // only the hound cares
			animations: {
				down: { frames: [0, 1], fps: 6, loop: true },
				up: { frames: [2, 3], fps: 6, loop: true },
				side: { frames: [4, 5], fps: 6, loop: true }
			}
		});
		gameView.add(player);

		// Walk animation facing from the first path segment (good enough —
		// per-corner facing would need per-frame JS, against the house rule)
		function faceAlong(sprite, from, to) {
			var dx = to.x - from.x;
			var dy = to.y - from.y;
			if (Math.abs(dx) > Math.abs(dy)) {
				sprite.scaleX = (dx < 0 ? -1 : 1) * Math.abs(sprite.scaleX);
				return 'side';
			}
			return dy < 0 ? 'up' : 'down';
		}

		player.addEventListener('pathcomplete', function () {
			player.stop();
			player.frame = 0;
			clearDots();
		});

		// --- Route visualization -----------------------------------------

		var dots = [];

		function clearDots() {
			dots.forEach(function (dot) {
				gameView.remove(dot);
			});
			dots = [];
		}

		function dropDot(point, size, color, opacity, zIndex) {
			var dot = Game.createSprite({
				sheet: ballSheet,
				x: point.x,
				y: point.y,
				width: size,
				height: size,
				tintColor: color,
				opacity: opacity,
				zIndex: zIndex,
				touchEnabled: false
			});
			gameView.add(dot);
			dots.push(dot);
		}

		// --- Tap to walk -------------------------------------------------

		gameView.addEventListener('tap', function (e) {
			var from = { x: player.x, y: player.y };
			var to = { x: e.x, y: e.y };
			var path = gameView.findPath(from, to, PATH_OPTIONS);
			if (!path || path.length < 2) {
				return; // tapped outside the maze rect
			}
			clearDots();
			// every grid cell A* walks (raw), then the simplified corners
			var raw = gameView.findPath(from, to, {
				cellSize: TILE,
				groups: ['wall'],
				bounds: MAZE_BOUNDS,
				simplify: false
			});
			(raw || []).forEach(function (point) {
				dropDot(point, TILE * 0.18, '#7ec8ff', 0.5, 2);
			});
			path.forEach(function (point) {
				dropDot(point, TILE * 0.32, '#ffd54a', 0.9, 3);
			});
			player.play(faceAlong(player, from, path[1]));
			player.followPath(path, { speed: SPEED });
		});

		// --- The hound ---------------------------------------------------

		var den = tileCenter(9, 13);
		var hound = Game.createSprite({
			sheet: dogSheet,
			frame: 2, // sitting, until the first chase tick
			x: den.x,
			y: den.y,
			width: TILE * 0.9,
			height: TILE * 0.9,
			zIndex: 6,
			hitboxScale: 0.5,
			tintColor: '#ff9384',       // huntin' red
			collidesWith: ['player'],
			animations: {
				walk: { frames: [0, 1], fps: 7, loop: true }
			}
		});
		gameView.add(hound);

		var caught = 0;

		// Discrete AI: re-path on a game-clock timer, chase natively
		// between ticks (freezes with timeScale, unlike setInterval)
		var chaseTimer = gameView.every(800, function () {
			var from = { x: hound.x, y: hound.y };
			var path = gameView.findPath(from, { x: player.x, y: player.y }, PATH_OPTIONS);
			if (!path || path.length < 2) {
				return;
			}
			hound.scaleX = path[1].x < hound.x ? -1 : 1;
			hound.play('walk');
			hound.followPath(path, { speed: TILE * 2.6 });
		});
		win.addEventListener('close', function () {
			gameView.cancelTimer(chaseTimer);
		});

		hound.addEventListener('collision', function () {
			caught++;
			caughtText.text = 'CAUGHT ' + caught;
			player.flash('#ff5040', 350);
			gameView.shake({ strength: TILE * 0.3, duration: 350 });
			// back to the den; sit until the next chase tick
			hound.followPath(null);
			hound.stop();
			hound.frame = 2;
			hound.x = den.x;
			hound.y = den.y;
		});

		// --- HUD ---------------------------------------------------------

		var UNIT = Math.max(1, Math.round(TILE / 14));
		gameView.add(Game.createText({
			text: 'TAP A TILE - A* FINDS THE WAY',
			maxWidth: Math.round(W * 0.9 / UNIT),
			align: 'center',
			screenFixed: true,
			x: W / 2,
			y: oy / 2,
			scale: UNIT,
			tintColor: '#ffd54a',
			zIndex: 20
		}));
		var caughtText = Game.createText({
			text: 'CAUGHT 0',
			screenFixed: true,
			x: W / 2,
			y: H - oy / 2,
			scale: UNIT,
			tintColor: '#ff9384',
			zIndex: 20
		});
		gameView.add(caughtText);
	}

	win.add(gameView);
	// Back — return to the launcher
	var backButton = Ti.UI.createButton({
		title: 'Back',
		top: Ti.Platform.osname === 'android' ? 10 : 40,
		left: 10,
		color: '#fff',
		backgroundColor: '#000',
		borderColor: '#fff',
		borderWidth: 1,
		font: { fontSize: 12 }
	});
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);

	win.open();
};
