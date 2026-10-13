"""Run with: uv run --with pillow --with fonttools python tests/test_default_font.py"""
import io
from pathlib import Path
import sys
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import build_default_font as builder


class DefaultFontTests(unittest.TestCase):
    def setUp(self):
        self.expected = builder.atlas()

    def test_platform_images_and_character_maps_match_generator(self):
        paths = {'android': 'android/src/ti/game/engine/DefaultFont.java',
                 'ios': 'ios/Classes/TGDefaultFont.m'}
        for platform, path in paths.items():
            with self.subTest(platform=platform):
                source = (ROOT / path).read_text()
                _, data = builder.payload(source, platform)
                actual = Image.open(io.BytesIO(data)).convert('RGBA')
                self.assertEqual(actual.size, (144, 120))
                self.assertEqual(actual.tobytes(), self.expected.tobytes())
                marker = 'characters.append("' + builder.EXTRA + '");' if platform == 'android' else '[characters appendString:@"' + builder.EXTRA + '"];'
                self.assertIn(marker, source)
                self.assertIn('c = 32; c < 127; c++', source)

    def test_ascii_positions_and_cell_metrics_are_preserved(self):
        self.assertEqual(builder.CHARACTERS[:95], ''.join(chr(c) for c in range(32, 127)))
        self.assertEqual((builder.WIDTH, builder.HEIGHT, builder.COLS), (9, 15, 16))
        java = (ROOT / 'android/src/ti/game/engine/DefaultFont.java').read_text()
        ios = (ROOT / 'ios/Classes/TGDefaultFont.m').read_text()
        self.assertIn('CHAR_WIDTH = 9;', java)
        self.assertIn('CHAR_HEIGHT = 15;', java)
        self.assertIn('kCharWidth = 9;', ios)
        self.assertIn('kCharHeight = 15;', ios)

    def tile(self, char):
        i = builder.CHARACTERS.index(char)
        return self.expected.crop((i % 16 * 9, i // 16 * 15, i % 16 * 9 + 9, i // 16 * 15 + 15)).getchannel('A')

    def test_all_non_space_characters_have_pixels_without_cell_bleed(self):
        self.assertEqual(len(set(builder.CHARACTERS)), len(builder.CHARACTERS))
        for char in builder.CHARACTERS:
            with self.subTest(char=char):
                tile = self.tile(char)
                if char == ' ':
                    self.assertIsNone(tile.getbbox())
                else:
                    self.assertIsNotNone(tile.getbbox())
                    self.assertIsNone(tile.crop((8, 0, 9, 15)).getbbox())
                    self.assertIsNone(tile.crop((0, 0, 9, 4)).getbbox())
        self.assertLessEqual(set(self.expected.getchannel('A').getdata()), {0, 255})

    def test_requested_languages_and_distinct_accent_glyphs(self):
        for language in ['ÁÉÍÓÚÜÑáéíóúüñ¿¡', 'ÄÖÜäöüß', 'ËÏëïÈèÊêÀà']:
            self.assertTrue(set(language) <= set(builder.CHARACTERS))
        for accented, base in zip('ÁÉÍÓÚÜÑáéíóúüñÄÖäöËÏëïÈèÊêÀà', 'AEIOUUNaeiouunAOaoEIeiEeEeAa'):
            self.assertNotEqual(self.tile(accented).tobytes(), self.tile(base).tobytes(), accented)
        self.assertNotIn('ẞ', builder.CHARACTERS)


if __name__ == '__main__':
    unittest.main(verbosity=2)
