# ti.game — iOS port (OpenGL ES 2.0 / CADisplayLink)

Obj-C twin of the Android module: same JS API, same engine architecture
(see the repo `README.md` and `AGENTS.md`). The entire game loop runs on
a dedicated render thread driven by a `CADisplayLink`; JS property writes
land in atomic fields the render thread reads each frame — the iOS
equivalent of Android's GLSurfaceView + volatile-field pattern.

All sources in `Classes/` are complete ports of their Android
counterparts — each file header names its Java twin. When changing
engine behavior, change both platforms (see `AGENTS.md`).

Note for agents working on a non-Mac machine: this module can only be
compiled on macOS, so editor/clang diagnostics about missing Apple
headers (`Foundation.h`, `TitaniumKit`, ...) are environment noise, not
code errors.

## Build

```bash
cd ios
ti build -p ios --build-only   # packages the module zip
```

The example app in `example/` is pure JS and cross-platform — add the
iOS module zip to its `tiapp.xml` and run `ti build -p ios` to verify
changes with the demos.

## Implementation notes

- **Threads**: main thread = JS property writes + touch
  (`TGTouchController`); render thread = `TGGLView`'s CADisplayLink →
  `TGSceneRenderer.drawFrame`. Scene list access is synchronized, sprite
  scalars are atomic properties.
- **Coordinates**: scene units are surface **pixels** (view points ×
  contentScale), identical to Android — touch positions are scaled
  before hit-testing, and `resize` reports pixel sizes.
- **Backgrounding**: the loop pauses on
  `UIApplicationWillResignActiveNotification` (GL calls in the
  background kill iOS apps) and resumes on DidBecomeActive.
- **Textures**: uploaded premultiplied (CGBitmapContext) to match the
  batcher's (ONE, ONE_MINUS_SRC_ALPHA) blending, lazily on first use
  from the render thread — same flow as Android; context-loss recovery
  paths are kept even though iOS effectively never loses the context.
- **Touch parity**: tap timeout 300 ms, ~8 pt touch slop, drag events
  throttled to ~10 Hz, pinch = incremental two-finger distance ratio,
  rotate = two-finger angle delta — mirroring `TouchController.java`.
