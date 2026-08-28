// ti.game hitbox demo — why hitboxScaleX/Y exist, made visible.
//
// The gameView starts with debug: true, so every sprite draws its
// collision AABB (green), sprite/touch bounds (blue) and anchor (orange).
// Two identical adventurers walk against a center wall and stand on the
// same floor:
//
// - FULL FRAME (left): no hitbox tuning. The drawing is 20x44 inside its
//   32x48 frame, so the green box is mostly air — he stops a body's width
//   short of the wall and hovers above the floor on his frame padding
// - TUNED (right): hitboxScaleX: 0.62 / hitboxScaleY: 0.92 shrink the box
//   per axis to the drawing — he walks flush up to the wall and his feet
//   land on the floor
//
// Tap anywhere to toggle the right one's tuning on/off and watch the
// green box snap between frame and drawing.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#2b3a67',
		debug: true
	});

	var platformSheet = Game.createSpriteSheet({ image: 'assets/platform.png', frameWidth: 256, frameHeight: 32 });
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

		var MARGIN = W * 0.1;          // turn-around distance from the edges
		var FLOOR_H = Math.round(H * 0.05);
		var PLAYER_W = Math.round(W * 0.16);
		var PLAYER_H = Math.round(PLAYER_W * 1.5);
		var TEXT = Math.max(1, Math.round(W / 480));

		// Floor and a center wall, both solid
		gameView.add(Game.createSprite({
			sheet: platformSheet,
			x: W / 2,
			y: H - FLOOR_H / 2,
			width: W,
			height: FLOOR_H,
			zIndex: 1,
			collisionGroup: 'solid'
		}));
		var wall = Game.createSprite({
			sheet: platformSheet,
			x: W / 2,
			y: H - FLOOR_H - H * 0.175,
			width: Math.round(W * 0.06),
			height: Math.round(H * 0.35),
			zIndex: 1,
			collisionGroup: 'solid'
		});
		gameView.add(wall);

		// Two identical walkers; only the hitbox tuning differs
		function makeWalker(x, tuned) {
			var walker = Game.createSprite({
				sheet: playerSheet,
				x: x,
				y: H - FLOOR_H - PLAYER_H,
				width: PLAYER_W,
				height: PLAYER_H,
				zIndex: 6,
				velocityX: W * 0.12,
				gravity: H * 2,
				solidWith: ['solid'],
				animations: {
					walk: { frames: [1, 2], fps: 6, loop: true }
				}
			});
			if (tuned) {
				// the drawing is 20x44 in its 32x48 frame — match it per axis
				walker.hitboxScaleX = 0.62;
				walker.hitboxScaleY = 0.92;
			}
			walker.play('walk');
			gameView.add(walker);
			return walker;
		}
		var fullFrame = makeWalker(W * 0.25, false); // patrols the left half
		var tuned = makeWalker(W * 0.75, true);      // patrols the right half

		// Labels above each half
		gameView.add(Game.createText({
			text: 'FULL FRAME\nSTOPS EARLY, HOVERS',
			align: 'center',
			x: W * 0.25,
			y: H * 0.22,
			scale: TEXT,
			lineSpacing: 1.4,
			tintColor: '#e8a1a1'
		}));
		gameView.add(Game.createText({
			text: 'TUNED HITBOX\nFLUSH WALL, FEET DOWN',
			align: 'center',
			x: W * 0.75,
			y: H * 0.22,
			scale: TEXT,
			lineSpacing: 1.4,
			tintColor: '#9fe8a1'
		}));
		gameView.add(Game.createText({
			text: 'GREEN = HITBOX   BLUE = SPRITE BOUNDS',
			align: 'center',
			x: W / 2,
			y: H * 0.09,
			scale: TEXT,
			tintColor: '#8a9bb8'
		}));
		var toggleLabel = Game.createText({
			text: 'TAP TO REMOVE THE TUNING',
			align: 'center',
			x: W * 0.75,
			y: H * 0.3,
			scale: TEXT,
			tintColor: '#c9b458'
		});
		gameView.add(toggleLabel);

		// Toggle the right walker's tuning to compare live: the green box
		// snaps between the 32x48 frame and the 20x44 drawing, and the
		// solids push him up / let him settle accordingly.
		gameView.addEventListener('tap', function () {
			var on = tuned.hitboxScaleX === 1;
			tuned.hitboxScaleX = on ? 0.62 : 1;
			tuned.hitboxScaleY = on ? 0.92 : 1;
			toggleLabel.text = on ? 'TAP TO REMOVE THE TUNING' : 'TAP TO TUNE THE HITBOX';
		});

		// Patrol: reverse at the screen margins, and when the wall blocks
		// the walk (x stalls). Movement runs natively; JS only glances at
		// positions a few times a second — never per frame.
		var lastX = { full: null, tuned: null };
		watchdog = setInterval(function () {
			[[fullFrame, 'full'], [tuned, 'tuned']].forEach(function (entry) {
				var runner = entry[0];
				var key = entry[1];
				var blocked = lastX[key] !== null && Math.abs(runner.x - lastX[key]) < 1;
				var atEdge = (runner.velocityX > 0 && runner.x > W - MARGIN)
					|| (runner.velocityX < 0 && runner.x < MARGIN);
				if (blocked || atEdge) {
					runner.velocityX = -runner.velocityX;
				}
				runner.flipX = runner.velocityX < 0;
				lastX[key] = runner.x;
			});
		}, 250);
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
