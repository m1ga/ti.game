// ti.game bingo drum demo — inward circular containment plus pushable balls.
//
// One sheetless drum with `solidMode: 'contain'` and a circle hitbox, and
// 25 balls inside it. Containment is analytic: a ball whose center ends a
// frame further than R - r from the drum's center is pulled straight back
// onto that circle and its outward velocity reflected. There is no ring of
// wall sprites, so there are no seams for a ball to squeeze through and no
// forty extra collision tests per ball per frame.
//
// The balls are also `solidMode: 'push'` and list their own group, so they
// pile up and shove each other instead of overlapping — the same bilateral
// resolution the pool demo uses, here under gravity.
//
// Tap SHAKE to kick them all in a random direction. Left alone they settle
// on the lower arc: contact on the bottom of the drum grounds them exactly
// like landing on a platform, because the correcting normal points up.
//
// TUMBLE turns on one thin trigger at the bottom of the drum. Only the ball
// touching that strip receives an additive upward impulse; the rest
// move because gravity and `solidMode: 'push'` carry the impact through the
// pile. `collisionend` rearms that ball after it leaves the strip, so there is
// no repeating timer and no synchronized whole-drum kick.
//
// The container keeps its own debug outline on purpose: the green circle is
// the exact analytic boundary, not a stretched illustration pretending to
// match it. The launcher is outlined too, so the otherwise invisible contact
// strip remains visible in this teaching demo.
//
// Exports a start function; the demo opens its own window.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		extendSafeArea: false,   // keep content clear of the notch and home bar
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#0d1320',
		maxFps: 60
	});

	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32 });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var shakeSound = Game.createSound({ url: 'assets/crash.wav', volume: 0.4 });
	var tumbleSound = Game.createSound({
		url: 'assets/bingo_tumble.wav',
		music: true,
		loop: true,
		volume: 0.16
	});

	win.addEventListener('close', function () {
		shakeSound.stop();
		tumbleSound.stop();
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
		var DRUM = Math.min(W * 0.90, H * 0.59);
		var CX = W / 2;
		var CY = H * 0.51;
		var BALL = Math.max(12, Math.round(DRUM * 0.095));
		var COUNT = 25;
		var LAUNCHER_GROUP = 'drum-launcher';
		var LAUNCHER_WIDTH = BALL * 0.9;
		var LAUNCHER_HEIGHT = Math.max(4, BALL * 0.2);
		var LAUNCHER_TOP = CY + DRUM * 0.41;

		var COLORS = [
			'#f2d14b', '#2f6fd0', '#d63d3d', '#7b4bbd', '#e07a2b',
			'#2f9e5f', '#3fb6c4', '#e86ea8'
		];

		gameView.add(Game.createSprite({
			sheet: sparkSheet, frame: 0,
			x: CX, y: CY,
			width: W * 1.2, height: W * 1.2,
			tintColor: '#263d67', opacity: 0.16,
			blend: 'screen', touchEnabled: false, zIndex: 0
		}));

		gameView.add(Game.createText({
			text: 'BINGO DRUM',
			x: W / 2, y: H * 0.06,
			scale: UNIT * 1.35,
			letterSpacing: UNIT,
			tintColor: '#f6c85f',
			zIndex: 20
		}));
		gameView.add(Game.createText({
			text: "ONE CIRCLE  /  solidMode: 'contain'",
			align: 'center',
			x: W / 2, y: H * 0.105,
			scale: UNIT * 0.72,
			tintColor: '#7f91b5',
			zIndex: 20
		}));

		// --- The drum: one outlined boundary, with a simple visual shell ---

		var drumObjects = [
			Game.createSprite({
				sheet: wallSheet,
				x: CX - DRUM * 0.27, y: CY + DRUM * 0.48,
				width: DRUM * 0.08, height: DRUM * 0.22,
				rotation: 10, tintColor: '#9c6a37',
				touchEnabled: false, zIndex: 1
			}),
			Game.createSprite({
				sheet: wallSheet,
				x: CX + DRUM * 0.27, y: CY + DRUM * 0.48,
				width: DRUM * 0.08, height: DRUM * 0.22,
				rotation: -10, tintColor: '#9c6a37',
				touchEnabled: false, zIndex: 1
			}),
			Game.createSprite({
				sheet: wallSheet,
				x: CX, y: CY + DRUM * 0.59,
				width: DRUM * 0.72, height: DRUM * 0.07,
				tintColor: '#7f512c', touchEnabled: false, zIndex: 1
			}),
			Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: CX, y: CY,
				width: DRUM, height: DRUM,
				tintColor: '#f6c85f', opacity: 0.28,
				blend: 'screen', touchEnabled: false, zIndex: 2
			}),
			Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: CX, y: CY,
				width: DRUM * 0.90, height: DRUM * 0.90,
				tintColor: '#172238', opacity: 0.96,
				touchEnabled: false, zIndex: 3
			}),
			Game.createSprite({
				x: CX, y: CY,
				width: DRUM * 0.88, height: DRUM * 0.88,
				touchEnabled: false,
				hitboxShape: 'circle',
				collisionGroup: 'drum',
				solidMode: 'contain',   // keeps matched circles INSIDE it
				debug: true,            // exact green containment circle
				zIndex: 5
			})
		];
		gameView.add(drumObjects);

		// --- Contact launcher: visible trigger, not a solid ----------------
		//
		// The circle remains the only surface holding the balls. This sheetless
		// sprite only reports overlap while TUMBLE is active; making it solid as
		// well would resolve the overlap before collision events are checked and
		// leave every ball resting on an invisible flat shelf.

		gameView.add(Game.createSprite({
			x: CX,
			y: LAUNCHER_TOP + LAUNCHER_HEIGHT / 2,
			width: LAUNCHER_WIDTH,
			height: LAUNCHER_HEIGHT,
			collisionGroup: LAUNCHER_GROUP,
			touchEnabled: false,
			debug: true,
			zIndex: 6
		}));

		// --- The balls -------------------------------------------------------

		var balls = [];
		var launcherContacts = [];
		var tumbling = true;

		function clamp(value, min, max) {
			return Math.max(min, Math.min(max, value));
		}

		function launch(ball) {
			var offset = clamp((ball.x - CX) / (LAUNCHER_WIDTH / 2), -1, 1);
			var upwardImpulse = DRUM * (3 + Math.random() * 0.8);
			var inwardImpulse = -offset * DRUM * 0.35;
			var randomImpulse = (Math.random() - 0.5) * DRUM * 0.04;

			// Add the impulse to the live velocity instead of replacing it. The
			// caps keep repeated contacts energetic without becoming explosive.
			ball.velocityX = clamp(
				ball.velocityX + inwardImpulse + randomImpulse,
				-DRUM * 1.1,
				DRUM * 1.1
			);
			ball.velocityY = Math.max(ball.velocityY - upwardImpulse, -DRUM * 3.6);
		}

		function bindLauncher(ball) {
			var touching = false;
			ball.addEventListener('collision', function (e) {
				if (e.group !== LAUNCHER_GROUP || touching) {
					return;
				}
				touching = true;
				if (tumbling) {
					launch(ball);
				}
			});
			ball.addEventListener('collisionend', function (e) {
				if (e.group === LAUNCHER_GROUP) {
					touching = false;
				}
			});
			launcherContacts.push(function () {
				touching = false;
			});
		}

		for (var i = 0; i < COUNT; i++) {
			// Start them on a loose spiral so nothing begins overlapping
			var turn = i * 2.399963;              // golden angle, spreads evenly
			var spread = (DRUM / 2 - BALL) * Math.sqrt((i + 0.5) / COUNT) * 0.92;
			var ball = Game.createSprite({
				sheet: ballSheet,
				x: CX + Math.cos(turn) * spread,
				y: CY + Math.sin(turn) * spread,
				width: BALL, height: BALL,
				tintColor: COLORS[i % COLORS.length],
				hitboxShape: 'circle',
				hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
				gravity: 1400,
				restitution: 0.55,
				linearDamping: 0.35,
				touchEnabled: false,
				collisionGroup: 'ball',
				solidWith: ['drum', 'ball'],
				collidesWith: [LAUNCHER_GROUP],
				solidMode: 'push',
				zIndex: 10
			});
			bindLauncher(ball);
			balls.push(ball);
		}
		gameView.add(balls);

		// --- Shake -------------------------------------------------------------

		var shakeButton = Game.createText({
			text: '[ SHAKE ]',
			align: 'center',
			x: W * 0.27, y: H * 0.91,
			scale: UNIT * 1.1,
			tintColor: '#f6c85f',
			zIndex: 20
		});
		function kick(minSpeed, spread) {
			balls.forEach(function (ball) {
				var angle = Math.random() * Math.PI * 2;
				var speed = minSpeed + Math.random() * spread;
				ball.velocityX = Math.cos(angle) * speed;
				ball.velocityY = Math.sin(angle) * speed;
			});
		}

		shakeButton.addEventListener('tap', function () {
			shakeButton.flash('#fff', 150);
			shakeSound.play();
			gameView.shake({ strength: BALL * 0.5, duration: 400 });
			kick(700, 900);
		});
		gameView.add(shakeButton);

		// --- TUMBLE: contact-driven air jet ---------------------------------

		var tumbleButton = Game.createText({
			text: '[ TUMBLE ON ]',
			align: 'center',
			x: W * 0.74, y: H * 0.92,
			scale: UNIT * 1.1,
			tintColor: '#69f0ae',
			zIndex: 20
		});
		tumbleButton.addEventListener('tap', function () {
			tumbleButton.flash('#fff', 150);
			tumbling = !tumbling;
			launcherContacts.forEach(function (resetContact) {
				resetContact();
			});
			balls.forEach(function (ball) {
				ball.collidesWith = tumbling ? [LAUNCHER_GROUP] : [];
			});
			if (!tumbling) {
				tumbleSound.stop();
				tumbleButton.text = '[ TUMBLE OFF ]';
				tumbleButton.tintColor = '#8ab4ff';
				return;
			}
			tumbleSound.play();
			tumbleButton.text = '[ TUMBLE ON ]';
			tumbleButton.tintColor = '#69f0ae';
		});
		gameView.add(tumbleButton);
		tumbleSound.play();

		gameView.add(Game.createText({
			text: COUNT + ' PUSH BODIES  /  GREEN RING = CONTAINER',
			align: 'center',
			x: W / 2, y: H * 0.97,
			scale: UNIT * 0.65,
			tintColor: '#7f91b5',
			zIndex: 20
		}));
	}

	win.add(gameView);
	// Back — return to the launcher
	var backButton = Ti.UI.createLabel({
		text: '‹  EXAMPLES',
		top: Ti.Platform.osname === 'android' ? 10 : 40,
		left: 12,
		width: 96,
		height: 38,
		color: '#d8e4ff',
		backgroundColor: '#182033',
		borderColor: '#3c4a68',
		borderWidth: 1,
		borderRadius: 19,
		font: { fontSize: 12, fontWeight: 'bold' },
		textAlign: 'center',
		zIndex: 100
	});
	backButton.addEventListener('touchstart', function () { backButton.backgroundColor = '#263552'; });
	backButton.addEventListener('touchend', function () { backButton.backgroundColor = '#182033'; });
	backButton.addEventListener('touchcancel', function () { backButton.backgroundColor = '#182033'; });
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);
	win.open();
};
