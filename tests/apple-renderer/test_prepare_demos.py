"""Exercise diagnostic app generation against the real launcher and demos."""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile


ROOT = Path(__file__).resolve().parents[2]


class PrepareDemosTest(unittest.TestCase):
    def prepare(self, *options):
        temp = tempfile.TemporaryDirectory(prefix='ti-game-prepare-test-')
        self.addCleanup(temp.cleanup)
        base = Path(temp.name)
        repo = base / 'repo'
        script = repo / 'tests/apple-renderer/prepare_demos.py'
        script.parent.mkdir(parents=True)
        shutil.copy2(ROOT / 'tests/apple-renderer/prepare_demos.py', script)
        (repo / 'example').symlink_to(ROOT / 'example', target_is_directory=True)
        (repo / 'ios/dist').mkdir(parents=True)
        shutil.copy2(ROOT / 'ios/manifest', repo / 'ios/manifest')
        version = re.search(r'^version:\s*(.+)$', (repo / 'ios/manifest').read_text(), re.M)[1]
        # Packaging is an input to this generator; native execution is tested elsewhere.
        with zipfile.ZipFile(repo / f'ios/dist/ti.game-iphone-{version}.zip', 'w') as archive:
            archive.writestr(f'modules/iphone/ti.game/{version}/manifest', f'version: {version}\n')
        output = base / 'generated'
        result = subprocess.run(
            [sys.executable, str(script), '--output', str(output),
             '--icon', str(ROOT / 'example/assets/adventurer.png'), *options],
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((output / f'modules/iphone/ti.game/{version}/manifest').is_file())
        app = (output / 'Resources/app.js').read_text()
        names = json.loads(re.search(r'\.run\((\[.*\])\);', app)[1])
        for name in names:
            code = (output / 'Resources' / f'{name}.js').read_text()
            self.assertEqual(code.count("require('/metal-smoke').track("), 1, name)
        return output, names

    def test_mobile_prepares_touch_demos_without_mac_only_input(self):
        output, names = self.prepare()
        self.assertEqual(len(names), 34)
        self.assertNotIn('inputmap', names)
        self.assertIn('camera', names)
        self.assertIn('worldwrap', names)
        app = ET.parse(output / 'tiapp.xml').getroot()
        self.assertEqual(app.findtext('sdk-version'), '13.4.1.GA')

    def test_mac_option_includes_input_and_configures_indirect_pointer_events(self):
        output, names = self.prepare('--include-input', '--sdk', '13.4.0.GA')
        self.assertEqual(len(names), 35)
        self.assertEqual(names.count('inputmap'), 1)
        app = ET.parse(output / 'tiapp.xml').getroot()
        self.assertEqual(app.findtext('sdk-version'), '13.4.0.GA')
        plist = app.find('ios/plist/dict')
        self.assertIsNotNone(plist)
        children = list(plist)
        key = next(i for i, child in enumerate(children) if child.text == 'UIApplicationSupportsIndirectInputEvents')
        self.assertEqual(children[key + 1].tag, 'true')


if __name__ == '__main__':
    unittest.main()
