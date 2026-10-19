#!/usr/bin/env python3
"""Compile real canvas capture and GameView responder methods with UIKit.
Only the renderer and Titanium event sink are replaced; UIKit focus is real.
"""
from pathlib import Path
import argparse, subprocess
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
p=argparse.ArgumentParser();p.add_argument('--destination',default='platform=iOS Simulator,name=iPhone 16e,OS=18.6');p.add_argument('--output',default='/tmp/ti-game-input-uikit');args=p.parse_args()
out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
source=(ROOT/'ios/Classes/TiGameGameView.m').read_text()
def method(signature):
 start=source.index(signature);brace=source.index('{',start);depth=1;end=brace+1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end].replace('TiGameGameViewProxy','InputProxy')
methods=[method(sig) for sig in ['- (BOOL)canBecomeFirstResponder','- (void)focusInput','- (void)releaseInput','- (void)releaseKeyboardInput','- (void)releasePointerInput','- (void)inputWindowResigned:','- (BOOL)resignFirstResponder','- (NSSet<UIPress *> *)handleKeys:','- (void)pressesBegan:','- (void)pressesEnded:','- (void)pressesCancelled:']]
(out/'UIKitTests.m').write_text((HERE/'UIKitTests.m').read_text().replace('PRODUCTION_METHODS','\n'.join(methods)))
for name in ('Host.m','Host-Info.plist'):
 (out/name).write_text((HERE/name).read_text())
(out/'project.yml').write_text(f'''name: InputTests
settings:
  base:
    CLANG_ENABLE_OBJC_ARC: YES
    CODE_SIGNING_ALLOWED: NO
    GENERATE_INFOPLIST_FILE: YES
    INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents: YES
    IPHONEOS_DEPLOYMENT_TARGET: 18.6
    HEADER_SEARCH_PATHS: "{ROOT}/ios/Classes"
targets:
  Host:
    type: application
    platform: iOS
    sources: [Host.m]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: mx.codigomovil.tigame.inputhost
        GENERATE_INFOPLIST_FILE: NO
        INFOPLIST_FILE: Host-Info.plist
  InputTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: UIKitTests.m
      - path: {ROOT}/ios/Classes/TGInputResolver.m
      - path: {ROOT}/ios/Classes/TGCanvasInput.m
    dependencies:
      - target: Host
schemes:
  InputTests:
    build:
      targets:
        InputTests: all
    test:
      targets: [InputTests]
''')
subprocess.run(['xcodegen','generate','--spec',str(out/'project.yml')],check=True)
raise SystemExit(subprocess.run(['xcodebuild','test','-project',str(out/'InputTests.xcodeproj'),'-scheme','InputTests','-destination',args.destination,'-derivedDataPath',str(out/'DerivedData'),'SUPPORTS_MACCATALYST=YES','IPHONEOS_DEPLOYMENT_TARGET=15.0']).returncode)
