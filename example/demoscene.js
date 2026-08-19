// ti.game demoscene demo — old-school cracktro: sine scroller, copper
// bars, starfield and a chiptune, all on native animation.
//
// - sine text scroller: every character is its own text sprite riding
//   the SAME closed loop with followPath (sine wave across the screen,
//   return leg routed below the screen) — each letter's path array is
//   rotated by its arc offset, so constant path speed keeps the letter
//   spacing forever with zero per-frame JS
// - copper bars: full-width additive gradient bars on looping circle
//   paths — constant speed around a circle is a perfect sine in y, and
//   staggered start angles turn the bars into a trailing snake
// - logo floats on a small circle path with a glow; the subtitle pulses
//   by chaining opacity tweens from 'complete'
// - parallax starfield: two tileRepeat layers, each tween-scrolled by
//   exactly one 512px texture period and snapped back seamlessly
// - chiptune loop (square lead, C64-style arps, octave bass, noise
//   drums) on the streaming music backend, stopped when the window
//   closes
//
// Exports a start function; the demo opens its own window each time.

var Game = require('ti.game');

module.exports = function () {

	var win = Ti.UI.createWindow({
		backgroundColor: '#000',
		theme: 'Theme.Titanium.DayNight.NoTitleBar'
	});
	var gameView = Game.createGameView({ backgroundColor: '#05060f' });

	var starSheet = Game.createSpriteSheet({ image: 'assets/stars.png', frameWidth: 512, frameHeight: 512, repeat: true });
	var barSheet = Game.createSpriteSheet({ image: 'assets/copperbar.png', frameWidth: 8, frameHeight: 64 });

	var music = Game.createSound({ url: 'assets/demoscene.wav', music: true, loop: true, volume: 0.6 });
	win.addEventListener('close', function () {
		music.stop();
	});

	var initialized = false;
	gameView.addEventListener('resize', function (e) {
		if (!initialized) {
			initialized = true;
			init(e.width, e.height);
			music.play();
		}
	});

	// --- closed-loop helpers for the scroller --------------------------

	function makeLoop(points) {
		// cumulative arc length; total includes the closing segment
		var cum = [0];
		var total = 0;
		for (var i = 1; i < points.length; i++) {
			total += dist(points[i - 1], points[i]);
			cum.push(total);
		}
		return { points: points, cum: cum, total: total + dist(points[points.length - 1], points[0]) };
	}

	function dist(a, b) {
		var dx = b[0] - a[0], dy = b[1] - a[1];
		return Math.sqrt(dx * dx + dy * dy);
	}

	// The same loop, rewritten to start `offset` px along its arc —
	// letters on rotated copies of one loop keep their spacing forever.
	function rotatedPath(loop, offset) {
		var pts = loop.points, cum = loop.cum, total = loop.total;
		var n = pts.length;
		var s = ((offset % total) + total) % total;
		var i = 0;
		while (i < n - 1 && cum[i + 1] <= s) i++;
		var a = pts[i];
		var b = (i === n - 1) ? pts[0] : pts[i + 1];
		var segLen = ((i === n - 1) ? total : cum[i + 1]) - cum[i];
		var f = segLen > 0 ? (s - cum[i]) / segLen : 0;
		var out = [[a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]];
		for (var j = i + 1; j < n; j++) out.push(pts[j]);
		for (j = 0; j <= i; j++) out.push(pts[j]);
		// drop a duplicated endpoint (offset landed exactly on a vertex)
		if (dist(out[out.length - 1], out[0]) < 0.001) out.pop();
		return out;
	}

	function hsvToHex(h, s, v) {
		var i = Math.floor(h * 6) % 6;
		var f = h * 6 - Math.floor(h * 6);
		var p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
		var rgb = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i];
		return '#' + rgb.map(function (c) {
			return ('0' + Math.round(c * 255).toString(16)).slice(-2);
		}).join('');
	}

	function init(W, H) {

		var UNIT = Math.max(1, Math.round(W / 200)); // pixel-font scale

		// --- parallax starfield: scroll one texture period, snap back --

		[
			{ dur: 40000, opacity: 0.35, z: 0 },
			{ dur: 16000, opacity: 0.8, z: 1 }
		].forEach(function (layer) {
			var stars = Game.createSprite({
				sheet: starSheet,
				anchorX: 0, anchorY: 0,
				x: 0, y: 0,
				width: W + 512, height: H,
				tileRepeat: true,
				opacity: layer.opacity,
				zIndex: layer.z
			});
			gameView.add(stars);
			stars.addEventListener('complete', function () {
				stars.x = 0; // moved exactly -512 = one tile period: invisible
				stars.animate({ x: -512, duration: layer.dur, easing: Game.EASE_LINEAR });
			});
			stars.animate({ x: -512, duration: layer.dur, easing: Game.EASE_LINEAR });
		});

		// --- copper bars: sine bob = constant speed on a circle --------

		var BAR_R = H * 0.085;          // bob amplitude
		var barY = H * 0.40;
		var BAR_PERIOD = 2.4;           // seconds per bob
		for (var b = 0; b < 8; b++) {
			var phase = b * 0.45;       // stagger = trailing snake
			var circle = [];
			for (var k = 0; k < 32; k++) {
				var ang = phase + k / 32 * 2 * Math.PI;
				circle.push([W / 2 + BAR_R * Math.cos(ang), barY + BAR_R * Math.sin(ang)]);
			}
			var bar = Game.createSprite({
				sheet: barSheet,
				x: circle[0][0],
				y: circle[0][1],
				width: W + 2 * BAR_R + 8, // x sways ±R on the circle: keep it full-width
				height: H * 0.028,
				tintColor: hsvToHex(b / 8, 0.9, 1),
				blend: 'add',
				zIndex: 2
			});
			gameView.add(bar);
			bar.followPath(circle, { speed: 2 * Math.PI * BAR_R / BAR_PERIOD, loop: true });
		}

		// --- floating logo + pulsing subtitle --------------------------

		var logo = Game.createText({
			text: 'TI.GAME',
			x: W / 2,
			y: H * 0.14,
			scale: UNIT * 2.6,
			letterSpacing: 1,
			tintColor: '#ffd54a',
			glowColor: '#ff9500',
			glowBlur: 8,
			glowOpacity: 0.6,
			zIndex: 20
		});
		gameView.add(logo);
		var logoR = H * 0.015;
		var logoCircle = [];
		for (var m = 0; m < 24; m++) {
			var la = m / 24 * 2 * Math.PI;
			logoCircle.push([W / 2 + logoR * Math.cos(la), H * 0.14 + logoR * Math.sin(la)]);
		}
		logo.followPath(logoCircle, { speed: 2 * Math.PI * logoR / 3, loop: true });

		var sub = Game.createText({
			text: '* SINE SCROLLER * COPPER BARS * CHIPTUNE *',
			x: W / 2,
			y: H * 0.24,
			scale: Math.max(1, UNIT * 0.5), // 43 glyphs must fit the width
			tintColor: '#5ac8fa',
			zIndex: 20
		});
		gameView.add(sub);
		var dim = true;
		sub.addEventListener('complete', function () {
			dim = !dim;
			sub.animate({ opacity: dim ? 0.25 : 1, duration: 550, easing: Game.EASE_IN_OUT });
		});
		sub.animate({ opacity: 0.25, duration: 550, easing: Game.EASE_IN_OUT });

		// --- the sine scroller -----------------------------------------

		var MSG = 'HELLO WORLD !!!    WELCOME TO THE TI.GAME MEGA DEMO    '
			+ 'GREETINGS TO ALL TITANIUM CODERS    KEEP THE SCENE ALIVE ...    ';
		var SCALE = UNIT * 2;
		var SPACING = 9 * SCALE + UNIT;      // built-in font is 9px wide per glyph
		var SPEED = W * 0.28;                // px/s along the path
		var AMP = H * 0.10;
		var MID_Y = H * 0.68;
		var WAVE = W * 0.55;

		// visible leg: right edge to left edge along a sine wave
		var x0 = W + 60, x1 = -60;
		var pts = [];
		for (var x = x0; x >= x1; x -= 12) {
			pts.push([x, MID_Y + AMP * Math.sin(x / WAVE * 2 * Math.PI)]);
		}

		// off-screen return leg below the screen; a hidden detour spike
		// pads the loop so the whole message + a gap fits without overlap
		var deep = H + 80;
		var yExit = pts[pts.length - 1][1];
		var yEntry = pts[0][1];
		var arcVis = 0;
		for (var v = 1; v < pts.length; v++) arcVis += dist(pts[v - 1], pts[v]);
		var baseLen = arcVis + (deep - yExit) + (x0 - x1) + (deep - yEntry);
		var needed = MSG.length * SPACING + W * 0.5;
		var extra = Math.max(0, needed - baseLen);
		pts.push([x1, deep]);
		if (extra > 0) {
			var xm = (x0 + x1) / 2;
			pts.push([xm, deep]);
			pts.push([xm, deep + extra / 2]);
			pts.push([xm + 2, deep + extra / 2]);
			pts.push([xm + 2, deep]);
		}
		pts.push([x0, deep]); // loop: true closes back up to the entry point

		var loop = makeLoop(pts);
		for (var c = 0; c < MSG.length; c++) {
			if (MSG.charAt(c) === ' ') continue;
			// letter c trails the head by c * SPACING of arc length
			var path = rotatedPath(loop, loop.total - c * SPACING);
			var letter = Game.createText({
				text: MSG.charAt(c),
				x: path[0][0],
				y: path[0][1],
				scale: SCALE,
				tintColor: hsvToHex((c / 24) % 1, 0.75, 1),
				zIndex: 10
			});
			gameView.add(letter);
			letter.followPath(path, { speed: SPEED, loop: true });
		}
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
