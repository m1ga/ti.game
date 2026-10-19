# ti.game — Apple renderer

The Apple implementation uses Objective-C, Metal and `CAMetalLayer` for iPhone, iPad and Mac Catalyst. Android retains OpenGL ES. The JavaScript API, native scene simulation, top-left surface-pixel coordinates, filtering, premultiplied colors and draw order stay shared across platforms.

`TGMetalView` owns the display link, render thread, command queue and three frame slots. `TGMetalContext` shares the device, embedded shader library, pipelines and samplers. Sprite geometry remains six vertices per quad, eight floats per vertex and at most 1,000 quads per flush. Each slot has reusable vertex arenas; flushes use distinct aligned regions, including the later HUD pass. A slot cannot be reused until its command completes.

`TGSpriteSheet` publishes a strong `TGMetalTexture` reference containing the texture and sampler. Load/dispose publication is synchronized across renderers. `dispose()` prevents reloading, and already encoded commands retain their resources until completion. Closing one view does not invalidate another view’s sheet.

Camera effects render into a private intermediate texture only when active, then composite onto the drawable. The diagnostic HUD is drawn afterwards. Explicit pause and application suspension are separate; missing drawables and busy frame slots reset simulation timing. Shutdown stops CPU submissions and retains retiring renderer resources asynchronously until pending commands complete, without callbacks into destroyed proxies.

## Build

```sh
cd ios
ti build -p ios --build-only --sdk 13.4.1.GA
```

The CLI builds the XCFramework with iOS arm64, simulator arm64/x86_64 and Catalyst arm64/x86_64. The manifest enables `mac: true`; Xcode keeps `SDKROOT=iphoneos`, `SUPPORTED_PLATFORMS="iphoneos iphonesimulator"` and `SUPPORTS_MACCATALYST=YES`. The consuming app does not need a `default.metallib`: Metal Shading Language source is embedded and compiled once during device initialization. Initialization failures log a native diagnostic and stop the view.

The project still declares iOS 12. The Xcode 27.1 toolchain used for validation rejects deployment targets below iOS 15, and the installed SDK is 13.4.1.GA rather than the default `titanium.xcconfig` value. These external overrides reproduce that validation build without changing the declared minimum:

```sh
cat > /tmp/ti-game-validation.xcconfig <<'CONFIG'
TITANIUM_SDK_VERSION = 13.4.1.GA
IPHONEOS_DEPLOYMENT_TARGET = 15.0
CONFIG
XCODE_XCCONFIG_FILE=/tmp/ti-game-validation.xcconfig ti build -p ios --build-only --sdk 13.4.1.GA
```

An artifact built this way requires iOS 15. It does **not** certify iOS 12 compatibility. Certifying iOS 12 requires a compatible Xcode/Titanium toolchain and a suitable device; do not silently raise the source minimum or claim that old systems were tested. The module version remains upstream’s 1.0.0; identify experimental artifacts by source commit and SHA-256, not by that version alone. No release is published by the build.

## Verification

From the repository root, with Xcode and XcodeGen installed:

```sh
python3 tests/apple-renderer/run.py
python3 tests/apple-renderer/run.py --destination 'platform=macOS,variant=Mac Catalyst' --deployment-target 15.0 --output /tmp/asteroids-metal-port/catalyst-tests
python3 tests/apple-renderer/run.py --baseline --output /tmp/asteroids-metal-port/opengl-reference
python3 tests/test_rope_pause.py
python3 tests/test_periodic_path.py
```

The default simulator is iPhone 16e/iOS 18.6; override `--destination` and `--deployment-target` for another installed runtime. Projects, build products, pixel attachments and XCTest results go under `/tmp`, outside the checkout. The UIKit test host supports `UIScene` on current systems and the legacy window lifecycle on iOS 12. Device execution additionally accepts `--signing-profile`, `--signing-team` and `--signing-identity` together.

The tests execute production batching, texture upload, scene rendering and display-loop methods. Coverage includes blend modes, texture orientation/flips, silhouettes, text, particles, ropes, tile layers, effects/HUD composition, vertex memory/flush lifetime, shared textures, disposal before GPU submission, multi-view pause/resume, touch scale changes and telemetry. OpenGL reference fixtures run against the preserved Git baseline `127a08c`, without keeping a second renderer in production.

`tests/apple-renderer/prepare_demos.py --icon /path/to/DefaultIcon.png` prepares a separate Classic application that opens, renders and closes all 34 launcher demos. It writes `metal-demos.json` in its own application data directory. This is an integration smoke test; it does not replace an interactive visual/gameplay review or imply that every example mechanic was exercised.

`averagePresentMs` measures CPU drawable acquisition and presentation submission. It is not GPU duration. `presentFailures` counts drawable failures and each asynchronous command error consumed by the active telemetry window; terminal errors after close are logged. Submitting a command does not certify physical presentation. Instrumentation remains inactive without a HUD or `performance` listener.

Validation on 2026-10-19: the upstream-based version 1.0.0 package compiled with Titanium 13.4.1.GA; all 16 Metal XCTest cases passed on Apple Silicon Catalyst. Physical iPhone, iOS 12, Intel execution, complete interactive demo acceptance and controlled performance comparison remain pending. Earlier iPad results are historical and have not been repeated for this package. Packaging verifies architecture presence, not execution on that hardware.
