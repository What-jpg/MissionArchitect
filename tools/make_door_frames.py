"""Animated hub door, laid out like the very first door: the doorway is the vertical strip at the
building's edge (5 world px wide). Closed, the steel leaf is seen edge-on and fills that strip
exactly (like frame 1 of the classic animated-door sheet). Opening, the strip becomes a dark doorway
and the leaf swings out on its hinge at the wall edge, growing into a trapezoid with an amber handle.

Pixel art in the hub palette at 1 art px = 1/3 world px.
Usage: python tools/make_door_frames.py      (requires Pillow)
Outputs: assets/art/hub_door_anim.png, assets/art/animations/hub_door.tres
"""
import math
from PIL import Image, ImageDraw

OUT = (16, 26, 43, 255)
DEEP, D1, D2 = (10, 16, 28, 255), (22, 35, 58, 255), (32, 49, 71, 255)
M0, M1, M2, M3 = (52, 70, 91, 255), (75, 89, 107, 255), (99, 112, 130, 255), (137, 148, 164, 255)
L1, L2 = (184, 192, 202, 255), (210, 216, 223, 255)
AMB, AMBD, AMBL = (242, 201, 76, 255), (161, 122, 50, 255), (255, 228, 138, 255)

STRIP = 15            # doorway / closed-leaf width (5 world px = the wall-edge strip)
LEAF = 21             # leaf width when fully open, seen face-on (7 world px)
HEADER = 3            # steel lintel above the doorway
H = 75                # 25 world px from lintel top to the floor
SLANT = 9             # outer top corner drops this much at full swing (perspective)
ANGLES = [0, 28, 52, 72, 90]

def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + (255,)

def frame(angle):
    im = Image.new("RGBA", (STRIP + LEAF + 2, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = math.sin(math.radians(angle))
    top = HEADER
    # lintel
    d.rectangle([0, 0, STRIP - 1, HEADER - 1], fill=L1)
    d.line([0, HEADER - 1, STRIP - 1, HEADER - 1], fill=M2)
    if angle == 0:
        # closed: leaf edge-on fills the strip
        d.rectangle([0, top, STRIP - 1, H - 1], fill=M2)
        d.line([1, top, 1, H - 1], fill=M3)
        d.line([STRIP - 2, top, STRIP - 2, H - 1], fill=M0)
        for y in range(top + 6, H - 4, 12):
            d.line([2, y, STRIP - 3, y], fill=M1)
        d.rectangle([0, top, STRIP - 1, H - 1], outline=OUT)
        d.rectangle([STRIP - 5, top + 34, STRIP - 2, top + 40], fill=AMB, outline=OUT)   # handle
        d.point([(STRIP - 4, top + 35)], fill=AMBL)
        return im
    # open: dark doorway with jamb trim and a faint lit floor inside
    d.rectangle([0, top, STRIP - 1, H - 1], fill=DEEP)
    for i, y in enumerate(range(H - 14, H)):
        d.line([2, y, STRIP - 3, y], fill=shade(D2, 0.8 + i * 0.03))
    d.line([1, top, 1, H - 1], fill=M1)
    d.line([2, top + 1, STRIP - 3, top + 1], fill=AMBD)
    d.rectangle([0, top, STRIP - 1, H - 1], outline=OUT)
    # leaf: trapezoid hinged at the strip's outer edge, face width grows with sin(angle)
    w = max(2, round(LEAF * s))
    x0 = STRIP
    for i in range(w):
        t = i / max(1, w - 1)
        y_top = top + round(SLANT * s * t)
        k = 0.78 + 0.22 * t          # darker near the hinge (turned away from the light)
        d.line([x0 + i, y_top, x0 + i, H - 1], fill=shade(M2, k))
        if 0.2 <= t <= 0.8 and w >= 6:   # recessed panels follow the perspective
            span = H - 1 - y_top
            for a, b in ((0.12, 0.45), (0.55, 0.88)):
                ya, yb = y_top + round(span * a), y_top + round(span * b)
                d.line([x0 + i, ya, x0 + i, yb], fill=shade(M1, k))
                d.point([(x0 + i, ya)], fill=shade(M0, k))
                d.point([(x0 + i, yb)], fill=shade(M3, k))
        d.point([(x0 + i, y_top)], fill=shade(M3, k))
    d.line([x0 + w, top + round(SLANT * s), x0 + w, H - 1], fill=OUT)
    d.line([x0, top - 1, x0 + w, top + round(SLANT * s) - 1], fill=OUT)
    if w > 6:   # rivets near the corners
        for t in (0.12, 0.88):
            xi = x0 + round(t * (w - 1))
            d.point([(xi, top + round(SLANT * s * t) + 3), (xi, H - 4)], fill=L1)
    # amber handle near the free edge
    hx = x0 + max(1, round(0.82 * (w - 1)))
    hy = top + round(SLANT * s * 0.82) + (H - top) // 2 - 4
    hw = max(1, round(3 * s))
    d.rectangle([hx - hw, hy, hx, hy + 6], fill=AMB, outline=OUT)
    if hw > 1: d.point([(hx - hw + 1, hy + 1)], fill=AMBL)
    return im

frames = [frame(a) for a in ANGLES]
cw, ch = frames[0].size
SHADOW = 2
sheet = Image.new("RGBA", (cw * len(frames), ch + SHADOW), (0, 0, 0, 0))
for i, f in enumerate(frames):
    cell = Image.new("RGBA", (cw, ch + SHADOW), (0, 0, 0, 0))
    leaf_w = 0 if i == 0 else max(2, round(LEAF * math.sin(math.radians(ANGLES[i]))))
    for r in range(SHADOW):   # contact shadow under the doorway and the open leaf
        cell.paste((8, 12, 20, 100 - r * 40), (0, ch + r, STRIP + leaf_w + 1, ch + r + 1))
    cell.alpha_composite(f, (0, 0))
    sheet.paste(cell, (i * cw, 0))
sheet.save("assets/art/hub_door_anim.png")

n = len(frames)
subs = "".join(f'[sub_resource type="AtlasTexture" id="F{i}"]\natlas = ExtResource("1")\nregion = Rect2({i * cw}, 0, {cw}, {ch + SHADOW})\n\n' for i in range(n))
seq = ", ".join(f'{{"duration": 1.0, "texture": SubResource("F{i}")}}' for i in range(n))
open("assets/art/animations/hub_door.tres", "w").write(
    f'[gd_resource type="SpriteFrames" load_steps={n + 2} format=3]\n\n'
    '[ext_resource type="Texture2D" path="res://assets/art/hub_door_anim.png" id="1"]\n\n' + subs +
    f'[resource]\nanimations = [{{"frames": [{seq}], "loop": false, "name": &"open", "speed": 12.0}}]\n')
print("cell", (cw, ch + SHADOW), "frames", n, "strip art px", STRIP)
