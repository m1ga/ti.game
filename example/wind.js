// ti.game wind demo — `gravityX`, the horizontal sibling of `gravity`.
//
// `gravity` has always been vertical acceleration on velocityY, and it
// still is: this does not turn it into a vector and does not rename it.
// `gravityX` is a second constant acceleration, applied to velocityX in
// the same integration step. Default 0, so nothing that exists today
// moves differently.
//
// Falling leaves drift sideways under it. The buttons change the wind and
// every leaf answers immediately, with no per-frame JavaScript: the value
// is read natively each tick, the way gravity is.
//
// The lower strip shows the other use, which has nothing to do with wind:
// a top-down puck on a table whose "down" is sideways. Same property, no
// vertical gravity at all.
//
// Exports a start function; the demo opens its own window.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#102332',
		extendSafeArea: false,   // keep content clear of the notch and home bar
		title: 'Wind (gravityX)',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#102332',
		maxFps: 60
	});

	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var meadowSheet = Game.createSpriteSheet({ image: 'assets/meadow.png', frameWidth: 270, frameHeight: 480, smoothing: false });
	var oakSheet = Game.createSpriteSheet({ image: 'assets/oak.png', frameWidth: 128, frameHeight: 160, smoothing: false });
	var windSound = Game.createSound({ url: 'assets/thrust.wav', loop: true, volume: 0 });

	var dropTimer = null;
	win.addEventListener('close', function () {
		if (dropTimer !== null) {
			gameView.cancelTimer(dropTimer);
			dropTimer = null;
		}
		windSound.stop();
		gameView.pause();
		gameView.removeAllSprites();
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
		var LEAF = Math.max(10, Math.round(W * 0.03));
		var FLOOR_Y = H * 0.57;
		var STRIP_Y = H * 0.88;

		var WINDS = [-900, -450, -150, 0, 150, 450, 900]; // px/s²
		var WIND_NAMES = [
			'<<< STRONG LEFT',
			'<< LEFT',
			'< LIGHT LEFT',
			'CALM',
			'LIGHT RIGHT >',
			'RIGHT >>',
			'STRONG RIGHT >>>'
		];
		var windIndex = 3;
		var leaves = [];
		var scene = [];

		// A simple outdoor scene makes the force readable at a glance.
		scene.push(Game.createSprite({
			sheet: meadowSheet,
			x: W / 2, y: FLOOR_Y / 2,
			width: W, height: FLOOR_Y,
			touchEnabled: false,
			zIndex: -20
		}));

		var treeHeight = Math.min(H * 0.31, W * 0.52);
		scene.push(Game.createSprite({
			sheet: oakSheet,
			x: W * 0.87, y: FLOOR_Y + 2,
			anchorY: 1,
			width: treeHeight * 0.8, height: treeHeight,
			touchEnabled: false,
			zIndex: 2
		}));

		scene.push(Game.createText({
			text: 'GRAVITYX LAB',
			x: W / 2, y: H * 0.045,
			scale: UNIT * 0.72,
			tintColor: '#31546b',
			zIndex: 30
		}));
		scene.push(Game.createText({
			text: 'SIDEWAYS GRAVITY',
			x: W / 2, y: H * 0.085,
			scale: UNIT * 1.3,
			tintColor: '#16364d',
			zIndex: 30
		}));
		scene.push(Game.createText({
			text: 'THE LEAVES FALL DOWN WHILE THE WIND PULLS SIDEWAYS',
			align: 'center',
			x: W / 2, y: H * 0.125,
			scale: UNIT * 0.55,
			tintColor: '#31546b',
			zIndex: 30
		}));

		// Floor and catch zone: leaves land, then get cleared
		scene.push(Game.createSprite({
			sheet: sparkSheet, frame: 0,
			x: W / 2, y: FLOOR_Y,
			width: W * 1.04, height: Math.max(8, UNIT * 5),
			tintColor: '#315747',
			touchEnabled: false,
			collisionGroup: 'floor',
			zIndex: 5
		}));

		function drop() {
			// Retire anything that has settled or blown off the sides
			for (var i = leaves.length - 1; i >= 0; i--) {
				var old = leaves[i];
				if (old.y >= FLOOR_Y - LEAF || old.x < -LEAF * 2 || old.x > W + LEAF * 2) {
					gameView.remove(old);
					leaves.splice(i, 1);
				}
			}
			if (leaves.length > 40) {
				return;
			}
			var leaf = Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: W * (0.2 + Math.random() * 0.6),
				y: -LEAF,
				width: LEAF * 1.45, height: LEAF * 0.62,
				rotation: Math.random() * 180,
				tintColor: ['#d95d39', '#ee9b36', '#f2ca52', '#a84332'][Math.floor(Math.random() * 4)],
				gravity: 260,
				gravityX: WINDS[windIndex],
				angularVelocity: -120 + Math.random() * 240,
				touchEnabled: false,
				solidWith: ['floor'],
				restitution: 0.15,
				zIndex: 10
			});
			leaves.push(leaf);
			gameView.add(leaf);
		}
		dropTimer = gameView.every(140, drop);

		// --- Wind controls ------------------------------------------------

		var readout = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.655,
			scale: UNIT * 0.82,
			tintColor: '#eaf5f6',
			zIndex: 30
		});

		function applyWind() {
			var wind = WINDS[windIndex];
			readout.text = WIND_NAMES[windIndex] + '\nGRAVITYX = ' + wind + ' PX/S/S';
			leaves.forEach(function (leaf) {
				leaf.gravityX = wind;
			});
			puck.gravityX = wind;
			windSound.volume = Math.abs(wind) / 900 * 0.16;
		}

		function makeWindButton(label, x, step) {
			var button = Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: x, y: H * 0.735,
				width: W * 0.25, height: Math.max(38, UNIT * 20),
				tintColor: '#244b61',
				zIndex: 25
			});
			var buttonLabel = Game.createText({
				text: label,
				align: 'center',
				x: x, y: H * 0.735,
				scale: UNIT * 0.82,
				tintColor: '#d7eef2',
				touchEnabled: false,
				zIndex: 30
			});
			button.addEventListener('tap', function () {
				windIndex = Math.min(WINDS.length - 1, Math.max(0, windIndex + step));
				button.flash('#6aa9bd', 140);
				applyWind();
			});
			return [button, buttonLabel];
		}

		// --- Top-down strip: sideways "down", no vertical gravity ----------

		scene.push(Game.createText({
			text: 'SIDEWAYS TABLE  /  VERTICAL GRAVITY = 0',
			align: 'center',
			x: W / 2, y: H * 0.805,
			scale: UNIT * 0.58,
			tintColor: '#78a7b5',
			zIndex: 30
		}));
		scene.push(Game.createSprite({
			sheet: sparkSheet, frame: 0,
			x: W / 2, y: STRIP_Y,
			width: W * 0.78, height: Math.max(4, UNIT * 2),
			tintColor: '#1b3b4e',
			touchEnabled: false,
			zIndex: 3
		}));

		[W * 0.06, W * 0.94].forEach(function (wallX) {
			scene.push(Game.createSprite({
				sheet: sparkSheet, frame: 0,
				x: wallX, y: STRIP_Y,
				width: Math.max(8, UNIT * 4), height: LEAF * 5,
				tintColor: '#41697b',
				touchEnabled: false,
				collisionGroup: 'edge',
				zIndex: 5
			}));
		});

		var puck = Game.createSprite({
			sheet: ballSheet,
			x: W / 2, y: STRIP_Y,
			width: LEAF * 2.2, height: LEAF * 2.2,
			tintColor: '#69f0ae',
			hitboxShape: 'circle',
			hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
			gravity: 0,               // no fall at all
			gravityX: WINDS[windIndex],
			restitution: 0.7,
			swept: true,
			touchEnabled: false,
			solidWith: ['edge'],
			zIndex: 10
		});
		scene.push(puck);

		scene.push(readout);
		scene = scene.concat(makeWindButton('-  LESS WIND', W * 0.25, -1));
		scene = scene.concat(makeWindButton('MORE WIND  +', W * 0.75, 1));
		gameView.add(scene);
		applyWind();
		windSound.play();
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win);
	win.open();
};
