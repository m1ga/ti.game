// ti.game path & chain demo — native path following and animation chaining.
//
// - a ship flies a looping diamond circuit with followPath: corner
//   smoothing rounds the diamond into an oval, rotate: true keeps the
//   nose pointing along the path — zero JS in the loop
// - a guard patrols a sharp-cornered rectangle (no smoothing, no
//   rotate) while a looping walk animation plays — path movement and
//   sheet animation run natively side by side
// - tap the guard: play('hop', { then: 'walk' }) chains natively — the
//   one-shot hop finishes and the walk loop resumes without any
//   animationcomplete juggling in JS (tap the bird for a two-step
//   chain: flap, flap again, then settle into idle)
// - tap open ground: the dog runs a one-shot smoothed zig-zag path to
//   the tap point and 'pathcomplete' fires at the end (it stops the
//   walk animation and flashes)
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		title: 'Path & chain',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({ backgroundColor: '#101223' });

	var shipSheet = Game.createSpriteSheet({ image: 'assets/ship.png', frameWidth: 64, frameHeight: 64 });
	var playerSheet = Game.createSpriteSheet({ image: 'assets/adventurer.png', frameWidth: 32, frameHeight: 48, smoothing: false });
	var birdSheet = Game.createSpriteSheet({ image: 'assets/bird.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		// --- Ship: looping smoothed circuit, nose along the path ----------

		var ship = Game.createSprite({
			sheet: shipSheet,
			width: Math.round(W * 0.12),
			height: Math.round(W * 0.12),
			zIndex: 10
		});
		gameView.add(ship);
		ship.followPath([
			{ x: W * 0.50, y: H * 0.06 },
			{ x: W * 0.90, y: H * 0.20 },
			{ x: W * 0.50, y: H * 0.34 },
			{ x: W * 0.10, y: H * 0.20 }
		], {
			speed: W * 0.35,
			loop: true,
			rotate: true,       // heading 0 = up, like sprite rotation
			smoothing: W * 0.12 // rounds the diamond into an oval
		});

		// --- Guard: sharp rectangle patrol + chained hop on tap -----------

		var guard = Game.createSprite({
			sheet: playerSheet,
			width: Math.round(W * 0.12),
			height: Math.round(W * 0.18),
			zIndex: 10,
			animations: {
				walk: { frames: [1, 2], fps: 6, loop: true },
				// one-shot; chained back into walk via play(..., { then })
				hop: { frames: [0, 1, 0, 2, 0], fps: 12, loop: false }
			}
		});
		guard.play('walk');
		gameView.add(guard);
		guard.followPath([
			{ x: W * 0.22, y: H * 0.46 },
			{ x: W * 0.78, y: H * 0.46 },
			{ x: W * 0.78, y: H * 0.60 },
			{ x: W * 0.22, y: H * 0.60 }
		], { speed: W * 0.16, loop: true });

		guard.addEventListener('tap', function () {
			// the whole sequence in one call — no animationcomplete handler
			guard.play('hop', { then: 'walk' });
		});

		// --- Bird: two-step chain on tap ----------------------------------

		var bird = Game.createSprite({
			sheet: birdSheet,
			x: W * 0.85,
			y: H * 0.72,
			width: Math.round(W * 0.14),
			height: Math.round(W * 0.14),
			zIndex: 10,
			animations: {
				idle: { frames: [0, 0, 0, 1, 0, 0, 0, 2], fps: 3, loop: true },
				flap: { frames: [0, 1, 2, 1], fps: 10, loop: false }
			}
		});
		bird.play('idle');
		gameView.add(bird);
		bird.addEventListener('tap', function () {
			// `then` takes an array too: flap twice, then settle into idle
			bird.play('flap', { then: ['flap', 'idle'] });
		});

		// --- Dog: one-shot zig-zag path to the tap, pathcomplete ----------

		var dog = Game.createSprite({
			sheet: dogSheet,
			x: W * 0.15,
			y: H * 0.85,
			width: Math.round(W * 0.10),
			height: Math.round(W * 0.10),
			zIndex: 10,
			animations: {
				walk: { frames: [0, 1], fps: 7, loop: true }
			}
		});
		gameView.add(dog);
		dog.addEventListener('pathcomplete', function () {
			dog.stop();
			dog.flash('#ffd54a', 300);
		});

		gameView.addEventListener('tap', function (e) {
			// taps on the actors are handled above; only open ground below
			// the patrol area (and off the bird) sends the dog
			if (e.y < H * 0.66
				|| (Math.abs(e.x - bird.x) < W * 0.08 && Math.abs(e.y - bird.y) < W * 0.08)) {
				return;
			}
			var midX = (dog.x + e.x) / 2;
			var midY = (dog.y + e.y) / 2;
			var side = (e.x > dog.x) ? 1 : -1;
			dog.flipX = side < 0; // art faces right; mirror when running left
			dog.play('walk');
			dog.followPath([
				{ x: dog.x, y: dog.y },
				{ x: midX, y: midY - H * 0.06 * side }, // zig
				{ x: e.x, y: e.y }
			], { speed: W * 0.45, smoothing: W * 0.08 });
		});

		// --- Row labels ---------------------------------------------------

		function label(text, topPercent) {
			win.add(Ti.UI.createLabel({
				text: text,
				color: '#aab',
				font: { fontSize: 15 },
				shadowColor: '#000',
				shadowOffset: { x: 0, y: 1 },
				top: topPercent + '%'
			}));
		}
		label('followPath: loop + rotate + smoothing', 12); // below the Back button
		label("tap the guard: play('hop', { then: 'walk' })", 39);
		label('tap the bird: chain flap → flap → idle', 64);
		label('tap the ground: one-shot path + pathcomplete', 92);
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win);

	win.open();
};
