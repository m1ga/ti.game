// ti.game examples — launcher.
//   Basic:  sprite playground (animations, drag, pinch/rotate, tweens)
//   Puzzle: drag & drop pieces into a grid, snap or tween back home
//   Flappy: flying pig — tap to flap, gravity, gates, parallax background
//   Platformer: run & jump onto platforms with on-screen controls
//   Volley: Blobby Volley style — you vs. a simple computer player
//   Racing: pixel top-down racer with drifting, checkpoints and laps
//   Cards: select three cards from your hand and play them to the middle
//   Asteroids: turn/thrust/shoot — Newtonian flight with screen wrapping
//   Zelda: top-down tile level — solid house/water, depth-sorted trees
//   Skate: endless skateboard runner — jump the walls and pits
//   Point & click: adventure scene — walk by tapping, talk to the bird

var demos = [
	{ title: 'Basic demo', start: require('/basic') },
	{ title: 'Puzzle demo', start: require('/puzzle') },
	{ title: 'Flappy pig', start: require('/flappy') },
	{ title: 'Platformer', start: require('/platformer') },
	{ title: 'Volley', start: require('/volley') },
	{ title: 'Racing', start: require('/racing') },
	{ title: 'Cards', start: require('/cards') },
	{ title: 'Asteroids', start: require('/asteroids') },
	{ title: 'Zelda', start: require('/zelda') },
	{ title: 'Skate', start: require('/skate') },
	{ title: 'Point & click', start: require('/pointclick') }
];

var win = Ti.UI.createWindow({
	backgroundColor: '#202030',
	layout: 'vertical',
	theme: "Theme.Titanium.DayNight.NoTitleBar"
});

win.add(Ti.UI.createLabel({
	text: 'ti.game examples',
	color: '#fff',
	font: { fontSize: 24, fontWeight: 'bold' },
	top: 80
}));

demos.forEach(function (demo, index) {
	var button = Ti.UI.createButton({
		title: demo.title,
		top: index === 0 ? 20 : 10,
		width: 220
	});
	button.addEventListener('click', function () {
		demo.start();
	});
	win.add(button);
});

win.open();
