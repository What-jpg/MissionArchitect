"""Clean the sprites cut from the old JPG sheets so they sit with the new pixel-art set.

Each sprite is reduced to a small adaptive palette (removes JPEG noise and colour speckle),
semi-transparent fringe pixels are snapped to fully opaque/transparent, and a 1 px dark outline
(#101A2B, the shared outline colour of the new assets) is added. Originals are kept in assets/art/legacy/.

Usage: python tools/clean_legacy_sprites.py          (requires Pillow)
"""
import os, shutil
from PIL import Image

ART = "assets/art"
LEGACY = os.path.join(ART, "legacy")
OUTLINE = (16, 26, 43, 255)
SPRITES = {
    # name: (colours, outline)
    "rocket": (20, True), "stage_1": (16, True), "stage_2": (16, True),
    "lander": (24, True), "lander_legs": (24, True),
    "mission_console": (32, True), "archive_shelf": (32, True), "workshop": (32, True),
    "laboratory": (32, True), "ground_antenna": (20, True), "ladder": (10, True),
    "flag": (8, True), "beacon": (8, True),
    "earth": (32, False), "moon": (20, False),
    "icon_mass": (12, False), "icon_energy": (12, False), "icon_budget": (12, False),
    "icon_data": (12, False), "icon_signal": (12, False), "icon_time": (12, False),
}

def clean(name: str, colours: int, outline: bool) -> None:
    src = os.path.join(LEGACY, name + ".png")
    if not os.path.exists(src):
        shutil.copy(os.path.join(ART, name + ".png"), src)
    im = Image.open(src).convert("RGBA")
    alpha = im.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    rgb = im.convert("RGB").quantize(colors=colours, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    if outline:
        w, h = out.size
        src_px = out.load()
        border = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        bp = border.load()
        for y in range(h):
            for x in range(w):
                if src_px[x, y][3]:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and src_px[nx, ny][3]:
                        bp[x, y] = OUTLINE
                        break
        border.alpha_composite(out)
        out = border
    out.save(os.path.join(ART, name + ".png"))

if __name__ == "__main__":
    os.makedirs(LEGACY, exist_ok=True)
    for name, (colours, outline) in SPRITES.items():
        clean(name, colours, outline)
    print("cleaned", len(SPRITES), "sprites; originals in", LEGACY)
