// ti.game trigger zones demo — the collision enter/exit lifecycle.
//
// `collision` fires once when an overlap begins, `collisionend` once when
// it ends — the Unity/Godot trigger pattern (there is deliberately no
// per-frame "stay" event; JS holds the in-between state itself).
//
// - WATER: drag the hero in and out of the pool — he tints blue on
//   `collision` and dries off on `collisionend`; the status label tracks
//   the state without any polling
// - PRESSURE PLATE: the plate listens with collidesWith: ['ball'] and
//   holds a door open exactly while something rests on it — drag the
//   ball onto the plate (door slides up), drag it away (door slides
//   back). Resting on the plate fires nothing extra: enter once, exit
//   once.
// - [ REMOVE BALL ]: deletes the ball WHILE it sits on the plate —
//   removing a contact partner counts as separation, so the plate still
//   gets its `collisionend` and the door closes instead of sticking open
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#1a2028'
	});

	var heroSheet = Game.createSpriteSheet({ image: 'assets/adventurer.png', frameWidth: 32, frameHeight: 48, smoothing: false });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var UNIT = Math.max(1, Math.round(W / 380));

		gameView.add(Game.createText({
			text: 'COLLISION ENTER / EXIT',
			x: W / 2, y: H * 0.05,
			scale: UNIT * 1.2,
			tintColor: '#ffd54a',
			zIndex: 20
		}));

		var lastEvent = Game.createText({
			text: 'drag the hero and the ball',
			x: W / 2, y: H * 0.95,
			scale: UNIT,
			tintColor: '#8a94b8',
			zIndex: 20
		});
		gameView.add(lastEvent);

		function log(message) {
			lastEvent.text = message;
			lastEvent.flash('#fff', 200);
		}

		// --- WATER: tint while inside, revert on exit --------------------

		var pool = Game.createSprite({
			sheet: wallSheet,
			x: W * 0.32, y: H * 0.3,
			width: W * 0.44, height: H * 0.18,
			tintColor: '#3d6fd4',
			opacity: 0.35,
			touchEnabled: false,   // drags pass through to the hero
			collisionGroup: 'water',
			zIndex: 2
		});
		var waterStatus = Game.createText({
			text: 'ON DRY LAND',
			x: W * 0.32, y: H * 0.16,
			scale: UNIT,
			tintColor: '#9adcff',
			zIndex: 20
		});
		var hero = Game.createSprite({
			sheet: heroSheet, frame: 0,
			x: W * 0.75, y: H * 0.3,
			width: W * 0.12, height: W * 0.18,
			draggable: true,
			collidesWith: ['water'],
			zIndex: 10
		});
		hero.addEventListener('collision', function (e) {
			if (e.group === 'water') {
				hero.tintColor = '#7fb2ff';
				waterStatus.text = 'IN THE WATER';
				log('collision - hero in water');
			}
		});
		hero.addEventListener('collisionend', function (e) {
			if (e.group === 'water') {
				hero.tintColor = null;
				waterStatus.text = 'ON DRY LAND';
				log('collisionend - hero left water');
			}
		});
		gameView.add([pool, waterStatus, hero]);

		// --- PRESSURE PLATE: door open exactly while occupied ------------

		var DOOR_H = H * 0.2;
		var doorClosedY = H * 0.62;
		var plate = Game.createSprite({
			sheet: wallSheet,
			x: W * 0.3, y: H * 0.72,
			width: W * 0.2, height: 14,
			tintColor: '#7a6a4a',
			touchEnabled: false,
			collidesWith: ['ball']   // the PLATE is the listener here
		});
		var door = Game.createSprite({
			sheet: wallSheet,
			x: W * 0.78, y: doorClosedY,
			width: 18, height: DOOR_H,
			tintColor: '#b85c5c',
			zIndex: 5
		});
		var plateStatus = Game.createText({
			text: 'DOOR CLOSED',
			x: W * 0.3, y: H * 0.62,
			scale: UNIT,
			tintColor: '#ffb2a8',
			zIndex: 20
		});
		plate.addEventListener('collision', function () {
			door.clearTweens();
			door.animate({ y: doorClosedY - DOOR_H, duration: 350, easing: Game.EASE_OUT });
			plateStatus.text = 'DOOR OPEN';
			log('collision - door opens');
		});
		plate.addEventListener('collisionend', function () {
			door.clearTweens();
			door.animate({ y: doorClosedY, duration: 350, easing: Game.EASE_IN });
			plateStatus.text = 'DOOR CLOSED';
			log('collisionend - door closes');
		});
		var ball = Game.createSprite({
			sheet: ballSheet,
			x: W * 0.7, y: H * 0.82,
			width: W * 0.1, height: W * 0.1,
			hitboxShape: 'circle',
			draggable: true,
			collisionGroup: 'ball',
			zIndex: 10
		});
		gameView.add([plate, door, plateStatus, ball]);

		// --- removing a partner mid-contact still fires collisionend -----

		var ballInScene = true;
		var removeButton = Game.createText({
			text: '[ REMOVE BALL ]',
			x: W * 0.7, y: H * 0.9,
			scale: UNIT,
			tintColor: '#8ab4ff',
			zIndex: 20
		});
		removeButton.addEventListener('tap', function () {
			removeButton.flash('#fff', 150);
			if (ballInScene) {
				// if the ball sits on the plate, the plate hears
				// collisionend and the door closes — no stuck door
				gameView.remove(ball);
				removeButton.text = '[ RESPAWN BALL ]';
			} else {
				ball.x = W * 0.7;
				ball.y = H * 0.82;
				gameView.add(ball);
				removeButton.text = '[ REMOVE BALL ]';
			}
			ballInScene = !ballInScene;
		});
		gameView.add(removeButton);
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
