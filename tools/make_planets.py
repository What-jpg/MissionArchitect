"""Render the Earth and Moon sprites from NASA global maps, in the game's pixel style.

Sources (public domain, NASA):
  Moon  — LRO LROC colour mosaic, NASA Scientific Visualization Studio "CGI Moon Kit"
          https://svs.gsfc.nasa.gov/4720  (lroc_color_poles_1k.jpg)
  Earth — Blue Marble based flat Earth map, NASA Scientific Visualization Studio
          https://svs.gsfc.nasa.gov/3615  (flat_earth_Largest_still.0330.jpg)
Each equirectangular map is projected onto a sphere (orthographic view, light from the upper left),
rendered at 64 px, reduced to a small palette, outlined and scaled ×3 with nearest neighbour,
so it matches the other sprites (1 art px = 1/3 world px). Output size and framing match the
previous earth.png / moon.png (192 × 192).

Usage: python tools/make_planets.py <moon_map.jpg> <earth_map.jpg>      (requires Pillow, NumPy)
"""
import sys
import numpy as np
from PIL import Image

N = 64          # art resolution of the sprite
R = 29.5        # planet radius in art px (previous sprites filled ~92% of the canvas)
OUTLINE = (16, 26, 43)

def render(map_path, lon0_deg, colours, atmosphere=None, contrast=1.0, brightness=1.0, ambient=0.25):
    src = np.asarray(Image.open(map_path).convert("RGB"), dtype=np.float32) / 255.0
    h, w, _ = src.shape
    ss = 4                                   # supersample for clean edges before pixelating
    n = N * ss
    c = (n - 1) / 2.0
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    x = (xs - c) / (R * ss)
    y = (c - ys) / (R * ss)
    r2 = x * x + y * y
    inside = r2 <= 1.0
    z = np.sqrt(np.clip(1.0 - r2, 0, 1))
    lat = np.arcsin(np.clip(y, -1, 1))
    lon = np.arctan2(x, z) + np.radians(lon0_deg)
    u = ((lon / (2 * np.pi) + 0.5) % 1.0) * (w - 1)
    v = (0.5 - lat / np.pi) * (h - 1)
    tex = src[v.astype(int).clip(0, h - 1), u.astype(int).clip(0, w - 1)]
    tex = np.clip((tex - 0.5) * contrast + 0.5, 0, 1) * brightness
    # Lambert light from the upper left, with a soft ambient term like the rest of the art.
    light = np.array([-0.55, 0.55, 0.63]); light /= np.linalg.norm(light)
    shade = np.clip(x * light[0] + y * light[1] + z * light[2], 0, 1)
    tex = np.clip(tex * (ambient + (1.1 - ambient) * shade)[..., None], 0, 1)
    rgba = np.zeros((n, n, 4), dtype=np.float32)
    rgba[..., :3] = tex
    rgba[..., 3] = inside.astype(np.float32)
    if atmosphere is not None:               # thin blue limb glow for the Earth
        rim = np.clip((np.sqrt(r2) - 0.86) / 0.14, 0, 1) * inside
        a = np.array(atmosphere, dtype=np.float32) / 255.0
        rgba[..., :3] = rgba[..., :3] * (1 - 0.6 * rim[..., None]) + a * 0.6 * rim[..., None]
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").resize((N, N), Image.BOX)
    alpha = img.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    rgb = img.convert("RGB").quantize(colors=colours, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGBA")
    rgb.putalpha(alpha)
    # 1 px dark outline, like every other sprite
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    px, op = rgb.load(), out.load()
    for yy in range(N):
        for xx in range(N):
            if px[xx, yy][3]: continue
            if any(0 <= xx + dx < N and 0 <= yy + dy < N and px[xx + dx, yy + dy][3]
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                op[xx, yy] = OUTLINE + (255,)
    out.alpha_composite(rgb)
    return out.resize((N * 3, N * 3), Image.NEAREST)

if __name__ == "__main__":
    # Moon: near side facing Earth (longitude 0) — Mare Tranquillitatis sits right of centre.
    render(sys.argv[1], 0, 16, contrast=1.35, brightness=1.45, ambient=0.62).save("assets/art/moon.png")
    # Earth: Europe and Africa, the hemisphere facing the player's launch site.
    render(sys.argv[2], 20, 24, atmosphere=(115, 190, 240), contrast=1.1, brightness=1.3, ambient=0.45).save("assets/art/earth.png")
    print("moon.png and earth.png written (192×192)")
