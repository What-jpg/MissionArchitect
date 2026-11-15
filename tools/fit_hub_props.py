"""Fit the hand-made hub props (hub_props_v2) to the hub and the player.

For each prop: crop to visible pixels, scale by height to a size that matches the astronaut
(1 art px = 1/3 world px, like every hub sprite), keep a small crisp palette, add a soft
contact shadow on the floor, and write the sprite offset so the feet stand exactly on the floor.
The animated door is built separately by tools/make_door_frames.py.

Usage: python tools/fit_hub_props.py <folder with *_v2.png>      (requires Pillow)
"""
import re, sys
from PIL import Image, ImageDraw

SHADOW = 3  # rows of floor shadow below the feet, in art px
# source: (output, art height before trimming soft edges, scene file to update or None)
TARGETS = {
    "control_center_v2.png": ("mission_console.png", 54, "scenes/hub/MissionConsole.tscn"),
    "workshop_v2.png": ("workshop.png", 60, "scenes/hub/Workshop.tscn"),
    "laboratory_v2.png": ("laboratory.png", 52, "scenes/hub/Laboratory.tscn"),
    "archive_cabinet_v2.png": ("archive_shelf.png", 74, "scenes/hub/Archive.tscn"),
}

def solid_bbox(im: Image.Image, share: float = 0.03):
    """Bounding box of real content: rows/columns with at least `share` opaque pixels (ignores stray specks)."""
    a = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    w, h = a.size
    px = a.load()
    rows = [y for y in range(h) if sum(1 for x in range(0, w, 2) if px[x, y]) >= share * w / 2]
    cols = [x for x in range(w) if sum(1 for y in range(0, h, 2) if px[x, y]) >= share * h / 2]
    return (cols[0], rows[0], cols[-1] + 1, rows[-1] + 1)

def fit(src: str, name: str, out: str, height: int, scene):
    im = Image.open(f"{src}/{name}").convert("RGBA")
    im = im.crop(solid_bbox(im))
    width = max(1, round(im.width * height / im.height))
    small = im.resize((width, height), Image.BOX)
    alpha = small.getchannel("A").point(lambda a: 255 if a >= 140 else 0)
    rgb = small.convert("RGB").quantize(colors=48, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).convert("RGBA")
    rgb.putalpha(alpha)
    rgb = rgb.crop(rgb.getchannel("A").getbbox())                     # no empty rows under the feet
    full = Image.new("RGBA", (rgb.width + 6, rgb.height + SHADOW), (0, 0, 0, 0))
    sd = ImageDraw.Draw(full)
    for i in range(SHADOW):                           # soft floor shadow, widest at the feet
        a = 110 - i * 35
        sd.line([2 + i, rgb.height + i, full.width - 3 - i, rgb.height + i], fill=(8, 12, 20, a))
    full.alpha_composite(rgb, (3, 0))
    full.save(f"assets/art/{out}")
    # Sprite is centred: put the bottom of the object (not the shadow) on the station's floor point.
    offset = -(full.height / 2 - SHADOW) / 3
    if scene:
        text = open(scene, encoding="utf-8").read()
        text = re.sub(r'(\[node name="Sprite2D" type="Sprite2D" parent="\."\][^\[]*?position = )Vector2\([^)]*\)',
                      lambda m: m.group(1) + "Vector2(0, %.3f)" % offset, text, count=1)
        open(scene, "w", encoding="utf-8").write(text)
    print(out, full.size, "offset", round(offset, 3))
    return full.size

if __name__ == "__main__":
    for name, (out, h, scene) in TARGETS.items():
        fit(sys.argv[1], name, out, h, scene)
