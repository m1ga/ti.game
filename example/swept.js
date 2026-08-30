// ti.game swept AABB demo — why fast bullets need `swept: true`.
//
// Two identical shooting lanes fire a bullet at a thin wall every 700 ms
// at the same speed. The top lane's bullets are ordinary sprites; the
// bottom lane's have `swept: true`, so their movement is collision-tested
// as a path instead of only at the end position of each frame.
//
// At low speed both lanes hit. Crank the speed up with the text buttons:
// once a bullet travels further per frame than the wall is thick, the
// normal lane's bullets teleport straight through (the wall never sees
// an overlap) and rack up MISSes in the catch zone behind it — while the
// swept lane keeps hitting no matter how fast the bullets get.
//
// The HUD is all bitmap-font text sprites; SLOWER/FASTER are tap-able
// text buttons. Exports a start function; the demo opens its own window.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		title: 'Swept collision',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#141824'
	});

	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32 });

	var fireTimer = null;
	win.addEventListener('close', function () {
		if (fireTimer !== null) {
			clearInterval(fireTimer);
			fireTimer = null;
		}
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var UNIT = Math.max(1, Math.round(W / 380));
		var WALL_W = 8;
		var WALL_X = W * 0.72;
		var BULLET = Math.max(10, Math.round(W * 0.014));
		var SPEEDS = [600, 1200, 2400, 4800, 9600, 19200]; // px/s
		var speedIndex = 0;

		gameView.add(Game.createText({
			text: 'SWEPT AABB',
			x: W / 2, y: H * 0.06,
			scale: UNIT * 1.4,
			tintColor: '#ffd54a',
			zIndex: 20
		}));

		var lanes = [
			{ name: 'NORMAL  swept: false', color: '#ff8a80', y: H * 0.3, swept: false, hits: 0, misses: 0 },
			{ name: 'SWEPT   swept: true', color: '#69f0ae', y: H * 0.62, swept: true, hits: 0, misses: 0 }
		];

		lanes.forEach(function (lane) {
			lane.wall = Game.createSprite({
				sheet: wallSheet,
				x: WALL_X, y: lane.y,
				width: WALL_W, height: H * 0.18,
				tintColor: '#9aa4c8',
				collisionGroup: 'wall',
				zIndex: 5
			});
			lane.burst = Game.createEmitter({
				sheet: sparkSheet, frame: 0,
				rate: 0, lifetime: 450,
				speed: 300, spread: 360,
				size: 12, blend: 'add', tint: '#ffd54a',
				startOpacity: 1, endOpacity: 0,
				startScale: 1, endScale: 0.4,
				x: WALL_X, y: lane.y, zIndex: 9
			});
			lane.title = Game.createText({
				text: lane.name,
				x: 16, y: lane.y - H * 0.13,
				anchorX: 0, anchorY: 0,
				scale: UNIT,
				tintColor: lane.color,
				zIndex: 20
			});
			lane.score = Game.createText({
				text: 'HIT 0   MISS 0',
				x: W - 16, y: lane.y - H * 0.13,
				anchorX: 1, anchorY: 0,
				scale: UNIT,
				zIndex: 20
			});
			gameView.add([lane.wall, lane.burst, lane.title, lane.score]);
		});

		// Catch zone well behind the wall: anything arriving here tunneled
		// straight through (wide enough that even the fastest bullet can't
		// skip it — its own overlap test stays discrete)
		gameView.add(Game.createSprite({
			x: W * 1.35, y: H / 2,
			width: W * 0.7, height: H * 2,
			collisionGroup: 'void'
		}));

		function updateScore(lane) {
			lane.score.text = 'HIT ' + lane.hits + '   MISS ' + lane.misses;
		}

		function fire(lane) {
			var bullet = Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: W * 0.06, y: lane.y,
				width: BULLET, height: BULLET,
				blend: 'add',
				tintColor: lane.color,
				velocityX: SPEEDS[speedIndex],
				swept: lane.swept,
				collidesWith: ['wall', 'void']
			});
			bullet.addEventListener('collision', function (e) {
				gameView.remove(bullet);
				if (e.group === 'wall') {
					lane.hits++;
					lane.wall.flash('#fff', 200);
					lane.burst.emit(14);
				} else {
					lane.misses++; // reached the catch zone: tunneled through
					lane.score.flash('#ff5252', 250);
				}
				updateScore(lane);
			});
			gameView.add(bullet);
		}

		fireTimer = setInterval(function () {
			lanes.forEach(fire);
		}, 700);

		// --- speed controls: text sprites as buttons ---------------------

		var speedText = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.88,
			scale: UNIT,
			zIndex: 20
		});

		function updateSpeed() {
			var speed = SPEEDS[speedIndex];
			speedText.text = 'SPEED ' + speed + ' px/s = '
				+ Math.round(speed / 60) + ' px/frame\nWALL ' + WALL_W + ' px thick';
		}
		updateSpeed();

		function makeSpeedButton(label, alignX, step) {
			var button = Game.createText({
				text: label,
				x: alignX, y: H * 0.96,
				scale: UNIT,
				tintColor: '#8ab4ff',
				zIndex: 20
			});
			button.addEventListener('tap', function () {
				speedIndex = Math.min(SPEEDS.length - 1, Math.max(0, speedIndex + step));
				button.flash('#fff', 150);
				updateSpeed();
			});
			return button;
		}

		gameView.add([
			speedText,
			makeSpeedButton('[ < SLOWER ]', W * 0.25, -1),
			makeSpeedButton('[ FASTER > ]', W * 0.75, 1)
		]);
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win);
	win.open();
};
