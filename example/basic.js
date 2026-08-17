// ti.game basic demo — sprite sheet animation, drag & drop, gestures, tweens.
// Uses hero.jpg (4 columns x 2 rows of 64x64 frames) from assets/:
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
		image: 'assets/hero.jpg',
		frameWidth: 64,
		frameHeight: 64
		// or TexturePacker: image: 'assets/hero.png', atlas: 'assets/hero.json'
	});

	var hero = Game.createSprite({
		sheet: sheet,
		x: 200,
		y: 300,
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
		x: 100,
		y: 120,
		frame: 7,
		opacity: 0.6,
		zIndex: -1
	});

	ghost.addEventListener('complete', function () {
		// ping-pong between two corners forever
		ghost.animate({
			x: (ghost.x < 200) ? 300 : 100,
			rotation: ghost.rotation + 360,
			duration: 1500,
			easing: Game.EASE_IN_OUT
		});
	});

	// Arrays cross the bridge once and enter the native scene together.
	gameView.add([hero, ghost]);
	ghost.animate({ x: 300, rotation: 360, duration: 1500, easing: Game.EASE_IN_OUT });

	win.add(gameView);
	// Back — return to the launcher
	var backButton = Ti.UI.createButton({
		title: 'Back',
		top: 40,
		left: 20
	});
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);

	win.open();
};
