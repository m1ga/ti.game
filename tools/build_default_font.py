#!/usr/bin/env python3
"""Build the embedded 9x15 pixel font. Requires Pillow and fontTools.
Run: uv run --with pillow --with fonttools python tools/build_default_font.py [--check]
"""
import argparse
import base64
import io
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / 'tools/default-font/PressStart2P-Regular.ttf'
ASCII = ''.join(chr(c) for c in range(32, 127))
EXTRA = 'ÁÉÍÓÚÜÑáéíóúüñ¿¡ÄÖäößËÏëïÈèÊêÀà'
CHARACTERS = ASCII + EXTRA
WIDTH, HEIGHT, COLS = 9, 15, 16


def atlas():
    font = ImageFont.truetype(str(FONT), 8)
    cmap = TTFont(FONT).getBestCmap()
    missing = [c for c in CHARACTERS if ord(c) not in cmap]
    if missing:
        raise ValueError('Missing glyphs: ' + ''.join(missing))
    result = Image.new('RGBA', (COLS * WIDTH, ((len(CHARACTERS) + COLS - 1) // COLS) * HEIGHT), (255, 255, 255, 0))
    for i, char in enumerate(CHARACTERS):
        tile = Image.new('RGBA', (WIDTH, HEIGHT), (255, 255, 255, 0))
        draw = ImageDraw.Draw(tile)
        draw.fontmode = '1'
        draw.text((0, 4), char, font=font, fill='white')
        result.paste(tile, (i % COLS * WIDTH, i // COLS * HEIGHT))
    return result


def payload(source, platform):
    name = 'PNG_BASE64' if platform == 'android' else 'kPngBase64'
    match = re.search(r'(' + name + r' = )(.*?);', source, re.S)
    return match, base64.b64decode(''.join(re.findall(r'"([^"\n]*)"', match[2])))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    image = atlas()
    buf = io.BytesIO()
    image.save(buf, format='PNG', optimize=True)
    data = base64.b64encode(buf.getvalue()).decode()
    paths = {'android': ROOT / 'android/src/ti/game/engine/DefaultFont.java',
             'ios': ROOT / 'ios/Classes/TGDefaultFont.m'}
    for platform, path in paths.items():
        source = path.read_text()
        match, old = payload(source, platform)
        if args.check:
            current = Image.open(io.BytesIO(old)).convert('RGBA')
            assert current.size == image.size and current.tobytes() == image.tobytes(), path
            marker = 'characters.append("' + EXTRA + '");' if platform == 'android' else '[characters appendString:@"' + EXTRA + '"];'
            assert marker in source, path
        else:
            prefix = '\n\t\t+ ' if platform == 'android' else '\n\t@'
            value = '""' if platform == 'android' else '@""'
            value += ''.join(prefix + '"' + data[i:i + 76] + '"' for i in range(0, len(data), 76))
            path.write_text(source[:match.start(2)] + value + source[match.end(2):])
    print(f'{len(CHARACTERS)} glyphs, {image.width}x{image.height}, cells {WIDTH}x{HEIGHT}; both platforms ' + ('verified' if args.check else 'updated'))


if __name__ == '__main__':
    main()
