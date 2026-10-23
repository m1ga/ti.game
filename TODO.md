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

## Developer experience (sprinkle in between)

- [ ] TypeScript definitions (`ti.game.d.ts`) for the JS API.
- [ ] Aseprite JSON import alongside TexturePacker — tags auto-define
      named animations.

## Deliberately out of scope

2D lighting/shadows, skeletal animation (Spine), full rigid-body physics
(Box2D-class) and render-to-texture are outside the module's scope. A dim
overlay plus additive sprites can cover simple light effects with the existing
`blend: 'add'` mode.
