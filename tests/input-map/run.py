#!/usr/bin/env python3
"""Execute production native digital resolvers. Requires JDK; Objective-C requires macOS."""
from pathlib import Path
import platform, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='ti-game-input-') as out:
 subprocess.run(['javac','-Xlint:all','-d',out,str(ROOT/'android/src/ti/game/engine/InputResolver.java'),str(ROOT/'tests/input-map/ResolverTest.java')],check=True)
 subprocess.run(['java','-cp',out,'ResolverTest'],check=True)
 if platform.system()=='Darwin':
  subprocess.run(['xcrun','clang','-fobjc-arc','-Wall','-Werror','-framework','Foundation','-I'+str(ROOT/'ios/Classes'),str(ROOT/'tests/input-map/resolver.m'),str(ROOT/'ios/Classes/TGInputResolver.m'),'-o',out+'/resolver'],check=True)
  subprocess.run([out+'/resolver'],check=True)
