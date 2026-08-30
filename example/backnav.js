// ti.game examples — shared "back to the launcher" control.
//
// Android: the demo window shows an action bar (Theme.Titanium.DayNight), so
// the Up arrow closes it — no overlay button. iOS has no navigation bar in
// these demos, so it gets a small '‹ EXAMPLES' pill instead.
//
//   require('/backnav')(win);
//   require('/backnav')(win, { text: '#e8dcff', background: '#24183b',
//                              border: '#594477', pressed: '#3a2758' });
//
// The palette only affects the iOS pill; pass one when the default teal
// clashes with a demo's background.

var DEFAULT_PALETTE = {
	text: '#eaf5f6',
	background: '#18394d',
	border: '#41697b',
	pressed: '#28576d'
};

module.exports = function (win, palette) {
	if (Ti.Platform.osname === 'android') {
		win.addEventListener('open', function () {
			var actionBar = win.activity.actionBar;
			if (actionBar) {
				actionBar.displayHomeAsUp = true;
				actionBar.onHomeIconItemSelected = function () {
					win.close();
				};
			}
		});
		return;
	}

	palette = palette || DEFAULT_PALETTE;
	var backButton = Ti.UI.createLabel({
		text: '‹  EXAMPLES',
		top: 40,
		left: 12,
		width: 96,
		height: 38,
		color: palette.text,
		backgroundColor: palette.background,
		borderColor: palette.border,
		borderWidth: 1,
		borderRadius: 19,
		font: { fontSize: 12, fontWeight: 'bold' },
		textAlign: 'center',
		zIndex: 100
	});
	backButton.addEventListener('touchstart', function () { backButton.backgroundColor = palette.pressed; });
	backButton.addEventListener('touchend', function () { backButton.backgroundColor = palette.background; });
	backButton.addEventListener('touchcancel', function () { backButton.backgroundColor = palette.background; });
	backButton.addEventListener('click', function () {
		win.close();
	});
	win.add(backButton);
};
