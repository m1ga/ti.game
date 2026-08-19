// ti.game camera demo — follow, dead-zones, bounds, zoom and shake.
//
// - a world twice the screen size in both directions: one ground sprite
//   tiling a 64px texture via tileRepeat, oak trees as landmarks
//   (ySort-depth with the player)
// - tap anywhere to walk there; the camera follows with a dead-zone in
//   BOTH axes (leftMargin/rightMargin + topMargin/bottomMargin) and
//   `smoothing`, clamped to the world rect via cameraBounds
// - − / + buttons zoom `cameraScale` around the view center — taps keep
//   working while zoomed because touch mapping goes through the camera
// - 💥 triggers a native camera shake (projection-only, so follow,
//   bounds and touches are unaffected)
// - 🎛 cycles fullscreen camera effects (cameraEffect): a green
//   night-vision tint, then a glitch filter — the whole scene renders
//   into an offscreen texture and back through the effect shader
// - parallax via scrollFactor: cloud shadows drift over the world at
//   1.35x camera speed (closer to the camera than the ground), and a
//   sun glow sits at scrollFactor 0 — pinned to the view like a HUD,
//   but still part of the zooming world (unlike screenFixed)
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#1c2418'
	});

	var groundSheet = Game.createSpriteSheet({ image: 'assets/ground.png', frameWidth: 64, frameHeight: 64, repeat: true });
	var treeSheet = Game.createSpriteSheet({ image: 'assets/oak.png', frameWidth: 128, frameHeight: 160, smoothing: false });
	var playerSheet = Game.createSpriteSheet({ image: 'assets/adventurer.png', frameWidth: 32, frameHeight: 48, smoothing: false });
	var cloudSheet = Game.createSpriteSheet({ image: 'assets/clouds.png', frameWidth: 512, frameHeight: 128 });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var WORLD_W = W * 2;
		var WORLD_H = H * 2;
		var PLAYER_W = Math.round(W * 0.13);
		var PLAYER_H = Math.round(PLAYER_W * 1.5);
		var TREE_W = Math.round(W * 0.3);
		var WALK_SPEED = W * 0.5;

		// One sprite covers the whole world — tileRepeat keeps the 64px
		// ground texture at native density instead of stretching it 2x2
		// screens wide
		gameView.add(Game.createSprite({
			sheet: groundSheet,
			x: WORLD_W / 2,
			y: WORLD_H / 2,
			width: WORLD_W,
			height: WORLD_H,
			tileRepeat: true,
			zIndex: 1
		}));

		// Landmark trees, depth-sorted against the player
		[
			[0.15, 0.2], [0.5, 0.12], [0.85, 0.25],
			[0.25, 0.55], [0.7, 0.5], [0.1, 0.8],
			[0.45, 0.85], [0.88, 0.75], [0.6, 0.3]
		].forEach(function (p) {
			gameView.add(Game.createSprite({
				sheet: treeSheet,
				x: WORLD_W * p[0],
				y: WORLD_H * p[1],
				width: TREE_W,
				height: TREE_W * 1.25,
				zIndex: 5,
				ySort: true
			}));
		});

		// --- Parallax: scrollFactor instead of hand-scrolled layers ------

		// Cloud shadows above the world: closer to the camera than the
		// ground, so they pan FASTER than 1:1 (scrollFactor > 1). The
		// slow velocityX drift is ordinary world movement on top.
		[
			[0.2, 0.25, 0.5], [0.7, 0.15, 0.4], [0.45, 0.6, 0.55],
			[0.9, 0.7, 0.45], [0.15, 0.85, 0.5]
		].forEach(function (c) {
			gameView.add(Game.createSprite({
				sheet: cloudSheet,
				x: WORLD_W * c[0],
				y: WORLD_H * c[1],
				width: W * c[2] * 2,
				height: W * c[2] * 0.5,
				opacity: 0.35,
				scrollFactor: 1.35,
				velocityX: W * 0.01,
				touchEnabled: false,
				zIndex: 20
			}));
		});

		// Sun glow at scrollFactor 0: pinned to the view like a HUD, but
		// still zooming around the view center (screenFixed wouldn't)
		gameView.add(Game.createSprite({
			sheet: sparkSheet,
			x: W * 0.85,
			y: H * 0.1,
			width: W * 0.2,
			height: W * 0.2,
			tintColor: '#ffd54a',
			blend: 'add',
			opacity: 0.8,
			scrollFactor: 0,
			touchEnabled: false,
			zIndex: 19
		}));

		var player = Game.createSprite({
			sheet: playerSheet,
			x: WORLD_W / 2,
			y: WORLD_H / 2,
			width: PLAYER_W,
			height: PLAYER_H,
			zIndex: 5,
			ySort: true,
			animations: {
				idle: { frames: [0], fps: 1, loop: true },
				walk: { frames: [1, 2], fps: 6, loop: true }
			}
		});
		player.play('idle');
		gameView.add(player);

		// Dead-zone follow on both axes, eased, clamped to the world rect.
		// maxY is the legacy platformer clamp — lift it for a free world.
		gameView.follow(player, {
			leftMargin: 0.4, rightMargin: 0.6,
			topMargin: 0.4, bottomMargin: 0.6,
			smoothing: 0.12,
			maxY: WORLD_H
		});
		gameView.cameraBounds = { minX: 0, minY: 0, maxX: WORLD_W, maxY: WORLD_H };

		// --- Tap to walk (world coordinates, zoom-aware) -----------------

		gameView.addEventListener('tap', function (e) {
			var targetX = Math.min(Math.max(e.x, PLAYER_W), WORLD_W - PLAYER_W);
			var targetY = Math.min(Math.max(e.y, PLAYER_H), WORLD_H - PLAYER_H / 2);
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
		});

		player.addEventListener('complete', function () {
			player.play('idle');
		});

		// --- Controls: zoom out / shake / zoom in ------------------------

		var zoomLabel = Ti.UI.createLabel({
			text: 'Tap to walk — zoom 1.0x',
			color: '#fff',
			font: { fontSize: 18, fontWeight: 'bold' },
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 2 },
			top: 40
		});

		function setZoom(factor) {
			var scale = Math.min(2.5, Math.max(0.5, gameView.cameraScale * factor));
			gameView.cameraScale = scale;
			zoomLabel.text = 'Tap to walk — zoom ' + scale.toFixed(1) + 'x';
		}

		function makeButton(title, position, onPress) {
			var button = Ti.UI.createLabel({
				text: title,
				textAlign: 'center',
				color: '#fff',
				font: { fontSize: 26, fontWeight: 'bold' },
				backgroundColor: '#59000000',
				borderRadius: 32,
				width: '64dp',
				height: '64dp',
				bottom: '24dp'
			});
			button.addEventListener('touchstart', function () {
				button.backgroundColor = '#8c000000';
				onPress();
			});
			['touchend', 'touchcancel'].forEach(function (event) {
				button.addEventListener(event, function () {
					button.backgroundColor = '#59000000';
				});
			});
			for (var key in position) {
				button[key] = position[key];
			}
			win.add(button);
		}

		makeButton('−', { left: '24dp' }, function () {
			setZoom(1 / 1.25);
		});
		makeButton('💥', { left: '104dp' }, function () {
			gameView.shake({ strength: W * 0.02, duration: 500 });
		});
		// 🎛 cycles the fullscreen camera effects: night-vision tint → glitch
		var EFFECTS = [
			{ effect: 'none' },
			{ effect: 'tint', tint: '#4f8', intensity: 0.7 },
			{ effect: 'glitch', intensity: 1.6 }
		];
		var effectIndex = 0;
		makeButton('🎛', { right: '104dp' }, function () {
			effectIndex = (effectIndex + 1) % EFFECTS.length;
			var fx = EFFECTS[effectIndex];
			gameView.cameraEffect = fx.effect;
			if (fx.tint) {
				gameView.cameraTint = fx.tint;
			}
			if (fx.intensity !== undefined) {
				gameView.cameraEffectIntensity = fx.intensity;
			}
		});
		makeButton('+', { right: '24dp' }, function () {
			setZoom(1.25);
		});

		win.add(zoomLabel);
	}

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
