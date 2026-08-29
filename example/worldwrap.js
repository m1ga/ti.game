// ti.game circular-world playground.
// Hold either direction and orbit the six-screen world. The player, camera,
// full-width solid TileLayer, touchable overlap target and swept solid bolt
// all meet at the same seam. No JavaScript writes positions per frame.

var Game = require('ti.game');

module.exports = function () {
	var win = Ti.UI.createWindow({ backgroundColor: '#000', extendSafeArea: false, theme: 'Theme.Titanium.DayNight.NoTitleBar' });
	var gameView = Game.createGameView({
		backgroundColor: '#8ed8f8',
		maxFps: 60
	});
	var tileSheet = Game.createSpriteSheet({ image: 'assets/tiles.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var cloudSheet = Game.createSpriteSheet({ image: 'assets/clouds.png', frameWidth: 512, frameHeight: 128 });
	var hillSheet = Game.createSpriteSheet({ image: 'assets/hills.png', frameWidth: 512, frameHeight: 114 });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64, smoothing: false });
	var sparkSheet = Game.createSpriteSheet({ image: 'assets/spark.png', frameWidth: 16, frameHeight: 16 });
	var noteSheet = Game.createSpriteSheet({ image: 'assets/note.png', frameWidth: 32, frameHeight: 32, smoothing: false });
	var pipeSheet = Game.createSpriteSheet({ image: 'assets/pipe.png', frameWidth: 64, frameHeight: 64, smoothing: false });
	var initialized = false;

	gameView.addEventListener('resize', function (e) {
		if (initialized) return;
		initialized = true;
		build(e.width, e.height);
	});

	function build(W, H) {
		var TILE = Math.max(32, Math.round(W / 15));
		var COLS = Math.ceil(W / TILE) * 6;
		var WORLD_W = COLS * TILE;
		var BACKDROP_W = WORLD_W / 6;
		var FLOOR_Y = Math.round(H * 0.78);
		var PLAYER = Math.max(96, Math.round(W * 0.22));
		var TARGET = Math.max(52, Math.round(W * 0.11));
		var LAUNCHER = Math.max(52, Math.round(W * 0.09));
		var BOLT = 24;
		var TARGET_HIT_SCALE = 0.9;
		var BOLT_HIT_SCALE = 0.875;
		var RUN_SPEED = W * 0.9;
		var data = [];
		for (var row = 0; row < 3; row++) {
			var cells = [];
			for (var col = 0; col < COLS; col++) {
				cells.push(row === 0 ? 0 : 2);
			}
			data.push(cells);
		}

		gameView.worldWrapX = { minX: 0, maxX: WORLD_W };
		gameView.cameraBounds = { minX: 0, minY: 0, maxX: WORLD_W, maxY: H };

		// The sun is nearly fixed while repeated cloud and hill layers move at
		// different fractions of the camera speed. All movement stays native.
		var sun = Game.createSprite({
			sheet: sparkSheet, frame: 0,
			x: W * 0.79, y: H * 0.19,
			width: W * 0.25, height: W * 0.25,
			tintColor: '#ffd76a', opacity: 0.7, blend: 'screen',
			screenFixed: true, touchEnabled: false, zIndex: 0
		});
		function parallaxCopies(sheet, y, width, height, scrollFactor, opacity, zIndex) {
			var copies = [];
			for (var i = 0; i < 6; i++) {
				copies.push(Game.createSprite({
					sheet: sheet,
					x: width / 2 + i * width, y: y,
					width: width, height: height,
					scrollFactor: scrollFactor, opacity: opacity,
					wrapWorldX: true, touchEnabled: false, zIndex: zIndex
				}));
			}
			return copies;
		}
		var clouds = parallaxCopies(
			cloudSheet, H * 0.28,
			BACKDROP_W, BACKDROP_W / 4, 0.16, 0.82, 1
		);
		var hills = parallaxCopies(
			hillSheet, FLOOR_Y - BACKDROP_W * 114 / 1024,
			BACKDROP_W, BACKDROP_W * 114 / 512, 0.42, 1, 2
		);
		hills.forEach(function (hill, index) {
			hill.flipX = (index % 2) === 1;
		});
		var terrain = Game.createTileLayer({
			sheet: tileSheet, data: data, tileWidth: TILE, tileHeight: TILE,
			x: 0, y: FLOOR_Y, collisionGroup: 'terrain', solid: [0, 2], zIndex: 3
		});
		// Split the shot evenly around the seam. The target center sits one
		// combined hit radius past the second half, so contact (not its
		// center) occurs exactly as far after minX as the muzzle is before maxX.
		var SHOT_HALF = W * 0.14;
		var SHOT_Y = FLOOR_Y - TARGET / 2;
		var CONTACT_RADII = TARGET * 0.5 * TARGET_HIT_SCALE
			+ BOLT * 0.5 * BOLT_HIT_SCALE;
		var MUZZLE_X = WORLD_W - SHOT_HALF;
		var TARGET_X = SHOT_HALF + CONTACT_RADII;
		var target = Game.createSprite({
			sheet: ballSheet, x: TARGET_X, y: SHOT_Y,
			width: TARGET, height: TARGET,
			hitboxShape: 'circle', hitboxScale: TARGET_HIT_SCALE,
			collisionGroup: 'seam-target', wrapWorldX: true, touchEnabled: true, zIndex: 5
		});
		var launcher = Game.createSprite({
			sheet: pipeSheet,
			x: MUZZLE_X - LAUNCHER * 0.48, y: SHOT_Y,
			width: LAUNCHER, height: LAUNCHER, rotation: 90,
			wrapWorldX: true, touchEnabled: false, zIndex: 5
		});
		var player = Game.createSprite({
			sheet: dogSheet, x: WORLD_W - PLAYER * 2, y: FLOOR_Y - PLAYER / 2,
			frame: 2, width: PLAYER, height: PLAYER, velocityX: 0, gravity: H * 2,
			solidWith: ['terrain'], collidesWith: ['seam-target'],
			wrapWorldX: true, pixelSnap: true, touchEnabled: false, zIndex: 6,
			animations: {
				walk: { frames: [0, 1], fps: 12, loop: true }
			}
		});
		var bolt = Game.createSprite({
			sheet: noteSheet, frame: 0, width: BOLT, height: BOLT, visible: false,
			hitboxShape: 'circle', hitboxScale: BOLT_HIT_SCALE,
			swept: true, solidWith: ['seam-target'], wrapWorldX: true,
			touchEnabled: false, zIndex: 7
		});
		var UNIT = Math.max(1, Math.round(W / 380));
		// minX and maxX are the same point in a circular world. Opposite
		// anchors place each label on its own side of that shared seam.
		var SEAM_Y = FLOOR_Y - PLAYER * 1.35;
		var seamEnd = Game.createText({
			text: 'END  >|', x: WORLD_W, y: SEAM_Y,
			anchorX: 1, scale: UNIT * 0.9, tintColor: '#a33e35',
			wrapWorldX: true, touchEnabled: false, zIndex: 8
		});
		var seamStart = Game.createText({
			text: '|<  START', x: 0, y: SEAM_Y,
			anchorX: 0, scale: UNIT * 0.9, tintColor: '#176b55',
			wrapWorldX: true, touchEnabled: false, zIndex: 8
		});
		var title = Game.createText({
			text: 'CIRCULAR WORLD', x: W / 2, y: H * 0.085,
			scale: UNIT * 1.4, letterSpacing: UNIT,
			tintColor: '#173b58', screenFixed: true, zIndex: 20
		});
		var hint = Game.createText({
			text: 'HOLD A DIRECTION TO CROSS THE SEAM', x: W / 2, y: H * 0.125,
			scale: UNIT * 0.75, tintColor: '#386b7a',
			screenFixed: true, zIndex: 20
		});
		var status = Game.createText({
			text: '', x: W / 2, y: H * 0.16,
			scale: UNIT * 0.8, tintColor: '#244f66',
			screenFixed: true, zIndex: 20
		});
		var legend = Game.createText({
			text: 'FLOOR: REPEATED TILE   DOG: SPRITE OVERLAP\n'
				+ 'BOLT: SWEPT SEAM HIT   TAP: WRAPPED TOUCH',
			align: 'center', x: W / 2, y: H * 0.205,
			scale: Math.max(0.85, UNIT * 0.7), lineSpacing: 1.2,
			tintColor: '#4e7b88', screenFixed: true, zIndex: 20
		});
		var normalHits = 0;
		var sweptHits = 0;
		var tapHits = 0;
		var floorReady = false;
		function updateStatus() {
			status.text = 'FLOOR ' + (floorReady ? 'OK' : '...')
				+ '  DOG ' + normalHits + '  BOLT ' + sweptHits + '  TAP ' + tapHits;
		}
		player.addEventListener('land', function (e) {
			if (!e.other) {
				floorReady = true;
				updateStatus();
			}
		});
		player.addEventListener('collision', function () {
			normalHits++;
			updateStatus();
		});
		bolt.addEventListener('wallhit', function () {
			sweptHits++;
			bolt.visible = false;
			bolt.velocityX = 0;
			updateStatus();
		});
		target.addEventListener('tap', function () {
			tapHits++;
			target.flash('#ffffff', 180);
			updateStatus();
		});
		gameView.add(sun);
		gameView.add(clouds);
		gameView.add(hills);
		gameView.add([
			terrain, launcher, target, player, bolt, seamEnd, seamStart,
			title, hint, status, legend
		]);
		updateStatus();
		gameView.follow(player, { leftMargin: 0.28, rightMargin: 0.48, smoothing: 0.1, maxY: H });

		var fireTimer = gameView.every(1500, function () {
			bolt.x = MUZZLE_X;
			bolt.y = SHOT_Y;
			bolt.velocityX = W * 1.2;
			bolt.visible = true;
			launcher.flash('#fff3a0', 100);
		});
		win.addEventListener('close', function () { gameView.cancelTimer(fireTimer); });

		function directionButton(label, side, velocity) {
			var button = Ti.UI.createLabel({
				text: label, width: '64dp', height: '64dp', bottom: '18dp',
				color: '#f4fbff', backgroundColor: '#cc173b58',
				borderColor: '#7aa6b2', borderWidth: 1, borderRadius: '32dp',
				font: { fontSize: 24, fontWeight: 'bold' }, textAlign: 'center'
			});
			button[side] = '20dp';
			button.addEventListener('touchstart', function () {
				player.velocityX = velocity;
				player.flipX = velocity < 0;
				player.play('walk');
				button.backgroundColor = '#ee275f78';
			});
			['touchend', 'touchcancel'].forEach(function (name) {
				button.addEventListener(name, function () {
					player.velocityX = 0;
					player.stop();
					player.frame = 2;
					button.backgroundColor = '#cc173b58';
				});
			});
			win.add(button);
		}
		directionButton('◀', 'left', -RUN_SPEED);
		directionButton('▶', 'right', RUN_SPEED);
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
	backButton.addEventListener('click', function () { win.close(); });
	win.add(backButton);
	win.open();
};
