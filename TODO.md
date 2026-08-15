# ti.game — TODO

Planned engine features, in priority order. Everything follows the house
rule: JS describes and reacts, the engine runs per frame — no bridge
traffic in the loop.

## 1. Camera completion

- [x] Horizontal dead-zone follow (`leftMargin`/`rightMargin` follow
      options).
- [x] Camera bounds: `gameView.cameraBounds = { minX, minY, maxX, maxY }`.
- [x] Follow smoothing/lerp (`smoothing` follow option).
- [x] `cameraScale` (zoom), anchored on the view center — touch mapping
      accounts for it.
- [x] Native camera shake: `gameView.shake({ strength, duration })` —
      detuned-sine rumble on the projection only (skate demo shakes on
      crash; camera.js demos two-axis follow, bounds, zoom and shake).

## 2. Sprite color & blending

- [ ] `tint` on sprites (the batcher already has vertex color — nearly
      free) and a `flash(color, duration)` helper for damage/invincibility.
- [ ] `blend: 'add'` per sprite/emitter for glows, fire, lasers (one
      batch flush on blend change).
- [x] `tileRepeat`: GL_REPEAT so a small texture tiles across a wide
      sprite instead of stretching — `repeat: true` on the sheet,
      `tileRepeat: true|'x'|'y'` on the sprite (skate street/skyline and
      raised road use it). Power-of-two textures only on ES 2.0.

## 3. Collision staples

- [x] Circle hitboxes (`hitboxShape: 'circle'`) — circle/circle and
      circle/AABB collision events, contact-normal solid resolution
      (corner bounces), round touch area, circle debug overlay. Volley
      ball and asteroids use it.
- [ ] One-way platforms (jump up through, land on top).
- [ ] Moving platforms that carry the rider.
- [ ] Swept AABB option per sprite so fast bullets stop tunneling.
- [ ] `gameView.raycast(x0, y0, x1, y1, groups)` one-shot query —
      line-of-sight, ground probes.
- [ ] Slopes (platformer terrain) — only if terrain games become a goal.

## 4. Tile maps

- [ ] First-class native tilemap layer: Tiled JSON import, batched quads
      from one texture, any map size (topdown.js builds a sprite per tile
      — fine at 16x12, dead at 200x200).
- [ ] Collision layer: solid tiles feed the existing solidWith/collision
      systems without per-tile sprites.

## 5. Font rendering

- [ ] Bitmap-font text sprites: `Game.createText({ font, text })` using a
      glyph atlas (BMFont/AngelCode format plus a simple monospace grid
      mode) — HUD scores/labels inside the GL scene instead of overlaid
      Titanium labels, so they can scroll with the camera, z-sort, tween
      and wobble like any sprite.
- [ ] `text` property updates re-layout natively; per-glyph quads go
      through the SpriteBatch.
- [ ] Ship a default pixel font atlas in the module assets; generator
      script for custom fonts.
- [ ] Migrate the demo HUDs (flappy score, racing laps, volley score,
      asteroids rocks) once available.

## 6. Input

- [ ] Native virtual joystick/d-pad that writes directly into a sprite's
      `velocity`/`steering`/`throttle` (`joystick.bind(sprite, ...)`) —
      no bridge in the loop; replaces the hand-rolled button overlays in
      the demos.
- [ ] Gamepad support (Android key/motion events, iOS GCController) with
      the same native binding plus discrete button events.

## 7. Sprite parenting

- [ ] `parent` property: children inherit transform (turret on a tank,
      hat on a hero, multi-part bosses). Touches transform math,
      hit-testing and ySort — the biggest structural item here.

## 8. Audio polish

- [ ] `playbackRate` with optional random pitch jitter (SoundPool rate /
      AVAudioPlayer.rate) so repeated effects stop sounding robotic.
- [ ] Stereo pan from world x.
- [ ] `fadeTo(volume, duration)` as a native tween for music transitions.

## 9. Animation polish

- [ ] Per-frame animation events (footsteps on frames 1 and 3).
- [ ] Chaining: `play('attack', { then: 'idle' })` instead of juggling
      `animationcomplete` handlers in JS.

## Developer experience (sprinkle in between)

- [ ] Stats overlay next to the debug overlay: fps, draw calls, sprite
      and particle counts.
- [ ] TypeScript definitions (`ti.game.d.ts`) for the JS API.
- [ ] Aseprite JSON import alongside TexturePacker — tags auto-define
      named animations.

## Deliberately out of scope

2D lighting/shadows, skeletal animation (Spine), full rigid-body physics
(Box2D-class), render-to-texture — each is a project the size of
everything built so far and the target genres rarely miss them. If
"lighting" ever comes up: a screen-dim overlay plus additive light
sprites gets 90% for 1% of the cost (needs item 2's `blend: 'add'`).
