// ti.game rope demo — a native Verlet rope hanging from a draggable ball.
//
// - SEGMENTS woven rope links connect to a ball at the top; drag the
//   ball around (or fling it) and the rope swings, folds and trails
//   behind it
// - everything runs in the native game loop: the ball is a normal
//   draggable sprite moved by the touch controller, and the rope's
//   Verlet solver (integration + distance constraints) reads its
//   position each frame — zero bridge traffic in the whole interaction
// - a second rope hangs from a fixed anchor with a ball pinned to its
//   tail, showing the head/tail pinning options
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#20242e'
	});

	var ropeSheet = Game.createSpriteSheet({ image: 'assets/rope.png', frameWidth: 16, frameHeight: 32, smoothing: false });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var SEGMENTS = 14;             // number of rope links — change me
		var BALL = Math.round(W * 0.16);
		var SEG_LEN = H * 0.04;
		var THICKNESS = W * 0.03;

		// --- Rope 1: hangs from a draggable ball -------------------------

		var ball = Game.createSprite({
			sheet: ballSheet,
			x: W / 2,
			y: H * 0.22,
			width: BALL,
			height: BALL,
			zIndex: 10,
			draggable: true,
			hitboxShape: 'circle'
		});
		gameView.add(ball);

		gameView.add(Game.createRope({
			sheet: ropeSheet,
			segments: SEGMENTS,
			segmentLength: SEG_LEN,
			thickness: THICKNESS,
			gravity: H * 1.6,
			damping: 0.985,
			iterations: 3,
			head: ball,                // pinned to the ball — drag it!
			zIndex: 5
		}));

		// --- Rope 2: fixed anchor, ball pinned to the tail ---------------

		var weight = Game.createSprite({
			sheet: ballSheet,
			x: W * 0.15,
			y: H * 0.1 + (SEGMENTS - 4) * SEG_LEN,
			width: BALL * 0.7,
			height: BALL * 0.7,
			zIndex: 10,
			draggable: true,
			hitboxShape: 'circle'
		});
		gameView.add(weight);

		gameView.add(Game.createRope({
			sheet: ropeSheet,
			segments: SEGMENTS - 4,
			segmentLength: SEG_LEN,
			thickness: THICKNESS * 0.8,
			gravity: H * 1.6,
			x: W * 0.15,               // fixed head anchor
			y: H * 0.1,
			tail: weight,              // ...and the weight hangs off the end
			zIndex: 5
		}));

		win.add(Ti.UI.createLabel({
			text: 'Drag the balls — native Verlet ropes',
			color: '#fff',
			font: { fontSize: 18, fontWeight: 'bold' },
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 2 },
			top: 40
		}));
	}

	win.add(gameView);
	win.open();
};
