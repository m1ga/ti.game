#!/usr/bin/env python3
"""Generate the XCTest project outside the checkout and run native GPU tests.
Requires Xcode, xcodegen and an installed simulator. Override --destination as needed.
The test deployment target must meet the module's iOS 15 minimum.
"""
import argparse
from pathlib import Path
import subprocess
import tarfile
import io

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--signing-profile')
parser.add_argument('--signing-team')
parser.add_argument('--signing-identity')
parser.add_argument('--only-testing', action='append', default=[])
parser.add_argument('--baseline', action='store_true', help='Run preserved OpenGL fixtures against upstream/main baseline 127a08c')
parser.add_argument('--destination', default='platform=iOS Simulator,name=iPhone 16e,OS=18.6')
parser.add_argument('--deployment-target', default='18.6')
parser.add_argument('--output', default='/tmp/asteroids-metal-port')
args = parser.parse_args()
if any((args.signing_profile, args.signing_team, args.signing_identity)) and not all((args.signing_profile, args.signing_team, args.signing_identity)):
    parser.error("Signing requires --signing-profile, --signing-team and --signing-identity together")
output = Path(args.output).resolve()
output.mkdir(parents=True, exist_ok=True)
spec = (HERE / 'project.yml').read_text()
for source in ('RendererTests.m', 'Host.m', '../../ios/Classes'):
    spec = spec.replace('path: ' + source, 'path: ' + str((HERE / source).resolve()))
spec = spec.replace('$(SRCROOT)/../../ios/Classes', str((HERE / '../../ios/Classes').resolve()))
spec = spec.replace('$(SRCROOT)/include', str(HERE / 'include'))
spec = spec.replace('$(SRCROOT)/Host-Info.plist', str(HERE / 'Host-Info.plist'))
if args.baseline:
    baseline = output / 'opengl-baseline'
    baseline.mkdir(exist_ok=True)
    archive = subprocess.run(['git', '-C', str(HERE.parents[1]), 'archive', '127a08c', 'ios/Classes'], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(archive)) as files:
        files.extractall(baseline, filter='data')
    spec = spec.replace(str(HERE / 'RendererTests.m'), str(HERE / 'OpenGLReferenceTests.m'))
    spec = spec.replace(str((HERE / '../../ios/Classes').resolve()), str(baseline / 'ios/Classes'))
    spec = spec.replace('Metal.framework', 'OpenGLES.framework').replace('TGMetalView.m', 'TGGLView.m')
    spec = spec.replace('          - TGMetalContext.m\n', '')
(output / 'project.yml').write_text(spec)
signing = []
if args.signing_profile:
    signing = ['CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_STYLE=Manual',
               'PROVISIONING_PROFILE_SPECIFIER=' + args.signing_profile,
               'DEVELOPMENT_TEAM=' + args.signing_team, 'CODE_SIGN_IDENTITY=' + args.signing_identity]
subprocess.run(['xcodegen', 'generate', '--spec', str(output / 'project.yml')], check=True)
raise SystemExit(subprocess.run(['xcodebuild', 'test', '-project', str(output / 'RendererTests.xcodeproj'),
    '-scheme', 'RendererTests', '-destination', args.destination, '-derivedDataPath', str(output / 'DerivedData'),
    'IPHONEOS_DEPLOYMENT_TARGET=' + args.deployment_target] + ['-only-testing:' + name for name in args.only_testing] + signing).returncode)
