#!/usr/bin/env python3
"""Generate bitmap font atlases for ti.game from a TTF/OTF font.

Grid mode (monospace fonts — the simple createFont grid format):

    python3 genfont.py --ttf NotoSansMono-Bold.ttf --size 14 --grid -o myfont

  Writes myfont.png (16 columns, ASCII 32..126, hard 1-bit pixels) and
  prints the charWidth/charHeight values to pass to Game.createFont().

BMFont mode (any font — proportional metrics + kerning):

    python3 genfont.py --ttf SomeFont.ttf --size 28 -o myfont

  Writes myfont.png and myfont.fnt (AngelCode text format) for
  Game.createFont({ font: 'myfont.fnt' }).

Glyphs are rasterized without antialiasing by default (pixel-art look,
scale text sprites up with smoothing: false); pass --smooth for
antialiased glyphs (larger sizes, smoothing: true).
"""

import argparse

from PIL import Image, ImageDraw, ImageFont

CHARS = "".join(chr(c) for c in range(32, 127))
GRID_COLS = 16


def load_font(path, size):
    return ImageFont.truetype(path, size)


def save_atlas(atlas, path):
    """White RGB + glyph alpha: the engine multiplies texture * tint, so
    glyphs must be white-on-transparent, never white-on-black."""
    white = Image.new("L", atlas.size, 255)
    Image.merge("RGBA", (white, white, white, atlas)).save(path, optimize=True)


def render_glyph(font, ch, mode):
    """Rasterize one glyph; returns (image, bbox) with line-top origin."""
    bbox = font.getbbox(ch, anchor="la")
    x0, y0, x1, y1 = bbox
    w, h = max(1, x1 - x0), max(1, y1 - y0)
    tile = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(tile)
    draw.fontmode = mode  # "1" = no antialiasing
    draw.text((-x0, -y0), ch, font=font, fill=255, anchor="la")
    return tile, bbox


def generate_grid(font, out, mode):
    """Monospace grid: 16 columns of fixed cells, row-major from char 32."""
    tiles = {}
    x_min, x_max = 10 ** 6, -(10 ** 6)
    y_min, y_max = 10 ** 6, -(10 ** 6)
    for ch in CHARS:
        tile, (x0, y0, x1, y1) = render_glyph(font, ch, mode)
        if tile.getbbox():  # visible pixels
            tiles[ch] = (tile, x0, y0)
            x_min = min(x_min, x0)
            x_max = max(x_max, x1)
            y_min = min(y_min, y0)
            y_max = max(y_max, y1)
    # Cell = the widest glyph, so wide letters (W, %) never bleed into the
    # neighbor cell; the grid's advance equals the cell width.
    cell_w = x_max - x_min
    cell_h = y_max - y_min
    rows = (len(CHARS) + GRID_COLS - 1) // GRID_COLS
    atlas = Image.new("L", (GRID_COLS * cell_w, rows * cell_h), 0)
    for i, ch in enumerate(CHARS):
        if ch not in tiles:
            continue
        tile, x0, y0 = tiles[ch]
        cx = (i % GRID_COLS) * cell_w
        cy = (i // GRID_COLS) * cell_h
        atlas.paste(tile, (cx + x0 - x_min, cy + y0 - y_min))
    save_atlas(atlas, out + ".png")
    print(f"{out}.png: {atlas.width}x{atlas.height}, "
          f"charWidth: {cell_w}, charHeight: {cell_h}, chars 32..126")
    print(f"Game.createFont({{ image: '{out}.png', "
          f"charWidth: {cell_w}, charHeight: {cell_h} }})")


def generate_bmfont(font, out, mode, texture_width):
    """BMFont text format: shelf-packed atlas + .fnt with kerning pairs."""
    ascent, descent = font.getmetrics()
    line_height = ascent + descent
    pad = 1
    glyphs = []  # (ch, tile, x0, y0, advance)
    for ch in CHARS:
        tile, (x0, y0, x1, y1) = render_glyph(font, ch, mode)
        visible = tile.getbbox() is not None
        glyphs.append((ch, tile if visible else None, x0, y0, font.getlength(ch)))

    # Shelf packing in input order (uniform sizes pack fine)
    pen_x, pen_y, shelf_h = pad, pad, 0
    placed = {}
    for ch, tile, x0, y0, adv in glyphs:
        if tile is None:
            continue
        if pen_x + tile.width + pad > texture_width:
            pen_x = pad
            pen_y += shelf_h + pad
            shelf_h = 0
        placed[ch] = (pen_x, pen_y)
        pen_x += tile.width + pad
        shelf_h = max(shelf_h, tile.height)
    height = pen_y + shelf_h + pad

    atlas = Image.new("L", (texture_width, height), 0)
    for ch, tile, x0, y0, adv in glyphs:
        if tile is not None:
            atlas.paste(tile, placed[ch])
    save_atlas(atlas, out + ".png")

    kernings = []
    for a in CHARS:
        for b in CHARS:
            k = font.getlength(a + b) - font.getlength(a) - font.getlength(b)
            if abs(k) >= 0.5:
                kernings.append((ord(a), ord(b), round(k)))

    lines = [
        f'info face="{font.getname()[0]}" size={font.size} bold=0 italic=0 '
        'charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1',
        f'common lineHeight={line_height} base={ascent} scaleW={texture_width} '
        f'scaleH={height} pages=1 packed=0',
        f'page id=0 file="{out.rsplit("/", 1)[-1]}.png"',
        f'chars count={len(glyphs)}',
    ]
    for ch, tile, x0, y0, adv in glyphs:
        if tile is None:
            x, y, w, h = 0, 0, 0, 0
        else:
            (x, y), w, h = placed[ch], tile.width, tile.height
        lines.append(
            f'char id={ord(ch)} x={x} y={y} width={w} height={h} '
            f'xoffset={x0} yoffset={y0} xadvance={round(adv)} page=0 chnl=15')
    if kernings:
        lines.append(f'kernings count={len(kernings)}')
        lines.extend(f'kerning first={a} second={b} amount={k}' for a, b, k in kernings)
    with open(out + ".fnt", "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{out}.png: {atlas.width}x{atlas.height}, {out}.fnt: "
          f"{len(placed)} glyphs, {len(kernings)} kerning pairs")
    print(f"Game.createFont({{ font: '{out}.fnt' }})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ttf", required=True, help="TTF/OTF font file")
    parser.add_argument("--size", type=int, default=14, help="pixel size (default 14)")
    parser.add_argument("--grid", action="store_true",
                        help="monospace grid atlas instead of BMFont")
    parser.add_argument("--smooth", action="store_true", help="antialiased glyphs")
    parser.add_argument("--texture-width", type=int, default=256,
                        help="BMFont atlas width (default 256)")
    parser.add_argument("-o", "--out", required=True, help="output basename")
    args = parser.parse_args()

    font = load_font(args.ttf, args.size)
    mode = "L" if args.smooth else "1"
    if args.grid:
        generate_grid(font, args.out, mode)
    else:
        generate_bmfont(font, args.out, mode, args.texture_width)


if __name__ == "__main__":
    main()
