// ti.game zelda demo — top-down tile level with depth sorting.
//
// - walk with the d-pad (8-way via multitouch); you can only move on the
//   ground tiles: the water border and the house are solid (`solidWith`)
// - trees don't block — walk below one and you render in front of it,
//   walk above and you disappear behind the canopy (`ySort: true` orders
//   sprites by their bottom edge within the same zIndex)
// - the whole map is sprites from one pixel-art tile sheet
//   (`smoothing: false`), so it renders in very few draw calls
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({
		backgroundColor: '#1c2430'
		// debug: true                              // collision shapes for every sprite
		// debug: { hitbox: true, hud: 'topRight' }  // ...plus the performance HUD
	});

	// 16px art upscaled ~5x with smoothing: false = chunky retro pixels
	var tileSheet = Game.createSpriteSheet({ image: 'assets/tiles.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var houseSheet = Game.createSpriteSheet({ image: 'assets/house.png', frameWidth: 48, frameHeight: 42, smoothing: false });
	var treeSheet = Game.createSpriteSheet({ image: 'assets/tree.png', frameWidth: 24, frameHeight: 32, smoothing: false });
	var walkerSheet = Game.createSpriteSheet({ image: 'assets/walker.png', frameWidth: 16, frameHeight: 16, smoothing: false });
	var dogSheet = Game.createSpriteSheet({ image: 'assets/dog.png', frameWidth: 16, frameHeight: 16, smoothing: false });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		// Scene units per dp: measure the real surface scale instead of
		// trusting logicalDensityFactor — the iOS simulator renders at 1x
		// while the density factor still reports the device scale
		var density = Ti.Platform.osname === 'android'
			? Ti.Platform.displayCaps.logicalDensityFactor
			: H / Ti.Platform.displayCaps.platformHeight;
		var buttonZone = Math.round(130 * density);

		// Tile map: G grass, F flowers, P path, W water (solid border)
		var MAP = [
			'WWWWWWWWWWWW',
			'WGGGGGGGGGGW',
			'WGFGGGGGGGGW',
			'WGGGGGGGGGGW',
			'WGGGGGGPGGGW',
			'WGGFGGGPGFGW',
			'WGGGGGGPGGGW',
			'WGGGGGGPGGGW',
			'WGFGGGGPGGFW',
			'WGGGGGGPGGGW',
			'WGGGGGGGGGGW',
			'WGGFGGGGGFGW',
			'WGGGGGGGGGGW',
			'WGGGGGGGGGGW',
			'WWWWWWWWWWWW'
		];
		var COLS = MAP[0].length;
		var ROWS = MAP.length;
		var FRAMES = { G: 0, F: 1, P: 2, W: 3 };

		var TILE = Math.floor(Math.min(W / COLS, (H - buttonZone) / ROWS));
		var ox = (W - COLS * TILE) / 2;                  // center the map
		var oy = (H - buttonZone - ROWS * TILE) / 2;

		function tileCenter(col, row) {
			return { x: ox + (col + 0.5) * TILE, y: oy + (row + 0.5) * TILE };
		}

		for (var row = 0; row < ROWS; row++) {
			for (var col = 0; col < COLS; col++) {
				var kind = MAP[row].charAt(col);
				var pos = tileCenter(col, row);
				var tile = Game.createSprite({
					sheet: tileSheet,
					frame: FRAMES[kind],
					x: pos.x,
					y: pos.y,
					width: TILE,
					height: TILE,
					zIndex: 0,
					// only ground is walkable — water blocks like a wall
					collisionGroup: (kind === 'W') ? 'solid' : null,
					animations: (kind === 'W')
						? { flow: { frames: [3, 4, 5, 4], fps: 3, loop: true } }
						: null
				});
				if (kind === 'W') {
					// random start delay so the shore doesn't ripple in sync
					(function (water) {
						setTimeout(function () {
							water.play('flow');
						}, Math.random() * 1000);
					})(tile);
				}
				gameView.add(tile);
			}
		}

		// --- The house (blocks movement, depth-sorted at its base) -------

		var housePos = tileCenter(7.5, 2.2);
		gameView.add(Game.createSprite({
			sheet: houseSheet,
			x: housePos.x,
			y: housePos.y,
			width: TILE * 4,
			height: TILE * 3.5,
			zIndex: 5,
			ySort: true,
			hitboxScale: 0.9,
			collisionGroup: 'solid'
		}));

		// --- Trees (no collision — walk behind or in front) --------------

		var trees = [];
		[
			[2.5, 4.5], [3.5, 9.5], [9.5, 7.5], [2.2, 12.3], [9.6, 11.8]
		].forEach(function (t) {
			var pos = tileCenter(t[0], t[1]);
			gameView.add(Game.createSprite({
				sheet: treeSheet,
				x: pos.x,
				y: pos.y,
				width: TILE * 1.5,
				height: TILE * 2,
				zIndex: 5,
				ySort: true
			}));
			// remembered for the dog: trunk position and base line
			trees.push({ x: pos.x, baseY: pos.y + TILE });
		});

		// --- The player --------------------------------------------------

		var start = tileCenter(5, 12);
		var SPEED = TILE * 3.5; // tiles per second
		var player = Game.createSprite({
			sheet: walkerSheet,
			x: start.x,
			y: start.y,
			width: TILE,
			height: TILE,
			zIndex: 5,
			ySort: true,             // sorted against trees and the house
			hitboxScale: 0.6,        // top-down games feel best with a small body box
			solidWith: ['solid'],
			animations: {
				down: { frames: [0, 1], fps: 6, loop: true },
				up: { frames: [2, 3], fps: 6, loop: true },
				side: { frames: [4, 5], fps: 6, loop: true }
			}
		});
		gameView.add(player);

		// --- The dog: follows the player, sits when nothing happens ------

		var dog = Game.createSprite({
			sheet: dogSheet,
			frame: 2, // starts sitting
			x: start.x - TILE * 1.2,
			y: start.y + TILE * 0.15,
			width: TILE * 0.85,
			height: TILE * 0.85,
			zIndex: 5,
			ySort: true,             // sorted against trees/house like the player
			hitboxScale: 0.5,
			solidWith: ['solid'],    // no swimming, no walking through the house
			animations: {
				walk: { frames: [0, 1], fps: 7, loop: true },
				pee: { frames: [3, 4], fps: 3, loop: true } // lift the leg :-)
			}
		});
		gameView.add(dog);

		var DOG_SPEED = SPEED * 1.1;        // slightly faster, so it can catch up
		var FOLLOW_DISTANCE = TILE * 1.4;   // how close it wants to stay
		var SNIFF_DISTANCE = TILE * 1.8;    // a tree this close is interesting
		var PEE_DURATION = 1800;            // ms of business
		var PEE_COOLDOWN = 12000;           // ms before the next tree visit
		var dogState = '';
		var peeTarget = null;               // spot beside a trunk to walk to
		var peeUntil = 0;
		var nextPeeAllowed = 5000;          // small grace period after start

		function setDogState(state) {
			if (state === dogState) {
				return;
			}
			dogState = state;
			if (state === 'walk') {
				dog.play('walk');
			} else if (state === 'pee') {
				dog.play('pee');
			} else {
				dog.stop();
				dog.frame = (state === 'sit') ? 2 : 0;
			}
		}

		// Coarse decision timer (like the volley AI) — the actual movement
		// runs natively via velocity between ticks
		var dogTimer = setInterval(function () {
			var now = Date.now();
			var dx = player.x - dog.x;
			var dy = player.y - dog.y;
			var dist = Math.sqrt(dx * dx + dy * dy);

			// busy at a tree — no following whatsoever until finished; only
			// then does the timer fall back into companion mode
			if (dogState === 'pee') {
				dog.velocityX = 0;
				dog.velocityY = 0;
				if (now >= peeUntil) {
					nextPeeAllowed = now + PEE_COOLDOWN;
					setDogState('stand'); // next tick: walk back to the player
				}
				return;
			}

			// walking over to a chosen tree
			if (peeTarget) {
				if (dist > TILE * 5) {
					// player left — priorities! Short cooldown so the same
					// tree isn't re-sniffed on the very next tick
					peeTarget = null;
					nextPeeAllowed = now + 4000;
				} else {
					var tx = peeTarget.x - dog.x;
					var ty = peeTarget.y - dog.y;
					var tdist = Math.sqrt(tx * tx + ty * ty);
					if (tdist < TILE * 0.15) {
						dog.velocityX = 0;
						dog.velocityY = 0;
						dog.scaleX = (peeTarget.treeX > dog.x) ? 1 : -1; // face the trunk
						peeUntil = now + PEE_DURATION;
						peeTarget = null;
						setDogState('pee');
					} else {
						dog.velocityX = (tx / tdist) * DOG_SPEED;
						dog.velocityY = (ty / tdist) * DOG_SPEED;
						if (Math.abs(tx) > 2) {
							dog.scaleX = (tx > 0) ? 1 : -1;
						}
						setDogState('walk');
					}
					return;
				}
			}

			// any interesting tree nearby?
			if (now >= nextPeeAllowed) {
				for (var k = 0; k < trees.length; k++) {
					var tree = trees[k];
					var ddx = tree.x - dog.x;
					var ddy = tree.baseY - dog.y;
					if (Math.sqrt(ddx * ddx + ddy * ddy) < SNIFF_DISTANCE) {
						var side = (dog.x < tree.x) ? -1 : 1; // approach from its side
						peeTarget = {
							x: tree.x + side * TILE * 0.45,
							y: tree.baseY - TILE * 0.15,
							treeX: tree.x
						};
						return;
					}
				}
			}

			// normal companion behavior
			if (dist > FOLLOW_DISTANCE) {
				dog.velocityX = (dx / dist) * DOG_SPEED;
				dog.velocityY = (dy / dist) * DOG_SPEED;
				if (Math.abs(dx) > 2) {
					dog.scaleX = (dx > 0) ? 1 : -1; // face where it's headed
				}
				setDogState('walk');
			} else {
				dog.velocityX = 0;
				dog.velocityY = 0;
				// player still walking → stand ready; player idle → sit down
				setDogState((moveX !== 0 || moveY !== 0) ? 'stand' : 'sit');
			}
		}, 100);

		win.addEventListener('close', function () {
			clearInterval(dogTimer);
		});

		// --- D-pad (8-way movement via multitouch) -----------------------

		var moveX = 0;
		var moveY = 0;
		var lastFacing = 'down';
		var walking = false; // engine keeps the animation name after stop(),
		                     // so track the running state ourselves

		function applyMovement() {
			player.velocityX = moveX * SPEED;
			player.velocityY = moveY * SPEED;
			if (moveX === 0 && moveY === 0) {
				player.stop();
				walking = false;
				player.frame = { down: 0, up: 2, side: 4 }[lastFacing];
				return;
			}
			var facing = (moveX !== 0) ? 'side' : (moveY < 0 ? 'up' : 'down');
			if (moveX !== 0) {
				player.scaleX = moveX; // side frames face right; flip for left
			}
			if (!walking || facing !== lastFacing) {
				player.play(facing);
				walking = true;
			}
			lastFacing = facing;
		}

		function makeButton(title, position) {
			var button = Ti.UI.createLabel({
				text: title,
				textAlign: 'center',
				color: '#fff',
				font: { fontSize: 30, fontWeight: 'bold' },
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

		function bindHold(button, axis, dir) {
			button.addEventListener('touchstart', function () {
				if (axis === 'x') {
					moveX = dir;
				} else {
					moveY = dir;
				}
				applyMovement();
			});
			['touchend', 'touchcancel'].forEach(function (event) {
				button.addEventListener(event, function () {
					if (axis === 'x' && moveX === dir) {
						moveX = 0;
					} else if (axis === 'y' && moveY === dir) {
						moveY = 0;
					}
					applyMovement();
				});
			});
		}

		var leftButton = makeButton('◀', { left: '24dp' });
		var rightButton = makeButton('▶', { left: '112dp' });
		var upButton = makeButton('▲', { right: '112dp' });
		var downButton = makeButton('▼', { right: '24dp' });

		bindHold(leftButton, 'x', -1);
		bindHold(rightButton, 'x', 1);
		bindHold(upButton, 'y', -1);
		bindHold(downButton, 'y', 1);

		applyMovement(); // standing frame

		win.add(leftButton);
		win.add(rightButton);
		win.add(upButton);
		win.add(downButton);
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
