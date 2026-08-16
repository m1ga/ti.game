# ti.game

A 2D sprite game engine module for Titanium SDK (Android and iOS),
rendered with OpenGL ES 2.0. You describe your scene and react to events
from JavaScript; everything that runs every frame — rendering, animation,
physics, collision, gestures — runs natively at 60 fps. The JS API is
identical on both platforms.

**Features**

- Sprite sheets (grid or TexturePacker atlas), frame animations, tweens
- Touch: tap, press, drag & drop, pinch-to-scale, two-finger rotate
- Physics: velocity + gravity, platformer solids, bouncing (restitution),
  arcade car model with drifting + skid marks, Newtonian flight (thrust)
- Collision groups with events, invisible trigger zones, hitbox tuning
- Parallax scroll looping, screen wrapping, idle wobble animation
- Pixel-art mode (nearest-neighbor filtering), debug overlay for hitboxes
- Sound: low-latency overlapping effects + looping music (`createSound`),
  auto-paused and resumed with the app
- Particles: native pooled emitters (`createEmitter`) — continuous rate or
  bursts, follow a sprite, tint/scale/fade over lifetime
- Verlet ropes (`createRope`) — pin ends to sprites or points, swings
  natively (chains, capes, bridges, grappling hooks)
- Fullscreen camera effects (`cameraEffect`) — tint and glitch shader
  passes over the whole rendered scene; sprite glow highlights
  (`glowColor`/`glowBlur`)
- 15 example games in `example/` covering every feature

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
- **Tweens**: `sprite.animate({ x, y, scale, rotation, opacity, glowOpacity,
  duration, delay, easing })` (ms; easing from the `EASE_*` constants) animates
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

Sprite touches are multi-touch: every finger runs its own gesture, so
several sprites can be pressed, tapped or dragged at the same time (each
sprite belongs to at most one finger). A second finger that lands on
empty space — or on the sprite already held — instead pinches/rotates
the held sprite (per its `pinchable`/`rotatable` flags).

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
  the GameView scroll the view, `cameraScale` zooms around the view
  center, and `cameraBounds` clamps the visible rect into a level rect.
  `follow(sprite, options)` tracks a sprite natively with dead-zones —
  vertical always (the platformer demo scrolls up when the player climbs
  into the top third), horizontal when `leftMargin`/`rightMargin` are
  given, optionally eased with `smoothing`. `shake()` adds impact rumble
  without touching the camera position. Touch input is mapped back to
  world space automatically (zoom included), so taps and drags work
  while scrolled; overlaid Titanium controls are screen-fixed and
  unaffected.
- **Camera effects**: `cameraEffect` (`'none'`/`'tint'`/`'glitch'`)
  applies a fullscreen shader pass to the whole rendered scene —
  `'tint'` multiplies with `cameraTint` (night vision, flashback,
  poison), `'glitch'` is a broken-signal filter (sliced row offsets,
  RGB split, flicker). `cameraEffectIntensity` (0..1) scales either.
  With `'none'` the extra pass is skipped entirely.
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
- `hitboxShape: 'circle'` makes the hitbox a circle (radius = half the
  smaller drawn side × `hitboxScale`) — for balls and asteroids. Circle
  sprites also resolve against solids along the contact normal, so a
  ball bounces off a corner diagonally instead of like a box (the volley
  ball and the asteroids use it), and their touch area is round.
- `debug: true` on a sprite (or on the GameView for everything) renders
  the shapes: **green** = collision AABB (with `hitboxScale`), **blue** =
  sprite/touch bounds, **orange dot** = anchor.

### Play sounds

```javascript
var jump = Game.createSound({ url: 'assets/jump.wav', volume: 0.8 });
jump.play();   // fire-and-forget; rapid plays overlap

var music = Game.createSound({ url: 'assets/theme.mp3', music: true, loop: true });
music.play();
```

Effect mode (the default) is built for low latency: on Android the sample
lives in a shared `SoundPool`, on iOS in a small pool of preloaded
players — call `play()` from any event handler (`land`, `collision`,
`complete`, a button) and repeated plays overlap instead of cutting each
other off. `music: true` picks the streaming backend
(`MediaPlayer`/`AVAudioPlayer`) for longer tracks; music pauses when the
app goes to the background and resumes with it, like the render loop.
`volume` (0..1) and `loop` are live properties. WAV, MP3 and OGG (Android)
/ WAV, MP3, M4A (iOS) from app resources or file paths.

The skate demo wires `jump.wav`/`crash.wav` into its jump and wipeout
handlers and loops a chiptune track on the music backend; the events
listed under collisions (`land`, `collision`, `drifting`, tween
`complete`) are natural hook points for more.

### Particles

```javascript
var smoke = Game.createEmitter({
    sheet: puffSheet, frame: 0,
    rate: 30,                          // particles/sec while `emitting`
    lifetime: 600,                     // ms, like all JS durations
    speed: 120, angle: 0, spread: 60,  // cone: 0 = up, clockwise degrees
    gravity: -40, size: 24,
    startScale: 1, endScale: 2.5,
    startOpacity: 0.8, endOpacity: 0,
    tint: '#889', zIndex: 9,
    target: car                        // follow a sprite — or set x/y
});
gameView.add(smoke);

boom.emit(30);                         // one-shot burst (rate can stay 0)
```

Spawning, integration, fading and drawing all run in the native game
loop — JS only writes configuration and calls `emit()`. Each particle's
speed is randomized between 50% and 100% of `speed` so bursts don't form
perfect rings; scale and opacity interpolate start → end over `lifetime`.
Particles are pooled (`maxParticles`, default 200, hard cap 1000) and all
share one sheet frame, so an emitter renders as a single batch run —
tint your art at runtime by using white particle textures. Emitters sort
into the scene by `zIndex` (drawing above sprites of the same z). The
skate demo uses both modes: a dust trail following the board
(`target` + `emitting`) and a spark burst on crash (`emit(26)`).

### Ropes

```javascript
var rope = Game.createRope({
    sheet: ropeSheet,          // one frame, textured along each link
    segments: 14,
    segmentLength: 40,         // px
    thickness: 12,             // drawn width, px
    gravity: 1500, damping: 0.98, iterations: 3,
    head: ball,                // pin the head to a sprite — or set x/y
    zIndex: 5
});
gameView.add(rope);
```

A native Verlet chain: integration and distance constraints run in the
game loop, segments render as quads oriented along the rope (one sheet
frame → one batch run). Pin the `head` to a sprite — a draggable ball, a
character's hand — and the rope follows with zero bridge traffic, or use
`x`/`y` for a fixed anchor. An optional `tail` sprite pins the other end
(hanging weights, bridges). `endX`/`endY` read the live position of the
loose end (grappling-hook tips). See `rope.js` for both variants.

With a `tail` sprite, `maxLength` (px, 0 = off) turns the rope into a
tether: whenever the head→tail distance exceeds it, the rope pulls the
sprites back onto the limit each frame and cancels their outward
velocity — so a falling weight snaps taut and swings like a pendulum
instead of stretching the rope (leashes, wrecking balls, yo-yos). The
tether yields at the end no finger owns: with a fixed head anchor the
tail sprite is simply leashed, but with sprites on both ends you can
drag either one and the other is towed behind once the rope goes taut
(carts, chained crates).

### Depth in top-down scenes

`ySort: true` sorts sprites within the same `zIndex` by their **bottom
edge** (feet, trunk base) instead of a fixed order — walk below a tree
and you draw in front of it, walk above and you vanish behind the canopy.
Give the player, trees and buildings the same `zIndex` with `ySort`, keep
ground tiles on a lower `zIndex`, and the Zelda-style depth illusion
falls out automatically (see `topdown.js`).

## Learn from the examples

`example/app.js` is a launcher; each demo is a self-contained file showing
a feature set — find the one closest to your game and start there:

| Demo | Shows |
|---|---|
| `basic.js` | Sheets, animations, drag/pinch/rotate, tween chaining |
| `puzzle.js` | Drag & drop with snapping, press-to-lift, tween-back-home, multi-touch (one piece per finger) |
| `flappy.js` | Gravity + tap impulse, trigger zones, parallax wrapping |
| `platformer.js` | `solidWith`, `onGround`/`land` (trampolines via the landed-on solid), camera `follow`, multitouch d-pad buttons |
| `volley.js` | `restitution` ball, JS-driven hit response, simple AI timer |
| `racing.js` | `carMode` drifting, skid marks, pixel art, lap/checkpoint logic |
| `cards.js` | Deck dealing, fanned hand UI, selection tweens, idle wobble |
| `asteroids.js` | `thrust`/`angularVelocity`, `wrapAround`, bullet pooling |
| `topdown.js` | Tile map from a string array, solid tiles/house, `ySort` depth, 8-way d-pad, follower NPC on a decision timer |
| `skate.js` | Endless runner: pixel-art parallax street, jump-button ollie over pooled obstacles, raised road sections to ride, crash sprite on collision |
| `pointclick.js` | Adventure scene: tap-to-walk via distance-sized tweens, verb-coin icons on a hotspot, JS hit-testing vs. view taps, `ySort` depth |
| `particles.js` | Emitter playground: continuous spark fountain, tap-for-fireworks bursts, smoke trail following a dragged sprite |
| `rhythm.js` | DDR-style note catcher: pooled notes on native velocity, `press`-event pads, timing-based good/bad sounds, tinted hit bursts, miss trigger zone |
| `camera.js` | Camera playground: two-axis dead-zone follow with smoothing, `cameraBounds`, zoom buttons (`cameraScale`), shake, fullscreen tint/glitch effects (`cameraEffect`), `tileRepeat` ground |
| `rope.js` | Native Verlet ropes: one hanging from a draggable ball (`head`), one from a fixed anchor with a weight pinned to the `tail` |

Run them with `ti build -p android` from `android/` (executes
`example/app.js` on a device/emulator).

## API reference

### Module

- `createGameView(options)` → GameView
- `createSpriteSheet(options)` → SpriteSheet
- `createSprite(options)` → Sprite
- `createSound(options)` → Sound
- `createEmitter(options)` → Emitter
- `createRope(options)` → Rope
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
| `cameraScale` | Zoom, anchored on the view center (default 1) |
| `cameraBounds` | `{ minX, minY, maxX, maxY }` world rect the visible area is clamped into; `null` = unbounded |
| `follow(sprite, options)` | Native dead-zone camera follow. Vertical: `topMargin`/`bottomMargin` (fractions of the visible height, defaults 0.33/0.7), clamped to `maxY` (default 0). Horizontal: enabled by `leftMargin`/`rightMargin` (defaults 0.35/0.65). `smoothing` (0..1, default 0 = snap) eases by that fraction of the remaining distance per 1/60 s |
| `stopFollow()` | Stop following; the camera stays where it is |
| `shake({ strength, duration })` | Camera shake: `strength` px (default 12), `duration` ms (default 400) — offsets only the projection, so follow/bounds/touches are unaffected |
| `cameraEffect` | Fullscreen shader over the whole scene: `'none'` (default), `'tint'`, `'glitch'` |
| `cameraTint` | Color for the `'tint'` effect, e.g. `'#4f8'` |
| `cameraEffectIntensity` | Effect strength 0..1 (tint mix / glitch amount; default 1) |
| `debug` | Draw collision shapes for every sprite |

Events: `press`, `tap`, `release` (any touch; payload `x`, `y`) and
`resize` (payload `width`, `height`).

### SpriteSheet

Options: `image`, `frameWidth`/`frameHeight` **or** `atlas`,
`smoothing` (default true), `repeat` (default false — GL_REPEAT wrap for
`tileRepeat` sprites; needs power-of-two texture dimensions).

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
| Sheet/animation | `sheet`, `frame`, `animations`, `animation` (read-only), `tileRepeat` (`true`/`'x'`/`'y'` — tile the frame at native size instead of stretching; sheet needs `repeat: true` and a frame spanning the whole texture) |
| Touch behaviors | `draggable`, `pinchable`, `rotatable`, `touchEnabled` (false = touches pass through to sprites underneath) |
| Physics | `velocityX`, `velocityY`, `gravity`, `maxSpeed` |
| Solids | `solidWith`, `onGround` (read-only), `restitution` |
| Collision | `collisionGroup`, `collidesWith`, `hitboxScale`, `hitboxShape` (`'rect'`/`'circle'` — circles also bounce off solid corners along the contact normal), `debug` |
| Car | `carMode`, `throttle`, `steering`, `enginePower`, `turnRate`, `grip`, `drag`, `skidMarks`, `skidThreshold`, `drifting` (read-only) |
| Flight | `thrust`, `angularVelocity`, `wrapAround` |
| Wrap/loop | `wrapX`, `wrapShift` |
| Idle wobble | `idleAnimation`, `idleRotation`, `idleMovement`, `idleSpeed` |
| Glow | `glowColor` (e.g. `'#ffc94d'`), `glowBlur` (blur radius in px; `0` = off), `glowOpacity` (halo strength 0..1, tweenable via `animate` — fade a glow in/out without touching the blur) — a tinted, blurred silhouette of the current frame drawn behind the sprite by a shader pass (selection highlights, power-ups); follows the sprite's shape, rotation and opacity |

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

### Sound

Options: `url` (required), `volume` (0..1, default 1), `loop`,
`music` (default false; choose at creation, not changeable later).

| Member | Description |
|---|---|
| `play()` | Start playback (effects: overlapping; queued until the sample is loaded) |
| `pause()` | Pause; `play()` continues where it stopped |
| `stop()` | Stop and rewind to the beginning |
| `volume` | Live volume, 0..1 |
| `loop` | Repeat until `stop()` |
| `music` | Which backend was chosen (read-only) |

### Emitter

Add/remove via `gameView.add(emitter)` / `remove(emitter)`, like sprites.
All properties are live.

| Group | Properties |
|---|---|
| Placement | `x`, `y`, `target` (sprite to follow, null to detach), `offsetX`, `offsetY`, `zIndex` |
| Look | `sheet`, `frame`, `size` (base px width; 0 = frame size), `tint`, `startScale`/`endScale`, `startOpacity`/`endOpacity` |
| Motion | `speed` (px/s, randomized 50–100%), `angle` (0 = up, clockwise), `spread` (degrees), `gravity` (px/s²), `lifetime` (ms) |
| Emission | `rate` (particles/s), `emitting`, `maxParticles` (default 200, max 1000) |

Methods: `emit(n)` (one-shot burst on top of `rate`), `clear()` (kill all
live particles).

## Architecture & source layout

```
android/src/ti/game/
├── TiGameModule.java        Module entry; easing constants
├── GameViewProxy.java       createGameView() — owns the Scene
├── TiGameView.java          TiUIView wrapping GLSurfaceView + lifecycle
├── SpriteProxy.java         createSprite() — JS-facing sprite API
├── SpriteSheetProxy.java    createSpriteSheet() — grid or atlas
├── SoundProxy.java          createSound() — SoundPool effect or MediaPlayer music
├── EmitterProxy.java        createEmitter() — JS-facing particle emitter
├── RopeProxy.java           createRope() — JS-facing Verlet rope
└── engine/                  Pure native engine (no per-frame bridge use)
    ├── Scene.java           Scene graph, solids, collisions, wrapping
    ├── ParticleEmitter.java Pooled particles: spawn, integrate, fade, draw
    ├── Rope.java            Verlet chain: integrate, constrain, draw
    ├── SoundEngine.java     Shared SoundPool + audio lifecycle
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

### iOS

`ios/` contains an Obj-C twin of the module — same JS API, same engine
class-per-class (`Classes/TG*` mirrors `engine/`, `Classes/TiGame*` the
proxies), rendered with OpenGL ES 2.0 and driven by a `CADisplayLink` on
a dedicated render thread. Implementation notes (threading, pixel
coordinates, backgrounding) are in `ios/README.md`; when changing engine
behavior, change both platforms (see `AGENTS.md`).

## Build

```bash
cd android
ti build -p android --build-only   # package android/dist/ti.game-android-<version>.zip
ti build -p android                # run the example app on a device/emulator

cd ios                             # macOS only
ti build -p ios --build-only       # package the iOS module zip
```
