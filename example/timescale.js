// ti.game timeScale demo — slow motion and pause on the whole scene.
//
// gameView.timeScale multiplies the dt fed to everything the engine
// ticks: sprite physics, sheet animations, tweens, particles, camera.
// Rendering and touch keep running, so 0 works as a pause that still
// draws — no render-loop stop, no state to save.
//
// - a dog runs laps across the screen (walk animation + velocityX +
//   wrapAround) and a spark fountain sprays continuously
// - a ball bounces on an invisible floor (gravity + restitution)
// - the buttons at the bottom set timeScale to 1, 0.5, 0.1 or 0 —
//   watch animation frames, physics and particles all slow together
// - two clocks: GAME counts via gameView.every(1000, ...) on the game
//   clock, so it slows and freezes with the buttons; REAL counts via
//   setInterval and keeps ticking — use after()/every() for spawn
//   waves and respawn delays so pausing really pauses them
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({ backgroundColor: '#1c2340' });
	var realTimer = null;
	win.addEventListener('close', function () {
		if (realTimer !== null) {
			clearInterval(realTimer);
			realTimer = null;
		}
	});

	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var DOG = Math.round(W * 0.16);
		var BALL = Math.round(W * 0.14);
		var floorY = H * 0.62;

		// Invisible floor for the ball (and the dog's track reference)
		gameView.add(Game.createSprite({
			x: W / 2, y: floorY + 20, width: W, height: 40,
			collisionGroup: 'floor'
		}));

		// --- Dog: runs laps, wraps around the screen edges ---------------

		var dog = Game.createSprite({
			sheet: dogSheet,
			x: W * 0.2,
			y: floorY - DOG / 2,
			width: DOG,
			height: DOG,
			zIndex: 5,
			velocityX: W * 0.3,
			wrapAround: true,
			animations: {
				run: { frames: [0, 1], fps: 8, loop: true }
			}
		});
		dog.play('run');
		gameView.add(dog);

		// --- Ball: perpetual bounce off the invisible floor --------------

		var ball = Game.createSprite({
			sheet: ballSheet,
			x: W * 0.75,
			y: H * 0.3, // bounce apex stays below the REAL clock
			width: BALL,
			height: BALL,
			zIndex: 5,
			gravity: H * 1.5,
			hitboxShape: 'circle',
			restitution: 1, // full reflection — bounces forever
			solidWith: ['floor']
		});
		gameView.add(ball);

		// --- Spark fountain ----------------------------------------------

		gameView.add(Game.createEmitter({
			sheet: sparkSheet,
			x: W * 0.5,
			y: floorY,
			zIndex: 3,
			rate: 40,
			lifetime: 1400,
			speed: H * 0.5,
			angle: 0,          // up
			spread: 40,
			gravity: H * 0.6,
			blend: 'add',
			tint: '#ffd54a',
			startScale: 1.2,
			endScale: 0.4
		}));

		// --- Game clock vs wall clock ------------------------------------

		var UNIT = Math.max(1, Math.round(W / 200));
		var gameSeconds = 0;
		var realSeconds = 0;
		var gameClock = Game.createText({
			text: 'GAME 0s',
			x: W * 0.28,
			y: H * 0.2, // below the hint label
			scale: UNIT,
			tintColor: '#4dff88',
			zIndex: 10
		});
		var realClock = Game.createText({
			text: 'REAL 0s',
			x: W * 0.72,
			y: H * 0.2, // below the hint label
			scale: UNIT,
			tintColor: '#ff8a80',
			zIndex: 10
		});
		gameView.add(gameClock);
		gameView.add(realClock);

		// every() ticks on the game clock — ½× makes it a 2 s second,
		// ⏸ stops it entirely; the JS interval doesn't care
		gameView.every(1000, function () {
			gameSeconds++;
			gameClock.text = 'GAME ' + gameSeconds + 's';
			gameClock.flash('#fff', 120);
		});
		realTimer = setInterval(function () { // the wall-clock counterexample
			realSeconds++;
			realClock.text = 'REAL ' + realSeconds + 's';
		}, 1000);

		// --- timeScale buttons -------------------------------------------

		var SPEEDS = [
			{ title: '1×', value: 1 },
			{ title: '½×', value: 0.5 },
			{ title: '⅒×', value: 0.1 },
			{ title: '⏸', value: 0 }
		];
		var buttons = SPEEDS.map(function (speed, index) {
			var button = Ti.UI.createLabel({
				text: speed.title,
				textAlign: 'center',
				color: '#fff',
				font: { fontSize: 24, fontWeight: 'bold' },
				backgroundColor: '#59000000',
				borderRadius: 35,
				width: '70dp',
				height: '70dp',
				bottom: '24dp',
				left: (12 + index * 25) + '%'
			});
			button.addEventListener('click', function () {
				gameView.timeScale = speed.value; // the whole scene obeys
				buttons.forEach(function (other) {
					other.backgroundColor = '#59000000';
				});
				button.backgroundColor = '#8c2a6df4';
			});
			win.add(button);
			return button;
		});
		buttons[0].backgroundColor = '#8c2a6df4'; // 1× active at start

		win.add(Ti.UI.createLabel({
			text: 'timeScale slows physics, animation and particles together',
			color: '#aab',
			font: { fontSize: 15 },
			textAlign: 'center',
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 1 },
			top: 90, // below the Back button
			left: 20,
			right: 20
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

	win.open();
};
