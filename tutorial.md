# Getting started with ti.game

This tutorial builds one small scene from scratch: a sprite that idles,
plays a walk animation, and walks to wherever you tap. Each step adds a
few lines; the complete file is at the end. For the full API see
`README.md`, for bigger patterns see the demos in `example/`.

## 1. Install the module

Build it (or grab the prebuilt zip from `android/dist/`):

```bash
cd android
ti build -p android --build-only   # produces android/dist/ti.game-android-<version>.zip
```

Add the zip to your app (`~/Library/Application Support/Titanium/modules`
or the app's `modules/` folder) and register it in `tiapp.xml`:

```xml
<modules>
  <module platform="android">ti.game</module>
</modules>
```

Then require it in your `app.js`:

```javascript
var Game = require('ti.game');
```

## 2. Set up a basic scene

A scene is a **GameView** inside a normal Titanium window. The engine
runs the game loop natively at 60 fps — you never write a loop yourself,
you just describe the scene and react to events.

```javascript
var win = Ti.UI.createWindow({
	backgroundColor: '#000',
	theme: 'Theme.Titanium.DayNight.NoTitleBar'
});
var gameView = Game.createGameView({
	backgroundColor: '#8ed8f8'   // GL clear color = your sky
});
win.add(gameView);
win.open();
```

One important habit from the start: **don't size your level from
`Ti.Platform.displayCaps`** — it includes the system bars. The GameView
fires `resize` with the real surface size in pixels; build everything
there:

```javascript
var initialized = false;
gameView.addEventListener('resize', function (e) {
	if (!initialized) {
		initialized = true;
		init(e.width, e.height);   // the actual scene coordinate space
	}
});

function init(W, H) {
	// everything below goes in here
}
```

Coordinates are top-left origin, y-down, in surface pixels — touch
coordinates map 1:1.

## 3. Add a sprite

Sprites get their frames from a **SpriteSheet** — an image cut into
equal cells (or a TexturePacker atlas). This example uses the walk
sheet from the point-and-click demo, `example/assets/adventurer.png`:
three 32x48 cells side by side (idle, walk A, walk B). Copy it next to
your `app.js`.

```javascript
var sheet = Game.createSpriteSheet({
	image: 'adventurer.png',
	frameWidth: 32,
	frameHeight: 48,
	smoothing: false   // nearest-neighbor — keeps pixel art crisp
});

var hero = Game.createSprite({
	sheet: sheet,
	x: W / 2,          // (x, y) positions the anchor — default is the center
	y: H / 2,
	width: 96,         // omit to use the frame size; scaling is free
	height: 144
});
gameView.add(hero);
```

That's a static sprite showing frame 0.

## 4. Add a sprite animation

Declare named animations on the sprite — frame indices plus an fps —
and start one with `play()`. The frame stepping happens natively; JS is
not involved while it runs.

```javascript
var hero = Game.createSprite({
	sheet: sheet,
	x: W / 2,
	y: H / 2,
	width: 96,
	height: 144,
	animations: {
		idle: { frames: [0], fps: 1, loop: true },
		walk: { frames: [1, 2], fps: 6, loop: true }
	}
});
hero.play('idle');
```

Non-looping animations fire an `animationcomplete` event when they
finish — handy for one-shot effects (see the jump handling in
`example/platformer.js`).

## 5. React to a click

Sprites fire high-level touch events (`tap`, `press`, `dragstart`, ...)
after native hit-testing against their transformed bounds. The GameView
itself also fires `tap` for **every** touch, which is perfect for
"click anywhere" controls:

```javascript
hero.addEventListener('tap', function () {
	// tapped the hero itself
});

gameView.addEventListener('tap', function (e) {
	// tapped anywhere; e.x / e.y are scene coordinates
});
```

Note that both fire when the tap lands on the sprite — if that matters,
compare `e.x`/`e.y` against the sprite's bounds in the view handler
(see `example/pointclick.js`).

## 6. Move the sprite and play the animation

The cheapest way to move something is to let the engine do it. For
"go to this position" use a tween: `animate()` runs natively and fires
`complete` when done. Combine it with `play()` and a `scaleX` flip and
you have a walking character:

```javascript
var WALK_SPEED = W * 0.35;   // px/s

gameView.addEventListener('tap', function (e) {
	var distance = Math.sqrt(
		Math.pow(e.x - hero.x, 2) + Math.pow(e.y - hero.y, 2));
	if (distance < 4) {
		return;
	}
	hero.scaleX = e.x < hero.x ? -1 : 1;   // face the walk direction
	hero.clearTweens();                    // cancel a walk in progress
	hero.play('walk');
	hero.animate({
		x: e.x,
		y: e.y,
		duration: distance / WALK_SPEED * 1000,   // constant speed
		easing: Game.EASE_LINEAR
	});
});

hero.addEventListener('complete', function () {
	hero.play('idle');   // arrived — stop walking
});
```

For continuous motion (runners, projectiles, platformers) set
`velocityX`/`velocityY`/`gravity` instead of tweening — the engine
integrates them every frame. The rule of thumb for everything in
ti.game: **JS sets a property once per input or event; the engine does
the per-frame work.** If you're about to move a sprite from a
`setInterval`, there's a native feature that does it better (velocity,
tween, `carMode`, `thrust`, ...).

## The complete app.js

```javascript
var Game = require('ti.game');

var win = Ti.UI.createWindow({
	backgroundColor: '#000',
	theme: 'Theme.Titanium.DayNight.NoTitleBar'
});
var gameView = Game.createGameView({
	backgroundColor: '#8ed8f8'
});

var sheet = Game.createSpriteSheet({
	image: 'adventurer.png',
	frameWidth: 32,
	frameHeight: 48,
	smoothing: false
});

var initialized = false;
gameView.addEventListener('resize', function (e) {
	if (!initialized) {
		initialized = true;
		init(e.width, e.height);
	}
});

function init(W, H) {
	var WALK_SPEED = W * 0.35;

	var hero = Game.createSprite({
		sheet: sheet,
		x: W / 2,
		y: H / 2,
		width: 96,
		height: 144,
		animations: {
			idle: { frames: [0], fps: 1, loop: true },
			walk: { frames: [1, 2], fps: 6, loop: true }
		}
	});
	hero.play('idle');
	gameView.add(hero);

	gameView.addEventListener('tap', function (e) {
		var distance = Math.sqrt(
			Math.pow(e.x - hero.x, 2) + Math.pow(e.y - hero.y, 2));
		if (distance < 4) {
			return;
		}
		hero.scaleX = e.x < hero.x ? -1 : 1;
		hero.clearTweens();
		hero.play('walk');
		hero.animate({
			x: e.x,
			y: e.y,
			duration: distance / WALK_SPEED * 1000,
			easing: Game.EASE_LINEAR
		});
	});

	hero.addEventListener('complete', function () {
		hero.play('idle');
	});
}

win.add(gameView);
win.open();
```

## Where to go next

- **Physics & collisions**: `velocityX/Y`, `gravity`, `solidWith`,
  `collidesWith` — see `example/flappy.js` and `example/platformer.js`.
- **Drag & drop, pinch, rotate**: set `draggable`/`pinchable`/
  `rotatable` — see `example/basic.js` and `example/puzzle.js`.
- **Scrolling worlds**: `cameraX/Y`, `follow()`, parallax via
  `wrapX`/`wrapShift` — see `example/skate.js`.
- The full property/event reference is in `README.md`.
