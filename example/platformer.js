// ti.game platformer demo — ground, platforms, and a little slime guy.
//
// - hold ◀ / ▶ to run, press ⬆ to jump (only while standing on something)
// - jumping onto the platforms works: the engine's `solidWith` collision
//   resolution pushes the player out of solids and tracks `onGround`
// - the staircase platforms are one-way (oneWay: true): jump up through
//   them from below and land on top — no head bumps
// - a hazard-striped steel platform patrols sideways on a ping-pong
//   tween; stand on it and the engine carries you along natively — it's
//   a regular two-way solid, so it also blocks you from below
// - the buttons are separate Titanium views, so multitouch works:
//   hold right and press jump at the same time
//
// The level is built on the game view's `resize` event, so all sizes come
// from the actual GL surface — not the display size, which includes the
// system bars and would push bottom-anchored sprites off screen.
//
// Uses player.png (4 frames 64x64: idle, walk1, walk2, jump — flipped via
// scaleX for facing), platform.png, moverplatform.png and ground.png.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#8ed8f8'
		// debug: true  // show collision shapes for every sprite
	});

	var playerSheet = Game.createSpriteSheet({ image: 'assets/player.png', frameWidth: 64, frameHeight: 64 });
	var platformSheet = Game.createSpriteSheet({ image: 'assets/platform.png', frameWidth: 256, frameHeight: 32 });
	var moverSheet = Game.createSpriteSheet({ image: 'assets/moverplatform.png', frameWidth: 256, frameHeight: 32 });
	var trampolineSheet = Game.createSpriteSheet({ image: 'assets/trampoline.png', frameWidth: 128, frameHeight: 32 });
	var groundSheet = Game.createSpriteSheet({ image: 'assets/ground.png', frameWidth: 64, frameHeight: 64 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var PLAYER_SIZE = Math.round(Math.min(W, H) * 0.14);
		var RUN_SPEED = W * 0.4;           // px/s
		var GRAVITY = H * 2.2;             // px/s^2
		var JUMP = H * 0.95;               // takeoff speed, px/s (height ~ JUMP^2 / 2*GRAVITY ≈ 0.2*H)

		// Keep the floor above the on-screen controls (80dp buttons + margins)
		// Scene units per dp: measure the real surface scale instead of
		// trusting logicalDensityFactor — the iOS simulator renders at 1x
		// while the density factor still reports the device scale
		var density = Ti.Platform.osname === 'android'
			? Ti.Platform.displayCaps.logicalDensityFactor
			: H / Ti.Platform.displayCaps.platformHeight;
		var buttonZone = Math.round(130 * density);
		var groundTop = H - buttonZone;

		// --- Level: ground, platforms, edge walls ------------------------

		// Ground fills from groundTop to the bottom edge, so the area behind
		// the buttons is dirt instead of sky
		gameView.add(Game.createSprite({
			sheet: groundSheet,
			x: W / 2,
			y: (groundTop + H) / 2,
			width: W,
			height: H - groundTop,
			collisionGroup: 'solid'
		}));

		// Staircase of platforms, 0.14*H per step — comfortably below the
		// ~0.2*H jump height, alternating sides so you can hop all the way up
		var PLAT_H = Math.round(H * 0.035);
		var STEP = H * 0.14;
		[
			{ x: W * 0.28, y: groundTop - STEP, w: W * 0.32 },
			{ x: W * 0.30, y: groundTop - STEP * 3, w: W * 0.28 },
			{ x: W * 0.70, y: groundTop - STEP * 4, w: W * 0.28 },
			{ x: W * 0.32, y: groundTop - STEP * 5, w: W * 0.28 },
			{ x: W * 0.68, y: groundTop - STEP * 6, w: W * 0.26 },
			{ x: W * 0.30, y: groundTop - STEP * 7, w: W * 0.26 },
			{ x: W * 0.34, y: groundTop - STEP * 9, w: W * 0.28 },
			{ x: W * 0.68, y: groundTop - STEP * 10, w: W * 0.30 }
		].forEach(function (p) {
			gameView.add(Game.createSprite({
				sheet: platformSheet,
				x: p.x,
				y: p.y,
				width: p.w,
				height: PLAT_H,
				collisionGroup: 'solid',
				oneWay: true // jump up through, land on top
			}));
		});

		// Moving platform: patrols on a ping-pong tween at step 2 — the
		// solid resolver applies its per-frame movement to whoever stands
		// on it, so the rider is carried without any JS in the loop.
		// Unlike the staircase it is a normal two-way solid: no oneWay,
		// so it also bumps your head from below.
		var mover = Game.createSprite({
			sheet: moverSheet,
			x: W * 0.18,
			y: groundTop - STEP * 2,
			width: W * 0.26,
			height: PLAT_H,
			collisionGroup: 'solid'
		});
		gameView.add(mover);
		function patrol() {
			mover.animate({
				x: (mover.x < W * 0.35) ? W * 0.5 : W * 0.18,
				duration: 2600,
				easing: Game.EASE_IN_OUT
			});
		}
		mover.addEventListener('complete', patrol);
		patrol();

		// Trampolines replace the platforms at steps 2 and 8 — landing on
		// one bounces the player automatically (see the 'land' handler)
		[
			{ x: W * 0.66, y: groundTop - STEP * 2 },
			{ x: W * 0.70, y: groundTop - STEP * 8 }
		].forEach(function (t) {
			gameView.add(Game.createSprite({
				sheet: trampolineSheet,
				x: t.x,
				y: t.y,
				width: W * 0.30,
				height: PLAT_H * 1.6,
				collisionGroup: 'trampoline'
			}));
		});

		// invisible walls so the player can't run off screen — tall enough
		// to cover the whole climb
		[-20, W + 20].forEach(function (x) {
			gameView.add(Game.createSprite({
				x: x, y: -H, width: 40, height: H * 6, collisionGroup: 'solid'
			}));
		});

		// --- Player ------------------------------------------------------

		var player = Game.createSprite({
			sheet: playerSheet,
			x: W * 0.15,
			y: groundTop - PLAYER_SIZE / 2,
			width: PLAYER_SIZE,
			height: PLAYER_SIZE,
			zIndex: 10,
			gravity: GRAVITY,
			hitboxScale: 0.85,
			solidWith: ['solid', 'trampoline'],
			animations: {
				idle: { frames: [0], fps: 1, loop: true },
				walk: { frames: [1, 2], fps: 8, loop: true }
			}
		});
		player.play('idle');
		gameView.add(player);

		// Camera: scroll up once the player rises into the top third of the
		// screen, follow back down, never below the starting view
		gameView.follow(player, { topMargin: 0.33, bottomMargin: 0.7, maxY: 0 });

		// --- Controls (moveDir: -1 left, 0 idle, 1 right) ----------------

		var moveDir = 0;

		function applyMovement() {
			player.velocityX = moveDir * RUN_SPEED;
			if (moveDir !== 0) {
				player.scaleX = moveDir; // flip the art to face the way we run
			}
			if (player.onGround) {
				player.play(moveDir !== 0 ? 'walk' : 'idle');
			}
		}

		player.addEventListener('land', function (e) {
			if (e.group === 'trampoline') {
				// bounce right back up, higher than a normal jump
				player.velocityY = -JUMP * 1.1;
				player.stop();
				player.frame = 3;
				var trampoline = e.other; // the one we landed on
				trampoline.frame = 1;     // squash the mat briefly
				setTimeout(function () {
					trampoline.frame = 0;
				}, 150);
				return;
			}
			applyMovement(); // back from the jump frame to walk/idle
		});

		function jump() {
			if (player.onGround) {
				player.velocityY = -JUMP;
				player.stop();
				player.frame = 3; // jump pose until we land
			}
		}

		// Each button is its own view — Android splits pointers between
		// sibling views, so holding a direction and pressing jump works
		// simultaneously.
		function makeButton(title, position) {
			var button = Ti.UI.createLabel({
				text: title,
				textAlign: 'center',
				color: '#fff',
				font: { fontSize: 30, fontWeight: 'bold' },
				backgroundColor: '#59000000',
				borderRadius: 40,
				width: '80dp',
				height: '80dp',
				bottom: '24dp'
			});
			// manual press feedback — touchFeedback's ripple can't animate on
			// this canvas and spams "RippleDrawable" errors in the log
			button.addEventListener('touchstart', function () {
				button.backgroundColor = '#8c000000';
			});
			['touchend', 'touchcancel'].forEach(function (event) {
				button.addEventListener(event, function () {
					button.backgroundColor = '#59000000';
				});
			});
			for (var key in position) {
				button[key] = position[key];
			}
			return button;
		}

		function bindHold(button, dir) {
			button.addEventListener('touchstart', function () {
				moveDir = dir;
				applyMovement();
			});
			['touchend', 'touchcancel'].forEach(function (event) {
				button.addEventListener(event, function () {
					if (moveDir === dir) {
						moveDir = 0;
						applyMovement();
					}
				});
			});
		}

		var leftButton = makeButton('◀', { left: '24dp' });
		var jumpButton = makeButton('⬆', {});           // centered
		var rightButton = makeButton('▶', { right: '24dp' });

		bindHold(leftButton, -1);
		bindHold(rightButton, 1);
		jumpButton.addEventListener('touchstart', jump);

		win.add(leftButton);
		win.add(jumpButton);
		win.add(rightButton);
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
