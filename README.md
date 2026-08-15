# ti.game

A 2D sprite game engine module for Titanium SDK (Android), rendered with
OpenGL ES 2.0. You describe your scene and react to events from
JavaScript; everything that runs every frame — rendering, animation,
physics, collision, gestures — runs natively at 60 fps.

**Features**

- Sprite sheets (grid or TexturePacker atlas), frame animations, tweens
- Touch: tap, press, drag & drop, pinch-to-scale, two-finger rotate
- Physics: velocity + gravity, platformer solids, bouncing (restitution),
  arcade car model with drifting + skid marks, Newtonian flight (thrust)
- Collision groups with events, invisible trigger zones, hitbox tuning
- Parallax scroll looping, screen wrapping, idle wobble animation
- Pixel-art mode (nearest-neighbor filtering), debug overlay for hitboxes
- 11 example games in `example/` covering every feature

New to the module? `tutorial.md` walks through your first scene
step by step — sprite, animation, tap-to-move.

## Quick start

1. Build the module (or grab `android/dist/ti.game-android-<version>.zip`)
   and add it to your app's `tiapp.xml`:

   ```xml
   <modules>
     <module platform="android">ti.game</module>
   </modules>
   ```

2. A minimal game:

   ```javascript
   var Game = require('ti.game');

   var win = Ti.UI.createWindow({ backgroundColor: '#000' });
   var gameView = Game.createGameView({ backgroundColor: '#202030' });

   var sheet = Game.createSpriteSheet({
       image: 'hero.png',
       frameWidth: 64, frameHeight: 64   // grid sheet
       // or: atlas: 'hero.json'         // TexturePacker JSON (hash or array)
       // add smoothing: false for crisp pixel art
   });

   var hero = Game.createSprite({
       sheet: sheet,
       x: 100, y: 200,
       draggable: true,
       animations: {
           walk: { frames: [0, 1, 2, 3], fps: 12, loop: true },
           jump: { frames: [4, 5, 6], fps: 10 }
       }
   });
   hero.play('walk');
   hero.addEventListener('tap', function () { hero.play('jump'); });

   gameView.add(hero);
   win.add(gameView);
   win.open();
   ```

That's the whole model: create a **GameView** (the canvas), create
**SpriteSheets** (textures cut into frames), create **Sprites** (things on
screen), set properties, listen for events. You never write a game loop —
the engine runs it natively.

## Core concepts

### JS describes, native executes

The Kroll bridge (JS ↔ Java) is far too slow for per-frame work. So the
JS API is a *scene description*: setting `sprite.x`, `sprite.velocityY` or
`sprite.throttle` writes into a native object that the render thread reads
every frame. Events flow the other way — the engine fires discrete,
high-level events (`tap`, `dragend`, `collision`, `land`, `complete`),
never anything per-frame. If you find yourself wanting a `setInterval`
that moves a sprite, look for the native feature that does it instead
(velocity, tween, thrust, carMode, ...). Coarse timers for *decisions*
(an AI choosing where to go, autofire) are fine — see the volley and
asteroids demos.

### Coordinates

Top-left origin, y-down, in surface **pixels** — touch coordinates map
1:1. `(x, y)` positions the sprite's anchor point (default `0.5/0.5` =
center). Rotation is in degrees, positive = clockwise.

### Size your level on `resize`, not on the display size

`Ti.Platform.displayCaps` includes the system bars, so bottom-anchored
sprites computed from it can land below the visible surface. The GameView
fires `resize` with the real surface size — build your level there:

```javascript
gameView.addEventListener('resize', function (e) {
    if (!initialized) {
        initialized = true;
        buildLevel(e.width, e.height);   // the actual scene coordinate space
    }
});
```

## Performance: what runs where

Three threads touch a running game — knowing what happens on each is the
key to understanding both the performance and the API design:

| Thread | Runs | Bridge involved? |
|---|---|---|
| **GL render thread** | The entire game loop: delta time, physics (velocity/gravity, solids, `carMode`, `thrust`), collision checks, tween/animation/idle ticking, skid trail, wrapping, z-sorting, batching, drawing | No |
| **Android UI thread** | Touch handling: hit-testing, drag movement, pinch/rotate gestures | No |
| **JS/Kroll thread** | Your game code: creating sprites, setting properties, handling events | Yes — this is the only place the Titanium bridge exists |

**Per frame, on-device, zero bridge traffic.** Every 16 ms tick reads and
writes only native `Sprite` objects in the scene graph. A drag moves the
sprite on the UI thread; a tween, a falling bird, a drifting car, a
bouncing ball all advance on the GL thread. Nothing in the frame loop
waits for — or even talks to — JavaScript, so JS garbage collection or a
busy app thread can't cause stutter.

**What crosses the bridge, and when:**

- *Property writes* (`hero.x = 100`, `car.throttle = 1`) — one cheap
  bridge hop per assignment, writing a volatile field the render thread
  picks up next frame. Setting a property once per user input is the
  intended pattern.
- *Property reads* (`ball.x`) — synchronous snapshot of the live native
  value. Fine for event handlers and coarse timers (the volley AI reads a
  few per 80 ms tick); don't poll them in a tight loop.
- *Events* — fired natively only when something discrete happens, and only
  if a listener is registered (`hasListeners` is checked before paying the
  bridge cost). Continuous gestures are throttled (`drag` at ~10 Hz);
  nothing fires per frame by design.

**Rendering.** Sprites are drawn by an ES 2.0 batcher that accumulates
quads and issues one draw call per texture switch (up to 1000 quads per
batch). Practical consequence: pack your art into as few sheets as
possible — a scene whose sprites share one atlas renders in a single draw
call regardless of sprite count. Per-sprite transform math is done on the
CPU and is trivial at typical scene sizes; hundreds of animated, moving
sprites are no problem. Textures upload to the GPU once, lazily, on first
use; the EGL context is preserved across app pauses, and after a real
context loss everything (textures, shaders) is re-created automatically.

**Collision cost** is O(colliders × candidates) per frame — each sprite
with `collidesWith`/`solidWith` is tested against sprites carrying a
matching `collisionGroup`. Keep group lists targeted (a bullet checking
`['asteroid']` tests 5 sprites, not the whole scene) and it stays
negligible.

**Rule of thumb:** if JS runs code every frame, you're fighting the
engine; if JS only reacts to events and sets properties, you get native
performance for free.

## Building blocks

### Show and animate things

- **Sheets**: `createSpriteSheet({ image, frameWidth, frameHeight })` for
  grids, or `{ image, atlas }` for TexturePacker JSON. `smoothing: false`
  switches to nearest-neighbor filtering for pixel art. Textures load
  lazily on the GL thread and survive EGL context loss automatically.
- **Frame animations**: declare named animations on the sprite
  (`{ frames, fps, loop }`), control with `play(name)` / `stop()` / the
  `frame` property. Non-looping animations fire `animationcomplete`.
- **Tweens**: `sprite.animate({ x, y, scale, rotation, opacity, duration,
  delay, easing })` (ms; easing from the `EASE_*` constants) animates
  natively and fires `complete`. Chain moves by re-calling `animate` from
  the `complete` handler.
- **Idle wobble**: `idleAnimation: true` adds a gentle organic sway —
  up to `idleRotation` degrees and `idleMovement` px around the base
  transform, `idleSpeed` scales the frequency. Every sprite gets its own
  phase; it composes with tweens/drags and unwinds exactly when disabled.
  Tip: disable it *before* tweening a sprite to a spot where alignment
  matters (see the cards demo).

### React to touch

Enable behaviors per sprite: `draggable` (native drag & drop),
`pinchable` (two-finger scale), `rotatable` (two-finger rotate). The
engine hit-tests taps against the sprites' transformed shapes (rotation
and scale included, topmost first) and fires `press`, `tap`, `dragstart`,
`drag` (~10 Hz), `dragend`, `release`, `pinch`, `rotate`. The drag itself
happens natively — JS only hears the milestones.

The GameView also fires `press` / `tap` / `release` for *every* touch
(tap-anywhere controls, flappy-style). Standard Titanium touch events are
not available on the game view — but ordinary Titanium buttons/views
overlaid on top work normally, and separate views receive simultaneous
pointers, which is how the demos do multitouch d-pads (hold ▶ + jump).

### Move things (pick the model that fits your game)

| Model | Properties | Feels like |
|---|---|---|
| Plain velocity | `velocityX/Y` (px/s), `gravity` (px/s²) | Flappy, projectiles, falling |
| Platformer | velocity + `solidWith`, `onGround`, `land` event | Mario-style run & jump |
| Bouncing body | `restitution` (0..1) on top of `solidWith` | Balls, pinball-ish |
| Car (`carMode`) | `throttle`, `steering` (-1..1); `enginePower`, `maxSpeed`, `turnRate`, `grip`, `drag` | Top-down racer with drift |
| Newtonian flight | `thrust` (px/s² along heading), `angularVelocity` (deg/s), `maxSpeed` | Asteroids |

Notes:

- **Solids**: `solidWith: ['group']` blocks movement against sprites in
  those groups — the engine pushes the sprite out along the axis of least
  penetration. Landing sets read-only `onGround` (gate jumps on it) and
  fires `land`; sides act as walls; below stops upward motion.
- **Drift is emergent** in `carMode`: lateral grip is finite, so hard
  cornering at speed keeps sideways momentum. Lower `grip` = more drift.
  `skidMarks: true` leaves fading rubber trails while drifting
  (`skidThreshold` tunes what counts, read-only `drifting` reports it —
  handy for sound effects).
- **Camera**: sprites live in world coordinates; `cameraX`/`cameraY` on
  the GameView scroll the view, and `follow(sprite, options)` tracks a
  sprite natively with a vertical dead-zone (the platformer demo scrolls
  up when the player climbs into the top third). Touch input is mapped
  back to world space automatically, so taps and drags work while
  scrolled; overlaid Titanium controls are screen-fixed and unaffected.
- **Screen wrapping**: `wrapAround: true` re-enters from the opposite edge
  (Asteroids). For scrolling backgrounds use `wrapX`/`wrapShift`: two
  screen-wide copies with `{ wrapX: -W/2, wrapShift: 2*W }` and a negative
  `velocityX` make a seamless parallax layer with no JS in the loop.

### Detect hits and score

Tag obstacles with a `collisionGroup` and set
`collidesWith: ['group', ...]` on the moving sprite: it fires a
`collision` event (payload: `group`, `other` sprite, `x`, `y`) once per
overlap-enter, re-arming after separation. This is independent of
`solidWith` — use solids to *block*, collision events to *react*.

- A sprite with `width`/`height` but **no sheet** renders nothing and
  works as an invisible trigger: score zones, goals, checkpoints,
  ceilings (flappy, racing and volley demos all use these).
- `hitboxScale` shrinks the collision box around the anchor — art rarely
  fills its frame, and slightly small hitboxes feel fairer.
- `debug: true` on a sprite (or on the GameView for everything) renders
  the shapes: **green** = collision AABB (with `hitboxScale`), **blue** =
  sprite/touch bounds, **orange dot** = anchor.

### Depth in top-down scenes

`ySort: true` sorts sprites within the same `zIndex` by their **bottom
edge** (feet, trunk base) instead of a fixed order — walk below a tree
and you draw in front of it, walk above and you vanish behind the canopy.
Give the player, trees and buildings the same `zIndex` with `ySort`, keep
ground tiles on a lower `zIndex`, and the Zelda-style depth illusion
falls out automatically (see `zelda.js`).

## Learn from the examples

`example/app.js` is a launcher; each demo is a self-contained file showing
a feature set — find the one closest to your game and start there:

| Demo | Shows |
|---|---|
| `basic.js` | Sheets, animations, drag/pinch/rotate, tween chaining |
| `puzzle.js` | Drag & drop with snapping, press-to-lift, tween-back-home |
| `flappy.js` | Gravity + tap impulse, trigger zones, parallax wrapping |
| `platformer.js` | `solidWith`, `onGround`/`land` (trampolines via the landed-on solid), camera `follow`, multitouch d-pad buttons |
| `volley.js` | `restitution` ball, JS-driven hit response, simple AI timer |
| `racing.js` | `carMode` drifting, skid marks, pixel art, lap/checkpoint logic |
| `cards.js` | Fanned hand UI, selection tweens, idle wobble |
| `asteroids.js` | `thrust`/`angularVelocity`, `wrapAround`, bullet pooling |
| `zelda.js` | Tile map from a string array, solid tiles/house, `ySort` depth, 8-way d-pad, follower NPC on a decision timer |
| `skate.js` | Endless runner: pixel-art parallax street, jump-button ollie over pooled obstacles, raised road sections to ride, crash sprite on collision |
| `pointclick.js` | Adventure scene: tap-to-walk via distance-sized tweens, verb-coin icons on a hotspot, JS hit-testing vs. view taps, `ySort` depth |

Run them with `ti build -p android` from `android/` (executes
`example/app.js` on a device/emulator).

## API reference

### Module

- `createGameView(options)` → GameView
- `createSpriteSheet(options)` → SpriteSheet
- `createSprite(options)` → Sprite
- Easing constants: `EASE_LINEAR`, `EASE_IN`, `EASE_OUT`, `EASE_IN_OUT`,
  `EASE_BOUNCE`, `EASE_ELASTIC`

### GameView

| Member | Description |
|---|---|
| `add(sprite)` / `remove(sprite)` | Manage sprites in the scene |
| `removeAllSprites()` | Clear the scene |
| `pause()` / `resume()` | Render loop control (activity lifecycle is automatic) |
| `backgroundColor` | GL clear color |
| `surfaceWidth` / `surfaceHeight` | Surface size in px (read-only) |
| `cameraX` / `cameraY` | World-space offset of the view (scrolling) |
| `follow(sprite, { topMargin, bottomMargin, maxY })` | Native vertical dead-zone camera follow — scrolls when the sprite crosses `topMargin`/`bottomMargin` (fractions of the surface height, defaults 0.33/0.7), clamped to `maxY` (default 0) |
| `stopFollow()` | Stop following; the camera stays where it is |
| `debug` | Draw collision shapes for every sprite |

Events: `press`, `tap`, `release` (any touch; payload `x`, `y`) and
`resize` (payload `width`, `height`).

### SpriteSheet

Options: `image`, `frameWidth`/`frameHeight` **or** `atlas`,
`smoothing` (default true).

| Member | Description |
|---|---|
| `frameCount` | Number of frames (0 until loaded for grid sheets) |
| `frameNames` | Atlas frame names, sorted (atlas sheets only) |
| `frameIndex(name)` | Index for an atlas frame name, `-1` if unknown |

### Sprite

All properties are live: reading returns the current native value, even
mid-drag or mid-tween. All can be passed at creation.

| Group | Properties |
|---|---|
| Transform | `x`, `y`, `width`, `height` (default: frame size), `scale`, `scaleX`, `scaleY` (negative flips), `rotation`, `anchorX`, `anchorY`, `opacity`, `visible`, `zIndex`, `ySort` |
| Sheet/animation | `sheet`, `frame`, `animations`, `animation` (read-only) |
| Touch behaviors | `draggable`, `pinchable`, `rotatable` |
| Physics | `velocityX`, `velocityY`, `gravity`, `maxSpeed` |
| Solids | `solidWith`, `onGround` (read-only), `restitution` |
| Collision | `collisionGroup`, `collidesWith`, `hitboxScale`, `debug` |
| Car | `carMode`, `throttle`, `steering`, `enginePower`, `turnRate`, `grip`, `drag`, `skidMarks`, `skidThreshold`, `drifting` (read-only) |
| Flight | `thrust`, `angularVelocity`, `wrapAround` |
| Wrap/loop | `wrapX`, `wrapShift` |
| Idle wobble | `idleAnimation`, `idleRotation`, `idleMovement`, `idleSpeed` |

Methods: `play(name)`, `stop()`, `animate(options)`, `clearTweens()`.

Events:

| Event | Payload | When |
|---|---|---|
| `press` | `x`, `y`, `touchX`, `touchY` | Finger down on the sprite |
| `release` | `x`, `y` | Finger up/cancel after a press (fires after `tap`/`dragend`) |
| `tap` | `x`, `y`, `touchX`, `touchY` | Quick touch without movement |
| `dragstart` | `x`, `y` | Drag exceeded touch slop |
| `drag` | `x`, `y` | Throttled to ~10 Hz while dragging |
| `dragend` | `x`, `y` | Finger lifted; sprite already moved natively |
| `pinch` | `scaleX`, `scaleY` | While two-finger scaling |
| `rotate` | `rotation` | While two-finger rotating |
| `animationcomplete` | `animation` | Non-looping sheet animation finished |
| `complete` | final transform values | Tween finished |
| `collision` | `group`, `other`, `x`, `y` | Overlap with a `collidesWith` group began |
| `land` | `x`, `y`, `other` (the solid), `group` | Landed on top of a `solidWith` solid |

## Architecture & source layout

```
android/src/ti/game/
├── TiGameModule.java        Module entry; easing constants
├── GameViewProxy.java       createGameView() — owns the Scene
├── TiGameView.java          TiUIView wrapping GLSurfaceView + lifecycle
├── SpriteProxy.java         createSprite() — JS-facing sprite API
├── SpriteSheetProxy.java    createSpriteSheet() — grid or atlas
└── engine/                  Pure native engine (no per-frame bridge use)
    ├── Scene.java           Scene graph, solids, collisions, wrapping
    ├── Sprite.java          State + physics/animation/tween/idle ticking
    ├── SpriteSheet.java     Texture + UV frame table
    ├── Animation.java       Frame indices + fps + loop
    ├── SceneRenderer.java   GLSurfaceView.Renderer — the game loop
    ├── SpriteBatch.java     ES 2.0 batcher, one draw call per texture
    ├── SkidTrail.java       Fading skid-mark ring buffer
    ├── TextureManager.java  GL upload, context-loss recovery
    ├── TouchController.java Hit test, drag, pinch, rotate
    ├── Tween.java           Native property animation
    └── Easing.java          Easing functions
```

Contribution rules for the codebase live in `AGENTS.md`; planned features
(sound, particles, font rendering) in `TODO.md`.

### iOS port (experimental)

`ios/` contains an Obj-C twin of the module — same JS API, same engine
class-per-class (`Classes/TG*` mirrors `engine/`, `Classes/TiGame*` the
proxies), rendered with OpenGL ES 2.0 and driven by a `CADisplayLink` on
a dedicated render thread. It has not been compiled or run yet: the
Xcode project must be scaffolded once on a Mac and the first build will
need shaking out — see `ios/README.md` for the exact steps and the
implementation notes (threading, pixel coordinates, backgrounding).

## Build

```bash
cd android
ti build -p android --build-only   # package android/dist/ti.game-android-<version>.zip
ti build -p android                # run the example app on a device/emulator

cd ios                             # macOS only; scaffold first (ios/README.md)
ti build -p ios --build-only       # package the iOS module zip
```
