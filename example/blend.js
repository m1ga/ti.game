// ti.game blend & flash demo — blend modes and damage flashes.
//
// - four rows of overlapping spark sprites with red/green/blue tints,
//   identical except for the blend property: 'normal' (overlaps cover),
//   'add' (overlaps sum and bloom toward white), 'multiply' (darkens
//   what's behind — the bright meadow strip goes shadowy) and 'screen'
//   (lightens softly, converging on white instead of blowing out)
// - the multiply/screen rows sit on a bright meadow strip, because
//   multiply over a near-black backdrop would just go black
// - the sparks drift on the native idle wobble, so the overlaps shift
//   and mix live with zero JS in the loop
// - a row of ships shows sprite.flash(color, duration): tap one to
//   fire a solid-color silhouette overlay that fades out natively;
//   the right ship auto-blinks on a timer — the classic
//   invincibility pattern (see the asteroids demo's last life)
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({ backgroundColor: '#101223' });

	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var shipSheet = Game.createSpriteSheet({ image: 'assets/ship.png', frameWidth: 64, frameHeight: 64 });
	var meadowSheet = Game.createSpriteSheet({ image: 'assets/meadow.png', frameWidth: 270, frameHeight: 480, smoothing: false });

	var blinkTimer = null;
	win.addEventListener('close', function () {
		if (blinkTimer !== null) {
			clearInterval(blinkTimer);
			blinkTimer = null;
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

		var SPARK = Math.round(W * 0.24);
		var SHIP = Math.round(W * 0.16);
		var TINTS = ['#f44', '#4f4', '#48f'];

		// Bright meadow strip behind the multiply/screen rows — multiply
		// over the near-black window background would just go black
		gameView.add(Game.createSprite({
			sheet: meadowSheet,
			x: W * 0.5,
			y: H * 0.59,
			width: W,
			height: H * 0.36,
			zIndex: -1
		}));

		// --- Blend rows: identical except for the blend property ----------

		function sparkRow(y, blend) {
			TINTS.forEach(function (tint, index) {
				gameView.add(Game.createSprite({
					sheet: sparkSheet,
					x: W * (0.32 + index * 0.18), // close enough to overlap
					y: y,
					width: SPARK,
					height: SPARK,
					tintColor: tint,
					blend: blend,
					zIndex: index,
					// native drift so the overlaps shift and mix live
					idleAnimation: true,
					idleRotation: 0,
					idleMovement: W * 0.03,
					idleSpeed: 0.5
				}));
			});
		}
		sparkRow(H * 0.14, 'normal');
		sparkRow(H * 0.30, 'add');
		sparkRow(H * 0.50, 'multiply');
		sparkRow(H * 0.68, 'screen');

		// --- Flash row: tap a ship, watch the silhouette overlay fade -----

		var FLASHES = [
			{ color: '#fff', duration: 300 },    // classic white damage hit
			{ color: '#ff5252', duration: 600 }, // longer red burn
			{ color: '#ffd54a', duration: 250 }  // gold blip (auto-blinks too)
		];
		var ships = FLASHES.map(function (config, index) {
			var ship = Game.createSprite({
				sheet: shipSheet,
				x: W * (0.25 + index * 0.25),
				y: H * 0.88,
				width: SHIP,
				height: SHIP,
				zIndex: 10
			});
			ship.addEventListener('tap', function () {
				ship.flash(config.color, config.duration);
			});
			gameView.add(ship);
			return ship;
		});

		// Invincibility-style auto-blink on the right ship; the fade
		// itself runs in the engine, JS just retriggers it
		blinkTimer = setInterval(function () {
			ships[2].flash(FLASHES[2].color, FLASHES[2].duration);
		}, 800);

		// --- Row labels ---------------------------------------------------

		function label(text, topPercent) {
			win.add(Ti.UI.createLabel({
				text: text,
				color: '#aab',
				font: { fontSize: 16 },
				shadowColor: '#000',
				shadowOffset: { x: 0, y: 1 },
				top: topPercent + '%'
			}));
		}
		label("blend: 'normal' — overlaps cover", 4);
		label("blend: 'add' — overlaps bloom", 20);
		label("blend: 'multiply' — darkens the backdrop", 41);
		label("blend: 'screen' — soft lighten, no blowout", 59);
		label('tap a ship to flash(color, duration)', 78);
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
