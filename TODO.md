# ti.game — TODO

Planned engine features, in priority order. The same rule applies throughout:
JS describes and reacts; the engine runs each frame without bridge traffic.
The current implemented API is documented in [README.md](README.md).

## 1. Camera completion

- [ ] `gameView.panTo(x, y, { duration, easing })` — native cinematic
      camera moves for cutscene beats, instead of following an invisible
      sprite; fires a `pancomplete`-style event and hands control back
      to `follow` if one is active.

## 2. Collision staples

- [ ] Slopes (platformer terrain) — a tilted `'rotatedRect'` solid already
      carries a rider and resolves along its face (slopes.js). What is still
      missing is the platformer feel on top of it: walking up a slope without
      the step-up stutter, **surface friction that acts along the contact
      only** (`linearDamping` bleeds speed in every direction, which is right
      for a pool table and wrong for a hill), and terrain built from more
      than one flat ramp.

## 3. Tile maps

- [ ] Tile map follow-ups: animated tiles (frame cycling per id),
      `raycast` against solid cells, `collision` events for trigger
      tiles (water, lava), a Tiled loader helper that resolves tileset
      images and multiple layers from one JSON.

## 4. Font rendering

- [x] The built-in pixel font includes accented Spanish, German, Dutch and
      selected French characters. `tools/build_default_font.py` rebuilds the
      embedded atlas; [Font](README.md#font) lists the exact character set.
- [ ] Add configurable character sets to `tools/genfont.py`, whose custom
      font output still defaults to ASCII 32..126. Broader scripts and
      combining-mark layout remain outside the built-in font's coverage.

## 5. Input

- [x] Configurable native digital actions for keyboard, mouse buttons and
      gamepads, with contexts, aggregate press/release, raw keyboard events
      and canvas focus. See [Configurable digital input](README.md#configurable-digital-input)
      for the current Mac right/middle mouse limitation.
- [ ] Native virtual joystick/d-pad that writes directly into a sprite's
      `velocity`/`steering`/`throttle` (`joystick.bind(sprite, ...)`) —
      no bridge in the loop; replaces the hand-rolled button overlays in
      the demos. Both halves it needs already exist for the debug HUD:
      `ScreenOverlay` draws in surface pixels, and the touch controllers
      hit-test in surface pixels before converting to world space.
      Should take a pad's left stick as well as the on-screen one.

## 6. Sprite parenting

- [ ] Full `parent` transform inheritance beyond `attachTo`: inherited scale,
      visibility, flips and tint, plus touch and y-sort hierarchy for
      multi-part bosses. This remains the structural part not yet covered.

## 7. Audio polish

- [ ] `playbackRate` with optional random pitch jitter (SoundPool rate /
      AVAudioPlayer.rate) so repeated effects stop sounding robotic.
- [ ] Stereo pan from world x.
- [ ] `fadeTo(volume, duration)` as a native tween for music transitions.

## 8. Animation polish

- [ ] Per-frame animation events (footsteps on frames 1 and 3).
- [ ] Tween `repeat` / `yoyo` options on `animate` (count or infinite) —
      blinks, pulses and ping-pong scrolls stay fully native instead of
      re-launching from `complete` in JS (the demoscene subtitle and
      starfield do exactly that). `tintColor` as a tweenable property in
      the same pass.
- [ ] Animation loop modes: ping-pong playback, a per-sprite speed
      multiplier and a random start offset — a field of torches
      shouldn't flicker in sync.

## 9. Performance

- [x] Collision broadphase: `Broadphase.java`/`TGBroadphase` index the
      tagged sprites in a uniform grid twice per frame; the solid resolver,
      bilateral pairs, sweeps and collision events query it instead of
      scanning the full list. `tests/test_broadphase.py` compares it with an
      exact pair scan.
- [ ] Tile layer vertex cache: `TileLayer.draw` rebuilds one quad per
      visible cell every frame. Cache a vertex buffer per chunk, invalidated
      by `setTile`/`data` writes and recreated after context loss.
- [ ] Mipmaps for sheets (opt-in per `SpriteSheet`) so zoomed-out scenes
      (`cameraScale < 1`) stop shimmering.

## 10. Platform parity and open bugs

- [ ] Close the README "Current platform differences" list: `animations`
      setter on Android, completion `frame` on iOS, live `legend`/`firstGid`/
      `cols`/`rows` setters on Android, one agreed rule for invalid ratio
      writes, one agreed `raycast` groups signature.
- [ ] TexturePacker `trimmed` and `rotated` frames: `SpriteSheetProxy.toFrame`
      reads only `frame`, so trimmed atlases draw shifted and rotated frames
      draw sideways. Honor `spriteSourceSize`, `sourceSize` and `rotated`.
- [ ] Open behavior bugs from the Sep 2026 review:
      a removed sprite keeps its `colliding` set (re-adding can miss
      `collision` or fire a stale `collisionend`);
      `TileLayerProxy.setData` with a flat array reuses stale `cols`/`rows`;
      `GamepadController.isGamepadSource` counts `SOURCE_DPAD` as a gamepad
      (TV remote d-pads are consumed);
      `TouchController` lets a second finger claim a sprite while the first
      is captured by the debug HUD, and never sends its `release`;
      `SpriteProxy.animate()` reads `scaleX/scaleY/opacity/glowOpacity` with
      `TiConvert.toFloat`, so ratio strings like `'0%'` no-op there;
      `SpriteSheetProxy.frameNames` is rebuilt on the GL thread on context
      restore and read unsynchronized from JS;
      `animationTime`/`idleTime` accumulators are never wrapped (~36 h).

## 11. Scene queries and steering

- [ ] `sprite.moveTowards(targetOrPoint, { speed })` with an `arrive` event
      and `lookAt(target)` — homing enemies and turrets without JS polling.
      `followPath`/`findPath` cover fixed routes only.
- [ ] Native spatial queries: `spritesInRect`, `spritesNear(x, y, radius,
      groups)` and `spriteAt(x, y)` return once instead of JS reading
      `x`/`y` per sprite over the bridge.
- [ ] Bulk read `gameView.snapshot([sprites])` returning one array of
      transforms, and `remove([objects])` to mirror `add([...])`.

## 12. Rendering building blocks

- [ ] `fillColor` sprite without a sheet, drawn with the white texture the
      debug overlay already owns — health bars, fade-to-black, prototyping.
- [ ] `fill` fraction (crop along one axis) on top of it for progress bars.
- [ ] Nine-slice scaling for dialog panels and buttons from one small
      texture.
- [ ] Clip rect (`scissor`) on a sprite for scrolling inventories and
      minimaps.
- [ ] Design resolution: `designWidth`/`designHeight` with
      `fit: 'contain' | 'cover'` and letterboxing, replacing the per-game
      `resize` arithmetic the README asks every example to write.

## 13. Physics, text and tween follow-ups

- [ ] `mass` for `solidMode: 'push'` pairs (equal mass is assumed today) and
      `maxFallSpeed`. Surface friction is tracked under section 2.
- [ ] Camera `zoomTo` and follow look-ahead alongside `panTo`.
- [ ] Tween sequencing (`then` chain on `animate`, like `play`), reverse
      playback for sheet animations, `width`/`height` as tween targets.
- [ ] Text outline/drop shadow in the glyph pass; native typewriter reveal
      with a `textcomplete` event.
- [ ] Sound `complete` event alongside the audio polish in section 7.

## Developer experience (sprinkle in between)

- [ ] TypeScript definitions (`ti.game.d.ts`) for the JS API.
- [ ] Aseprite JSON import alongside TexturePacker — tags auto-define
      named animations.
- [ ] JVM `Scene` fixture that drives `Scene.update` without a renderer, for
      regression tests of collision and solid resolution beyond the scalar
      Python fixtures in `tests/`.

## Deliberately out of scope

2D lighting/shadows, skeletal animation (Spine), full rigid-body physics
(Box2D-class) and render-to-texture are outside the module's scope. A dim
overlay plus additive sprites can cover simple light effects with the existing
`blend: 'add'` mode.
