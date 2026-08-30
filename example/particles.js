// ti.game particles demo — the emitter API in all three modes.
//
// - a continuous fountain sprays golden sparks from the bottom edge
//   (`rate`, gravity pulls them back down)
// - tap anywhere for a firework burst at that spot (`emit(n)`, rate 0),
//   cycling through tint colors per tap
// - drag the ball around: a puff emitter follows it (`target`), leaving
//   a fading smoke trail — all three emitters run entirely natively
//
// Both emitters draw white particle art (spark.png) tinted at runtime,
// so one tiny texture covers every color used here.
//
// The debug HUD is on (`debug: { hud: 'topRight' }`) — the particle count
// climbs with every firework. Tap it to expand it.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		title: 'Particles',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#181828',
		debug: { hud: 'topRight' }   // tap the HUD to expand it
	});

	// white particle frames (0 = soft puff, 1 = pixel spark)
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var UNIT = Math.min(W, H);

		// --- Continuous: a spark fountain at the bottom ------------------

		var fountain = Game.createEmitter({
			sheet: sparkSheet,
			frame: 1,
			x: W / 2,
			y: H - UNIT * 0.05,
			rate: 90,
			lifetime: 1600,
			speed: H * 0.75,          // launch upward...
			angle: 0,
			spread: 25,
			gravity: H * 0.45,        // ...and fall back down
			size: UNIT * 0.03,
			startScale: 1,
			endScale: 0.4,
			startOpacity: 1,
			endOpacity: 0,
			tint: '#ffcc44',
			maxParticles: 400
		});
		gameView.add(fountain);

		// --- Burst on tap: fireworks -------------------------------------

		var COLORS = ['#ff5544', '#44cc66', '#5588ff', '#ffcc44', '#cc66ff', '#44ddee'];
		var colorIndex = 0;

		var firework = Game.createEmitter({
			sheet: sparkSheet,
			frame: 1,
			rate: 0,                  // burst-only
			lifetime: 900,
			speed: UNIT * 0.6,
			spread: 360,
			gravity: H * 0.25,
			size: UNIT * 0.035,
			startScale: 1,
			endScale: 0.3,
			startOpacity: 1,
			endOpacity: 0,
			maxParticles: 500
		});
		gameView.add(firework);

		gameView.addEventListener('tap', function (e) {
			firework.x = e.x;
			firework.y = e.y;
			firework.tint = COLORS[colorIndex++ % COLORS.length];
			firework.emit(45);
		});

		// --- Following: a draggable ball with a smoke trail --------------

		var ball = Game.createSprite({
			sheet: ballSheet,
			x: W / 2,
			y: H * 0.3,
			width: UNIT * 0.14,
			height: UNIT * 0.14,
			zIndex: 10,
			draggable: true
		});
		gameView.add(ball);

		var trail = Game.createEmitter({
			sheet: sparkSheet,
			frame: 0,                 // soft puff
			target: ball,             // follows the sprite, even mid-drag
			rate: 45,
			lifetime: 700,
			speed: UNIT * 0.04,
			spread: 360,
			size: UNIT * 0.06,
			startScale: 0.8,
			endScale: 2,
			startOpacity: 0.35,
			endOpacity: 0,
			tint: '#8899cc',
			zIndex: 9                 // puffs appear behind the ball
		});
		gameView.add(trail);

		win.add(Ti.UI.createLabel({
			text: 'Tap for fireworks — drag the ball',
			color: '#fff',
			font: { fontSize: 20, fontWeight: 'bold' },
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 2 },
			top: 90 // below the Back button
		}));
	}

	win.add(gameView);
	// Back — return to the launcher. Android uses the action bar's Up arrow;
	// iOS keeps an overlay button because there is no navigation bar.
	if (Ti.Platform.osname === 'android') {
		win.addEventListener('open', function () {
			var actionBar = win.activity.actionBar;
			if (actionBar) {
				actionBar.displayHomeAsUp = true;
				actionBar.onHomeIconItemSelected = function () {
					win.close();
				};
			}
		});
	} else {
		var backButton = Ti.UI.createLabel({
			text: '‹  EXAMPLES',
			top: 40,
			left: 12,
			width: 96,
			height: 38,
			color: '#eaf5f6',
			backgroundColor: '#18394d',
			borderColor: '#41697b',
			borderWidth: 1,
			borderRadius: 19,
			font: { fontSize: 12, fontWeight: 'bold' },
			textAlign: 'center',
			zIndex: 100
		});
		backButton.addEventListener('touchstart', function () { backButton.backgroundColor = '#28576d'; });
		backButton.addEventListener('touchend', function () { backButton.backgroundColor = '#18394d'; });
		backButton.addEventListener('touchcancel', function () { backButton.backgroundColor = '#18394d'; });
		backButton.addEventListener('click', function () {
			win.close();
		});
		win.add(backButton);
	}

	win.open();
};
