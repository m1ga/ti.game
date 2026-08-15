// ti.game flappy demo — a flying pig with flapping wings.
//
// - tap anywhere: the pig gets a push up; otherwise gravity pulls it down
// - fly through the 5 gates to win; hitting a pipe or the ground ends the run
// - parallax background: slow clouds, medium hills, fast ground
//
// Everything per-frame is native: the pig falls via `gravity`, gates and
// the ground scroll via `velocityX` / linear tweens, and scoring/death are
// `collision` events (invisible score-zone sprites in the gaps). JS only
// reacts to taps and events.
//
// The world is built on the game view's `resize` event, so all sizes come
// from the real GL surface (pixels) — displayCaps is points on iOS.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#8ed8f8',
		// debug: true  // show collision shapes for every sprite
	});

	var GATE_COUNT = 5;

	var pigSheet = Game.createSpriteSheet({ image: 'assets/pig.png', frameWidth: 128, frameHeight: 128 });
	var pipeSheet = Game.createSpriteSheet({ image: 'assets/pipe.png', frameWidth: 64, frameHeight: 64 });
	var cloudSheet = Game.createSpriteSheet({ image: 'assets/clouds.png', frameWidth: 512, frameHeight: 128 });
	var hillSheet = Game.createSpriteSheet({ image: 'assets/hills.png', frameWidth: 512, frameHeight: 110 });
	var groundSheet = Game.createSpriteSheet({ image: 'assets/ground.png', frameWidth: 64, frameHeight: 64 });

	var scoreLabel = Ti.UI.createLabel({
		text: '0 / ' + GATE_COUNT,
		color: '#fff',
		font: { fontSize: 28, fontWeight: 'bold' },
		shadowColor: '#4a785a',
		shadowOffset: { x: 0, y: 2 },
		top: 40
	});
	var statusLabel = Ti.UI.createLabel({
		text: 'Tap to start!',
		color: '#fff',
		font: { fontSize: 22, fontWeight: 'bold' },
		shadowColor: '#4a785a',
		shadowOffset: { x: 0, y: 2 }
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var SPEED = W * 0.35;              // world scroll speed, px/s
		var GATE_SPACING = W * 0.55;
		var GAP = H * 0.26;                // vertical opening in a gate
		var GRAVITY = H * 1.9;             // px/s^2
		var FLAP = -H * 0.6;               // upward push per tap, px/s
		var PIG_SIZE = Math.round(Math.min(W, H) * 0.15);
		var PIPE_W = Math.round(W * 0.13);
		var GROUND_H = Math.round(H * 0.1);
		var groundTop = H - GROUND_H;

		// --- Parallax layers (two copies each, cycled with linear tweens) ----

		var layers = [];

		// Each layer is two screen-wide copies scrolling left via native
		// velocity; the engine's wrapX/wrapShift teleports a copy that left the
		// screen back behind its sibling — seamless, no JS in the loop.
		function makeLayer(sheet, y, height, speed, z, group) {
			var copies = [];
			for (var i = 0; i < 2; i++) {
				var s = Game.createSprite({
					sheet: sheet,
					x: W / 2 + i * W,
					y: y,
					width: W,
					height: height,
					zIndex: z,
					wrapX: -W / 2,
					wrapShift: 2 * W
				});
				if (group) {
					s.collisionGroup = group;
				}
				gameView.add(s);
				copies.push(s);
			}

			return {
				start: function () {
					copies.forEach(function (copy) {
						copy.velocityX = -speed;
					});
				},
				stop: function () {
					copies.forEach(function (copy) {
						copy.velocityX = 0;
					});
				}
			};
		}

		layers.push(makeLayer(cloudSheet, H * 0.18, H * 0.22, SPEED * 0.15, 1));
		layers.push(makeLayer(hillSheet, groundTop - H * 0.12, H * 0.24, SPEED * 0.4, 2));
		layers.push(makeLayer(groundSheet, groundTop + GROUND_H / 2, GROUND_H, SPEED, 8, 'ground'));

		// Invisible ceiling: bounces the pig back instead of letting it escape
		gameView.add(Game.createSprite({
			x: W / 2, y: -20, width: W * 3, height: 40, collisionGroup: 'ceiling'
		}));

		// --- The 5 gates -----------------------------------------------------

		var gates = [];

		function makeGate() {
			var top = Game.createSprite({ sheet: pipeSheet, width: PIPE_W, rotation: 180, zIndex: 5, collisionGroup: 'pipe' });
			var bottom = Game.createSprite({ sheet: pipeSheet, width: PIPE_W, zIndex: 5, collisionGroup: 'pipe' });
			// invisible score zone in the gap (no sheet = collision-only sprite)
			var zone = Game.createSprite({ width: PIPE_W * 0.3, height: GAP, collisionGroup: 'score' });
			gameView.add(top);
			gameView.add(bottom);
			gameView.add(zone);

			var parts = [top, bottom, zone];
			return {
				place: function (x) {
					var minCenter = GAP / 2 + H * 0.12;
					var maxCenter = groundTop - GAP / 2 - H * 0.08;
					var gapCenter = minCenter + Math.random() * (maxCenter - minCenter);
					var gapTop = gapCenter - GAP / 2;
					var gapBottom = gapCenter + GAP / 2;
					top.height = gapTop;
					top.x = x;
					top.y = gapTop / 2;
					bottom.height = groundTop - gapBottom;
					bottom.x = x;
					bottom.y = (gapBottom + groundTop) / 2;
					zone.x = x;
					zone.y = gapCenter;
				},
				setSpeed: function (v) {
					parts.forEach(function (p) {
						p.velocityX = v;
					});
				}
			};
		}

		for (var i = 0; i < GATE_COUNT; i++) {
			gates.push(makeGate());
		}

		// --- The pig ---------------------------------------------------------

		var pig = Game.createSprite({
			sheet: pigSheet,
			x: W * 0.28,
			y: H * 0.42,
			width: PIG_SIZE,
			height: PIG_SIZE,
			zIndex: 10,
			hitboxScale: 0.7, // the art doesn't fill the frame; keep collisions fair
			collidesWith: ['pipe', 'ground', 'score', 'ceiling'],
			animations: {
				fly: { frames: [0, 1, 2, 1], fps: 10, loop: true }
			}
		});
		gameView.add(pig);

		// --- Game state ------------------------------------------------------

		var score = 0;
		var started = false;
		var over = false;

		function reset() {
			score = 0;
			scoreLabel.text = '0 / ' + GATE_COUNT;
			statusLabel.text = 'Tap to start!';
			statusLabel.visible = true;
			started = false;
			over = false;
			pig.clearTweens();
			pig.y = H * 0.42;
			pig.velocityY = 0;
			pig.gravity = 0;
			pig.rotation = 0;
			pig.opacity = 1;
			pig.scale = 1;
			pig.play('fly');
			gates.forEach(function (gate, index) {
				gate.setSpeed(0);
				gate.place(W * 1.2 + index * GATE_SPACING);
			});
			layers.forEach(function (layer) {
				layer.start();
			});
		}

		function start() {
			started = true;
			statusLabel.visible = false;
			pig.gravity = GRAVITY;
			gates.forEach(function (gate) {
				gate.setSpeed(-SPEED);
			});
		}

		function freeze() {
			over = true;
			pig.gravity = 0;
			pig.velocityY = 0;
			pig.stop();
			gates.forEach(function (gate) {
				gate.setSpeed(0);
			});
			layers.forEach(function (layer) {
				layer.stop();
			});
		}

		function gameOver() {
			freeze();
			statusLabel.text = 'Oink! Game over — tap to retry';
			statusLabel.visible = true;
			pig.animate({ rotation: 180, opacity: 0.7, duration: 400, easing: Game.EASE_IN });
		}

		function winGame() {
			freeze();
			statusLabel.text = 'You made it! Tap to play again';
			statusLabel.visible = true;
			pig.animate({ rotation: pig.rotation + 360, scale: 1.3, duration: 800, easing: Game.EASE_IN_OUT });
		}

		pig.addEventListener('collision', function (e) {
			if (over) {
				return;
			}
			if (e.group === 'score') {
				score++;
				scoreLabel.text = score + ' / ' + GATE_COUNT;
				if (score >= GATE_COUNT) {
					winGame();
				}
			} else if (e.group === 'ceiling') {
				pig.velocityY = H * 0.1; // gentle bounce back down
			} else {
				gameOver();
			}
		});

		// Tap anywhere: flap (view-level press, fires wherever the touch lands)
		gameView.addEventListener('press', function () {
			if (over) {
				reset();
				return;
			}
			if (!started) {
				start();
			}
			pig.velocityY = FLAP;
			pig.clearTweens();
			pig.rotation = -15;
			pig.animate({ rotation: 25, duration: 900, easing: Game.EASE_IN });
		});

		reset();
	}

	win.add(gameView);
	win.add(scoreLabel);
	win.add(statusLabel);
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
