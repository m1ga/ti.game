// ti.game puzzle demo — drag the pieces from the right side into the grid.
//
// - press-and-hold a piece: it scales up so you see you're holding it
// - multi-touch: each finger grabs its own piece, so several pieces can
//   be dragged at the same time (all handlers here are per-sprite)
// - drop it near a free grid cell: it snaps into place
// - drop it anywhere else: it tweens back to its starting position
// - fill all four cells to solve the puzzle
// - Restart puts every piece back to its starting position
//
// Uses puzzle.png (3x2 grid of 64x64 RGBA frames, transparent background):
// 0-3 pieces, 4 empty cell, 5 highlighted cell.
//
// The board is built on the game view's `resize` event, so all sizes come
// from the real GL surface (pixels) — displayCaps is points on iOS.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

// Toast on Android; Ti.UI.createNotification does not exist on iOS,
// so show an alert dialog there instead.
function notify(message) {
	if (Ti.Platform.osname === 'android') {
		Ti.UI.createNotification({ message: message }).show();
	} else {
		Ti.UI.createAlertDialog({ message: message, ok: 'OK' }).show();
	}
}

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({ backgroundColor: '#202030' });

	var sheet = Game.createSpriteSheet({
		image: 'assets/puzzle.png',
		frameWidth: 64,
		frameHeight: 64
	});

	var pieces = [];

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var CELL = Math.round(Math.min(W, H) / 5);
		var GAP = Math.round(CELL * 0.14);
		var PIECE = Math.round(CELL * 0.9);
		var SNAP_DISTANCE = CELL * 0.65; // how close a drop must be to snap in
		var COLS = 2;
		var ROWS = 2;

		// --- The grid (left side) ------------------------------------------

		var gridCenterX = W * 0.32;
		var gridCenterY = H * 0.45;
		var cells = [];

		for (var row = 0; row < ROWS; row++) {
			for (var col = 0; col < COLS; col++) {
				var cx = gridCenterX + (col - (COLS - 1) / 2) * (CELL + GAP);
				var cy = gridCenterY + (row - (ROWS - 1) / 2) * (CELL + GAP);
				gameView.add(Game.createSprite({
					sheet: sheet,
					frame: 4,
					x: cx,
					y: cy,
					width: CELL,
					height: CELL,
					zIndex: 0
				}));
				cells.push({ x: cx, y: cy, piece: null });
			}
		}

		// --- The pieces (right side) ---------------------------------------

		function makePiece(index) {
			var homeX = W - CELL * 0.75;
			var homeY = H * 0.18 + index * (CELL * 1.1);
			var currentCell = null;

			var piece = Game.createSprite({
				sheet: sheet,
				frame: index,
				x: homeX,
				y: homeY,
				width: PIECE,
				height: PIECE,
				draggable: true,
				zIndex: 10
			});

			piece.addEventListener('press', function () {
				piece.zIndex = 100; // draw above everything while held
				piece.animate({ scale: 1.15, duration: 120, easing: Game.EASE_OUT });
			});

			piece.addEventListener('dragstart', function () {
				// picked back out of the grid — free its cell
				if (currentCell) {
					currentCell.piece = null;
					currentCell = null;
				}
			});

			piece.addEventListener('release', function () {
				piece.animate({ scale: 1, duration: 120, easing: Game.EASE_OUT });
			});

			piece.addEventListener('dragend', function (e) {
				var best = null;
				var bestDistance = SNAP_DISTANCE;
				cells.forEach(function (cell) {
					if (cell.piece) {
						return;
					}
					var d = Math.sqrt(Math.pow(e.x - cell.x, 2) + Math.pow(e.y - cell.y, 2));
					if (d < bestDistance) {
						bestDistance = d;
						best = cell;
					}
				});

				piece.zIndex = 10;
				if (best) {
					// close enough — snap into the cell
					best.piece = piece;
					currentCell = best;
					piece.animate({ x: best.x, y: best.y, duration: 150, easing: Game.EASE_OUT });
					checkSolved();
				} else {
					// dropped somewhere else — tween back home
					piece.animate({ x: homeX, y: homeY, duration: 400, easing: Game.EASE_IN_OUT });
				}
			});

			gameView.add(piece);

			return {
				sprite: piece,
				reset: function () {
					if (currentCell) {
						currentCell.piece = null;
						currentCell = null;
					}
					piece.rotation = piece.rotation % 360; // don't unwind solved-spin turns
					piece.animate({
						x: homeX,
						y: homeY,
						rotation: 0,
						scale: 1,
						duration: 400,
						easing: Game.EASE_IN_OUT
					});
				}
			};
		}

		for (var i = 0; i < 4; i++) {
			pieces.push(makePiece(i));
		}

		function checkSolved() {
			var solved = cells.every(function (cell) {
				return cell.piece !== null;
			});
			if (!solved) {
				return;
			}
			pieces.forEach(function (piece, i) {
				piece.sprite.animate({
					rotation: piece.sprite.rotation + 360,
					duration: 600,
					delay: i * 100,
					easing: Game.EASE_IN_OUT
				});
			});
			notify('Solved!');
		}
	}

	win.add(gameView);

	// Restart — a regular Titanium button overlaying the game view
	var restartButton = Ti.UI.createButton({
		title: 'Restart',
		bottom: 30,
		left: 20
	});
	restartButton.addEventListener('click', function () {
		pieces.forEach(function (piece) {
			piece.reset();
		});
	});
	win.add(restartButton);

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
