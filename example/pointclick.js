// ti.game point-and-click demo — a tiny adventure-game scene.
//
// - a pixel meadow with an oak on the left; a bird with a 3-frame idle
//   animation (perch, blink, tail flick) sits in the canopy
// - tap anywhere on the meadow and the player walks there: findPath
//   routes around the oak's trunk (an invisible obstacle box) and
//   followPath walks the waypoints natively — tap behind the tree and
//   the player circles it instead of clipping through
// - tap the bird and a verb coin appears: a hand and a talk icon.
//   Hand: "You can't take the bird" — Talk: "Tschirp tschirp"
// - the player and the tree share a zIndex with `ySort`, so walking
//   above the trunk base puts the player behind the tree
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		title: 'Point & click',
		theme: 'Theme.Titanium.DayNight'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#74bae8'
		// debug: true                              // collision shapes for every sprite
		// debug: { hitbox: true, hud: 'topRight' }  // ...plus the performance HUD
	});

	var bgSheet = Game.createSpriteSheet({ image: 'assets/meadow.png', frameWidth: 270, frameHeight: 480, smoothing: false });
	var treeSheet = Game.createSpriteSheet({ image: 'assets/oak.png', frameWidth: 128, frameHeight: 160, smoothing: false });
	var birdSheet = Game.createSpriteSheet({ image: 'assets/bird.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var playerSheet = Game.createSpriteSheet({ image: 'assets/adventurer.png', frameWidth: 32, frameHeight: 48, smoothing: false });
	var iconSheet = Game.createSpriteSheet({ image: 'assets/icons.png', frameWidth: 56, frameHeight: 56, smoothing: false });

	var sayTimer = null;
	win.addEventListener('close', function () {
		if (sayTimer !== null) {
			clearTimeout(sayTimer);
			sayTimer = null;
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

		var WALK_SPEED = W * 0.35;         // px/s
		var PLAYER_W = Math.round(W * 0.15);
		var PLAYER_H = Math.round(PLAYER_W * 1.5);
		var TREE_W = Math.round(W * 0.45);
		var TREE_H = Math.round(TREE_W * 1.25);
		var BIRD = Math.round(W * 0.10);
		var ICON = Math.round(W * 0.17);

		// The meadow starts below the painted horizon; the player can only
		// walk there (classic adventure-game walkable floor)
		var WALK_TOP = H * 0.5;

		gameView.add(Game.createSprite({
			sheet: bgSheet, x: W / 2, y: H / 2, width: W, height: H, zIndex: 1
		}));

		var tree = Game.createSprite({
			sheet: treeSheet,
			x: W * 0.22,
			y: H * 0.62 - TREE_H / 2,   // trunk base at 0.62*H
			width: TREE_W,
			height: TREE_H,
			zIndex: 5,
			ySort: true
		});
		gameView.add(tree);

		// The trunk as a pathfinding obstacle: an invisible box (opacity 0
		// keeps it out of rendering and touch, but findPath and raycast
		// still see it) around where the player's CENTER may not go — the
		// canopy stays free, so walking behind the tree still works.
		gameView.add(Game.createSprite({
			sheet: treeSheet,
			opacity: 0,
			touchEnabled: false,
			x: tree.x,
			y: H * 0.62 - PLAYER_H / 2,
			width: TREE_W * 0.35,
			height: PLAYER_H * 0.8,
			collisionGroup: 'obstacle'
		}));

		var bird = Game.createSprite({
			sheet: birdSheet,
			x: W * 0.32,
			y: H * 0.40,
			width: BIRD,
			height: BIRD,
			zIndex: 6,
			animations: {
				// mostly perched, an occasional blink and tail flick
				idle: { frames: [0, 0, 0, 1, 0, 0, 0, 2], fps: 3, loop: true }
			}
		});
		bird.play('idle');
		gameView.add(bird);

		var player = Game.createSprite({
			sheet: playerSheet,
			x: W * 0.7,
			y: H * 0.75,
			width: PLAYER_W,
			height: PLAYER_H,
			zIndex: 5,
			ySort: true,   // shares the tree's zIndex — depth by bottom edge
			scaleX: -1,    // face the tree
			animations: {
				idle: { frames: [0], fps: 1, loop: true },
				walk: { frames: [1, 2], fps: 6, loop: true }
			}
		});
		player.play('idle');
		gameView.add(player);

		// --- Verb coin: hand + talk icons next to the bird ---------------

		function makeIcon(frame, x) {
			var icon = Game.createSprite({
				sheet: iconSheet,
				frame: frame,
				x: x,
				y: bird.y,
				width: ICON,
				height: ICON,
				zIndex: 20,
				visible: false,
				idleAnimation: true,   // gentle wobble while the coin is open
				idleRotation: 4,
				idleMovement: 2
			});
			gameView.add(icon);
			return icon;
		}

		var handIcon = makeIcon(0, W * 0.48);
		var talkIcon = makeIcon(1, W * 0.64);

		function showIcons() {
			handIcon.visible = true;
			talkIcon.visible = true;
		}

		function hideIcons() {
			handIcon.visible = false;
			talkIcon.visible = false;
		}

		// --- Speech/status line on top -----------------------------------

		var label = Ti.UI.createLabel({
			text: '',
			color: '#fff',
			font: { fontSize: 22, fontWeight: 'bold' },
			shadowColor: '#20222c',
			shadowOffset: { x: 0, y: 2 },
			top: 90, // below the Back button
			visible: false
		});

		function say(text) {
			label.text = text;
			label.visible = true;
			if (sayTimer !== null) {
				clearTimeout(sayTimer);
			}
			sayTimer = setTimeout(function () {
				sayTimer = null;
				label.visible = false;
			}, 2500);
		}

		// --- Interactions ------------------------------------------------

		bird.addEventListener('tap', showIcons);

		handIcon.addEventListener('tap', function () {
			hideIcons();
			say("You can't take the bird");
		});

		talkIcon.addEventListener('tap', function () {
			hideIcons();
			say('Tschirp tschirp');
		});

		// The walkable floor in sprite-center coordinates (tap points are
		// feet positions; the sprite walks by its center)
		var WALK_BOUNDS = {
			minX: W * 0.06,
			minY: WALK_TOP - PLAYER_H / 2,
			maxX: W * 0.94,
			maxY: H * 0.95 - PLAYER_H / 2
		};

		function walkTo(x, y) {
			var targetX = Math.min(Math.max(x, WALK_BOUNDS.minX), WALK_BOUNDS.maxX);
			var targetY = Math.min(Math.max(y - PLAYER_H / 2, WALK_BOUNDS.minY), WALK_BOUNDS.maxY);
			// A* around the trunk box; a tap on the tree snaps to its edge
			var path = gameView.findPath(
				{ x: player.x, y: player.y },
				{ x: targetX, y: targetY },
				{
					cellSize: Math.round(W * 0.04),
					groups: ['obstacle'],
					clearance: PLAYER_W * 0.35,  // keep half a body off the trunk
					bounds: WALK_BOUNDS
				});
			if (!path || path.length < 2) {
				return;
			}
			player.scaleX = path[1].x < player.x ? -1 : 1;
			player.play('walk');
			player.followPath(path, { speed: WALK_SPEED });
		}

		player.addEventListener('pathcomplete', function () {
			player.play('idle');
		});

		// The view fires `tap` for every touch, including ones the bird and
		// the icons already handled — hit-test those in JS and only treat
		// the rest as a walk command.
		function over(sprite, x, y) {
			return sprite.visible !== false
				&& Math.abs(x - sprite.x) <= sprite.width / 2 + PLAYER_W * 0.2
				&& Math.abs(y - sprite.y) <= sprite.height / 2 + PLAYER_W * 0.2;
		}

		gameView.addEventListener('tap', function (e) {
			if (over(bird, e.x, e.y) || over(handIcon, e.x, e.y) || over(talkIcon, e.x, e.y)) {
				return;
			}
			hideIcons();
			walkTo(e.x, e.y);
		});

		win.add(label);
		say('Tap the meadow to walk around');
	}

	win.add(gameView);
	// Back — action bar Up on Android, overlay pill on iOS (see backnav.js)
	require('/backnav')(win);

	win.open();
};
