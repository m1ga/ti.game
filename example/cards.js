// ti.game card demo — pick three cards from your hand and play them.
//
// - five cards fanned at the bottom ("my hand")
// - tap a card to select it: it slides up a bit and scales slightly up
//   (tap again to deselect; at most three can be selected)
// - the Done button tweens the three selected cards to the middle of the
//   screen, placed next to each other — then turns into Reset
//
// Everything is sprite taps + native tweens; no engine additions needed.
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

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

		// --- The hand: five cards in a slight fan ------------------------

		for (var i = 0; i < 5; i++) {
			(function (index) {
				var home = handPosition(index - 2); // -2..2 around the middle
				var sprite = Game.createSprite({
					sheet: sheet,
					frame: index,
					x: home.x,
					y: home.y,
					rotation: home.rotation,
					width: CARD_W,
					height: CARD_H,
					zIndex: index,
					// gentle native wobble; each sprite has its own phase
					idleAnimation: true,
					idleRotation: 2.5,              // degrees of sway
					idleMovement: CARD_H * 0.035,   // px of drift
					idleSpeed: 0.7
				});
				var card = { sprite: sprite, home: home, selected: false, played: false };

				sprite.addEventListener('tap', function () {
					if (card.played || played) {
						return;
					}
					if (card.selected) {
						card.selected = false;
						sprite.animate({
							x: home.x, y: home.y, rotation: home.rotation,
							scale: 1, duration: 150, easing: Game.EASE_OUT
						});
					} else if (selectedCards().length < MAX_SELECTED) {
						card.selected = true;
						sprite.animate({
							y: home.y - LIFT, scale: 1.12,
							duration: 150, easing: Game.EASE_OUT
						});
					}
				});

				sprite.addEventListener('complete', function () {
					// wobble again once a tween lands the card in the hand;
					// played cards stay still so the middle row stays aligned
					if (!card.played) {
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
			var selection = selectedCards();
			if (selection.length < MAX_SELECTED) {
				Ti.UI.createNotification({ message: 'Select 3 cards' }).show();
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
			played = false;
			doneButton.title = 'Done';
			// everything tweens back to its original fan slot; the complete
			// listener re-enables the wobble once each card has arrived
			cards.forEach(function (card, index) {
				card.played = false;
				card.selected = false;
				card.sprite.zIndex = index;
				card.sprite.animate({
					x: card.home.x,
					y: card.home.y,
					rotation: card.home.rotation,
					scale: 1,
					duration: 300,
					easing: Game.EASE_IN_OUT
				});
			});
		}

		win.add(doneButton);
	}

	win.add(gameView);
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
