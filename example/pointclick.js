// ti.game point-and-click demo — a tiny adventure-game scene.
//
// - a pixel meadow with an oak on the left; a bird with a 3-frame idle
//   animation (perch, blink, tail flick) sits in the canopy
// - tap anywhere on the meadow and the player walks there (a linear
//   tween sized by distance, walk animation while moving)
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
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#74bae8'
		// debug: true  // show collision shapes for every sprite
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

		function walkTo(x, y) {
			var targetX = Math.min(Math.max(x, W * 0.06), W * 0.94);
			var targetY = Math.min(Math.max(y, WALK_TOP), H * 0.95) - PLAYER_H / 2;
			var distance = Math.sqrt(
				Math.pow(targetX - player.x, 2) + Math.pow(targetY - player.y, 2));
			if (distance < 4) {
				return;
			}
			player.scaleX = targetX < player.x ? -1 : 1;
			player.clearTweens();
			player.play('walk');
			player.animate({
				x: targetX,
				y: targetY,
				duration: distance / WALK_SPEED * 1000,
				easing: Game.EASE_LINEAR
			});
		}

		player.addEventListener('complete', function () {
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
