// ti.game circle solids demo — a round solid resolves as a circle.
//
// Top half: each solid has its own emitter. A ball starts somewhere across
// the width of its assigned shape and falls straight down; only the contact
// geometry decides which way it leaves. Every ball can still hit every
// solid if its rebound carries it there, and the balls use `push` contacts
// when they meet one another. RECT is the default, axis-aligned, so the balls come off flat
// faces and hard corners. CIRCLE takes the normal from center to center,
// so an off-center hit slides away diagonally the way a real round post
// would send it. ROTATED is a square turned 45°: with the default `'rect'`
// its collision box would be re-boxed square to the screen and grow,
// leaving balls parked on a flat top that is not there, so it declares
// `'rotatedRect'` and the box turns with the art.
//
// Bottom half: the same shot fired twice, at the two `solidMode` values.
// In the BLOCK row (the default) the balls separate and stop overlapping,
// but the struck ball takes none of the momentum — every solid is
// immovable, so the shooter bounces off it and the target sits there. In
// the PUSH row each pair is resolved once instead of once per direction:
// half the separation to each body, and the closing velocity exchanged at
// equal mass, so the struck ball actually leaves and the shooter stops.
// Same restitution, same speed, same geometry — only the mode differs.
//
// The shape overlay starts off, because the comparison should read as a
// scene first. Turn it on to see the collision geometry: on
// the left the green collision square sits square to the screen while the
// blue sprite bounds are a diamond, and on the right the two agree. The
// button turns it off when you would rather just watch the balls.
//
// Exports a start function; the demo opens its own window.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		extendSafeArea: false,   // keep content clear of the notch and home bar
		title: 'Circle solids',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#101522',
		debug: false,
		maxFps: 60
	});

	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32 });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var shootSound = Game.createSound({ url: 'assets/laser.wav', volume: 0.35 });

	var dropTimer = null;
	win.addEventListener('close', function () {
		if (dropTimer !== null) {
			gameView.cancelTimer(dropTimer);
			dropTimer = null;
		}
		shootSound.stop();
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
		var POST = Math.max(40, Math.round(W * 0.13));
		var BALL = Math.max(12, Math.round(W * 0.04));
		var POST_Y = H * 0.34;
		var ambient = [
			Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: W * 0.15, y: H * 0.19,
				width: W * 0.62, height: W * 0.62,
				tintColor: '#25436b', opacity: 0.14,
				blend: 'screen', touchEnabled: false, zIndex: 0
			}),
			Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: W * 0.86, y: H * 0.52,
				width: W * 0.55, height: W * 0.55,
				tintColor: '#3a285f', opacity: 0.12,
				blend: 'screen', touchEnabled: false, zIndex: 0
			})
		];
		gameView.add(ambient);

		gameView.add(Game.createText({
			text: 'CIRCLE SOLIDS',
			x: W * 0.62, y: H * 0.05,
			scale: UNIT * 1.35,
			letterSpacing: UNIT,
			tintColor: '#f6c85f',
			zIndex: 20
		}));
		gameView.add(Game.createText({
			text: 'THREE EMITTERS  /  ANY BALL, ANY SHAPE',
			align: 'center',
			x: W / 2, y: H * 0.095,
			scale: UNIT * 0.7,
			tintColor: '#7f91b5',
			zIndex: 20
		}));

		// --- Shared drop field -------------------------------------------

		var lanes = [
			{ x: W * 0.18, shape: 'rect', round: false, spin: 0, name: 'RECT', color: '#ff8a80' },
			{ x: W * 0.50, shape: 'circle', round: true, spin: 0, name: 'CIRCLE', color: '#69f0ae' },
			{ x: W * 0.82, shape: 'rotatedRect', round: false, spin: 45, name: 'ROTATED', color: '#8ab4ff' }
		];

		lanes.forEach(function (lane) {
			lane.live = [];
			gameView.add(Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: lane.x, y: H * 0.34,
				width: W * 0.27, height: H * 0.45,
				tintColor: lane.color, opacity: 0.08,
				blend: 'screen', touchEnabled: false, zIndex: 0
			}));
			lane.post = Game.createSprite({
				sheet: lane.round ? ballSheet : wallSheet,
				x: lane.x, y: POST_Y,
				width: POST, height: POST,
				rotation: lane.spin,
				tintColor: lane.color,
				opacity: 0.82,
				touchEnabled: false,
				hitboxShape: lane.shape,
				// All three shapes are one solid field. Balls list this shared
				// group, so their spawn position no longer restricts which
				// shape they can hit.
				collisionGroup: 'contact-surface',
				zIndex: 5
			});
			lane.probe = Game.createSprite({
				// Same shape and size as the post, invisible, no art: solids
				// fire no events, so this twin reports the touch through
				// collidesWith while the post itself does the blocking.
				x: lane.x, y: POST_Y,
				width: POST, height: POST,
				rotation: lane.spin,
				touchEnabled: false,
				hitboxShape: lane.shape,
				collisionGroup: 'probe' + lane.name,
				zIndex: 1
			});
			lane.title = Game.createText({
				text: lane.name,
				align: 'center',
				x: lane.x, y: H * 0.145,
				scale: UNIT * 0.9,
				tintColor: lane.color,
				zIndex: 20
			});
			gameView.add([lane.post, lane.probe, lane.title]);
		});

		// One line for the three shapes instead of three overlapping ones, and
		// sampled a couple of frames AFTER the touch. The collision event can
		// fire a frame early for a swept sprite — checkCollisions falls back
		// to the path test — so reading the velocity right there catches the
		// ball on its way in, not on its way out.
		var lastOut = { RECT: '--', CIRCLE: '--', ROTATED: '--' };
		var readout = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.515,
			scale: UNIT * 0.7,
			tintColor: '#aab8d4',
			zIndex: 20
		});
		function updateReadout() {
			readout.text = 'EXIT VX   ' + lastOut.RECT
				+ '  /  ' + lastOut.CIRCLE
				+ '  /  ' + lastOut.ROTATED;
		}
		updateReadout();
		gameView.add(readout);

		// Catch zone under the field: a ball that got here is done bouncing
		gameView.add(Game.createSprite({
			x: W / 2, y: H * 0.63,
			width: W * 2, height: BALL * 2,
			touchEnabled: false,   // invisible, but it would still eat taps
			collisionGroup: 'void'
		}));

		gameView.add(Game.createText({
			text: 'RANDOM OFFSET  /  BOUNCE 0.32 - 0.88',
			align: 'center',
			x: W / 2, y: H * 0.565,
			scale: UNIT * 0.68,
			tintColor: '#7f91b5',
			zIndex: 20
		}));

		// A ball that settles on top of a post never reaches the catch zone,
		// so the zone alone leaks. Each emitter retires its oldest parked ball
		// after its lane reaches the visual limit.
		var MAX_PER_EMITTER = 6;

		function retire(lane, ball) {
			var i = lane.live.indexOf(ball);
			if (i >= 0) {
				lane.live.splice(i, 1);
				gameView.remove(ball);
			}
		}

		function randomBetween(min, max) {
			return min + Math.random() * (max - min);
		}

		var probeToName = {
			probeRECT: 'RECT',
			probeCIRCLE: 'CIRCLE',
			probeROTATED: 'ROTATED'
		};

		function spawnBall(lane) {
			var restitution = randomBetween(0.32, 0.88);
			var maxOffset = Math.max(0, (POST - BALL) * 0.45);
			var ball = Game.createSprite({
				sheet: ballSheet,
				x: lane.x + randomBetween(-maxOffset, maxOffset),
				y: H * 0.19,
				width: BALL, height: BALL,
				tintColor: lane.color,
				hitboxShape: 'circle',
				hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
				gravity: 900,
				velocityX: 0,
				restitution: restitution,
				swept: true,
				touchEnabled: false,
				collisionGroup: 'drop-ball',
				solidWith: ['contact-surface', 'drop-ball'],
				solidMode: 'push',
				collidesWith: ['void', 'probeRECT', 'probeCIRCLE', 'probeROTATED'],
				zIndex: 10
			});
			lane.live.push(ball);
			while (lane.live.length > MAX_PER_EMITTER) {
				retire(lane, lane.live[0]);
			}
			ball.addEventListener('collision', function (e) {
				if (e.group === 'void') {
					retire(lane, ball);
					return;
				}
				var shapeName = probeToName[e.group];
				if (!shapeName) {
					return;
				}
				// Two frames later: by then the resolver has certainly run,
				// whether the event fired on the real overlap or a frame
				// early off the swept path test
				gameView.after(34, function () {
					lastOut[shapeName] = String(Math.round(ball.velocityX));
					updateReadout();
				});
			});
			gameView.add(ball);
		}

		function drop() {
			// One vertical drop per shape. Only the horizontal point of release
			// and the ball's restitution vary; there is no artificial side push.
			lanes.forEach(spawnBall);
		}
		dropTimer = gameView.every(1100, drop);
		drop();

		// --- Ball vs ball: block (default) above, push below --------------

		gameView.add(Game.createText({
			text: 'ONE SHOT  /  TWO SOLID MODES',
			align: 'center',
			x: W / 2, y: H * 0.675,
			scale: UNIT * 0.8,
			tintColor: '#8ab4ff',
			zIndex: 20
		}));

		var rows = [
			{ y: H * 0.755, mode: 'block', label: "BLOCK  /  target stays put", color: '#ff8a80' },
			{ y: H * 0.875, mode: 'push', label: "PUSH  /  momentum transfers", color: '#69f0ae' }
		];

		rows.forEach(function (row) {
			// Side walls so the shooter comes back instead of leaving
			[W * 0.06, W * 0.94].forEach(function (wallX) {
				gameView.add(Game.createSprite({
					sheet: wallSheet,
					x: wallX, y: row.y,
					width: 8, height: BALL * 3,
					tintColor: '#9aa4c8',
					touchEnabled: false,
					collisionGroup: 'wall',
					zIndex: 5
				}));
			});

			gameView.add(Game.createText({
				text: row.label,
				x: W * 0.10, y: row.y - BALL * 2.2,
				anchorX: 0, anchorY: 0,
				scale: UNIT * 0.8,
				tintColor: row.color,
				zIndex: 20
			}));

			// Each row gets its own group, so the two rows never interact
			var group = 'ball-' + row.mode;
			function rowBall(x, color) {
				var ball = Game.createSprite({
					sheet: ballSheet,
					x: x, y: row.y,
					width: BALL * 1.5, height: BALL * 1.5,
					tintColor: color,
					hitboxShape: 'circle',
					hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
					restitution: 0.9,
					swept: true,
					touchEnabled: false,
					collisionGroup: group,
					solidWith: [group, 'wall'],
					solidMode: row.mode,
					zIndex: 10
				});
				gameView.add(ball);
				return ball;
			}
			row.shooter = rowBall(W * 0.2, '#ffd54a');
			row.target = rowBall(W * 0.62, '#e0e0e0');
		});

		var shootButton = Game.createText({
			text: '[ SHOOT AGAIN ]',
			align: 'center',
			x: W / 2, y: H * 0.955,
			scale: UNIT,
			tintColor: '#8ab4ff',
			zIndex: 20
		});
		function shootRows(playSound) {
			if (playSound) {
				shootSound.play();
			}
			rows.forEach(function (row) {
				row.shooter.x = W * 0.2;
				row.shooter.y = row.y;
				row.shooter.velocityY = 0;
				row.shooter.velocityX = 700;
				row.target.x = W * 0.62;
				row.target.y = row.y;
				row.target.velocityX = 0;
				row.target.velocityY = 0;
			});
		}
		shootButton.addEventListener('tap', function () {
			shootButton.flash('#fff', 150);
			shootRows(true);
		});
		gameView.add(shootButton);
		gameView.after(450, function () {
			shootRows(false);
		});
		// The overlay is the argument in this demo, but it also makes the
		// screen read like a tool rather than a game, so it is a toggle
		// rather than a fixture. Green is the collision shape, blue the
		// sprite's own bounds, and orange the anchor.
		var shapesOn = false;
		var shapesButton = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.61,
			scale: UNIT * 0.8,
			tintColor: '#8ab4ff',
			zIndex: 20
		});
		function updateShapes() {
			shapesButton.text = shapesOn ? '[ DEBUG SHAPES ON ]' : '[ DEBUG SHAPES OFF ]';
			gameView.debug = shapesOn;
		}
		shapesButton.addEventListener('tap', function () {
			shapesOn = !shapesOn;
			shapesButton.flash('#fff', 150);
			updateShapes();
		});
		updateShapes();
		gameView.add(shapesButton);
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win, { text: '#d8e4ff', background: '#182033', border: '#3c4a68', pressed: '#263552' });
	win.open();
};
