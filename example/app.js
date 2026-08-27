// ti.game examples — launcher.
//   Basic:  sprite playground (animations, drag, pinch/rotate, tweens)
//   Puzzle: drag & drop pieces into a grid, snap or tween back home
//   Flappy: flying pig — tap to flap, gravity, gates, parallax background
//   Platformer: run & jump onto platforms with on-screen controls
//   Plinko: a staggered wall of circular solids — every peg is a circle hitbox
//   Volley: Blobby Volley style — you vs. a simple computer player
//   Racing: pixel top-down racer with pixel snapping, drifting, checkpoints and laps
//   Cards: select three cards from your hand and play them to the middle
//   Asteroids: turn/thrust/shoot — Newtonian flight with screen wrapping
//   Zelda: top-down tile level — solid house/water, depth-sorted trees
//   Skate: endless skateboard runner — jump the walls and pits
//   Point & click: adventure scene — tap to walk (A* around the tree), talk to the bird
//   Particles: spark fountain, tap fireworks, smoke trail on a dragged ball
//   Rhythm: DDR-style — catch falling gems on the beat pads
//   Camera: dead-zone follow, bounds, zoom buttons and screen shake
//   Circle solids: three emitters; every ball can hit any shape and push the other emitted balls
//   Rope: native Verlet ropes — drag the balls they hang from
//   Flip: flipX/flipY from movement — patrols turn around, tap flips gravity
//   Hitbox: debug overlays — full-frame vs hitboxScaleX/Y-tuned adventurer
//   Text: bitmap-font labels in the GL scene — HUD, world signs, text buttons
//   Swept: fast bullets vs a thin wall — swept: true stops the tunneling
//   Path & chain: native followPath circuits + play(name, { then }) chains
//   Raycast: line of sight, ledge probes and tap hitscan via gameView.raycast
//   Zones: collision/collisionend lifecycle — water tint, pressure-plate door
//   Demoscene: sine text scroller, copper bars, starfield + chiptune loop
//   Maze: A* playground — tap to route through a maze, a hound re-paths to you
//   Pool: 16 balls exchanging momentum — solidMode: 'push' plus linearDamping felt
//   Bingo drum: 25 balls in one circular container — solidMode: 'contain', no wall segments
//   Wind: gravityX — falling leaves drift sideways, and a top-down puck with gravity 0
//   Slopes: hitboxShape 'rotatedRect' on tilted ramps — a crate and a ball riding down them

var demos = [
	{ title: 'Asteroids', start: require('/asteroids') },
	{ title: 'Basic demo', start: require('/basic') },
	{ title: 'Bingo drum', start: require('/drum') },
	{ title: 'Blend & flash', start: require('/blend') },
	{ title: 'Camera', start: require('/camera') },
	{ title: 'Cards', start: require('/cards') },
	{ title: 'Circle solids', start: require('/circles') },
	{ title: 'Demoscene', start: require('/demoscene') },
	{ title: 'Flappy pig', start: require('/flappy') },
	{ title: 'Flip', start: require('/flip') },
	{ title: 'Hitbox', start: require('/hitbox') },
	{ title: 'Maze (A*)', start: require('/maze') },
	{ title: 'Particles', start: require('/particles') },
	{ title: 'Path & chain', start: require('/path') },
	{ title: 'Platformer', start: require('/platformer') },
	{ title: 'Plinko', start: require('/plinko') },
	{ title: 'Pool', start: require('/pool') },
	{ title: 'Point & click', start: require('/pointclick') },
	{ title: 'Puzzle demo', start: require('/puzzle') },
	{ title: 'Racing', start: require('/racing') },
	{ title: 'Raycast', start: require('/raycast') },
	{ title: 'Rhythm', start: require('/rhythm') },
	{ title: 'Rope', start: require('/rope') },
	{ title: 'Skate', start: require('/skate') },
	{ title: 'Slopes', start: require('/slopes') },
	{ title: 'Swept collision', start: require('/swept') },
	{ title: 'Text', start: require('/text') },
	{ title: 'Time scale', start: require('/timescale') },
	{ title: 'Top-Down Level', start: require('/topdown') },
	{ title: 'Trigger zones', start: require('/zones') },
	{ title: 'Volley', start: require('/volley') },
	{ title: 'Wind (gravityX)', start: require('/wind') }
];

var win = Ti.UI.createWindow({
	backgroundColor: '#202030',
	extendSafeArea: false,   // keep content clear of the notch and home bar
	layout: 'vertical',
	theme: "Theme.Titanium.DayNight.NoTitleBar"
});

win.add(Ti.UI.createLabel({
	text: 'ti.game examples',
	color: '#fff',
	extendSafeArea: false,
	font: { fontSize: 24, fontWeight: 'bold' },
	top: 20
}));

const sv = Ti.UI.createScrollView({
  layout: "vertical",
  top: 40,
  bottom: 40,
  contentHeight: Ti.UI.SIZE,
  width: Ti.UI.FILL
})

win.add(sv);

// Two demos per row
var row = null;
demos.forEach(function (demo, index) {
	if (index % 2 === 0) {
		row = Ti.UI.createView({
			layout: 'horizontal',
			horizontalWrap: false,
			width: Ti.UI.FILL,
			height: Ti.UI.SIZE,
			top: index === 0 ? 20 : 10
		});
		sv.add(row);
	}
	var button = Ti.UI.createButton({
		title: demo.title,
		left: '3%',
		width: '46%',
		color: '#fff',
		backgroundColor: '#000',
		borderColor: '#fff',
		borderWidth: 1
	});
	button.addEventListener('click', function () {
		demo.start();
	});
	row.add(button);
});

win.open();
