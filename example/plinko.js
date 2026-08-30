// ti.game Plinko demo — a wall of circular solids, which is the whole point.
//
// Eighty-six round pegs in a staggered grid. Every one of them is an
// ordinary sprite with `hitboxShape: 'circle'`, so a ball meeting a peg is
// resolved along the line between their centers: it comes off the shoulder
// of the peg at the angle the geometry gives, and which side it takes is
// decided by fractions of a pixel. That is the entire game. Resolved as
// bounding boxes instead, every peg would be a square with a flat top, and
// balls would stack up on them rather than scatter.
//
// `swept: true` matters here too. A ball picks up real speed down a tall
// board, and the pegs are small; without path testing it would step over
// one between frames and sail through the middle of the grid.
//
// The chips are solid to each other too, in `solidMode: 'push'`, so a pile
// forming in one channel shoves back instead of letting the next chip pass
// straight through it.
//
// Each chip listens for `solidimpact`. Peg, wall and divider contacts are
// reported once from the chip side; chip-to-chip contacts use a stable pair
// index so the two sides of the same physical hit do not play twice. A short
// cadence keeps a crowded board crisp instead of turning it into audio noise.
//
// The slots are trigger zones read through `collidesWith`, not solids, and
// the dividers between them are plain rects. A board tap chooses the drop
// point; the controls can also release one or ten chips across random points.
// The brightest center slot carries the top payout.
//
// Exports a start function; the demo opens its own window.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		extendSafeArea: false,   // keep content clear of the notch and home bar
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#160f2d',
		maxFps: 60
	});

	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var wallSheet = Game.createSpriteSheet({ image: 'assets/wall.png', frameWidth: 32, frameHeight: 32 });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var winSound = Game.createSound({ url: 'assets/good.wav', volume: 0.65 });
	var missSound = Game.createSound({ url: 'assets/bad.wav', volume: 0.45 });
	var impactSound = Game.createSound({ url: 'assets/plinko_click.wav', volume: 0.18 });
	var IMPACT_GAP = 35;
	var impactAt = 0;

	function playImpact(speed) {
		var now = Date.now();
		if (now - impactAt < IMPACT_GAP) {
			return;
		}
		impactAt = now;
		impactSound.volume = Math.max(0.08, Math.min(0.34, 0.08 + speed / 2200));
		impactSound.play();
	}

	win.addEventListener('close', function () {
		winSound.stop();
		missSound.stop();
		impactSound.stop();
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var UNIT = Math.max(1, Math.round(W / 380));
		var PAYOUTS = [100, 500, 1000, 0, 10000, 0, 1000, 500, 100];
		var SLOTS = PAYOUTS.length;

		var BOARD_L = W * 0.04;
		var BOARD_R = W * 0.96;
		var BOARD_W = BOARD_R - BOARD_L;
		var SLOT_W = BOARD_W / SLOTS;
		var TOP = H * 0.17;
		var SLOT_TOP = H * 0.80;
		var SLOT_BOTTOM = H * 0.90;

		var PEG = Math.max(5, Math.round(SLOT_W * 0.28));   // peg diameter
		var BALL = Math.max(9, Math.round(SLOT_W * 0.46));
		var ROWS = 9;
		var ROW_GAP = (SLOT_TOP - TOP) / (ROWS + 1);

		gameView.add(Game.createSprite({
			sheet: sparkSheet, frame: 0,
			x: W / 2, y: H * 0.47,
			width: W * 1.25, height: H * 0.76,
			tintColor: '#503879', opacity: 0.14,
			blend: 'screen', touchEnabled: false, zIndex: 0
		}));
		gameView.add(Game.createSprite({
			sheet: sparkSheet, frame: 0,
			x: W / 2, y: TOP - BALL * 0.55,
			width: BOARD_W * 0.92, height: BALL * 2.4,
			tintColor: '#8ab4ff', opacity: 0.12,
			blend: 'screen', touchEnabled: false, zIndex: 1
		}));

		gameView.add(Game.createText({
			text: 'PLINKO',
			x: W / 2, y: H * 0.055,
			scale: UNIT * 1.4,
			letterSpacing: UNIT * 2,
			tintColor: '#f6c85f',
			zIndex: 20
		}));
		var subtitle = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.105,
			scale: UNIT * 0.75,
			tintColor: '#a99bc9',
			zIndex: 20
		});
		gameView.add(subtitle);

		var CONTROL_Y = H * 0.145;
		var CONTROL_HALF_W = W * 0.16;
		var CONTROL_HALF_H = Math.max(22, H * 0.025);
		var dropOneButton = Game.createText({
			text: '[ DROP 1 ]',
			align: 'center',
			x: W * 0.32, y: CONTROL_Y,
			scale: UNIT * 0.9,
			tintColor: '#8ab4ff',
			touchEnabled: false,
			zIndex: 20
		});
		var dropTenButton = Game.createText({
			text: '[ DROP 10 ]',
			align: 'center',
			x: W * 0.68, y: CONTROL_Y,
			scale: UNIT * 0.9,
			tintColor: '#69f0ae',
			touchEnabled: false,
			zIndex: 20
		});
		gameView.add([dropOneButton, dropTenButton]);

		// --- Side walls ------------------------------------------------------

		[BOARD_L - SLOT_W * 0.25, BOARD_R + SLOT_W * 0.25].forEach(function (wallX) {
			gameView.add(Game.createSprite({
				sheet: wallSheet,
				x: wallX, y: (TOP + SLOT_TOP) / 2,
				width: SLOT_W * 0.3, height: SLOT_TOP - TOP,
				tintColor: '#6a4fa3',
				touchEnabled: false,
				collisionGroup: 'peg',
				zIndex: 4
			}));
		});

		// --- The pegs --------------------------------------------------------
		//
		// Staggered: even rows sit on the slot boundaries, odd rows on the slot
		// centers, so a ball leaving one peg always meets the next row offset
		// by half a step. That is what makes the path a random walk instead of
		// a straight drop.

		var pegs = [];
		for (var row = 0; row < ROWS; row++) {
			var odd = (row % 2) === 1;
			var count = odd ? SLOTS : SLOTS + 1;
			var startX = odd ? BOARD_L + SLOT_W / 2 : BOARD_L;
			for (var i = 0; i < count; i++) {
				pegs.push(Game.createSprite({
					sheet: ballSheet,
					x: startX + i * SLOT_W,
					y: TOP + ROW_GAP * (row + 1),
					width: PEG, height: PEG,
					tintColor: row === Math.floor(ROWS / 2) ? '#f6c85f'
						: odd ? '#9a82e8' : '#7ea2f8',
					hitboxShape: 'circle',
					hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
					touchEnabled: false,
					collisionGroup: 'peg',
					zIndex: 6
				}));
			}
		}
		gameView.add(pegs);
		// counted, not written down, so the caption cannot drift from the board
		subtitle.text = pegs.length + ' ROUND SOLIDS + SOLIDIMPACT\nTAP BOARD OR USE CONTROLS';

		// --- Slots: dividers are solid, the pockets are trigger zones --------

		var labels = [];
		for (var sIdx = 0; sIdx < SLOTS; sIdx++) {
			var cx = BOARD_L + SLOT_W * (sIdx + 0.5);

			if (sIdx > 0) {
				gameView.add(Game.createSprite({
					sheet: wallSheet,
					x: BOARD_L + SLOT_W * sIdx, y: (SLOT_TOP + SLOT_BOTTOM) / 2,
					width: Math.max(3, SLOT_W * 0.08), height: SLOT_BOTTOM - SLOT_TOP,
					tintColor: '#b56ac7',
					touchEnabled: false,
					collisionGroup: 'peg',
					zIndex: 6
				}));
			}

			// A thin strip right at the floor of the channel. Overlap begins
			// when the ball's EDGE reaches the strip's edge, so a tall zone
			// swallows the ball while it is still visibly falling — this one
			// is 12 px so the ball is all the way down before it counts. The
			// balls are swept, so a thin zone cannot be tunnelled through.
			gameView.add(Game.createSprite({
				x: cx, y: SLOT_BOTTOM - 6,
				width: SLOT_W * 0.85, height: 12,
				touchEnabled: false,
				collisionGroup: 'slot' + sIdx,
				zIndex: 3
			}));

			var payout = PAYOUTS[sIdx];
			labels.push(Game.createText({
				text: payout === 10000 ? '10K' : String(payout),
				align: 'center',
				x: cx, y: H * 0.925,
				scale: UNIT * (SLOTS > 7 ? 0.6 : 0.8),
				tintColor: payout >= 10000 ? '#f6c85f' : payout >= 1000 ? '#69f0ae' : payout > 0 ? '#8ab4ff' : '#675979',
				zIndex: 20
			}));
		}
		gameView.add(labels);

		// --- Score -----------------------------------------------------------

		var score = 0;
		var dropped = 0;
		var scoreText = Game.createText({
			text: '',
			align: 'center',
			x: W / 2, y: H * 0.965,
			scale: UNIT,
			zIndex: 20
		});
		function updateScore() {
			scoreText.text = 'DROPPED ' + dropped + '   /   SCORE ' + score;
		}
		updateScore();
		gameView.add(scoreText);

		// --- Dropping ---------------------------------------------------------

		// Keep the circle-vs-circle contacts readable instead of filling the
		// board with bodies. Twelve fits one DROP 10 batch plus two single drops.
		var MAX_LIVE = 12;
		var live = [];
		var COLORS = ['#ff8a80', '#ffd54a', '#69f0ae', '#8ab4ff', '#e86ea8', '#e07a2b'];

		function retire(ball) {
			var i = live.indexOf(ball);
			if (i >= 0) {
				live.splice(i, 1);
				gameView.remove(ball);
			}
		}

		function dropAt(x) {
			var lo = BOARD_L + BALL;
			var hi = BOARD_R - BALL;
			// A perfectly centered drop is a perfectly valid equilibrium: on this
			// nine-slot board W/2 lines up with the middle peg of the second row,
			// so a motionless chip can balance there forever. Real boards never
			// get that mathematical symmetry. Add a tiny alternating bias so an
			// exact-center tap still reaches a shoulder without favoring one side.
			var bias = (dropped % 2 === 0 ? -1 : 1) * PEG * 0.18;
			var dropX = Math.min(Math.max(x + bias, lo), hi);
			var ball = Game.createSprite({
				sheet: ballSheet,
				x: dropX, y: TOP - BALL,
				width: BALL, height: BALL,
				tintColor: COLORS[dropped % COLORS.length],
				hitboxShape: 'circle',
				hitboxScale: 0.9,   // ball.png draws to 0.90 of its frame, not to the edge
				gravity: 1100,
				velocityX: bias * 4,
				restitution: 0.42,
				impactThreshold: 55,
				swept: true,          // small pegs, fast ball: no stepping over one
				touchEnabled: false,
				// Chips are solid to each other as well as to the pegs, and
				// `push` makes that pairing bilateral: they split the
				// separation and trade the closing velocity instead of one
				// shoving the other aside. Without it they slide through one
				// another, which is the one thing a real board never does.
				collisionGroup: 'chip',
				solidWith: ['peg', 'chip'],
				solidMode: 'push',
				collidesWith: ['slot0', 'slot1', 'slot2', 'slot3', 'slot4',
					'slot5', 'slot6', 'slot7', 'slot8'],
				zIndex: 10
			});
			ball.impactId = dropped;
			ball.addEventListener('solidimpact', function (e) {
				if (e.group === 'chip') {
					var otherId = e.other && e.other.impactId;
					if (typeof otherId === 'number' && ball.impactId > otherId) {
						return;   // the other chip of this pair is speaking
					}
				} else if (e.group !== 'peg') {
					return;
				}
				playImpact(e.speed);
			});
			ball.addEventListener('collision', function (e) {
				var idx = parseInt(e.group.substring(4), 10);
				if (isNaN(idx)) {
					return;
				}
				score += PAYOUTS[idx];
				if (PAYOUTS[idx] === 0) {
					missSound.play();
					labels[idx].flash('#ff8a80', 280);
				} else {
					winSound.play();
					labels[idx].flash(PAYOUTS[idx] >= 10000 ? '#fff' : '#f6c85f', 350);
					if (PAYOUTS[idx] >= 10000) {
						gameView.shake({ strength: 5, duration: 180 });
					}
				}
				updateScore();
				scoreText.flash(PAYOUTS[idx] === 0 ? '#ff8a80' : '#ffffff', 220);
				retire(ball);
			});
			live.push(ball);
			while (live.length > MAX_LIVE) {
				retire(live[0]);
			}
			gameView.add(ball);
			dropped++;
			updateScore();
		}

		function dropRandom(count) {
			count = Math.min(count, MAX_LIVE - live.length);
			if (count <= 0) {
				return;
			}
			var lo = BOARD_L + BALL;
			var hi = BOARD_R - BALL;
			var span = (hi - lo) / count;
			for (var i = 0; i < count; i++) {
				// Divide the board into bands so a ten-chip release still uses
				// random points without clustering every chip in the same place.
				dropAt(lo + span * (i + Math.random()));
			}
		}

		function hitsControl(e, control) {
			return Math.abs(e.x - control.x) <= CONTROL_HALF_W
				&& Math.abs(e.y - CONTROL_Y) <= CONTROL_HALF_H;
		}

		gameView.addEventListener('tap', function (e) {
			if (hitsControl(e, dropOneButton)) {
				dropOneButton.flash('#fff', 150);
				dropRandom(1);
				return;
			}
			if (hitsControl(e, dropTenButton)) {
				dropTenButton.flash('#fff', 150);
				dropRandom(10);
				return;
			}
			dropAt(e.x);
		});
		gameView.after(350, function () {
			dropAt(W / 2);
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
		color: '#e8dcff',
		backgroundColor: '#24183b',
		borderColor: '#594477',
		borderWidth: 1,
		borderRadius: 19,
		font: { fontSize: 12, fontWeight: 'bold' },
		textAlign: 'center',
		zIndex: 100
	});
	backButton.addEventListener('touchstart', function () { backButton.backgroundColor = '#3a2758'; });
	backButton.addEventListener('touchend', function () { backButton.backgroundColor = '#24183b'; });
	backButton.addEventListener('touchcancel', function () { backButton.backgroundColor = '#24183b'; });
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);
	win.open();
};
