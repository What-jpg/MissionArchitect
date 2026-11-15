"""Add pixel glyphs missing from the UI font (arrows, Δ, ○ ● ✓ ✗ ≤ ₀ ₴, ʼ) on its 50-unit pixel grid.

Usage: python tools/add_font_glyphs.py <source.ttf> <output.ttf> [units_per_pixel]   (requires fonttools)
Running it on an already patched font simply redraws the same glyphs.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

U = 50  # font units per pixel (override with a 3rd argument)

right = ["......##..", "......###.", "##########", "##########", "......###.", "......##.."]
def mirror(rows): return [r[::-1] for r in rows]
def rot_ccw(rows):
    w = len(rows[0])
    return ["".join(rows[r][w - 1 - c] for r in range(len(rows))) for c in range(w)]
up = rot_ccw(right)

# code: (rows top→bottom, bottom row height above baseline in pixels)
GLYPHS = {
    0x2192: (right, 2),
    0x2190: (mirror(right), 2),
    0x2191: (up, 0),
    0x2193: (up[::-1], 0),
    0x0394: (["....##....", "...####...", "...#..#...", "..##..##..", "..#....#..", ".##....##.", ".#......#.", "##......##", "##########", "##########"], 0),
    0x25CB: (["..######..", ".########.", "###....###", "##......##", "##......##", "##......##", "##......##", "###....###", ".########.", "..######.."], 1),
    0x25CF: (["..######..", ".########.", "##########", "##########", "##########", "##########", "##########", "##########", ".########.", "..######.."], 1),
    0x2713: ([".........##", "........##.", ".......##..", "##....##...", ".##..##....", "..####.....", "...##......"], 1),
    0x2717: (["##.....##", ".##...##.", "..##.##..", "...###...", "..##.##..", ".##...##.", "##.....##"], 1),
    0x2264: ([".......##", ".....##..", "...##....", ".##......", "...##....", ".....##..", ".......##", ".........", "#########", "#########"], 0),
    0x2080: ([".####.", "##..##", "##..##", "##..##", ".####."], -2),
    0x20B4: ([".######.", "##....##", "......##", "########", ".....##.", "...##...", ".##.....", "########", "##......", "##....##", ".######."], 0),
}

def main(src: str, dst: str) -> None:
    f = TTFont(src)
    cmap = f.getBestCmap()
    order = f.getGlyphOrder()
    tables = [t for t in f["cmap"].tables if t.isUnicode()]
    for code, (rows, bottom) in GLYPHS.items():
        if code in cmap: continue          # keep the font's own design when it has the glyph
        name = "uni%04X" % code
        pen = TTGlyphPen(None)
        height = len(rows)
        for r, row in enumerate(rows):
            y = (bottom + height - 1 - r) * U
            for c, ch in enumerate(row):
                if ch == "#":
                    x = U + c * U
                    pen.moveTo((x, y)); pen.lineTo((x, y + U)); pen.lineTo((x + U, y + U)); pen.lineTo((x + U, y)); pen.closePath()
        f["glyf"][name] = pen.glyph()
        f["hmtx"][name] = ((len(rows[0]) + 2) * U, U)
        if name not in order: order.append(name)
        for t in tables: t.cmap[code] = name
    best = f.getBestCmap()
    if 0x2019 in best:
        for t in tables: t.cmap[0x02BC] = best[0x2019]
    f.setGlyphOrder(order)
    f.save(dst)
    print("glyphs:", ", ".join(chr(c) for c in GLYPHS))

if __name__ == "__main__":
    if len(sys.argv) > 3: U = int(sys.argv[3])
    main(sys.argv[1], sys.argv[2])
