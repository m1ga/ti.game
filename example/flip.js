// ti.game flip demo — flipX/flipY driven by movement direction.
//
// flipX/flipY mirror only the drawn frame: position, anchor, physics and
// hit testing stay untouched (unlike a negative scaleX). Three exhibits:
//
// - a bird patrols between two points with ping-pong tweens; every
//   'complete' reverses the tween and sets flipX to the travel direction
// - a dog runs on native velocityX; a slow JS watchdog turns it around
//   at the screen edges and sets flipX = running left
// - the player walks the floor the same way — and tapping anywhere
//   inverts gravity (VVVVVV style): they fall to the ceiling and walk
//   upside down with flipY until the next tap
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#2b3a67'
	});

	var platformSheet = Game.createSpriteSheet({ image: 'assets/platform.png', frameWidth: 256, frameHeight: 32 });
	var birdSheet = Game.createSpriteSheet({ image: 'assets/bird.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var playerSheet = Game.createSpriteSheet({ image: 'assets/adventurer.png', frameWidth: 32, frameHeight: 48, smoothing: false });

	var watchdog = null;
	win.addEventListener('close', function () {
		if (watchdog !== null) {
			clearInterval(watchdog);
			watchdog = null;
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

		var MARGIN = W * 0.12;         // turn-around distance from the edges
		var FLOOR_H = Math.round(H * 0.05);
		var PLAYER_W = Math.round(W * 0.13);
		var PLAYER_H = Math.round(PLAYER_W * 1.5);
		var DOG = Math.round(W * 0.12);
		var BIRD = Math.round(W * 0.12);

		// Floor and ceiling the player can stand on (and under)
		function makeSolid(y) {
			var solid = Game.createSprite({
				sheet: platformSheet,
				x: W / 2,
				y: y,
				width: W,
				height: FLOOR_H,
				zIndex: 1,
				collisionGroup: 'solid'
			});
			gameView.add(solid);
			return solid;
		}
		makeSolid(H - FLOOR_H / 2);   // floor
		makeSolid(FLOOR_H / 2);       // ceiling

		// --- Bird: tween patrol, flipX from the travel direction ----------

		var bird = Game.createSprite({
			sheet: birdSheet,
			x: MARGIN,
			y: H * 0.3,
			width: BIRD,
			height: BIRD,
			zIndex: 5,
			animations: {
				idle: { frames: [0, 0, 0, 1, 0, 0, 0, 2], fps: 3, loop: true }
			}
		});
		bird.play('idle');
		gameView.add(bird);

		function patrol() {
			var goingRight = bird.x < W / 2;
			bird.flipX = !goingRight;   // art faces right; mirror when flying left
			bird.animate({
				x: goingRight ? W - MARGIN : MARGIN,
				duration: 3000,
				easing: Game.EASE_IN_OUT
			});
		}
		bird.addEventListener('complete', patrol);
		patrol();

		// --- Dog: native velocity, flipX from the velocity sign -----------

		var dog = Game.createSprite({
			sheet: dogSheet,
			x: W / 2,
			y: H - FLOOR_H - DOG / 2,
			width: DOG,
			height: DOG,
			zIndex: 5,
			velocityX: W * 0.25,
			animations: {
				walk: { frames: [0, 1], fps: 7, loop: true }
			}
		});
		dog.play('walk');
		gameView.add(dog);

		// --- Player: same edge patrol, plus tap-to-invert gravity ---------

		var player = Game.createSprite({
			sheet: playerSheet,
			x: W * 0.25,
			y: H - FLOOR_H - PLAYER_H / 2,
			width: PLAYER_W,
			height: PLAYER_H,
			zIndex: 6,
			velocityX: W * 0.15,
			gravity: H * 2,
			solidWith: ['solid'],
			animations: {
				walk: { frames: [1, 2], fps: 6, loop: true }
			}
		});
		player.play('walk');
		gameView.add(player);

		gameView.addEventListener('tap', function () {
			player.gravity = -player.gravity;
			player.flipY = player.gravity < 0;   // upside down on the ceiling
		});

		// Movement runs natively; JS only glances at positions a few times a
		// second to turn the runners around and mirror them — never per frame.
		watchdog = setInterval(function () {
			[dog, player].forEach(function (runner) {
				if (runner.velocityX > 0 && runner.x > W - MARGIN) {
					runner.velocityX = -runner.velocityX;
				} else if (runner.velocityX < 0 && runner.x < MARGIN) {
					runner.velocityX = -runner.velocityX;
				}
				runner.flipX = runner.velocityX < 0;
			});
		}, 150);

		win.add(Ti.UI.createLabel({
			text: 'Tap to flip gravity',
			color: '#fff',
			font: { fontSize: 22, fontWeight: 'bold' },
			shadowColor: '#20222c',
			shadowOffset: { x: 0, y: 2 },
			top: 90 // below the Back button
		}));
	}

	win.add(gameView);
	// Back — return to the launcher
	var backButton = Ti.UI.createButton({
		title: 'Back',
		top: Ti.Platform.osname === 'android' ? 10 : 40,
		left: 10,
		color: '#fff',
		backgroundColor: '#000',
		borderColor: '#fff',
		borderWidth: 1,
		font: { fontSize: 12 }
	});
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);

	win.open();
};
