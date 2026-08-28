// ti.game basic demo — sprite sheet animation, drag & drop, gestures, tweens.
// Uses hero.png (4 columns x 2 rows of 64x64 frames) from assets/:
// frames 0-3 walk, 4-6 jump, 7 ghost.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});

	var gameView = Game.createGameView({
		backgroundColor: '#202030',
		maxFps: 60 // cap 120 Hz (ProMotion) displays; 0 = display refresh rate
	});

	var sheet = Game.createSpriteSheet({
		image: 'assets/hero.png',
		frameWidth: 64,
		frameHeight: 64
		// or TexturePacker: image + atlas: 'assets/hero.json' instead of the grid
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var HERO = Math.round(W * 0.35);
		var GHOST = Math.round(W * 0.28);

		var hero = Game.createSprite({
			sheet: sheet,
			x: W / 2,
			y: H / 2,
			width: HERO,
			height: HERO,
			draggable: true,
			pinchable: true,
			rotatable: true,
			animations: {
				walk: { frames: [0, 1, 2, 3], fps: 12, loop: true },
				jump: { frames: [4, 5, 6], fps: 10, loop: false }
			}
		});

		hero.play('walk');

		hero.addEventListener('tap', function () {
			hero.play('jump');
		});

		hero.addEventListener('animationcomplete', function (e) {
			// non-looping animation finished — go back to walking
			if (e.animation === 'jump') {
				hero.play('walk');
			}
		});

		hero.addEventListener('dragend', function (e) {
			// already moved natively; e.x / e.y is the final position
			Ti.API.info('hero dropped at ' + e.x + ', ' + e.y);
		});

		// A second, non-interactive sprite driven by native tweens
		var ghost = Game.createSprite({
			sheet: sheet,
			x: W * 0.25,
			y: H * 0.28,
			width: GHOST,
			height: GHOST,
			frame: 7,
			opacity: 0.6,
			zIndex: -1
		});

		ghost.addEventListener('complete', function () {
			// ping-pong between the two sides forever
			ghost.animate({
				x: (ghost.x < W / 2) ? W * 0.75 : W * 0.25,
				rotation: ghost.rotation + 360,
				duration: 1500,
				easing: Game.EASE_IN_OUT
			});
		});

		// Arrays cross the bridge once and enter the native scene together.
		gameView.add([hero, ghost]);
		ghost.animate({ x: W * 0.75, rotation: 360, duration: 1500, easing: Game.EASE_IN_OUT });
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
