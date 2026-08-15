// ti.game skate demo — an endless side-scrolling skateboard runner.
//
// - the street scrolls right-to-left; press the JUMP button to ollie over
//   brick walls and pits in the asphalt
// - sometimes a raised road section comes along: jump onto it, ride
//   along the higher level, and drop back down when it ends
// - hitting an obstacle wipes you out: crash pose + impact burst sprite,
//   tap anywhere to retry
// - jumping and crashing play native sound effects, and a looping
//   chiptune track runs on the music backend (createSound)
// - native particles (createEmitter): a dust trail follows the board
//   while rolling; crashing fires a spark burst via emit(n) plus a
//   native camera shake (gameView.shake)
// - dusk city skyline scrolls slowly behind (parallax), the street at
//   full speed — both via native wrapX/wrapShift, no JS in the loop
//
// The player never moves horizontally: gravity + an invisible ground
// solid handle the jump arc natively, obstacles scroll left with the
// same velocity as the street so they appear glued to it. JS only spawns
// obstacles on a coarse timer and reacts to `collision` / `land` events.
//
// All art is pixel style — sheets use `smoothing: false` for crisp
// nearest-neighbor scaling.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#4a4278'
		// debug: true  // show collision shapes for every sprite
	});

	var skaterSheet = Game.createSpriteSheet({ image: 'assets/skater.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	// repeat: true = GL_REPEAT wrap, so tileRepeat sprites tile these
	// textures at native pixel size instead of stretching them screen-wide
	var streetSheet = Game.createSpriteSheet({ image: 'assets/street.png', frameWidth: 512, frameHeight: 64, smoothing: false, repeat: true });
	var skylineSheet = Game.createSpriteSheet({ image: 'assets/skyline.png', frameWidth: 512, frameHeight: 64, smoothing: false, repeat: true });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var pitSheet = Game.createSpriteSheet({ image: 'assets/pit.png', frameWidth: 48, frameHeight: 24, smoothing: false });
	// white particle frames (0 = soft puff, 1 = pixel spark), tinted per emitter
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });

	// Low-latency effects from the shared native sound pool, plus a looping
	// chiptune track on the streaming music backend (auto-pauses with the app)
	var jumpSound = Game.createSound({ url: 'assets/jump.wav', volume: 0.8 });
	var crashSound = Game.createSound({ url: 'assets/crash.wav' });
	var music = Game.createSound({ url: 'assets/music.wav', music: true, loop: true, volume: 0.45 });

	var spawnTimer = null;
	var scoreTimer = null;

	function clearTimers() {
		if (spawnTimer !== null) {
			clearTimeout(spawnTimer);
			spawnTimer = null;
		}
		if (scoreTimer !== null) {
			clearInterval(scoreTimer);
			scoreTimer = null;
		}
	}
	win.addEventListener('close', function () {
		clearTimers();
		music.stop();
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var PLAYER = Math.round(Math.min(W, H) * 0.15);
		var SPEED = W * 0.5;              // world scroll speed, px/s
		var GRAVITY = H * 2.4;             // px/s^2
		var JUMP = H * 0.9;                // takeoff speed, px/s (~0.75 s air time)
		var RAISE = Math.round(H * 0.1);   // raised road height (jump apex is ~0.17*H)

		// Keep the street surface above the jump button (64dp + margins)
		var density = Ti.Platform.displayCaps.logicalDensityFactor;
		var buttonZone = Math.round(120 * density);
		var groundTop = H - buttonZone;

		// --- Parallax: skyline (slow) + street (full speed) --------------

		var layers = [];

		// Two screen-wide copies per layer scrolling left via native
		// velocity; wrapX/wrapShift teleports a copy that left the screen
		// back behind its sibling — seamless, no JS in the loop.
		function makeLayer(sheet, y, height, speed, z) {
			var copies = [];
			for (var i = 0; i < 2; i++) {
				var s = Game.createSprite({
					sheet: sheet,
					x: W / 2 + i * W,
					y: y,
					width: W,
					height: height,
					zIndex: z,
					tileRepeat: 'x',   // tile at native size, no horizontal stretch
					wrapX: -W / 2,
					wrapShift: 2 * W
				});
				gameView.add(s);
				copies.push(s);
			}
			return {
				setSpeed: function (v) {
					copies.forEach(function (copy) {
						copy.velocityX = -v;
					});
				}
			};
		}

		var SKY_H = H * 0.3;
		layers.push(makeLayer(skylineSheet, groundTop - SKY_H / 2, SKY_H, SPEED * 0.12, 1));
		layers.push(makeLayer(streetSheet, (groundTop + H) / 2, H - groundTop, SPEED, 8));

		// Invisible ground solid — the street layer is just the visuals
		gameView.add(Game.createSprite({
			x: W / 2, y: groundTop + 50, width: W * 2, height: 100, collisionGroup: 'ground'
		}));

		// --- Obstacles: pooled walls and pits ----------------------------

		var WALL_W = Math.round(PLAYER * 0.55);
		var WALL_H = Math.round(PLAYER * 0.75);
		var PIT_W = Math.round(PLAYER * 1.15);
		var PIT_H = Math.round(PLAYER * 0.5);

		function makePool(count, create) {
			var pool = [];
			for (var i = 0; i < count; i++) {
				var sprite = create();
				gameView.add(sprite);
				pool.push({ sprite: sprite, active: false });
			}
			return pool;
		}

		var walls = makePool(3, function () {
			return Game.createSprite({
				sheet: wallSheet,
				x: W * 2,
				y: groundTop - WALL_H / 2,
				width: WALL_W,
				height: WALL_H,
				zIndex: 9,
				collisionGroup: 'wall'
			});
		});

		// The pit sits in the street but its hitbox pokes slightly above
		// the surface, so it only catches a player rolling on the ground —
		// a jumping player's box is well clear of it.
		var pits = makePool(3, function () {
			return Game.createSprite({
				sheet: pitSheet,
				x: W * 2,
				y: groundTop + PIT_H / 2 - PLAYER * 0.12,
				width: PIT_W,
				height: PIT_H,
				zIndex: 9,
				collisionGroup: 'pit'
			});
		});

		// --- Raised road segments ----------------------------------------

		// A raised section is a solid block the player jumps onto and rides
		// until it ends (the ground solid takes over again). The block is
		// `solidWith` terrain like the ground, so landing/`onGround` just
		// work; an invisible trigger on its front face (group 'wall', top
		// margin so lip landings stay safe) turns rolling into it into a
		// crash instead of the solid shoving the player off screen.
		var platforms = [];
		for (var p = 0; p < 2; p++) {
			var raisedTop = groundTop - RAISE;
			var block = Game.createSprite({
				sheet: streetSheet,
				x: W * 2,
				y: (raisedTop + H) / 2,
				width: W,
				height: H - raisedTop,
				zIndex: 9,
				tileRepeat: 'x',   // segment length varies — keep the texture density
				collisionGroup: 'platform'
			});
			var face = Game.createSprite({
				x: W * 2,
				y: groundTop - (RAISE - PLAYER * 0.25) / 2,
				width: PLAYER * 0.1,
				height: Math.max(RAISE - PLAYER * 0.25, PLAYER * 0.2),
				collisionGroup: 'wall'
			});
			gameView.add(block);
			gameView.add(face);
			platforms.push({ block: block, face: face, active: false });
		}

		function platformSprites(o) {
			return o.block ? [o.block, o.face] : [o.sprite];
		}

		function allObstacles() {
			return walls.concat(pits, platforms);
		}

		function setObstacleSpeed(v) {
			allObstacles().forEach(function (o) {
				platformSprites(o).forEach(function (s) {
					s.velocityX = o.active ? -v : 0;
				});
			});
		}

		function deactivate(o) {
			o.active = false;
			platformSprites(o).forEach(function (s) {
				s.velocityX = 0;
				s.x = W * 2;
			});
		}

		function recycleObstacles() {
			allObstacles().forEach(function (o) {
				var width = o.block ? o.block.width : 0;
				if (o.active && (o.block || o.sprite).x < -width / 2 - PLAYER) {
					deactivate(o);
				}
			});
		}

		function takeInactive(pool) {
			for (var i = 0; i < pool.length; i++) {
				if (!pool[i].active) {
					return pool[i];
				}
			}
			return null;
		}

		// Extra gap after a raised segment so nothing spawns inside it
		var extraDelay = 0;

		function spawnObstacle() {
			recycleObstacles();
			extraDelay = 0;
			var roll = Math.random();
			if (roll < 0.25) {
				var platform = takeInactive(platforms);
				if (platform) {
					var length = W * (0.8 + Math.random() * 0.6);
					platform.active = true;
					platform.block.width = length;
					platform.block.x = W + length / 2 + PLAYER;
					platform.face.x = platform.block.x - length / 2;
					platform.block.velocityX = -SPEED;
					platform.face.velocityX = -SPEED;
					extraDelay = length / SPEED * 1000;
					return;
				}
			}
			var obstacle = takeInactive(roll < 0.6 ? walls : pits);
			if (obstacle) {
				obstacle.active = true;
				obstacle.sprite.x = W + PLAYER;
				obstacle.sprite.velocityX = -SPEED;
			}
		}

		function scheduleSpawn() {
			spawnTimer = setTimeout(function () {
				spawnObstacle();
				scheduleSpawn();
			}, 1100 + Math.random() * 800 + extraDelay);
		}

		// --- Particles ---------------------------------------------------

		// Dust kicked up behind the board while rolling: a continuous
		// emitter following the player (offset to the rear wheels).
		// Everything runs natively — JS only toggles `emitting`.
		var dust = Game.createEmitter({
			sheet: sparkSheet,
			frame: 0,
			rate: 22,
			lifetime: 450,
			speed: W * 0.08,
			angle: -35,               // up and back (0 = up, clockwise)
			spread: 50,
			size: PLAYER * 0.22,
			startScale: 0.7,
			endScale: 1.8,
			startOpacity: 0.45,
			endOpacity: 0,
			tint: '#8a8580',
			zIndex: 9,
			offsetX: -PLAYER * 0.32,
			offsetY: PLAYER * 0.42
		});
		gameView.add(dust);

		// Crash sparks: burst-only emitter (rate 0), fired via emit(n)
		var sparks = Game.createEmitter({
			sheet: sparkSheet,
			frame: 1,
			rate: 0,
			lifetime: 550,
			speed: W * 0.55,
			spread: 360,
			gravity: H * 1.6,
			size: PLAYER * 0.3,
			startScale: 1,
			endScale: 0.3,
			startOpacity: 1,
			endOpacity: 0,
			tint: '#ffb030',
			zIndex: 11
		});
		gameView.add(sparks);

		// --- Player ------------------------------------------------------

		var player = Game.createSprite({
			sheet: skaterSheet,
			x: W * 0.24,
			y: groundTop - PLAYER / 2,
			width: PLAYER,
			height: PLAYER,
			zIndex: 10,
			gravity: GRAVITY,
			hitboxScale: 0.9,
			solidWith: ['ground', 'platform'],
			collidesWith: ['wall', 'pit'],
			animations: {
				roll: { frames: [0, 1], fps: 6, loop: true }
			}
		});
		gameView.add(player);
		dust.target = player; // dust follows the board from here on

		// Impact burst shown on the player when crashing (same sheet —
		// the whole scene stays a single texture batch)
		var burst = Game.createSprite({
			sheet: skaterSheet,
			x: W * 0.24,
			y: groundTop - PLAYER / 2,
			width: PLAYER,
			height: PLAYER,
			zIndex: 12,
			visible: false,
			animations: {
				pop: { frames: [4, 5], fps: 10, loop: true }
			}
		});
		gameView.add(burst);

		// --- Game state --------------------------------------------------

		var score = 0;
		var over = false;

		var scoreLabel = Ti.UI.createLabel({
			text: '0 m',
			color: '#fff',
			font: { fontSize: 28, fontWeight: 'bold' },
			shadowColor: '#20222c',
			shadowOffset: { x: 0, y: 2 },
			top: 40
		});
		var statusLabel = Ti.UI.createLabel({
			text: '',
			color: '#fff',
			font: { fontSize: 22, fontWeight: 'bold' },
			shadowColor: '#20222c',
			shadowOffset: { x: 0, y: 2 },
			visible: false
		});

		function start() {
			score = 0;
			scoreLabel.text = '0 m';
			statusLabel.visible = false;
			over = false;
			burst.visible = false;
			burst.stop();
			player.clearTweens();
			player.x = W * 0.24;
			player.y = groundTop - PLAYER / 2;
			player.velocityY = 0;
			player.gravity = GRAVITY;
			player.rotation = 0;
			player.play('roll');
			allObstacles().forEach(deactivate);
			extraDelay = 0;
			layers.forEach(function (layer) {
				layer.setSpeed(SPEED);
			});
			clearTimers();
			scheduleSpawn();
			scoreTimer = setInterval(function () {
				score++;
				scoreLabel.text = score + ' m';
			}, 100);
			music.play(); // stop() rewinds, so every run starts the tune fresh
			sparks.clear();
			dust.emitting = true;
		}

		function crash(group) {
			over = true;
			music.stop();
			crashSound.play();
			clearTimers();
			player.gravity = 0;
			player.velocityY = 0;
			player.stop();
			player.frame = 3; // wipeout pose
			layers.forEach(function (layer) {
				layer.setSpeed(0);
			});
			setObstacleSpeed(0);
			if (group === 'pit') {
				// tumble into the hole a little
				player.animate({ y: player.y + PLAYER * 0.25, duration: 200, easing: Game.EASE_OUT });
			}
			burst.x = player.x;
			burst.y = player.y - PLAYER * 0.15;
			burst.visible = true;
			burst.play('pop');
			dust.emitting = false;
			sparks.x = player.x;
			sparks.y = player.y;
			sparks.emit(26);
			gameView.shake({ strength: PLAYER * 0.12, duration: 450 });
			statusLabel.text = 'Wipeout! Tap to retry';
			statusLabel.visible = true;
		}

		player.addEventListener('collision', function (e) {
			if (!over) {
				crash(e.group);
			}
		});

		player.addEventListener('land', function () {
			if (!over) {
				player.play('roll');
				dust.emitting = true;
			}
		});

		function jump() {
			if (!over && player.onGround) {
				jumpSound.play();
				dust.emitting = false; // no dust while airborne
				player.velocityY = -JUMP;
				player.stop();
				player.frame = 2; // tuck pose until we land
			}
		}

		gameView.addEventListener('press', function () {
			if (over) {
				start();
			}
		});

		// --- Jump button -------------------------------------------------

		var jumpButton = Ti.UI.createLabel({
			text: 'JUMP',
			textAlign: 'center',
			color: '#fff',
			font: { fontSize: 24, fontWeight: 'bold' },
			backgroundColor: '#59000000',
			borderRadius: 32,
			width: '150dp',
			height: '64dp',
			bottom: '24dp'
		});
		// manual press feedback — touchFeedback's ripple can't animate on
		// this canvas and spams "RippleDrawable" errors in the log
		jumpButton.addEventListener('touchstart', function () {
			jumpButton.backgroundColor = '#8c000000';
			jump();
		});
		['touchend', 'touchcancel'].forEach(function (event) {
			jumpButton.addEventListener(event, function () {
				jumpButton.backgroundColor = '#59000000';
			});
		});

		win.add(jumpButton);
		win.add(scoreLabel);
		win.add(statusLabel);

		start();
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
