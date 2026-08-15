// ti.game volley demo — Blobby Volley style: you (green, left) vs. a
// simple computer player (red, right).
//
// - same controls as the platformer: hold ◀ / ▶, press ⬆ to jump
//   (multitouch: separate views, so direction + jump work together)
// - the net blocks both players (solidWith) and bounces the ball
//   (restitution — native rigid-body style reflection off walls/net/ceiling)
// - hitting the ball reflects it away from the blob's center with an
//   upward bias (collision event, blobby-style)
// - ball touching the floor ends the round: the other side scores, and the
//   ball serves from the middle, pushed toward the player who conceded
// - the computer follows the ball on its side and jumps at it (a coarse
//   JS timer makes decisions; all motion stays native)
//
// The court is built on the game view's `resize` event, so all sizes come
// from the actual GL surface — not the display size, which includes the
// system bars and would push bottom-anchored sprites off screen.
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

	var scoreLabel = Ti.UI.createLabel({
		text: 'You 0 : 0 CPU',
		color: '#fff',
		font: { fontSize: 24, fontWeight: 'bold' },
		shadowColor: '#4a785a',
		shadowOffset: { x: 0, y: 2 },
		top: 40
	});

	var playerSheet = Game.createSpriteSheet({ image: 'assets/player.png', frameWidth: 64, frameHeight: 64 });
	var cpuSheet = Game.createSpriteSheet({ image: 'assets/player2.png', frameWidth: 64, frameHeight: 64 });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var netSheet = Game.createSpriteSheet({ image: 'assets/net.png', frameWidth: 32, frameHeight: 128 });
	var groundSheet = Game.createSpriteSheet({ image: 'assets/ground.png', frameWidth: 64, frameHeight: 64 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var PLAYER_SIZE = Math.round(Math.min(W, H) * 0.16);
		var BALL_SIZE = Math.round(Math.min(W, H) * 0.11);
		var RUN_SPEED = W * 0.45;
		var GRAVITY = H * 2.2;
		var JUMP = H * 0.85;
		var BALL_GRAVITY = H * 1.0;        // floatier than the players
		var HIT_SPEED = H * 0.85;          // ball speed after a blob hit
		var SERVE_PUSH = W * 0.22;

		// Keep the court above the on-screen controls (80dp buttons + margins)
		var density = Ti.Platform.displayCaps.logicalDensityFactor;
		var buttonZone = Math.round(130 * density);
		var groundTop = H - buttonZone;

		// --- Court: floor, walls, ceiling, net ---------------------------

		gameView.add(Game.createSprite({
			sheet: groundSheet,
			x: W / 2,
			y: (groundTop + H) / 2,
			width: W,
			height: H - groundTop,
			collisionGroup: 'floor'
		}));

		[-20, W + 20].forEach(function (x) {
			gameView.add(Game.createSprite({
				x: x, y: H / 2, width: 40, height: H * 3, collisionGroup: 'wall'
			}));
		});
		gameView.add(Game.createSprite({
			x: W / 2, y: -20, width: W * 2, height: 40, collisionGroup: 'wall'
		}));

		var NET_H = H * 0.24;
		gameView.add(Game.createSprite({
			sheet: netSheet,
			x: W / 2,
			y: groundTop - NET_H / 2,
			width: Math.max(24, W * 0.035),
			height: NET_H,
			zIndex: 5,
			collisionGroup: 'net'
		}));

		// --- Players -----------------------------------------------------

		function makeBlob(sheet, x) {
			var blob = Game.createSprite({
				sheet: sheet,
				x: x,
				y: groundTop - PLAYER_SIZE / 2,
				width: PLAYER_SIZE,
				height: PLAYER_SIZE,
				zIndex: 10,
				gravity: GRAVITY,
				hitboxScale: 0.85,
				collisionGroup: 'player',
				solidWith: ['floor', 'wall', 'net'],
				animations: {
					idle: { frames: [0], fps: 1, loop: true },
					walk: { frames: [1, 2], fps: 8, loop: true }
				}
			});
			blob.play('idle');
			gameView.add(blob);
			return blob;
		}

		var playerHomeX = W * 0.22;
		var cpuHomeX = W * 0.78;
		var player = makeBlob(playerSheet, playerHomeX);
		var cpu = makeBlob(cpuSheet, cpuHomeX);
		cpu.scaleX = -1; // face the net

		// --- Ball --------------------------------------------------------

		var ball = Game.createSprite({
			sheet: ballSheet,
			x: W / 2,
			y: H * 0.3,
			width: BALL_SIZE,
			height: BALL_SIZE,
			zIndex: 12,
			hitboxScale: 0.9,
			hitboxShape: 'circle',   // round ball: corner bounces off the net
			restitution: 0.75,
			solidWith: ['wall', 'net'],
			collidesWith: ['player', 'floor']
		});
		gameView.add(ball);

		// --- Score / round flow ------------------------------------------

		var scoreYou = 0;
		var scoreCpu = 0;
		var running = false;

		function serve(towardSide) {
			ball.x = W / 2;
			ball.y = H * 0.3;
			ball.rotation = 0;
			ball.gravity = BALL_GRAVITY;
			ball.velocityX = towardSide * SERVE_PUSH;
			ball.velocityY = 0;
			running = true;
		}

		function roundOver(cpuConceded) {
			running = false;
			ball.gravity = 0;
			ball.velocityX = 0;
			ball.velocityY = 0;
			if (cpuConceded) {
				scoreYou++;
			} else {
				scoreCpu++;
			}
			scoreLabel.text = 'You ' + scoreYou + ' : ' + scoreCpu + ' CPU';
			setTimeout(function () {
				// push toward whoever just conceded the point
				serve(cpuConceded ? 1 : -1);
			}, 1200);
		}

		ball.addEventListener('collision', function (e) {
			if (!running) {
				return;
			}
			if (e.group === 'player') {
				// blobby-style hit: reflect away from the blob's center, biased up
				var blob = e.other;
				var dx = ball.x - blob.x;
				var dy = ball.y - blob.y;
				var len = Math.sqrt(dx * dx + dy * dy) || 1;
				ball.velocityX = (dx / len) * HIT_SPEED;
				ball.velocityY = Math.min((dy / len) * HIT_SPEED, -HIT_SPEED * 0.45);
			} else if (e.group === 'floor') {
				roundOver(ball.x > W / 2);
			}
		});

		// --- Computer player ---------------------------------------------

		var aiTimer = setInterval(function () {
			var onCpuSide = ball.x > W / 2;
			var target = (running && onCpuSide) ? ball.x + PLAYER_SIZE * 0.2 : cpuHomeX;
			var dx = target - cpu.x;
			cpu.velocityX = (Math.abs(dx) > PLAYER_SIZE * 0.15) ? (dx > 0 ? RUN_SPEED : -RUN_SPEED) : 0;
			if (running && onCpuSide && cpu.onGround
					&& Math.abs(ball.x - cpu.x) < PLAYER_SIZE * 1.2
					&& ball.y < cpu.y && ball.velocityY > 0) {
				cpu.velocityY = -JUMP;
				cpu.stop();
				cpu.frame = 3;
			}
			if (cpu.onGround) {
				var anim = (cpu.velocityX !== 0) ? 'walk' : 'idle';
				if (cpu.animation !== anim) {
					cpu.play(anim);
				}
			}
		}, 80);

		win.addEventListener('close', function () {
			clearInterval(aiTimer);
		});

		// --- Your controls (same as the platformer) ----------------------

		var moveDir = 0;

		function applyMovement() {
			player.velocityX = moveDir * RUN_SPEED;
			if (moveDir !== 0) {
				player.scaleX = moveDir;
			}
			if (player.onGround) {
				player.play(moveDir !== 0 ? 'walk' : 'idle');
			}
		}

		player.addEventListener('land', applyMovement);

		function jump() {
			if (player.onGround) {
				player.velocityY = -JUMP;
				player.stop();
				player.frame = 3;
			}
		}

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
		var jumpButton = makeButton('⬆', {});
		var rightButton = makeButton('▶', { right: '24dp' });

		bindHold(leftButton, -1);
		bindHold(rightButton, 1);
		jumpButton.addEventListener('touchstart', jump);

		win.add(leftButton);
		win.add(jumpButton);
		win.add(rightButton);

		// first serve: random side
		serve(Math.random() < 0.5 ? -1 : 1);
	}

	win.add(gameView);
	win.add(scoreLabel);
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
