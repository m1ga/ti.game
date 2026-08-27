// ti.game slope demo — a tilted solid, seen from the platformer side.
//
// The ramps declare `hitboxShape: 'rotatedRect'`, so their collision box
// turns with the art instead of being re-boxed square to the screen. That
// is what makes the contact normal come out perpendicular to the ramp's
// real face, and it is the whole difference between a body that settles on
// a slope and slides, and one that stands on an invisible flat ledge.
//
// Two riders, because they take different paths through the engine. The
// crate is a plain rect, resolved against the ramp by separating axes — the
// case a platformer player is in. The ball is a circle, taken into the
// ramp's own frame and clamped there. Both end up with the same kind of
// answer: push out along the ramp's face, keep the speed along it.
//
// Neither one has friction along the surface, so they slide rather than
// roll to a halt; `linearDamping` bleeds speed in every direction at once,
// which is right for a pool table and wrong for a hill. Surface friction
// that only acts along the contact is a separate thing the engine lacks.
//
// The green surfaces are the springy ones: a solid carries its own
// `restitution`, and the springier of the two surfaces decides the bounce.
// The floor and the side walls are at 0.5 and the ramps at 0, so the same
// ball slides down a ramp and then rebounds off floor and walls without
// either value being changed mid-flight. The walls matter as much as the
// floor: at 0 they were a dead end and everything ended up parked in a
// corner, no matter how well the floor bounced.
//
// The shape overlay starts off, so this reads as a scene rather than a
// tool; the button turns it on, and then the ramps' green boxes can be seen
// turned and lying on their art instead of boxing it.
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
		backgroundColor: '#0d1422',
		debug: false,
		maxFps: 60
	});

	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32 });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var UNIT = Math.max(1, Math.round(W / 380));
		var RIDER = Math.max(18, Math.round(W * 0.06));
		var SHADOW_X = UNIT * 3;
		var SHADOW_Y = UNIT * 5;
		var debugShapes = [];
		var scene = [
			Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: W * 0.17, y: H * 0.29,
				width: W * 0.66, height: W * 0.66,
				tintColor: '#24476f', opacity: 0.13,
				blend: 'screen', touchEnabled: false, zIndex: 0
			}),
			Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: W * 0.88, y: H * 0.62,
				width: W * 0.58, height: W * 0.58,
				tintColor: '#4b315f', opacity: 0.11,
				blend: 'screen', touchEnabled: false, zIndex: 0
			}),
			Game.createText({
				text: 'SLOPE LAB',
				x: W / 2, y: H * 0.05,
				scale: UNIT * 1.35,
				letterSpacing: UNIT,
				tintColor: '#f6c85f',
				zIndex: 20
			}),
			Game.createText({
				text: 'ROTATED RECT RAMPS  /  RECT + CIRCLE RIDERS',
				align: 'center',
				x: W / 2, y: H * 0.095,
				scale: UNIT * 0.65,
				tintColor: '#7f91b5',
				zIndex: 20
			})
		];

		function addSurface(options) {
			var shadow = Game.createSprite({
				sheet: wallSheet,
				x: options.x + SHADOW_X, y: options.y + SHADOW_Y,
				width: options.width, height: options.height,
				rotation: options.rotation || 0,
				tintColor: '#1b263b',
				opacity: 0.72,
				touchEnabled: false,
				zIndex: 3
			});
			var surface = Game.createSprite({
				sheet: wallSheet,
				x: options.x, y: options.y,
				width: options.width, height: options.height,
				rotation: options.rotation || 0,
				tintColor: options.color,
				restitution: options.restitution || 0,
				touchEnabled: false,
				hitboxShape: options.hitboxShape || 'rect',
				collisionGroup: 'ramp',
				zIndex: 5
			});
			scene.push(shadow, surface);
			debugShapes.push(surface);
		}

		// --- Two ramps, alternating tilt, and a floor ----------------------
		//
		// Short on purpose. A rider sliding a long ramp arrives at the end
		// carrying every bit of speed the drop gave it and leaves as a
		// projectile — which looks like the ramp fired it. These are sized so
		// the first one hands the rider to the second, and the second to the
		// floor: verified by simulating the drop against the same arithmetic
		// the engine runs, not by eye.

		var ramps = [
			{ x: W * 0.28, y: H * 0.24, angle: 12 },
			{ x: W * 0.65, y: H * 0.42, angle: -12 }
		];
		ramps.forEach(function (ramp) {
			addSurface({
				x: ramp.x, y: ramp.y,
				width: W * 0.30, height: 14,
				rotation: ramp.angle,
				color: '#8291b5',
				hitboxShape: 'rotatedRect'
			});
		});

		// The floor has a bounce of its own. Restitution belongs to the
		// contact, and the springier of the two surfaces wins, so a rider
		// that slides down the ramps still rebounds here: the ball carries
		// 0.1, which is what it uses against the ramps, and meets 0.5 on
		// the floor. Without this the riders just parked in the corner.
		addSurface({
			x: W / 2, y: H * 0.86,
			width: W * 1.24, height: 12,
			color: '#58c99b',
			restitution: 0.5
		});

		// Side walls, so a rider that reaches the floor stays on screen.
		// Springy like the floor: at 0 they were a dead end, and a rider that
		// bounced its way across the floor just parked against one of them.
		[W * 0.02, W * 0.98].forEach(function (wallX) {
			addSurface({
				x: wallX, y: H * 0.72,
				width: 12, height: H * 0.34,
				color: '#58c99b',
				restitution: 0.5
			});
		});

		// --- The riders -----------------------------------------------------

		// Well onto the face of the first ramp, not on its end. Ramp 1 runs
		// from 0.133W to 0.427W, so a rider released at its very tip lands on
		// the corner instead of the slope and perches there.
		var START = { crateX: W * 0.20, ballX: W * 0.29, y: H * 0.15 };

		var crate = Game.createSprite({
			sheet: wallSheet,
			x: START.crateX, y: START.y,
			width: RIDER, height: RIDER,
			tintColor: '#f6c85f',
			gravity: 1100,
			restitution: 0,
			swept: true,
			touchEnabled: false,
			solidWith: ['ramp'],
			zIndex: 10
		});

		var ball = Game.createSprite({
			sheet: ballSheet,
			x: START.ballX, y: START.y,
			width: RIDER, height: RIDER,
			tintColor: '#63e6be',
			hitboxShape: 'circle',
			hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
			gravity: 1100,
			restitution: 0.1,   // it should slide like the crate, not hop down
			swept: true,
			touchEnabled: false,
			solidWith: ['ramp'],
			zIndex: 10
		});
		scene.push(crate, ball);
		debugShapes.push(crate, ball);

		scene.push(Game.createText({
			text: 'GREEN RAILS  /  SURFACE RESTITUTION 0.5',
			align: 'center',
			x: W / 2, y: H * 0.81,
			scale: UNIT * 0.68,
			tintColor: '#58c99b',
			zIndex: 20
		}));
		scene.push(Game.createText({
			text: 'RECT CRATE',
			align: 'center',
			x: W * 0.29, y: H * 0.90,
			scale: UNIT * 0.72,
			tintColor: '#f6c85f',
			zIndex: 20
		}));
		scene.push(Game.createText({
			text: 'CIRCLE BALL',
			align: 'center',
			x: W * 0.71, y: H * 0.90,
			scale: UNIT * 0.72,
			tintColor: '#63e6be',
			zIndex: 20
		}));

		var resetButton = Game.createText({
			text: '[ DROP AGAIN ]',
			align: 'center',
			x: W * 0.30, y: H * 0.96,
			scale: UNIT * 0.8,
			tintColor: '#8ab4ff',
			zIndex: 20
		});
		resetButton.addEventListener('tap', function () {
			resetButton.flash('#fff', 150);
			crate.x = START.crateX;
			crate.y = START.y;
			crate.velocityX = 0;
			crate.velocityY = 0;
			ball.x = START.ballX;
			ball.y = START.y;
			ball.velocityX = 0;
			ball.velocityY = 0;
		});
		// The overlay is the argument in this demo, but it also makes the
		// screen read like a tool rather than a game, so it is a toggle
		// rather than a fixture. Green is the collision shape, blue the
		// sprite's own bounds, and orange the anchor.
		var shapesOn = false;
		var shapesButton = Game.createText({
			text: '',
			align: 'center',
			x: W * 0.73, y: H * 0.96,
			scale: UNIT * 0.8,
			tintColor: '#7f91b5',
			zIndex: 20
		});
		function updateShapes() {
			shapesButton.text = shapesOn ? '[ SHAPES ON ]' : '[ SHAPES OFF ]';
			shapesButton.tintColor = shapesOn ? '#63e6be' : '#7f91b5';
			debugShapes.forEach(function (sprite) {
				sprite.debug = shapesOn;
			});
		}
		shapesButton.addEventListener('tap', function () {
			shapesOn = !shapesOn;
			shapesButton.flash('#fff', 150);
			updateShapes();
		});
		updateShapes();
		scene.push(resetButton, shapesButton);
		gameView.add(scene);
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
