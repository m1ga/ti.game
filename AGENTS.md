# AGENTS.md — ti.game

Guidance for AI agents working on this repository.

## What this is

A Titanium SDK Android module implementing a 2D sprite game engine on
OpenGL ES 2.0. Full architecture and API reference live in `README.md` —
read it first. `documentation/index.md` only points at the README; keep
docs in the README.

## Build & verify

```bash
cd android
ti build -p android --build-only --sdk 13.3.1.GA   # compiles Java + packages android/dist/ti.game-android-<version>.zip
ti build -p android --sdk 13.3.1.GA                # runs example/app.js as a test app (needs device/emulator)
```

Always pass `--sdk 13.3.1.GA` when building the Android module 
to make it compatible with older Titanium versions.

There are no unit tests; a successful `--build-only` build is the minimum
verification for any Java change. `android/build/` and `android/dist/` are
build output — never edit them.

## Architecture rules (do not break these)

1. **No per-frame bridge traffic.** The Kroll (JS↔Java) bridge is slow.
   Everything that runs every frame — rendering, animation ticking, tweens,
   drag handling — lives in `android/src/ti/game/engine/` and must not call
   into proxies except to fire discrete, high-level events (`tap`,
   `dragend`, `animationcomplete`, ...). Never add an event that fires per
   frame; throttle continuous events (see `drag` at ~10 Hz in
   `TouchController`).
2. **Proxies are thin.** Classes in `android/src/ti/game/` (`SpriteProxy`,
   `GameViewProxy`, `SpriteSheetProxy`) only translate JS properties/calls
   into writes on native engine objects. New sprite state goes on
   `engine/Sprite` (volatile fields), with a proxy getter/setter on top.
3. **Threading.** Three threads touch the scene: JS/Kroll thread (property
   writes, add/remove), UI thread (`TouchController`), GL thread
   (`SceneRenderer`). List access goes through `Scene.lock` /
   `Scene.snapshot()`; sprite scalar fields are `volatile`. GL calls
   (texture upload, drawing) happen only on the GL thread —
   `SpriteSheet.ensureLoaded` is called from `onDrawFrame` for that reason.
4. **Context loss.** Anything that creates GL resources must survive EGL
   context recreation: recreate in `onSurfaceCreated` (see
   `SpriteBatch.createGLResources`, `TextureManager.invalidateAll`).
5. **Coordinate system is fixed:** top-left origin, y-down, surface pixels,
   rotation in degrees clockwise, `(x, y)` = anchor point. JS API, hit
   testing and the projection matrix all assume this — change all or none.
6. **Firing events:** always guard with `proxy.hasListeners(event)` before
   `fireEvent` (it crosses the bridge); `fireEvent` is safe from any thread.
7. **Touch listener ownership.** `TiUIView.processProperties` calls
   `registerForTouch`, which installs Titanium's own `OnTouchListener` and
   would silently replace the engine's `TouchController`. `TiGameView`
   overrides `registerForTouch(View)` and `registerTouchEvents(View)` to
   keep the `TouchController` attached — don't remove those overrides, and
   don't call `view.setOnTouchListener` anywhere else.

## iOS twin

`ios/Classes/` is a class-per-class Obj-C port of the Android module —
`TG*` files mirror `engine/*.java` (each header names its twin),
`TiGame*` files mirror the proxies. The architecture rules above apply
identically (render thread instead of GL thread; atomic properties
instead of volatile fields; `_hasListeners:` before `fireEvent:`).
**When changing engine behavior, change both platforms** — the twins
must not drift. Building the iOS side requires macOS (`ios/README.md`);
on other machines, verify Java changes as usual and port the same edit
to the corresponding `TG*` file by hand.

## Conventions

- Java, tabs for indentation, opening brace on its own line for
  methods/classes (Titanium SDK style — match the existing files).
- Kroll annotations: `@Kroll.proxy(creatableInModule = TiGameModule.class)`
  makes `Game.createXyz()` factories automatically; `@Kroll.getProperty` /
  `@Kroll.setProperty` / `@Kroll.method` for the JS surface.
- JS-facing durations are milliseconds (Titanium convention); the engine
  uses seconds internally — convert at the proxy boundary.
- `manifest` (version, minsdk, architectures) and `android/timodule.xml`
  control packaging; bump `version` in `manifest` for releases.
- Update `README.md` and `example/app.js` when the JS API changes.
