// ti.game raycast demo — one-shot segment queries against the scene.
//
// - line of sight: a guard watches the dog across the screen; a timer
//   raycasts guard → dog against the draggable crate every 150 ms. Drag
//   the crate into the beam: the ray reports the impact point, the beam
//   shortens to hit.distance and turns red
// - ledge probe: a walker patrols a floating platform on native
//   velocity; a timer probes for ground a step ahead and below — when
//   the probe misses (no floor ahead), the walker turns around instead
//   of walking off the edge
// - hitscan: tap anywhere in the upper area — the turret raycasts along
//   the tap direction (extended to full range), flashes whatever it
//   hits first and reports group + distance; a clear ray says so
//
// Raycasts are discrete queries (timers, taps) — not per-frame JS
// polling; the beams are ordinary thin sprites stretched to the
// reported distance.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({ backgroundColor: '#101223' });

	var playerSheet = Game.createSpriteSheet({ image: 'assets/adventurer.png', frameWidth: 32, frameHeight: 48, smoothing: false });
	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var walkerSheet = Game.createSpriteSheet({ image: 'assets/walker.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var platformSheet = Game.createSpriteSheet({ image: 'assets/platform.png', frameWidth: 48, frameHeight: 16, smoothing: false });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var shipSheet = Game.createSpriteSheet({ image: 'assets/ship.png', frameWidth: 64, frameHeight: 64 });

	var timers = [];
	win.addEventListener('close', function () {
		timers.forEach(clearInterval);
		timers = [];
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		// A thin spark stretched from (x, y) along the ray — beams are
		// plain sprites; only the raycast result drives them
		function makeBeam(color) {
			var beam = Game.createSprite({
				sheet: sparkSheet,
				height: 4,
				anchorX: 0,
				anchorY: 0.5,
				tintColor: color,
				blend: 'add',
				touchEnabled: false,
				zIndex: 5
			});
			gameView.add(beam);
			return beam;
		}

		function aimBeam(beam, x0, y0, x1, y1, length) {
			beam.x = x0;
			beam.y = y0;
			beam.width = Math.max(1, length);
			beam.rotation = Math.atan2(y1 - y0, x1 - x0) * 180 / Math.PI;
		}

		// --- Line of sight: guard → dog, blocked by the crate -------------

		var guard = Game.createSprite({
			sheet: playerSheet,
			x: W * 0.10, y: H * 0.22,
			width: Math.round(W * 0.11), height: Math.round(W * 0.165),
			zIndex: 10
		});
		var dog = Game.createSprite({
			sheet: dogSheet,
			x: W * 0.90, y: H * 0.24,
			width: Math.round(W * 0.10), height: Math.round(W * 0.10),
			flipX: true, // face the guard
			zIndex: 10
		});
		var crate = Game.createSprite({
			sheet: wallSheet,
			x: W * 0.5, y: H * 0.38,
			width: Math.round(W * 0.16), height: Math.round(W * 0.16),
			draggable: true,
			collisionGroup: 'blocker',
			zIndex: 10
		});
		gameView.add([guard, dog, crate]);

		var sight = makeBeam('#4f4');
		timers.push(setInterval(function () {
			var x0 = guard.x + W * 0.04;
			var y0 = guard.y - W * 0.02; // eye height
			var hit = gameView.raycast(x0, y0, dog.x, dog.y, ['blocker']);
			if (hit) {
				aimBeam(sight, x0, y0, hit.x, hit.y, hit.distance);
				sight.tintColor = '#f44'; // view blocked at the impact point
			} else {
				var dx = dog.x - x0;
				var dy = dog.y - y0;
				aimBeam(sight, x0, y0, dog.x, dog.y, Math.sqrt(dx * dx + dy * dy));
				sight.tintColor = '#4f4';
			}
		}, 150));

		// --- Ledge probe: the walker turns before the platform edge -------

		var platform = Game.createSprite({
			sheet: platformSheet,
			x: W * 0.5, y: H * 0.55,
			width: Math.round(W * 0.7), height: Math.round(W * 0.06),
			collisionGroup: 'ground',
			zIndex: 8
		});
		var walker = Game.createSprite({
			sheet: walkerSheet,
			x: W * 0.5, y: H * 0.55 - W * 0.075,
			width: Math.round(W * 0.09), height: Math.round(W * 0.09),
			velocityX: W * 0.15,
			animations: { walk: { frames: [0, 1], fps: 7, loop: true } },
			zIndex: 10
		});
		walker.play('walk');
		gameView.add([platform, walker]);

		timers.push(setInterval(function () {
			// probe a step ahead of the feet, straight down: no ground
			// there means a ledge is coming — turn around
			var dir = (walker.velocityX >= 0) ? 1 : -1;
			var probeX = walker.x + dir * W * 0.07;
			var floor = gameView.raycast(probeX, walker.y, probeX, walker.y + W * 0.12, ['ground']);
			if (!floor) {
				walker.velocityX = -walker.velocityX;
				walker.flipX = walker.velocityX < 0;
			}
		}, 150));

		// --- Hitscan: tap to fire the turret ------------------------------

		var turret = Game.createSprite({
			sheet: shipSheet,
			x: W * 0.5, y: H * 0.85,
			width: Math.round(W * 0.13), height: Math.round(W * 0.13),
			zIndex: 10
		});
		gameView.add(turret);
		// give the fixed scenery a group so the shot can hit it too
		platform.collisionGroup = 'ground';
		dog.collisionGroup = 'critter';

		var shot = makeBeam('#ffd54a');
		shot.opacity = 0;
		var status = Ti.UI.createLabel({
			text: 'tap to fire the turret',
			color: '#aab',
			font: { fontSize: 15 },
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 1 },
			bottom: '2%'
		});
		win.add(status);

		gameView.addEventListener('tap', function (e) {
			if (e.y > H * 0.75) {
				return; // taps around the turret itself
			}
			// extend the tap direction to full range — hitscan, not walk-to
			var dx = e.x - turret.x;
			var dy = e.y - turret.y;
			var len = Math.sqrt(dx * dx + dy * dy);
			if (len < 1) {
				return;
			}
			var range = H * 1.2;
			var tx = turret.x + dx / len * range;
			var ty = turret.y + dy / len * range;
			turret.rotation = Math.atan2(dy, dx) * 180 / Math.PI + 90; // art faces up
			var hit = gameView.raycast(turret.x, turret.y, tx, ty, ['blocker', 'ground', 'critter']);
			var beamLength = hit ? hit.distance : range;
			aimBeam(shot, turret.x, turret.y, tx, ty, beamLength);
			shot.opacity = 1;
			shot.animate({ opacity: 0, duration: 250 });
			if (hit) {
				hit.sprite.flash('#ffd54a', 300);
				status.text = 'hit ' + hit.group + ' at ' + Math.round(hit.distance) + ' px';
			} else {
				status.text = 'clear — no hit within range';
			}
		});

		// --- Captions -----------------------------------------------------

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
		label('drag the crate into the line of sight', 8);
		label('the walker probes for ground ahead', 46);
		label('tap above to fire — hitscan raycast', 66);
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
