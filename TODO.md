# ti.game — TODO

Planned engine features, roughly in priority order.

## Sound

- [ ] Native sound playback API: `Game.createSound({ url })` with `play()`,
      `loop`, `volume` — backed by Android `SoundPool` for low-latency
      effects (jump, hit, collect) and `MediaPlayer` for music.
- [ ] Hook points already in place: `drifting` (tire squeal), `land`
      (footstep/thud), `collision` (impacts), trampoline bounce, the dog's
      pee state, card deal tweens (`complete`).
- [ ] Respect activity lifecycle (pause/resume music with the render loop).

## Particle effects

- [ ] Native particle emitter ticked in the game loop (no bridge traffic):
      `Game.createEmitter({ sheet, frame, rate, lifetime, speed, spread,
      gravity, startScale/endScale, startOpacity/endOpacity, tint? })`.
- [ ] Attachable to a position or following a sprite (exhaust, drift smoke,
      water splashes, asteroid explosions, sparkle on solved puzzle).
- [ ] Render through the existing SpriteBatch (particles from one sheet =
      still one draw call); pool internally, hard cap per emitter.
- [ ] Burst mode (`emit(n)`) for one-shot explosions vs. continuous rate.

## Font rendering

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
