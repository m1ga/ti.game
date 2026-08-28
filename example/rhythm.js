// ti.game rhythm demo — a Dance-Dance-Revolution-style note catcher.
//
// - colored gems fall down 3 lanes (random lane, spawned every 400 ms —
//   an eighth note of the 150 BPM chiptune track playing underneath)
// - press the target ring at the bottom of a lane when its gem arrives:
//   a tinted particle burst removes the gem, and the sound depends on
//   your timing — a bright arpeggio when the gem is in range ("PERFECT"
//   inside the tight window), a sour buzz when you press with nothing
//   close; gems that slip past the rings count as a MISS
// - pads use the `press` event (fires on finger down — a rhythm game
//   can't wait for the release), and each pad is hit-tested natively
//
// Notes fall via native velocity; JS acts only on press events (reading
// a few note.y values per press) and a coarse spawn timer.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#1c1830'
	});

	var noteSheet = Game.createSpriteSheet({ image: 'assets/note.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var padSheet = Game.createSpriteSheet({ image: 'assets/pad.png', frameWidth: 48, frameHeight: 48, smoothing: false });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });

	var goodSound = Game.createSound({ url: 'assets/good.wav', volume: 0.9 });
	var badSound = Game.createSound({ url: 'assets/bad.wav', volume: 0.8 });
	var music = Game.createSound({ url: 'assets/music.wav', music: true, loop: true, volume: 0.4 });

	var spawnTimer = null;
	var statusTimer = null;
	win.addEventListener('close', function () {
		if (spawnTimer !== null) {
			clearInterval(spawnTimer);
			spawnTimer = null;
		}
		if (statusTimer !== null) {
			clearTimeout(statusTimer);
			statusTimer = null;
		}
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

		var LANES = [W * 0.22, W * 0.5, W * 0.78];
		var LANE_TINTS = ['#e04848', '#48c060', '#4890e0'];
		var NOTE = Math.round(W * 0.16);
		var PAD = Math.round(W * 0.22);
		var PAD_Y = H * 0.8;
		var HIT_RANGE = H * 0.08;      // press counts while a gem is this close
		var PERFECT = H * 0.03;
		var SPAWN_MS = 400;            // eighth note at the track's 150 BPM
		var FALL_SPEED = (PAD_Y + NOTE) / 1.6;  // spawn-to-pad in 4 eighths

		// --- Lanes: guide lines + target pads ----------------------------

		LANES.forEach(function (x) {
			gameView.add(Game.createSprite({
				sheet: sparkSheet, frame: 0,   // stretched soft dot = glow line
				x: x, y: H / 2, width: 4, height: H,
				opacity: 0.25, zIndex: 1, touchEnabled: false
			}));
		});

		var pads = LANES.map(function (x, lane) {
			var pad = Game.createSprite({
				sheet: padSheet,
				x: x,
				y: PAD_Y,
				width: PAD,
				height: PAD,
				zIndex: 5
			});
			pad.addEventListener('press', function () {
				hitLane(lane, pad);
			});
			gameView.add(pad);
			return pad;
		});

		// --- Falling notes (pooled) --------------------------------------

		var notes = [];
		for (var i = 0; i < 10; i++) {
			var sprite = Game.createSprite({
				sheet: noteSheet,
				x: LANES[0],
				y: -NOTE * 2,
				width: NOTE,
				height: NOTE,
				zIndex: 10,
				visible: false,
				touchEnabled: false,   // gems must not swallow pad presses
				collidesWith: ['misszone']
			});
			var entry = { sprite: sprite, lane: 0, active: false };
			(function (note) {
				note.sprite.addEventListener('collision', function () {
					if (note.active) {   // slipped past the pads
						recycle(note);
						combo = 0;
						showStatus('MISS', '#e04848');
					}
				});
			})(entry);
			gameView.add(sprite);
			notes.push(entry);
		}

		// Invisible trigger below the pads catches gems that got away
		gameView.add(Game.createSprite({
			x: W / 2, y: PAD_Y + H * 0.13, width: W * 2, height: 30,
			collisionGroup: 'misszone'
		}));

		function recycle(note) {
			note.active = false;
			note.sprite.visible = false;
			note.sprite.velocityY = 0;
			note.sprite.y = -NOTE * 2;
		}

		function spawn() {
			for (var i = 0; i < notes.length; i++) {
				if (!notes[i].active) {
					var lane = Math.floor(Math.random() * 3);
					notes[i].active = true;
					notes[i].lane = lane;
					notes[i].sprite.frame = lane;   // lane-colored gem
					notes[i].sprite.x = LANES[lane];
					notes[i].sprite.y = -NOTE;
					notes[i].sprite.visible = true;
					notes[i].sprite.velocityY = FALL_SPEED;
					return;
				}
			}
		}

		// --- Hit feedback ------------------------------------------------

		var burst = Game.createEmitter({
			sheet: sparkSheet,
			frame: 1,
			rate: 0,
			lifetime: 500,
			speed: W * 0.45,
			spread: 360,
			gravity: H * 0.8,
			size: NOTE * 0.3,
			startScale: 1,
			endScale: 0.3,
			startOpacity: 1,
			endOpacity: 0,
			zIndex: 12
		});
		gameView.add(burst);

		var score = 0;
		var combo = 0;

		var scoreLabel = Ti.UI.createLabel({
			text: '0',
			color: '#fff',
			font: { fontSize: 30, fontWeight: 'bold' },
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 2 },
			top: 90 // below the Back button
		});
		var statusLabel = Ti.UI.createLabel({
			text: '',
			color: '#fff',
			font: { fontSize: 26, fontWeight: 'bold' },
			shadowColor: '#000',
			shadowOffset: { x: 0, y: 2 },
			top: 140, // below the score
			visible: false
		});

		function showStatus(text, color) {
			statusLabel.text = text + (combo > 1 ? '  x' + combo : '');
			statusLabel.color = color;
			statusLabel.visible = true;
			if (statusTimer !== null) {
				clearTimeout(statusTimer);
			}
			statusTimer = setTimeout(function () {
				statusTimer = null;
				statusLabel.visible = false;
			}, 700);
		}

		function hitLane(lane, pad) {
			// light the ring briefly
			pad.frame = 1;
			setTimeout(function () {
				pad.frame = 0;
			}, 120);

			// closest live gem in this lane
			var best = null;
			var bestDistance = Infinity;
			notes.forEach(function (note) {
				if (note.active && note.lane === lane) {
					var distance = Math.abs(note.sprite.y - PAD_Y);
					if (distance < bestDistance) {
						bestDistance = distance;
						best = note;
					}
				}
			});

			if (best !== null && bestDistance <= HIT_RANGE) {
				recycle(best);
				goodSound.play();
				burst.x = LANES[lane];
				burst.y = PAD_Y;
				burst.tint = LANE_TINTS[lane];
				burst.emit(18);
				combo++;
				var perfect = bestDistance <= PERFECT;
				score += perfect ? 3 : 1;
				scoreLabel.text = String(score);
				showStatus(perfect ? 'PERFECT!' : 'GOOD', perfect ? '#ffd050' : '#48c060');
			} else {
				badSound.play();
				combo = 0;
				showStatus('BAD', '#e04848');
			}
		}

		spawnTimer = setInterval(spawn, SPAWN_MS);
		music.play();

		win.add(scoreLabel);
		win.add(statusLabel);
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
