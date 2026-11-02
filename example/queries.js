// ti.game scene queries demo — spritesInRect, spritesNear and spriteAt.
//
// Two dozen critters drift across the meadow on native velocity and wrap
// at the edges. Nothing in JS tracks where they are: every question is
// one native query that comes back with sprite, group, x and y in the
// result rows, so the demo never reads a position per sprite over the
// bridge.
//
// - SCANNER: drag the translucent frame around. A 300 ms timer asks
//   spritesInRect for the critters under it; they turn green while they
//   are inside and the HUD counts them
// - tap a critter: spriteAt picks the topmost one under the finger and
//   flashes it white — hitbox shapes count, not drawn rects
// - tap empty grass: a blast. spritesNear returns everything within the
//   ring, nearest first; each critter is shoved away from the tap, the
//   nearest flashes red, and the HUD reports the count and the nearest
//   distance straight from the rows
//
// Like raycast, these are discrete queries (timers, taps), not per-frame
// JS polling. The scanner itself has no collisionGroup, so no query ever
// returns it.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		title: 'Scene queries',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({ backgroundColor: '#1c2418' });

	var groundSheet = Game.createSpriteSheet({ image: 'assets/ground.png', frameWidth: 64, frameHeight: 64, repeat: true });
	var walkerSheet = Game.createSpriteSheet({ image: 'assets/walker.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });

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

		var UNIT = Math.max(1, Math.min(W / 380, H / 680));
		var ART = Math.min(W, H);
		var CRITTER = Math.round(ART * 0.07);
		var BLAST_RADIUS = ART * 0.22;
		var SCAN_W = Math.round(W * 0.38);
		var SCAN_H = Math.round(H * 0.22);

		gameView.add(Game.createSprite({
			sheet: groundSheet,
			x: W / 2, y: H / 2,
			width: W, height: H,
			tileRepeat: true,
			touchEnabled: false,
			zIndex: 0
		}));

		// --- Critters: tagged circles drifting on native velocity ---------

		var critters = [];
		for (var i = 0; i < 24; i++) {
			var angle = Math.random() * Math.PI * 2;
			var speed = ART * (0.04 + Math.random() * 0.08);
			var critter = Game.createSprite({
				sheet: walkerSheet,
				x: W * (0.05 + Math.random() * 0.9),
				y: H * (0.18 + Math.random() * 0.7),
				width: CRITTER, height: CRITTER,
				velocityX: Math.cos(angle) * speed,
				velocityY: Math.sin(angle) * speed,
				flipX: Math.cos(angle) < 0,
				wrapAround: true,
				hitboxShape: 'circle',
				collisionGroup: 'critter',
				touchEnabled: false,          // queries find them, touches never need to
				animations: { walk: { frames: [0, 1], fps: 7, loop: true } },
				zIndex: 10
			});
			critter.play('walk');
			gameView.add(critter);
			critters.push(critter);
		}

		// --- HUD -----------------------------------------------------------

		gameView.add(Game.createText({
			text: 'DRAG THE SCANNER  /  TAP A CRITTER  /  TAP GRASS TO BLAST',
			align: 'center',
			screenFixed: true,
			x: W / 2, y: H * 0.06,
			scale: UNIT * 0.7,
			tintColor: '#8ab4ff',
			zIndex: 30
		}));
		var status = Game.createText({
			text: 'scanner: 0 critters',
			align: 'center',
			screenFixed: true,
			x: W / 2, y: H * 0.11,
			scale: UNIT * 0.8,
			tintColor: '#ffd54a',
			zIndex: 30
		});
		gameView.add(status);

		// --- Scanner: spritesInRect under a draggable frame ---------------

		var scanner = Game.createSprite({
			sheet: wallSheet,
			x: W * 0.5, y: H * 0.5,
			width: SCAN_W, height: SCAN_H,
			tintColor: '#69f0ae',
			opacity: 0.3,
			draggable: true,
			zIndex: 20
		});
		gameView.add(scanner);

		var scanned = [];
		timers.push(setInterval(function () {
			var rows = gameView.spritesInRect(
				scanner.x - SCAN_W / 2, scanner.y - SCAN_H / 2, SCAN_W, SCAN_H, ['critter']);
			scanned.forEach(function (sprite) {
				sprite.tintColor = '#ffffff';
			});
			scanned = rows.map(function (row) {
				row.sprite.tintColor = '#69f0ae';
				return row.sprite;
			});
			status.text = 'scanner: ' + rows.length + ' critter' + (rows.length === 1 ? '' : 's');
		}, 300));

		// --- Taps: spriteAt picks, spritesNear blasts --------------------

		var ring = Game.createSprite({
			sheet: sparkSheet,
			width: BLAST_RADIUS * 2, height: BLAST_RADIUS * 2,
			tintColor: '#ff8a80',
			blend: 'add',
			opacity: 0,
			touchEnabled: false,
			zIndex: 15
		});
		gameView.add(ring);

		gameView.addEventListener('tap', function (e) {
			if (Math.abs(e.x - scanner.x) < SCAN_W / 2 && Math.abs(e.y - scanner.y) < SCAN_H / 2) {
				return; // the scanner owns touches on itself
			}
			var picked = gameView.spriteAt(e.x, e.y, ['critter']);
			if (picked) {
				picked.sprite.flash('#ffffff', 300);
				status.text = 'picked a ' + picked.group + ' at ' + Math.round(picked.x) + ', ' + Math.round(picked.y);
				return;
			}
			var rows = gameView.spritesNear(e.x, e.y, BLAST_RADIUS, ['critter']);
			ring.x = e.x;
			ring.y = e.y;
			ring.clearTweens();
			ring.scale = 0.2;
			ring.opacity = 0.8;
			ring.animate({ scale: 1, opacity: 0, duration: 350, easing: Game.EASE_OUT });
			rows.forEach(function (row, index) {
				// rows carry x/y: no bridge read per critter to aim the shove
				var dx = row.x - e.x;
				var dy = row.y - e.y;
				var len = Math.sqrt(dx * dx + dy * dy) || 1;
				var push = ART * 0.6 * (1 - row.distance / BLAST_RADIUS);
				row.sprite.velocityX += (dx / len) * push;
				row.sprite.velocityY += (dy / len) * push;
				if (index === 0) {
					row.sprite.flash('#ff5252', 300);
				}
			});
			status.text = rows.length === 0
				? 'blast: nothing in range'
				: 'blast: ' + rows.length + ' in range, nearest ' + Math.round(rows[0].distance) + ' px';
		});
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win);

	win.open();
};
