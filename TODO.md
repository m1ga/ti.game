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
- [ ] `gameView.panTo(x, y, { duration, easing })` — native cinematic
      camera moves for cutscene beats, instead of following an invisible
      sprite; fires a `pancomplete`-style event and hands control back
      to `follow` if one is active.
- [x] Per-sprite parallax: `scrollFactor` (default 1) scales how much
      camera travel (and shake) moves a sprite — parallax backgrounds
      as one property instead of hand-scrolled layers (Phaser
      scrollFactor / Godot CanvasLayer equivalent). Implemented as a
      draw-time position offset by the unapplied share of the camera
      translation (zoom stays anchored on the view center, no batch
      flush per layer, no projection switch); touch maps back in
      hitTest/toSpriteSpace, debug overlays shift with the art.
      Rendering + touch only — x/y, physics and collisions stay in
      world coordinates. camera.js demos it.
- [x] Opt-in circular horizontal worlds: `gameView.worldWrapX = {
      minX, maxX }` defines the interval and `sprite.wrapWorldX = true`
      opts individual sprites in. Position normalization, camera follow,
      rendering, touch, overlap checks, solid resolution and swept movement
      all use the nearest periodic image. A `TileLayer` repeats across the
      seam only when it starts at `minX` and its width matches `maxX - minX`.
      Disabled by default. worldwrap.js covers the complete interaction
      surface.

## 2. Sprite color & blending

- [x] `tint` on sprites (the batcher already has vertex color — nearly
      free)
- [x] a `flash(color, duration)` helper for damage/invincibility —
      solid-color silhouette overlay (glow shader) that fades out
      natively; asteroids flashes the ship on crash.
- [x] `blend: 'add'` per sprite/emitter for glows, fire, lasers (one
      batch flush on blend change); asteroids uses it on the bolts.
- [x] `tileRepeat`: GL_REPEAT so a small texture tiles across a wide
      sprite instead of stretching — `repeat: true` on the sheet,
      `tileRepeat: true|'x'|'y'` on the sprite (skate street/skyline and
      raised road use it). Power-of-two textures only on ES 2.0.
- [x] More blend modes: `blend: 'multiply'` (shadows, darkening) and
      `'screen'` (soft light) — more glBlendFunc cases behind the
      existing per-sprite/emitter blend switching; premultiplied-alpha
      funcs (DST_COLOR, ONE_MINUS_SRC_ALPHA) / (ONE, ONE_MINUS_SRC_COLOR)
      so transparent texels leave the backdrop alone. The blend demo shows
      all four modes over a bright meadow strip.

## 3. Collision staples

- [x] Circle hitboxes (`hitboxShape: 'circle'`) — circle/circle and
      circle/AABB collision events, contact-normal solid resolution
      (corner bounces), round touch area, circle debug overlay. A solid
      that declares a circle hitbox resolves as a circle too, statically
      and under `swept: true`; a circle against a rectangular solid still
      sweeps as a box. Volley ball and asteroids use it, circles.js
      compares a rect post against a round one.
- [x] Per-axis hitbox correction (`hitboxScaleX` / `hitboxScaleY`) on top
      of the shared `hitboxScale`, so padded art can match its visible body
      without shrinking both axes equally. hitbox.js compares the raw and
      corrected shapes.
- [x] Bilateral circle-vs-circle response (`solidMode: 'push'`) — a pair
      that lists each other is resolved once, splitting the separation and
      exchanging the closing velocity at equal mass, so a struck ball
      actually leaves. No masses, no spin, no friction. pool.js.
- [x] Inward circular containment (`solidMode: 'contain'`) — a circular
      solid that keeps matched circles inside it, analytically, with no
      ring of wall sprites and no gaps. drum.js.
- [x] Rolling friction for ordinary sprites (`linearDamping`) — `drag` only
      ever worked inside carMode. Proportional, which is what a ball
      trickling to a halt looks like; a constant deceleration was tried and
      stops slow bodies dead, all together, which reads wrong. Stopped
      outright below 4 px/s. pool.js and drum.js.
- [x] Restitution read off both sides of a contact — a solid carries its own
      `restitution` and the springier of the two surfaces decides the bounce,
      the mix Box2D uses by default. Solids default to 0, so every existing
      scene is unchanged; what it buys is a springy floor under riders that
      are not themselves bouncy. slopes.js.
- [x] Discrete physical-impact events: `solidimpact` plus per-sprite
      `impactThreshold` for `block`, `contain` and bilateral `push`
      responses between sprites. The payload includes the other sprite,
      shared contact point, receiver normal, compensated closing speed and
      mixed restitution; receiver-specific gates suppress sustained contact
      and rearm after separation or at half-threshold. With no listeners the
      resolver returns before building payloads or gates, so there is no
      bridge traffic. TileLayer cells remain outside this sprite-only event
      by design. pool.js, drum.js and plinko.js exercise it.
- [x] Horizontal acceleration (`gravityX`) — the sibling of `gravity`;
      `gravity` keeps its exact meaning. Default 0. wind.js.
- [x] One-way platforms (jump up through, land on top) — `oneWay: true`
      on the solid; works for rect and circle riders. The platformer
      staircase uses it.
- [x] Native wall contacts: read-only `onWallLeft` / `onWallRight`, the
      discrete `wallhit` transition event and `wallSlideSpeed` for a native
      downward speed cap while pressed into a wall. Sprite and TileLayer
      walls share the same state.
- [x] Moving platforms that carry the rider — riders inherit the ground
      solid's per-frame movement (velocity, tweens, idle wobble; wrap
      teleports excluded) before resolution, so they're carried sideways
      and stay glued on the way down. Platformer demo has a patrolling
      steel platform (a regular two-way solid).
- [x] Swept AABB option per sprite so fast bullets stop tunneling —
      `swept: true` path-tests the frame's movement (Minkowski + slab)
      for both collision events and solid blocking (clamped to the
      impact point, then resolved by the normal static pass); the swept
      demo compares both lanes side by side.
- [x] `gameView.raycast(x0, y0, x1, y1, groups)` one-shot query —
      line-of-sight, ground probes. Nearest hit as { x, y, distance,
      group, sprite, normal } or null; slab test on rect AABBs, exact
      ray/circle for circle hitboxes; thread-safe for JS-initiated
      calls (own scratch, no GL-thread buffers). Discrete queries only
      (timers, taps) — not per-frame JS polling. raycast.js demos
      line of sight, ledge probes and tap hitscan.
- [x] Oriented rect hitboxes (`hitboxShape: 'rotatedRect'`) — the collision
      rect turns with the sprite instead of being re-boxed to the screen
      axes, so a tilted solid is hit on its real face and the normal comes
      out perpendicular to it. Circle-vs-OBB by taking the circle into the
      box's frame; rect-vs-OBB by separating axes (four, for rectangles),
      with the smallest overlap as the way out. Covers solids, overlap
      events, raycast, the swept pass and the debug overlay. Plain `'rect'`
      stays the default. circles.js and slopes.js.
- [ ] Slopes (platformer terrain) — a tilted `'rotatedRect'` solid already
      carries a rider and resolves along its face (slopes.js). What is still
      missing is the platformer feel on top of it: walking up a slope without
      the step-up stutter, **surface friction that acts along the contact
      only** (`linearDamping` bleeds speed in every direction, which is right
      for a pool table and wrong for a hill), and terrain built from more
      than one flat ramp.

## 4. Tile maps

- [x] First-class native tilemap layer: `Game.createTileLayer({ sheet,
      data, tileWidth, tileHeight, ... })` — one grid of frame indices,
      only the cells inside the camera are drawn (one batch run per
      layer), any map size. `data` takes rows of ids, a flat array, or
      strings + `legend`; Tiled JSON works through `firstGid` (gid 0 =
      empty, flip bits masked). Cells edited live with setTile/getTile,
      tileAt/cellAt map between world points and cells. tilemap.js draws
      a 120x90 island (topdown.js still builds a sprite per tile — fine
      at 16x12, dead at 200x200).
- [x] Collision layer: `collisionGroup` + `solid`/`oneWay` tile id lists
      (or `setBlocked` per cell) feed solidWith — rect, circle and swept
      movers, restitution, onGround/land — and findPath, with no per-tile
      sprites. A mover only tests the cells under its own hitbox, and
      faces shared between two solid cells are skipped so a slide along a
      tiled floor never snags on the seams.
- [ ] Tile map follow-ups: animated tiles (frame cycling per id),
      `raycast` against solid cells, `collision` events for trigger
      tiles (water, lava), a Tiled loader helper that resolves tileset
      images and multiple layers from one JSON.
- [x] A* pathfinding: `gameView.findPath(from, to, { cellSize, groups,
      clearance, bounds, diagonals, simplify })` returns waypoints ready
      for `followPath` — a discrete query like `raycast`, no per-frame
      JS (Godot AStar2D / GameMaker mp_grid equivalent). Rasterizes the
      `collisionGroup` sprites into a grid per query (no corner-cutting
      diagonals, octile A*, line-of-sight waypoint simplification;
      blocked start/goal snaps to the nearest free cell); when the
      tilemap collision layer lands it should feed the same grid.
      pointclick walks around the oak with it; maze.js is the full
      showcase (route visualization, tap-to-walk, a re-pathing chaser).

## 5. Font rendering

- [x] Bitmap-font text sprites: `Game.createText({ font, text })` using a
      glyph atlas (BMFont/AngelCode text + JSON formats with kerning,
      plus a simple monospace grid mode via `createFont`) — TextSprite
      extends Sprite, so text z-sorts, tweens, wobbles, tints, flashes
      and takes touches like any sprite.
- [x] `text` property updates re-layout natively; per-glyph quads go
      through the SpriteBatch (one batch run per label).
- [x] Default pixel font: a 9x15 grid embedded in the module as a ~1.2 KB
      base64 PNG (no asset resolution needed on either platform);
      `tools/genfont.py` generates grid or BMFont atlases from any TTF.
- [x] Migrated the demo HUDs (flappy score + status, racing laps, volley
      score, asteroids rocks); `text.js` demos the rest.
- [ ] The built-in font and `tools/genfont.py` are both hardcoded to
      ASCII 32..126, so no accents and no `ñ` — a missing glyph advances
      the pen and draws nothing. Spanish needs 18 more characters
      (~+0.5 KB in the embedded atlas); a `--charset` flag on the
      generator covers everyone else.
- [x] Bonus: `screenFixed` on any sprite — surface-coordinate rendering
      that ignores camera position/zoom/shake (touch maps back), so HUDs
      survive a scrolling camera without overlay views.
- [x] Word wrap: `maxWidth` on text sprites — glyph layout breaks lines
      natively (on word boundaries, re-wraps on `text` updates, respects
      `align`), so dialog boxes stop needing hand-broken `\n` lines.
      Measurement reuses the layout pen (kerning, letterSpacing), spaces
      around a soft break are dropped, a word wider than `maxWidth`
      overflows rather than breaking mid-word. text.js demos a dialog
      box wrapping a live-updating string.

## 6. Input

- [ ] Native virtual joystick/d-pad that writes directly into a sprite's
      `velocity`/`steering`/`throttle` (`joystick.bind(sprite, ...)`) —
      no bridge in the loop; replaces the hand-rolled button overlays in
      the demos. Both halves it needs already exist for the debug HUD:
      `ScreenOverlay` draws in surface pixels, and the touch controllers
      hit-test in surface pixels before converting to world space.
- [x] Gamepad support (Android key/motion events hooked at the activity
      Window, iOS GameController.framework) as discrete events:
      `buttondown`/`buttonup` with names normalized across pads (d-pad,
      hat *and* left stick all arrive as `up`/`down`/`left`/`right`, each
      name down once), `stick`/`trigger` throttled to ~20 Hz with
      transitions reported immediately, `gamepadconnected`/
      `gamepaddisconnected`, `gameView.gamepads` / `gameView.gamepad`
      snapshot, dead zone and stick-press hysteresis properties.
      Everything held is released on pause/disconnect. platformer.js
      runs on a pad. Still open: the native `bind(sprite)` from the
      joystick item above, which should take a pad's left stick as well
      as the on-screen one.

## 7. Sprite parenting

- [x] Lightweight native attachment: `attachTo(target, { offsetX, offsetY,
      rotate })`, `detach()` and read-only `attachedTo`. Children follow the
      target after physics without per-frame JS, cross world/screen-fixed
      coordinates correctly, inherit effective opacity and are removed with
      the target. This covers labels, health bars, shadows, hats and simple
      turrets.
- [ ] Full `parent` transform inheritance beyond `attachTo`: inherited scale,
      visibility, flips and tint, plus touch and y-sort hierarchy for
      multi-part bosses. This remains the structural part not yet covered.

## 8. Audio polish

- [ ] `playbackRate` with optional random pitch jitter (SoundPool rate /
      AVAudioPlayer.rate) so repeated effects stop sounding robotic.
- [ ] Stereo pan from world x.
- [ ] `fadeTo(volume, duration)` as a native tween for music transitions.

## 9. Animation polish

- [ ] Per-frame animation events (footsteps on frames 1 and 3).
- [ ] Tween `repeat` / `yoyo` options on `animate` (count or infinite) —
      blinks, pulses and ping-pong scrolls stay fully native instead of
      re-launching from `complete` in JS (the demoscene subtitle and
      starfield do exactly that). `tintColor` as a tweenable property in
      the same pass.
- [ ] Animation loop modes: ping-pong playback, a per-sprite speed
      multiplier and a random start offset — a field of torches
      shouldn't flicker in sync.
- [x] Chaining: `play('attack', { then: 'idle' })` instead of juggling
      `animationcomplete` handlers in JS — `then` takes a name or an
      array; the queue plays out natively as each non-looping animation
      finishes (a looping one ends the chain). path.js demos it.
- [x] Path following: `sprite.followPath([points], { speed, loop,
      rotate })` with optional corner smoothing — enemy patrol routes
      and bullet arcs run natively, no per-frame bridge traffic
      (Godot Path2D / Phaser PathFollower equivalent). `smoothing`
      rounds corners via precomputed quadratic Beziers; non-looping
      runs fire `pathcomplete`. Path movement feeds frameDelta, so
      path-driven platforms carry riders. path.js demos it.

## 10. Game clock

- [x] Native timers on the game clock: `gameView.after(ms, callback)` /
      `gameView.every(ms, callback)` return an id for `cancelTimer(id)`
      — they scale with `timeScale`, freeze at `0` and pause with the
      render loop, unlike `setTimeout` (Phaser time events / Godot
      Timer). Ticked inside Scene.update with the scaled dt; callbacks
      cross the bridge only on expiry (callAsync), or a `timer` event
      with the id fires when no callback was given. Repeating timers
      fire at most once per frame and restart their interval after a
      stall instead of bursting. timescale.js demos the freeze.

## Developer experience (sprinkle in between)

- [x] Human-readable values at the JS boundary: named anchor presets
      (`'bottom-left'`, `'center'`, ...) and percentage strings for every
      ratio property (`'80%'` opacity, hitbox scale, restitution, camera/time
      scale, sound volume, and so on), normalized through matching Android
      and iOS helpers.
- [x] Stats overlay next to the debug overlay: fps, draw calls, sprite
      and particle counts — `debug: { hud: 'topRight' }`, tap to expand,
      plus a `performance` event. Drawn with the bitmap-font engine and
      `setScreenSpace`, so it borrows the scene's default font (or any
      `hudFont` you pass) and adds no rendering path of its own. Present
      time and present failures are iOS-only; `GLSurfaceView` swaps
      buffers where the Android renderer cannot time it.
- [ ] TypeScript definitions (`ti.game.d.ts`) for the JS API.
- [ ] Aseprite JSON import alongside TexturePacker — tags auto-define
      named animations.

## Deliberately out of scope

2D lighting/shadows, skeletal animation (Spine), full rigid-body physics
(Box2D-class), render-to-texture — each is a project the size of
everything built so far and the target genres rarely miss them. If
"lighting" ever comes up: a screen-dim overlay plus additive light
sprites gets 90% for 1% of the cost (needs item 2's `blend: 'add'`).
