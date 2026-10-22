// A playable input map: native movement, shared digital actions and visible help.
module.exports = function () {
	var Game = require('ti.game');
	var nativeTitleBar = Ti.Platform.osname === 'android';
	var win = Ti.UI.createWindow({ backgroundColor: '#18394d', title: 'Configurable input', theme: 'Theme.Titanium.DayNight' });
	var view = Game.createGameView({ backgroundColor: '#8ed8f8', inputMap: { gameplay: {
		left: [{ device: 'keyboard', code: 'KeyA' }, { device: 'keyboard', code: 'KeyJ' }, { device: 'keyboard', code: 'ArrowLeft' }, { device: 'gamepad', button: 'left' }],
		right: [{ device: 'keyboard', code: 'KeyD' }, { device: 'keyboard', code: 'KeyL' }, { device: 'keyboard', code: 'ArrowRight' }, { device: 'gamepad', button: 'right' }],
		jump: [{ device: 'keyboard', code: 'Space' }, { device: 'gamepad', button: 'a' }],
		aimUp: [{ device: 'keyboard', code: 'KeyW' }, { device: 'keyboard', code: 'KeyI' }, { device: 'keyboard', code: 'ArrowUp' }, { device: 'gamepad', button: 'up' }],
		crouch: [{ device: 'keyboard', code: 'KeyS' }, { device: 'keyboard', code: 'KeyK' }, { device: 'keyboard', code: 'ArrowDown' }, { device: 'gamepad', button: 'down' }],
		fire: [{ device: 'mouse', button: 'left' }, { device: 'gamepad', button: 'x' }],
		pause: [{ device: 'keyboard', code: 'Escape' }],
		mouseRight: [{ device: 'mouse', button: 'right' }],
		mouseMiddle: [{ device: 'mouse', button: 'middle' }]
	}, paused: { pause: [{ device: 'keyboard', code: 'Escape' }] } } });
	var playerSheet = Game.createSpriteSheet({ image: 'assets/player.png', frameWidth: 64, frameHeight: 64 });
	var groundSheet = Game.createSpriteSheet({ image: 'assets/ground.png', frameWidth: 64, frameHeight: 64 });
	var hillsSheet = Game.createSpriteSheet({ image: 'assets/hills.png', frameWidth: 512, frameHeight: 114 });
	var ballSheet = Game.createSpriteSheet({ image: 'assets/ball.png', frameWidth: 64, frameHeight: 64 });
	var player, ground, hills, leftWall, rightWall;
	var held = { left: false, right: false, aimUp: false, crouch: false };
	var standingSize = 0, lastDirection = 1;
	var airborne = false;
	var facing = 1, density = 1, speed = 0, shots = 0, closed = false, typingActive = false;
	var timers = [];
	var paused = false, lastKey = 'KEY —', lastPad = 'PAD —';

	var title = Ti.UI.createLabel({ top: 30, left: 124, right: 16, height: 48,
		color: '#18394d', font: { fontSize: 18, fontWeight: 'bold' }, text: 'INPUT PLAYGROUND', touchEnabled: false });
	var help = Ti.UI.createView({ top: nativeTitleBar ? 12 : 82, width: '92%', height: Ti.UI.SIZE, layout: 'vertical',
		backgroundColor: '#18394d', borderRadius: 12, touchEnabled: false });
	var instructions = Ti.UI.createLabel({ top: 8, left: 12, right: 12, height: Ti.UI.SIZE,
		color: '#eaf5f6', font: { fontSize: 12 }, text: 'MOVE A/D · ←/→ · J/L    JUMP Space' });
	help.add(instructions);
	[
		'AIM W/I/↑ + direction    CROUCH S/K/↓',
		'FIRE Left click    PAUSE Esc',
		'PAD Stick/D-pad: move/aim/crouch · A jump · X fire',
		'MOUSE Right/Middle: test'
	].forEach(function (text, index) {
		help.add(Ti.UI.createLabel({ top: 5, bottom: index === 3 ? 8 : 0, left: 12, right: 12, height: Ti.UI.SIZE,
			color: index < 2 ? '#eaf5f6' : '#bed4de', font: { fontSize: index < 2 ? 12 : 11 }, text: text }));
	});
	var footer = Ti.UI.createView({ bottom: 16, width: '92%', height: 108,
		backgroundColor: '#18394d', borderRadius: 12 });
	var status = Ti.UI.createLabel({ top: 8, left: 12, right: 12, height: 18,
		color: '#8de8bd', font: { fontSize: 12 }, text: 'READY  /  SHOTS 0' });
	var inputStatus = Ti.UI.createLabel({ top: 28, left: 12, right: 12, height: 32,
		color: '#bed4de', font: { fontSize: 11 }, text: lastKey + '\n' + lastPad });
	var typing = Ti.UI.createTextField({ bottom: 8, left: 12, right: 148, height: 36,
		color: '#18394d', hintTextColor: '#587080', hintText: 'Type here', backgroundColor: '#fff', borderRadius: 8,
		font: { fontSize: 12 }, paddingLeft: 10 });
	var focus = Ti.UI.createButton({ bottom: 8, right: 12, width: 128, height: 36,
		font: { fontSize: 11 }, title: 'Focus canvas' });
	footer.add(status); footer.add(inputStatus); footer.add(typing); footer.add(focus);

	function movement() {
		if (!player) return;
		var bottom = player.y + player.height / 2;
		player.height = standingSize * (held.crouch && !airborne ? 0.55 : 1);
		player.y = bottom - player.height / 2;
		var direction = held.left && held.right ? lastDirection : Number(held.right) - Number(held.left);
		player.velocityX = direction * speed;
		if (direction) { facing = direction; player.scaleX = facing; }
		if (!airborne) player.play(direction ? 'walk' : 'idle');
	}
	function release() {
		held.left = held.right = held.aimUp = held.crouch = false;
		movement();
	}
	function focusCanvas() {
		if (closed) return;
		typingActive = false;
		typing.blur();
		view.inputContext = paused ? 'paused' : 'gameplay';
		view.focusInput();
		feedback('CANVAS READY');
	}
	function feedback(message) {
		status.text = paused ? 'PAUSED  /  Esc TO RESUME' : message + '  /  SHOTS ' + shots;
	}
	function togglePause() {
		paused = !paused;
		release();
		view.timeScale = paused ? 0 : 1;
		view.inputContext = paused ? 'paused' : 'gameplay';
		feedback('RESUMED');
	}
	function showInput() { inputStatus.text = lastKey + '\n' + lastPad; }
	['keydown', 'keyup'].forEach(function (name) {
		view.addEventListener(name, function (e) {
			var mods = e.modifiers || {};
			var prefix = ['control', 'shift', 'alt', 'meta'].filter(function (key) { return mods[key]; })
				.map(function (key) { return key.charAt(0).toUpperCase() + key.slice(1); });
			lastKey = 'KEY ' + prefix.concat([e.code]).join('+') + (name === 'keydown' ? ' DOWN' : ' UP');
			showInput();
		});
	});
	// These listeners only display diagnostics. Mapped actions have one gameplay route.
	['buttondown', 'buttonup'].forEach(function (name) {
		view.addEventListener(name, function (e) {
			lastPad = 'PAD ' + e.button + (name === 'buttondown' ? ' DOWN' : ' UP');
			showInput();
		});
	});
	view.addEventListener('stick', function (e) {
		lastPad = 'PAD ' + e.stick + ' stick ' + Number(e.x).toFixed(2) + ', ' + Number(e.y).toFixed(2);
		showInput();
	});
	view.addEventListener('trigger', function (e) {
		lastPad = 'PAD ' + e.trigger + ' ' + Number(e.value).toFixed(2);
		showInput();
	});
	view.addEventListener('gamepadconnected', function (e) { lastPad = 'PAD ' + e.name + ' CONNECTED'; showInput(); });
	view.addEventListener('gamepaddisconnected', function () { lastPad = 'PAD DISCONNECTED'; showInput(); });
	function jump() {
		if (!player || airborne || !player.onGround) return;
		airborne = true;
		movement();
		player.velocityY = -500 * density;
		player.stop();
		player.frame = 3;
	}
	function fire() {
		if (!player) return;
		var dx = held.aimUp ? (held.left && held.right ? lastDirection : Number(held.right) - Number(held.left)) : facing;
		var dy = held.aimUp ? -1 : 0;
		var length = Math.sqrt(dx * dx + dy * dy);
		dx /= length; dy /= length;
		var ball = Game.createSprite({ sheet: ballSheet, x: player.x + dx * player.width * 0.55,
			y: player.y + dy * player.height * 0.55, width: 18 * density, height: 18 * density,
			velocityX: dx * 420 * density, velocityY: dy * 420 * density, angularVelocity: facing * 240,
			collisionGroup: 'input-shot', touchEnabled: false, zIndex: 3 });
		view.add(ball);
		player.flash('#fff', 100);
		shots++;
		// The engine moves projectiles. JS only handles the one-shot expiry.
		var timer = view.after(1200, function () {
			view.remove(ball);
			var index = timers.indexOf(timer);
			if (index !== -1) timers.splice(index, 1);
		});
		timers.push(timer);
	}
	view.addEventListener('resize', function (e) {
		if (closed) return;
		help.width = footer.width = Math.min(600, Math.max(1, view.rect.width - 32));
		density = view.rect.width > 0 ? e.width / view.rect.width : Ti.Platform.displayCaps.logicalDensityFactor || 1;
		var size = Math.min(72 * density, e.height * 0.14, e.width * 0.18);
		var floorY = e.height * 0.67;
		speed = 240 * density;
		if (!player) {
			hills = Game.createSprite({ sheet: hillsSheet, touchEnabled: false, zIndex: -2 });
			ground = Game.createSprite({ sheet: groundSheet, collisionGroup: 'input-ground', touchEnabled: false, zIndex: -1 });
			leftWall = Game.createSprite({ collisionGroup: 'input-wall', touchEnabled: false });
			rightWall = Game.createSprite({ collisionGroup: 'input-wall', touchEnabled: false });
			player = Game.createSprite({ sheet: playerSheet, x: e.width / 2, zIndex: 2,
				solidWith: ['input-wall', 'input-ground'], animations: { idle: { frames: [0], fps: 1, loop: true }, walk: { frames: [1, 2], fps: 8, loop: true } } });
			player.addEventListener('land', function () { airborne = false; movement(); });
			view.add([hills, ground, leftWall, rightWall, player]);
		}
		hills.x = ground.x = e.width / 2;
		hills.width = ground.width = e.width;
		hills.height = e.height * 0.4; hills.y = floorY - hills.height / 2;
		ground.height = e.height - floorY; ground.y = floorY + ground.height / 2;
		leftWall.x = -size / 2; rightWall.x = e.width + size / 2;
		[leftWall, rightWall].forEach(function (wall) { wall.y = e.height / 2; wall.width = size; wall.height = e.height * 2; });
		standingSize = size;
		player.width = player.height = size;
		player.x = Math.max(size / 2, Math.min(e.width - size / 2, player.x));
		player.y = floorY - size / 2;
		player.velocityY = 0;
		player.gravity = 1400 * density;
		airborne = false;
		movement();
	});
	view.addEventListener('actiondown', function (e) {
		if (e.action === 'pause') { togglePause(); return; }
		if (paused) return;
		if (Object.prototype.hasOwnProperty.call(held, e.action)) {
			if (e.action === 'left' || e.action === 'right') lastDirection = e.action === 'left' ? -1 : 1;
			held[e.action] = true; movement();
		}
		else if (e.action === 'jump') jump();
		else if (e.action === 'fire') fire();
		else if (e.action === 'mouseRight' || e.action === 'mouseMiddle') { if (player) player.flash('#83d6ff', 200); }
		feedback(e.action.toUpperCase() + ' DOWN');
	});
	view.addEventListener('actionup', function (e) {
		if (Object.prototype.hasOwnProperty.call(held, e.action)) { held[e.action] = false; movement(); }
		feedback(e.action.toUpperCase() + ' UP');
	});
	typing.addEventListener('focus', function () { typingActive = true; view.inputContext = null; release(); status.text = 'TYPING  /  GAME INPUT OFF'; });
	focus.addEventListener('click', focusCanvas);
	// With actions disabled for text entry, the engine still delivers canvas taps.
	view.addEventListener('tap', focusCanvas);
	win.add(view);
	if (!nativeTitleBar) win.add(title);
	win.add(help); win.add(footer);
	require('/backnav')(win);
	win.addEventListener('open', focusCanvas);
	win.addEventListener('blur', function () { view.inputContext = null; release(); });
	win.addEventListener('focus', function () { if (!closed && !typingActive) { view.inputContext = paused ? 'paused' : 'gameplay'; view.focusInput(); } });
	win.addEventListener('close', function () {
		closed = true;
		view.inputContext = null;
		release();
		timers.forEach(function (timer) { view.cancelTimer(timer); });
		[playerSheet, groundSheet, hillsSheet, ballSheet].forEach(function (sheet) { sheet.unload(); });
	});
	win.open();
};
