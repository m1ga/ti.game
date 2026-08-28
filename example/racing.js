// ti.game racing demo — pixel top-down racer with drifting.
//
// - ◀ / ▶ steer, GAS / BRK pedals (multitouch: steer while accelerating)
// - native car physics (carMode): the engine splits velocity into forward
//   and lateral components; lateral grip is finite, so cornering fast
//   leaves sideways momentum — the drift
// - drive counter-clockwise: pass all 3 checkpoints, then cross the
//   checkered goal line to count a lap
// - pixel look: car.png and track.png are drawn as pixel art and rendered
//   with smoothing: false (GL_NEAREST)
//
// The track is built on the game view's `resize` event using the real GL
// surface size. The wall/checkpoint fractions match the track.png artwork.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#4e8846'
		// debug: true                              // collision shapes for every sprite
		// debug: { hitbox: true, hud: 'topRight' }  // ...plus the performance HUD
	});

	// HUD as a GL text sprite (built-in pixel font) — screenFixed keeps it
	// glued to the surface; positioned once the surface size is known
	var lapLabel = Game.createText({ text: 'Lap 0 - CP 0/3', screenFixed: true, zIndex: 100 });

	var trackSheet = Game.createSpriteSheet({ image: 'assets/track.png', frameWidth: 256, frameHeight: 256, smoothing: false });
	var carSheet = Game.createSpriteSheet({ image: 'assets/car.png', frameWidth: 64, frameHeight: 64, smoothing: false });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		lapLabel.scale = Math.max(1, Math.round(W / 260));
		lapLabel.x = W / 2;
		lapLabel.y = H * 0.07;
		gameView.add(lapLabel);

		// Keep the track above the on-screen controls
		// Scene units per dp: measure the real surface scale instead of
		// trusting logicalDensityFactor — the iOS simulator renders at 1x
		// while the density factor still reports the device scale
		var density = Ti.Platform.osname === 'android'
			? Ti.Platform.displayCaps.logicalDensityFactor
			: H / Ti.Platform.displayCaps.platformHeight;
		var buttonZone = Math.round(130 * density);
		var TH = H - buttonZone; // track region height

		// Fractions shared with the track.png artwork
		var OUTER = 0.05;              // outer edge of the asphalt
		var ISLAND_X0 = 0.30, ISLAND_X1 = 0.70;
		var ISLAND_Y0 = 0.33, ISLAND_Y1 = 0.67;

		var CAR_SIZE = Math.round(Math.min(W * 0.25, TH * 0.28) * 0.42);
		var MAX_SPEED = Math.min(W, TH) * 0.8;

		// --- Track image -------------------------------------------------

		gameView.add(Game.createSprite({
			sheet: trackSheet,
			x: W / 2,
			y: TH / 2,
			width: W,
			height: TH,
			zIndex: 0
		}));

		// --- Walls (invisible): outer border + inner island --------------

		var walls = [
			{ x: W / 2, y: TH * OUTER / 2, w: W, h: TH * OUTER },                       // top
			{ x: W / 2, y: TH - TH * OUTER / 2, w: W, h: TH * OUTER },                  // bottom
			{ x: W * OUTER / 2, y: TH / 2, w: W * OUTER, h: TH },                       // left
			{ x: W - W * OUTER / 2, y: TH / 2, w: W * OUTER, h: TH },                   // right
			{                                                                            // island
				x: W * (ISLAND_X0 + ISLAND_X1) / 2,
				y: TH * (ISLAND_Y0 + ISLAND_Y1) / 2,
				w: W * (ISLAND_X1 - ISLAND_X0),
				h: TH * (ISLAND_Y1 - ISLAND_Y0)
			}
		];
		walls.forEach(function (wall) {
			gameView.add(Game.createSprite({
				x: wall.x, y: wall.y, width: wall.w, height: wall.h, collisionGroup: 'wall'
			}));
		});

		// --- Checkpoints + goal (invisible strips across each lane) ------

		var laneY = TH * (ISLAND_Y1 + 1 - OUTER) / 2; // center of the bottom lane
		var checkpoints = [
			{ x: W * (ISLAND_X1 + 1 - OUTER) / 2, y: TH / 2, w: W * (1 - OUTER - ISLAND_X1), h: 24 }, // right lane
			{ x: W / 2, y: TH * (OUTER + ISLAND_Y0) / 2, w: 24, h: TH * (ISLAND_Y0 - OUTER) },        // top lane
			{ x: W * (OUTER + ISLAND_X0) / 2, y: TH / 2, w: W * (ISLAND_X0 - OUTER), h: 24 }          // left lane
		];
		checkpoints.forEach(function (cp, index) {
			var zone = Game.createSprite({
				x: cp.x, y: cp.y, width: cp.w, height: cp.h, collisionGroup: 'checkpoint'
			});
			zone.cpIndex = index;
			gameView.add(zone);
		});

		gameView.add(Game.createSprite({
			x: W / 2,
			y: laneY,
			width: W * 0.05,
			height: TH * (1 - OUTER - ISLAND_Y1),
			collisionGroup: 'goal'
		}));

		// --- The car -----------------------------------------------------

		var car = Game.createSprite({
			sheet: carSheet,
			x: W * 0.38,
			y: laneY,
			width: CAR_SIZE,
			height: CAR_SIZE,
			pixelSnap: true,
			rotation: 90,            // facing right along the bottom straight
			zIndex: 10,
			hitboxScale: 0.75,
			carMode: true,
			enginePower: MAX_SPEED * 1.1,
			maxSpeed: MAX_SPEED,
			turnRate: 210,
			grip: 3.2,               // low lateral grip = drifts in fast corners
			drag: 0.8,
			skidMarks: true,         // rear tires leave fading marks while drifting
			restitution: 0.3,
			solidWith: ['wall'],
			collidesWith: ['checkpoint', 'goal']
		});
		gameView.add(car);

		// --- Laps --------------------------------------------------------

		var laps = 0;
		var visited = {};

		function visitedCount() {
			return Object.keys(visited).length;
		}

		function updateLabel() {
			lapLabel.text = 'Lap ' + laps + ' - CP ' + visitedCount() + '/3';
		}

		car.addEventListener('collision', function (e) {
			if (e.group === 'checkpoint') {
				visited[e.other.cpIndex] = true;
				updateLabel();
			} else if (e.group === 'goal') {
				if (visitedCount() === 3) {
					laps++;
					visited = {};
					updateLabel();
				}
			}
		});

		// --- Controls: steering left, pedals right -----------------------

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
		var brakeButton = makeButton('BRK', { right: '112dp' }, 20);
		var gasButton = makeButton('GAS', { right: '24dp' }, 20);

		bindHold(leftButton, function () {
			car.steering = -1;
		}, function () {
			if (car.steering === -1) {
				car.steering = 0;
			}
		});
		bindHold(rightButton, function () {
			car.steering = 1;
		}, function () {
			if (car.steering === 1) {
				car.steering = 0;
			}
		});
		bindHold(gasButton, function () {
			car.throttle = 1;
		}, function () {
			if (car.throttle === 1) {
				car.throttle = 0;
			}
		});
		bindHold(brakeButton, function () {
			car.throttle = -1;
		}, function () {
			if (car.throttle === -1) {
				car.throttle = 0;
			}
		});

		win.add(leftButton);
		win.add(rightButton);
		win.add(brakeButton);
		win.add(gasButton);
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
