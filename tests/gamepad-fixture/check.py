"""Run the production iOS receiver source against macOS GameController.

Usage: python3 tests/gamepad-fixture/check.py [repository]
Requires macOS with GameController and a compiler.
The UIKit/TitaniumKit stubs only replace view lifecycle/event delivery.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path, nargs='?', default=Path(__file__).resolve().parents[2])
args = parser.parse_args()
here = Path(__file__).resolve().parent
classes = args.source.resolve() / 'ios/Classes'
with tempfile.TemporaryDirectory(prefix='asteroids-gamepad-test-') as temp:
    binary = str(Path(temp) / 'receivers')
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks',
                    '-framework', 'Foundation', '-framework', 'GameController', '-framework', 'QuartzCore',
                    '-I', str(here), '-I', str(classes),
                    str(classes / 'TGGamepadController.m'), str(here / 'receivers.m'),
                    '-o', binary], check=True)
    subprocess.run([binary], check=True)
