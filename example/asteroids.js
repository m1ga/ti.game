// ti.game asteroids demo — classic Newtonian flight.
//
// - ◀ / ▶ turn the ship (angularVelocity), THR burns the engine (thrust
//   along the heading, native) — while burning, the ship plays a flame
//   animation at its tail; releasing coasts on momentum
// - FIRE launches small yellow bolts from the ship's nose (pooled sprites
//   inheriting the ship's velocity); hold for autofire
// - five drifting, spinning asteroids; ship, rocks and bolts all wrap
//   around the screen edges (wrapAround)
// - shoot all five to clear the wave; the ship survives three hits,
//   shown as three dots in the top-right corner — a crash costs a dot
//   and grants brief invulnerability but the ship keeps flying; on the
//   last life it blinks red as a warning, at zero the game resets
// - native sound effects (createSound): a laser zap per shot, an
//   explosion when a rock (or the ship) blows up, and a looping engine
//   rumble while the thruster is held (loop + stop on release)
// - bolts render additively (blend: 'add') so they glow over the stars;
//   crashing triggers a native red damage flash (ship.flash)
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

// Toast on Android; Ti.UI.createNotification does not exist on iOS,
// so show an alert dialog there instead.
function notify(message) {
	if (Ti.Platform.osname === 'android') {
		Ti.UI.createNotification({ message: message }).show();
	} else {
		Ti.UI.createAlertDialog({ message: message, ok: 'OK' }).show();
	}
}

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({ backgroundColor: '#08091f' });

	var statusLabel = Ti.UI.createLabel({
		text: 'Rocks 0 / 5',
		color: '#fff',
		font: { fontSize: 22, fontWeight: 'bold' },
		shadowColor: '#000',
		shadowOffset: { x: 0, y: 2 },
		top: 90 // below the Back button
	});

	var shipSheet = Game.createSpriteSheet({ image: 'assets/ship.png', frameWidth: 64, frameHeight: 64 });
	var rockSheet = Game.createSpriteSheet({ image: 'assets/asteroid.png', frameWidth: 64, frameHeight: 64 });
	var starSheet = Game.createSpriteSheet({ image: 'assets/stars.png', frameWidth: 512, frameHeight: 512 });

	// Low-latency effects from the shared native sound pool; the thruster
	// loops while the button is held and stops on release.
	var laserSound = Game.createSound({ url: 'assets/laser.wav', volume: 0.7 });
	var explodeSound = Game.createSound({ url: 'assets/explode.wav' });
	var thrustSound = Game.createSound({ url: 'assets/thrust.wav', volume: 0.8, loop: true });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		statusLabel.scale = Math.max(1, Math.round(W / 260));
		statusLabel.x = W / 2;
		statusLabel.y = H * 0.07;
		gameView.add(statusLabel);

		var SHIP_SIZE = Math.round(Math.min(W, H) * 0.13);
		var ROCK_COUNT = 5;
		var TURN_SPEED = 220;              // deg/s while a turn button is held
		var THRUST = Math.min(W, H) * 0.9; // px/s^2
		var MAX_SPEED = Math.min(W, H) * 0.9;
		var BULLET_SPEED = Math.min(W, H) * 1.2;
		var BULLET_LIFE = 1200;            // ms
		var FIRE_INTERVAL = 250;           // ms autofire while held

		// --- Star background ---------------------------------------------

		gameView.add(Game.createSprite({
			sheet: starSheet, x: W / 2, y: H / 2, width: W, height: H, zIndex: 0
		}));

		// --- The ship ----------------------------------------------------

		var ship = Game.createSprite({
			sheet: shipSheet,
			x: W / 2,
			y: H / 2,
			width: SHIP_SIZE,
			height: SHIP_SIZE,
			zIndex: 10,
			maxSpeed: MAX_SPEED,
			wrapAround: true,
			hitboxScale: 0.6,
			hitboxShape: 'circle',
			collidesWith: ['asteroid'],
			animations: {
				thrust: { frames: [1, 2], fps: 14, loop: true } // flickering flame
			}
		});
		gameView.add(ship);

		// --- Asteroids ---------------------------------------------------

		var rocks = [];
		var destroyed = 0;

		for (var i = 0; i < ROCK_COUNT; i++) {
			var rock = Game.createSprite({
				sheet: rockSheet,
				frame: i % 2,
				zIndex: 5,
				wrapAround: true,
				hitboxScale: 0.8,
				hitboxShape: 'circle',   // round rocks collide as circles
				collisionGroup: 'asteroid'
			});
			gameView.add(rock);
			rocks.push(rock);
		}

		function spawnWave() {
			destroyed = 0;
			statusLabel.text = 'Rocks 0 / ' + ROCK_COUNT;
			rocks.forEach(function (rock, index) {
				// spawn near the edges, never on top of the ship
				var angle = (index / ROCK_COUNT) * Math.PI * 2 + Math.random() * 0.8;
				var radius = Math.min(W, H) * (0.35 + Math.random() * 0.12);
				var size = Math.round(Math.min(W, H) * (0.11 + Math.random() * 0.07));
				rock.width = size;
				rock.height = size;
				rock.x = W / 2 + Math.cos(angle) * radius;
				rock.y = H / 2 + Math.sin(angle) * radius;
				var driftAngle = Math.random() * Math.PI * 2;
				var driftSpeed = Math.min(W, H) * (0.06 + Math.random() * 0.1);
				rock.velocityX = Math.cos(driftAngle) * driftSpeed;
				rock.velocityY = Math.sin(driftAngle) * driftSpeed;
				rock.angularVelocity = (Math.random() * 2 - 1) * 60; // lazy spin
				rock.visible = true;
			});
		}

		// --- Lives: three dots top right, one gone per crash --------------

		var MAX_LIVES = 3;
		var lives = MAX_LIVES;
		var lifeDots = [];
		for (var d = 0; d < MAX_LIVES; d++) {
			var dot = Ti.UI.createView({
				width: '14dp',
				height: '14dp',
				borderRadius: '7dp',
				backgroundColor: '#ff5252',
				top: '98dp', // aligned with the status label
				right: (20 + d * 22) + 'dp'
			});
			win.add(dot);
			lifeDots.push(dot);
		}

		function updateLifeDots() {
			lifeDots.forEach(function (dot, index) {
				dot.opacity = (index < lives) ? 1 : 0.15;
			});
		}

		// Last-life warning: blink the ship red with the native flash
		// helper — one short JS timer, the fade itself runs in the engine
		var warnTimer = null;
		function updateWarning() {
			if (lives === 1 && warnTimer === null) {
				warnTimer = setInterval(function () {
					ship.flash('#ff5252', 350);
				}, 700);
			} else if (lives !== 1 && warnTimer !== null) {
				clearInterval(warnTimer);
				warnTimer = null;
			}
		}

		function resetShip() {
			ship.x = W / 2;
			ship.y = H / 2;
			ship.velocityX = 0;
			ship.velocityY = 0;
			ship.rotation = 0;
			ship.thrust = 0;
			ship.stop();
			ship.frame = 0;
		}

		var invulnerableUntil = 0; // grace period after a respawn
		ship.addEventListener('collision', function (e) {
			if (e.group !== 'asteroid' || Date.now() < invulnerableUntil) {
				return;
			}
			lives--;
			explodeSound.play();
			ship.flash('#ff5252', 400); // native damage flash
			if (lives <= 0) {
				notify('Game over!');
				lives = MAX_LIVES;
				resetShip();
				spawnWave(); // fresh rocks at the edges, fresh lives
			} else {
				// keep flying — the grace period below lets the ship
				// clear the rock it just clipped
				notify(lives === 1 ? 'Last life!' : 'Crashed!');
			}
			updateLifeDots();
			updateWarning();
			invulnerableUntil = Date.now() + 1500;
		});

		// --- Bullets (pooled) --------------------------------------------

		var bullets = [];
		for (var b = 0; b < 10; b++) {
			(function () {
				var bullet = Game.createSprite({
					sheet: shipSheet,
					frame: 3,
					width: SHIP_SIZE * 0.22,
					height: SHIP_SIZE * 0.4,
					blend: 'add', // bolts glow additively over the stars
					zIndex: 8,
					visible: false,
					wrapAround: true,
					hitboxScale: 1.4, // generous — bolts are tiny and fast
					collidesWith: ['asteroid']
				});
				var state = { sprite: bullet, active: false, generation: 0 };

				bullet.addEventListener('collision', function (e) {
					if (!state.active) {
						return;
					}
					deactivate(state);
					e.other.visible = false; // rock gone (no render, no collision)
					explodeSound.play();
					destroyed++;
					statusLabel.text = 'Rocks ' + destroyed + ' / ' + ROCK_COUNT;
					if (destroyed >= ROCK_COUNT) {
						notify('Wave cleared!');
						setTimeout(spawnWave, 1200);
					}
				});

				gameView.add(bullet);
				bullets.push(state);
			})();
		}

		function deactivate(state) {
			state.active = false;
			state.sprite.visible = false;
			state.sprite.velocityX = 0;
			state.sprite.velocityY = 0;
		}

		function shoot() {
			var state = null;
			for (var k = 0; k < bullets.length; k++) {
				if (!bullets[k].active) {
					state = bullets[k];
					break;
				}
			}
			if (!state) {
				return;
			}
			laserSound.play();
			var rad = ship.rotation * Math.PI / 180;
			var dirX = Math.sin(rad);
			var dirY = -Math.cos(rad);
			var bullet = state.sprite;
			bullet.x = ship.x + dirX * SHIP_SIZE * 0.55; // out of the nose
			bullet.y = ship.y + dirY * SHIP_SIZE * 0.55;
			bullet.rotation = ship.rotation;
			bullet.velocityX = ship.velocityX + dirX * BULLET_SPEED;
			bullet.velocityY = ship.velocityY + dirY * BULLET_SPEED;
			bullet.visible = true;
			state.active = true;
			state.generation++;
			var generation = state.generation;
			setTimeout(function () {
				// burn out — unless this pool slot was already recycled
				if (state.active && state.generation === generation) {
					deactivate(state);
				}
			}, BULLET_LIFE);
		}

		// --- Controls: turn left, pedals right ---------------------------

		function makeButton(title, position, fontSize) {
			var button = Ti.UI.createLabel({
				text: title,
				textAlign: 'center',
				color: '#fff',
				font: { fontSize: fontSize || 30, fontWeight: 'bold' },
				backgroundColor: '#59000000',
				borderRadius: 40,
				width: '80dp',
				height: '80dp',
				bottom: '24dp'
			});
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

		function bindHold(button, apply, release) {
			button.addEventListener('touchstart', apply);
			['touchend', 'touchcancel'].forEach(function (event) {
				button.addEventListener(event, release);
			});
		}

		var leftButton = makeButton('◀', { left: '24dp' });
		var rightButton = makeButton('▶', { left: '112dp' });
		var thrustButton = makeButton('THR', { right: '112dp' }, 20);
		var fireButton = makeButton('FIRE', { right: '24dp' }, 20);

		bindHold(leftButton, function () {
			ship.angularVelocity = -TURN_SPEED;
		}, function () {
			if (ship.angularVelocity < 0) {
				ship.angularVelocity = 0;
			}
		});
		bindHold(rightButton, function () {
			ship.angularVelocity = TURN_SPEED;
		}, function () {
			if (ship.angularVelocity > 0) {
				ship.angularVelocity = 0;
			}
		});
		bindHold(thrustButton, function () {
			ship.thrust = THRUST;
			ship.play('thrust'); // flame out of the tail while burning
			thrustSound.play(); // looping engine rumble
		}, function () {
			ship.thrust = 0;
			ship.stop();
			ship.frame = 0;
			thrustSound.stop();
		});

		var fireTimer = null;
		bindHold(fireButton, function () {
			shoot();
			fireTimer = setInterval(shoot, FIRE_INTERVAL);
		}, function () {
			if (fireTimer) {
				clearInterval(fireTimer);
				fireTimer = null;
			}
		});

		win.addEventListener('close', function () {
			if (fireTimer) {
				clearInterval(fireTimer);
			}
			if (warnTimer) {
				clearInterval(warnTimer);
			}
			thrustSound.stop(); // don't leave the loop running past the window
		});

		win.add(leftButton);
		win.add(rightButton);
		win.add(thrustButton);
		win.add(fireButton);

		spawnWave();
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
