// ti.game text demo — bitmap-font text sprites inside the GL scene.
//
// - all labels use the built-in pixel font (createText with no `font`),
//   scaled up crisply; a custom font would come from Game.createFont
//   ({ font: 'assets/myfont.fnt' } or a monospace grid image)
// - text objects ARE sprites: the title wobbles on idleAnimation with a
//   glow, the score pops with a tween and flashes on change, the hint
//   block is multi-line with align: 'center'
// - word wrap: the pond dialog is one long string with maxWidth — the
//   engine breaks lines on word boundaries and re-wraps every time the
//   text changes (tap it to cycle messages)
// - screenFixed: the HUD (score, title, RESET button) sticks to the
//   surface while the camera follows the dragged ball around a world
//   twice the screen size — the signposts are ordinary world-space text
//   and scroll past like any sprite
// - RESET is a text sprite with a tap listener — text buttons need no
//   Titanium overlay views
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#1c2030'
	});

	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });

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
		var UNIT = Math.max(1, Math.round(W / 200)); // pixel-font scale

		// --- world-space text: scrolls with the camera like any sprite ---

		[
			['NORTH MEADOW', 0.5, 0.1],
			['OLD OAK', 0.15, 0.45],
			['EAST GATE', 0.85, 0.5],
			['SOUTH POND', 0.5, 0.9]
		].forEach(function (sign) {
			gameView.add(Game.createText({
				text: sign[0],
				x: WORLD_W * sign[1],
				y: WORLD_H * sign[2],
				scale: UNIT,
				tintColor: '#8a9bb8',
				zIndex: 2
			}));
		});

		// Multi-line block, center-aligned, in the middle of the world
		gameView.add(Game.createText({
			text: 'DRAG THE BALL AROUND\nTHE CAMERA FOLLOWS\nTAP IT TO SCORE',
			align: 'center',
			x: WORLD_W / 2,
			y: WORLD_H / 2 - H * 0.2,
			scale: UNIT,
			lineSpacing: 1.4,
			tintColor: '#5c6b8a',
			zIndex: 2
		}));

		// --- word wrap: one long string, no hand-broken \n lines ---
		// maxWidth is in font-space px (pre-scale), so the wrap width on
		// screen is maxWidth * scale; assigning `text` re-wraps natively.

		var WISDOM = [
			'A WISE FROG ONCE SAID: THE POND LOOKS SMALL UNTIL YOU TRY TO HOP ACROSS IT IN A SINGLE JUMP.',
			'EVERY MESSAGE HERE IS ONE LONG STRING - THE ENGINE BREAKS THE LINES, NOT THE SOURCE CODE.',
			'A WORD LIKE ANTIDISESTABLISHMENTARIANISM OVERFLOWS INSTEAD OF BREAKING MID-WORD.'
		];
		var wisdomIndex = 0;
		var dialog = Game.createText({
			text: 'TAP FOR POND WISDOM',
			maxWidth: Math.round(W * 0.55 / UNIT),
			align: 'center',
			x: WORLD_W / 2,
			y: WORLD_H * 0.78,
			scale: UNIT,
			lineSpacing: 1.3,
			tintColor: '#9ad1a5',
			zIndex: 3
		});
		dialog.addEventListener('tap', function () {
			dialog.text = WISDOM[wisdomIndex++ % WISDOM.length];
			dialog.flash('#fff', 150);
		});
		gameView.add(dialog);

		// --- the ball: drag it, camera follows, tap it to score ---

		var ball = Game.createSprite({
			sheet: ballSheet,
			x: WORLD_W / 2,
			y: WORLD_H / 2,
			width: W * 0.14,
			height: W * 0.14,
			hitboxShape: 'circle',
			draggable: true,
			zIndex: 5
		});
		gameView.add(ball);

		gameView.cameraBounds = { minX: 0, minY: 0, maxX: WORLD_W, maxY: WORLD_H };
		gameView.follow(ball, {
			leftMargin: 0.35, rightMargin: 0.65,
			topMargin: 0.35, bottomMargin: 0.65,
			maxY: WORLD_H,
			smoothing: 0.12
		});

		// --- screen-fixed HUD: ignores the camera entirely ---

		var title = Game.createText({
			text: 'TEXT DEMO',
			screenFixed: true,
			x: W / 2,
			y: H * 0.08,
			scale: UNIT * 1.5,
			letterSpacing: 1,
			tintColor: '#ffd54a',
			glowColor: '#ffd54a',
			glowBlur: 6,
			glowOpacity: 0.5,
			idleAnimation: true,
			idleRotation: 2,
			idleMovement: 3,
			zIndex: 20
		});
		gameView.add(title);

		var score = 0;
		var scoreText = Game.createText({
			text: 'SCORE 0',
			screenFixed: true,
			x: 16,
			y: H * 0.15,
			anchorX: 0,
			anchorY: 0,
			scale: UNIT,
			zIndex: 20
		});
		gameView.add(scoreText);

		ball.addEventListener('tap', function () {
			score += 10;
			scoreText.text = 'SCORE ' + score;
			scoreText.flash('#4dff88', 250);
			// pop: text tweens like any sprite
			scoreText.animate({ scale: UNIT * 1.3, duration: 90, easing: Game.EASE_OUT });
			scoreText.addEventListener('complete', popBack);
			ball.flash('#fff', 120);
		});
		function popBack() {
			scoreText.removeEventListener('complete', popBack);
			scoreText.animate({ scale: UNIT, duration: 140, easing: Game.EASE_IN });
		}

		// A text sprite as a button — tap events work on text directly
		var reset = Game.createText({
			text: '[ RESET ]',
			screenFixed: true,
			x: W / 2,
			y: H * 0.92,
			scale: UNIT,
			tintColor: '#ff8a80',
			zIndex: 20
		});
		reset.addEventListener('tap', function () {
			score = 0;
			scoreText.text = 'SCORE 0';
			reset.flash('#fff', 200);
			ball.x = WORLD_W / 2;
			ball.y = WORLD_H / 2;
		});
		gameView.add(reset);
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
