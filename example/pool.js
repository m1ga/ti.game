// ti.game pool demo — what bilateral circle solids are for.
//
// Sixteen balls on a felt table. The cue ball and the fifteen object balls
// are all `hitboxShape: 'circle'` with `solidMode: 'push'` and they list
// each other's group, so the engine resolves each pair once: half the
// separation to each body, and the closing part of the relative velocity
// exchanged at equal mass. With `restitution` near 1 that is a straight
// swap of the normal components, which is exactly what an opening break
// looks like. Tangential speed is untouched, so cut shots leave at the
// angle the geometry says they should.
//
// The rails are ordinary rectangular solids (`solidMode: 'block'`, the
// default), so they still behave as immovable walls. The pockets are
// circular trigger zones read through `collidesWith`, not solids.
//
// `linearDamping` is the felt: a fraction of the speed shed every second,
// so a fast ball loses a lot and a slow one very little. That is what a
// ball trickling to a halt looks like. A constant deceleration was tried
// here and it stops the slow ones dead, all at once, which reads as wrong.
//
// There is no gate at all: tap whenever you like. A strike is an impulse,
// so it ADDS to whatever the cue is already carrying — catch it mid-roll
// and you bend its path rather than teleporting it onto a new one, which
// is both more useful and closer to what a cue actually does.
//
// Tap the table to shoot: the cue leaves toward the tap, and the further
// out you tap the harder it goes. Exports a start function; the demo opens
// its own window.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		extendSafeArea: false,   // keep content clear of the notch and home bar
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#071a12',
		maxFps: 60
	});

	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64, smoothing: false });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var tableSheet = Game.createSpriteSheet({ image: 'assets/puzzle.png', frameWidth: 64, frameHeight: 64 });
	var wallSheet = Game.createSpriteSheet({
		image: 'assets/wall.png',
		frameWidth: 32,
		frameHeight: 32,
		repeat: true,
		smoothing: false
	});

	var strikeSound = Game.createSound({ url: 'assets/crash.wav', volume: 0.22 });
	var pocketSound = Game.createSound({ url: 'assets/good.wav', volume: 0.6 });
	var scratchSound = Game.createSound({ url: 'assets/bad.wav', volume: 0.55 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var UNIT = Math.max(1, Math.round(W / 380));
		var RAIL = Math.max(12, Math.round(W * 0.035));
		var TABLE_MARGIN = Math.max(12, Math.round(W * 0.045));
		var TOP = H * 0.19;
		var BOTTOM = H * 0.84;
		var BALL = Math.max(16, Math.round(W * 0.058));
		var POCKET = BALL * 1.15;
		var FELT = {
			left: TABLE_MARGIN + RAIL,
			right: W - TABLE_MARGIN - RAIL,
			top: TOP + RAIL,
			bottom: BOTTOM - RAIL
		};
		var scene = [];

		var COLORS = [
			'#e9c94c', '#3f74c9', '#cc4b45', '#7953ad', '#de7d35',
			'#3a9765', '#944b34', '#25282d', '#e9c94c', '#3f74c9',
			'#cc4b45', '#7953ad', '#de7d35', '#3a9765', '#944b34'
		];

		scene.push(Game.createText({
			text: 'POOL LAB',
			x: W / 2, y: H * 0.05,
			scale: Math.max(2, UNIT + 1),
			tintColor: '#f2d47a',
			zIndex: 20
		}));
		scene.push(Game.createText({
			text: 'PUSH SOLIDS + LINEAR DAMPING',
			x: W / 2, y: H * 0.105,
			scale: UNIT,
			tintColor: '#7fae98',
			zIndex: 20
		}));

		var balls = [];
		var potted = 0;
		var feedbackTimer = 0;
		var DEFAULT_STATUS = 'TAP THE FELT TO BREAK';
		var hud = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.145,
			scale: UNIT,
			tintColor: '#e5eee9',
			zIndex: 20
		});
		var status = Game.createText({
			text: DEFAULT_STATUS,
			align: 'center',
			x: W / 2, y: H * 0.89,
			scale: UNIT,
			tintColor: '#f2d47a',
			zIndex: 20
		});
		var hint = Game.createText({
			text: 'DISTANCE SETS POWER\nSTRIKES ADD TO CURRENT MOTION',
			align: 'center',
			x: W / 2, y: H * 0.95,
			scale: UNIT,
			tintColor: '#7fae98',
			zIndex: 20
		});

		function updateHud() {
			hud.text = 'POTTED ' + potted + ' / 15';
		}

		function showFeedback(text, color, duration) {
			status.text = text;
			status.tintColor = color;
			if (feedbackTimer) {
				gameView.cancelTimer(feedbackTimer);
			}
			feedbackTimer = gameView.after(duration, function () {
				feedbackTimer = 0;
				status.text = DEFAULT_STATUS;
				status.tintColor = '#f2d47a';
			});
		}

		updateHud();
		scene.push(hud, status, hint);

		// A dark underlay and a rounded, tinted panel separate the table from
		// the HUD without adding a stack of borders or overlay views.
		scene.push(Game.createSprite({
			sheet: tableSheet,
			frame: 4,
			x: W / 2, y: (TOP + BOTTOM) / 2 + UNIT * 3,
			width: W - TABLE_MARGIN * 1.25,
			height: BOTTOM - TOP + RAIL,
			tintColor: '#020705',
			opacity: 0.7,
			touchEnabled: false,
			zIndex: 0
		}));
		scene.push(Game.createSprite({
			sheet: tableSheet,
			frame: 4,
			x: W / 2, y: (FELT.top + FELT.bottom) / 2,
			width: FELT.right - FELT.left + RAIL,
			height: FELT.bottom - FELT.top + RAIL,
			tintColor: '#126142',
			touchEnabled: false,
			zIndex: 1
		}));

		// --- Rails: ordinary rectangular solids, immovable ----------------

		[
			{ x: W / 2, y: TOP + RAIL / 2, w: W - TABLE_MARGIN * 2, h: RAIL },
			{ x: W / 2, y: BOTTOM - RAIL / 2, w: W - TABLE_MARGIN * 2, h: RAIL },
			{ x: TABLE_MARGIN + RAIL / 2, y: (TOP + BOTTOM) / 2, w: RAIL, h: BOTTOM - TOP },
			{ x: W - TABLE_MARGIN - RAIL / 2, y: (TOP + BOTTOM) / 2, w: RAIL, h: BOTTOM - TOP }
		].forEach(function (rail) {
			scene.push(Game.createSprite({
				sheet: wallSheet,
				x: rail.x, y: rail.y,
				width: rail.w, height: rail.h,
				tileRepeat: true,
				tintColor: '#754329',
				touchEnabled: false,   // taps belong to the view, not the table
				collisionGroup: 'rail',
				zIndex: 3
			}));
		});

		// Small rail sights make the play surface easier to read at a glance.
		[0.25, 0.5, 0.75].forEach(function (position) {
			var x = FELT.left + (FELT.right - FELT.left) * position;
			[TOP + RAIL / 2, BOTTOM - RAIL / 2].forEach(function (y) {
				scene.push(Game.createSprite({
					sheet: ballSheet,
					x: x, y: y,
					width: UNIT * 4, height: UNIT * 4,
					tintColor: '#e6c16d',
					touchEnabled: false,
					zIndex: 4
				}));
			});
		});

		// --- Pockets: circular trigger zones, not solids -------------------

		// Four in the corners and one at the middle of each LONG rail. The
		// table stands on end here, so the long rails are the left and right
		// ones — the middle pockets belong on the sides, not on the ends.
		var midY = (FELT.top + FELT.bottom) / 2;
		var midX = (FELT.left + FELT.right) / 2;
		var cueSpotY = FELT.top + (FELT.bottom - FELT.top) * 0.76;
		[
			{ x: FELT.left, y: FELT.top }, { x: FELT.right, y: FELT.top },
			{ x: FELT.left, y: midY }, { x: FELT.right, y: midY },
			{ x: FELT.left, y: FELT.bottom }, { x: FELT.right, y: FELT.bottom }
		].forEach(function (p) {
			scene.push(Game.createSprite({
				sheet: ballSheet,
				x: p.x, y: p.y,
				width: POCKET * 2, height: POCKET * 2,
				tintColor: '#020705',
				hitboxShape: 'circle',
				hitboxScale: 0.45,
				touchEnabled: false,
				collisionGroup: 'pocket',
				zIndex: 5
			}));
		});

		// --- Balls ---------------------------------------------------------

		function makeBall(x, y, color, isCue) {
			var ball = Game.createSprite({
				sheet: ballSheet,
				x: x, y: y,
				width: BALL, height: BALL,
				tintColor: color,
				hitboxShape: 'circle',
				// ball.png draws its circle out to 0.90 of the frame, not to the edge.
				hitboxScale: 0.9,
				restitution: 0.96,
				linearDamping: 0.62,     // felt: the ball trickles to a halt
				swept: true,             // no tunnelling through a thin rail
				collisionGroup: 'ball',
				solidWith: ['ball', 'rail'],
				solidMode: 'push',       // a body, not a wall
				collidesWith: ['pocket'],
				touchEnabled: false,
				zIndex: isCue ? 12 : 10
			});
			ball.addEventListener('collision', function () {
				if (isCue) {
					// scratch: spot the cue back on the head string
					ball.velocityX = 0;
					ball.velocityY = 0;
					ball.x = midX;
					ball.y = cueSpotY;
					ball.flash('#ff5252', 300);
					scratchSound.play();
					showFeedback('SCRATCH - CUE RESPOTTED', '#ef7c72', 1400);
					return;
				}
				gameView.remove(ball);
				var index = balls.indexOf(ball);
				if (index >= 0) {
					balls.splice(index, 1);
				}
				potted++;
				pocketSound.play();
				showFeedback('NICE POCKET', '#82d6a9', 1100);
				updateHud();
			});
			scene.push(ball);
			balls.push(ball);
			return ball;
		}

		var cue = makeBall(midX, cueSpotY, '#f7f1df', true);

		// Rack: five rows at the top of the portrait table, with the apex
		// pointing down toward the cue ball. The spacing
		// is a fraction of the DRAWN diameter (0.9 of the frame), which is
		// what the eye reads as touching; against the frame it looked loose.
		var apexY = FELT.top + (FELT.bottom - FELT.top) * 0.36;
		var gap = BALL * 0.9 * 1.02;
		var next = 0;
		for (var row = 0; row < 5; row++) {
			for (var seat = 0; seat <= row; seat++) {
				makeBall(
					midX + (seat - row / 2) * gap,
					apexY - row * gap * 0.88,
					COLORS[next % COLORS.length],
					false
				);
				next++;
			}
		}

		var aimMarker = Game.createSprite({
			sheet: sparkSheet,
			frame: 1,
			x: W / 2, y: midY,
			width: BALL * 0.8, height: BALL * 0.8,
			tintColor: '#f2d47a',
			opacity: 0,
			visible: false,
			touchEnabled: false,
			zIndex: 14
		});
		aimMarker.addEventListener('complete', function () {
			aimMarker.visible = false;
		});
		scene.push(aimMarker);

		// Commit the complete table in one bridge crossing.
		gameView.add(scene);

		// --- Aiming: tap to shoot ---------------------------------------------
		//
		// Direction is cue -> tap; power is how far out you tapped, capped.
		// Nothing has to be still first — not the object balls, not the cue.

		var MAX_REACH = W * 0.55;
		var MAX_SPEED = 2600;

		gameView.addEventListener('tap', function (e) {
			var dx = e.x - cue.x;
			var dy = e.y - cue.y;
			var reach = Math.sqrt(dx * dx + dy * dy);
			if (reach < BALL) {
				showFeedback('TAP AWAY FROM THE CUE TO AIM', '#a9c7b9', 1100);
				return; // tapped the cue itself
			}
			var speed = MAX_SPEED * Math.min(1, reach / MAX_REACH);
			// Added, not assigned: a strike is an impulse on top of the
			// momentum the ball already has
			cue.velocityX += (dx / reach) * speed;
			cue.velocityY += (dy / reach) * speed;
			cue.flash('#ffffff', 120);
			strikeSound.play();
			showFeedback('POWER ' + Math.round(speed / MAX_SPEED * 100) + '% - IMPULSE ADDED', '#f2d47a', 900);

			aimMarker.clearTweens();
			aimMarker.x = e.x;
			aimMarker.y = e.y;
			aimMarker.scale = 0.6;
			aimMarker.opacity = 0.9;
			aimMarker.visible = true;
			aimMarker.animate({
				scale: 1.5,
				opacity: 0,
				duration: 220,
				easing: Game.EASE_OUT
			});
		});
	}

	win.add(gameView);
	// Back — return to the launcher
	var backButton = Ti.UI.createLabel({
		text: '‹  EXAMPLES',
		top: Ti.Platform.osname === 'android' ? 10 : 40,
		left: 12,
		width: 96,
		height: 38,
		color: '#e5eee9',
		backgroundColor: '#172a21',
		borderColor: '#456555',
		borderWidth: 1,
		borderRadius: 19,
		font: { fontSize: 12, fontWeight: 'bold' },
		textAlign: 'center',
		zIndex: 100
	});
	backButton.addEventListener('touchstart', function () { backButton.backgroundColor = '#274538'; });
	backButton.addEventListener('touchend', function () { backButton.backgroundColor = '#172a21'; });
	backButton.addEventListener('touchcancel', function () { backButton.backgroundColor = '#172a21'; });
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);
	win.addEventListener('close', function () {
		strikeSound.stop();
		pocketSound.stop();
		scratchSound.stop();
		gameView.pause();
		gameView.removeAllSprites();
	});
	win.open();
};
