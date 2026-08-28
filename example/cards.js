// ti.game card demo — cards are dealt from a deck, pick three and play them.
//
// - a face-down deck sits in the top-right corner; on start the five hand
//   cards fly from the deck into a fan at the bottom, flipping face up as
//   they land (a runtime `frame` swap from the card back to the face)
// - tap a card to select it: it slides up a bit, scales slightly up and
//   gets a golden glow (native glow shader — glowColor/glowBlur); tap
//   again to deselect; at most three can be selected
// - the Done button tweens the three selected cards to the middle of the
//   screen, placed next to each other — then turns into Reset
// - Reset sweeps every card off the left edge, then deals five fresh
//   cards from the deck
//
// Everything is sprite taps + native tweens; no engine additions needed.
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
	var gameView = Game.createGameView({
		backgroundColor: '#2c6e4f' // card-table green
	});

	var sheet = Game.createSpriteSheet({ image: 'assets/cards.png', frameWidth: 64, frameHeight: 96 });

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
		}
	});

	function init(W, H) {

		var CARD_W = Math.round(Math.min(W * 0.19, H * 0.14));
		var CARD_H = Math.round(CARD_W * 1.5);
		var LIFT = CARD_H * 0.35;       // how far a selected card pops up
		var MAX_SELECTED = 3;
		var BACK_FRAME = 5;             // face-down card art in the sheet

		var cards = [];
		var played = false;

		// Fan slot for a card `offset` positions from the hand's center
		function handPosition(offset) {
			return {
				x: W / 2 + offset * CARD_W * 0.78,
				y: H - CARD_H * 0.72 - 150 + Math.abs(offset) * CARD_H * 0.07,
				rotation: offset * 7
			};
		}

		// --- The deck: a face-down stack in the top-right corner ---------

		var DECK_X = W - CARD_W * 0.85;
		var DECK_Y = CARD_H * 0.85;

		for (var d = 0; d < 3; d++) {
			gameView.add(Game.createSprite({
				sheet: sheet,
				frame: BACK_FRAME,
				x: DECK_X - d * 3,
				y: DECK_Y - d * 3,
				rotation: (d - 1) * 2,
				width: CARD_W,
				height: CARD_H,
				zIndex: d
			}));
		}

		// --- The hand: five cards, dealt from the deck --------------------

		for (var i = 0; i < 5; i++) {
			(function (index) {
				var home = handPosition(index - 2); // -2..2 around the middle
				var sprite = Game.createSprite({
					sheet: sheet,
					frame: BACK_FRAME,
					x: DECK_X,
					y: DECK_Y,
					width: CARD_W,
					height: CARD_H,
					zIndex: 30 + index,
					// gentle native wobble once in the hand; each sprite has
					// its own phase — off while flying so tweens land exactly
					idleAnimation: false,
					idleRotation: 2.5,              // degrees of sway
					idleMovement: CARD_H * 0.035,   // px of drift
					idleSpeed: 0.7
				});
				// state: 'dealing' (deck → hand), 'hand', 'leaving' (reset sweep)
				var card = { sprite: sprite, home: home, face: index, index: index,
					state: 'dealing', selected: false, played: false };

				sprite.addEventListener('tap', function () {
					if (card.state !== 'hand' || card.played || played) {
						return;
					}
					if (card.selected) {
						card.selected = false;
						sprite.animate({
							x: home.x, y: home.y, rotation: home.rotation,
							scale: 1, glowOpacity: 0, // fade the halo out
							duration: 150, easing: Game.EASE_OUT
						});
					} else if (selectedCards().length < MAX_SELECTED) {
						card.selected = true;
						// golden halo fades in with the lift — a native glow
						// shader pass, no extra sprites needed
						sprite.glowColor = '#ffc94d';
						sprite.glowBlur = CARD_W * 0.14;
						sprite.glowOpacity = 0;
						sprite.animate({
							y: home.y - LIFT, scale: 1.12, glowOpacity: 1,
							duration: 150, easing: Game.EASE_OUT
						});
					}
				});

				sprite.addEventListener('complete', function () {
					if (card.state === 'dealing') {
						// landed in the fan: flip face up and settle into the hand
						card.state = 'hand';
						sprite.frame = card.face;
						sprite.zIndex = card.index;
					}
					// wobble again once a tween lands the card in the hand;
					// played and leaving cards stay still
					if (card.state === 'hand' && !card.played) {
						sprite.idleAnimation = true;
					}
				});

				gameView.add(sprite);
				cards.push(card);
			})(i);
		}

		function selectedCards() {
			return cards.filter(function (card) {
				return card.selected;
			});
		}

		function busy() {
			return cards.some(function (card) {
				return card.state !== 'hand';
			});
		}

		// Fly every card from the deck into its fan slot, face down,
		// flipping on arrival (see the complete listener)
		function dealHand() {
			played = false;
			cards.forEach(function (card, index) {
				card.state = 'dealing';
				card.played = false;
				card.selected = false;
				card.sprite.idleAnimation = false;
				card.sprite.frame = BACK_FRAME;
				card.sprite.x = DECK_X;
				card.sprite.y = DECK_Y;
				card.sprite.rotation = 0;
				card.sprite.scale = 1;
				card.sprite.glowOpacity = 0;
				card.sprite.zIndex = 30 + index; // above the deck while flying
				card.sprite.animate({
					x: card.home.x,
					y: card.home.y,
					rotation: card.home.rotation,
					duration: 380,
					delay: index * 140,             // one card after another
					easing: Game.EASE_IN_OUT
				});
			});
		}

		// --- Done / Reset button -----------------------------------------

		var doneButton = Ti.UI.createButton({
			title: 'Done',
			bottom: 30,
			right: 20
		});

		doneButton.addEventListener('click', function () {
			if (played) {
				reset();
				return;
			}
			if (busy()) {
				return; // still dealing or sweeping
			}
			var selection = selectedCards();
			if (selection.length < MAX_SELECTED) {
				notify('Select 3 cards');
				return;
			}
			played = true;
			doneButton.title = 'Reset';
			selection.forEach(function (card, k) {
				card.played = true;
				card.selected = false;
				// stop the wobble before the flight — tweens write absolute
				// positions, so a card wobbling mid-tween would land with a
				// leftover offset; a still card lands exactly on target
				card.sprite.idleAnimation = false;
				card.sprite.zIndex = 20 + k; // above the remaining hand
				card.sprite.animate({
					x: W / 2 + (k - 1) * CARD_W * 1.15, // side by side in the middle
					y: H * 0.4,
					rotation: 0,
					scale: 1,
					glowOpacity: 0,                     // halo fades out in flight
					duration: 350,
					delay: k * 120,                     // staggered for effect
					easing: Game.EASE_IN_OUT
				});
			});

			// close the gap: re-fan the two remaining cards around the center
			var remaining = cards.filter(function (card) {
				return !card.played;
			});
			remaining.forEach(function (card, k) {
				var offset = k - (remaining.length - 1) / 2;
				var slot = handPosition(offset);
				card.sprite.animate({
					x: slot.x,
					y: slot.y,
					rotation: slot.rotation,
					scale: 1,
					duration: 300,
					delay: 250,
					easing: Game.EASE_IN_OUT
				});
			});
		});

		function reset() {
			doneButton.title = 'Done';
			// sweep everything off the left edge, then deal a fresh hand
			cards.forEach(function (card, index) {
				card.state = 'leaving';
				card.selected = false;
				card.sprite.idleAnimation = false;
				card.sprite.zIndex = 20 + index;
				card.sprite.animate({
					x: -CARD_W * 2,
					y: H * 0.5,
					rotation: -120,
					scale: 1,
					glowOpacity: 0,
					duration: 320,
					delay: index * 60,
					easing: Game.EASE_IN
				});
			});
			// last card leaves at 4*60+320 = 560ms; a short beat, then redeal
			setTimeout(dealHand, 750);
		}

		win.add(doneButton);

		// opening deal — a short beat so the deck is seen first
		setTimeout(dealHand, 350);
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
