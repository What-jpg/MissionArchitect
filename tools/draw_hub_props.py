"""Draw the hub props (mission console, workshop, laboratory, archive shelf, door) as clean pixel art
in the shared hub palette: 1 px #101A2B outline, light from the upper left, steel greys, amber and
cyan accents. Each art pixel shows as 2 screen pixels in game (sprites use scale 1/3 in a ×6 world).

Usage: python tools/draw_hub_props.py      (requires Pillow; writes into assets/art/)
"""
from PIL import Image, ImageDraw

OUT = (16, 26, 43, 255)
D1, D2 = (32, 49, 71, 255), (41, 59, 80, 255)
M0, M1, M2, M3 = (52, 70, 91, 255), (75, 89, 107, 255), (99, 112, 130, 255), (137, 148, 164, 255)
L1, L2, W = (184, 192, 202, 255), (210, 216, 223, 255), (233, 237, 240, 255)
AMB, AMB2, AMBD = (242, 201, 76, 255), (206, 155, 57, 255), (161, 122, 50, 255)
CY, CY2, CYD, CYB = (53, 182, 232, 255), (172, 223, 242, 255), (28, 102, 137, 255), (14, 40, 62, 255)
GRN, GRND = (111, 207, 127, 255), (46, 110, 70, 255)
PUR, PURD = (155, 107, 222, 255), (78, 52, 120, 255)
RED = (225, 100, 80, 255)

def canvas(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)

def box(d, x0, y0, x1, y1, light, base, dark, outline=True):
    """Bevelled block: lit top/left edge, shaded bottom/right edge, dark outline."""
    d.rectangle([x0, y0, x1, y1], fill=base)
    d.line([x0, y0, x1, y0], fill=light); d.line([x0, y0, x0, y1], fill=light)
    d.line([x0, y1, x1, y1], fill=dark); d.line([x1, y0, x1, y1], fill=dark)
    if outline: d.rectangle([x0 - 1, y0 - 1, x1 + 1, y1 + 1], outline=OUT)

def screen(d, x0, y0, x1, y1, kind):
    box(d, x0, y0, x1, y1, M3, M1, M0)
    d.rectangle([x0 + 2, y0 + 2, x1 - 2, y1 - 2], fill=CYB)
    for y in range(y0 + 3, y1 - 2, 2):
        d.line([x0 + 2, y, x1 - 2, y], fill=(18, 50, 76, 255))
    w, h = x1 - x0 - 6, y1 - y0 - 6
    if kind == "graph":
        pts = [(x0 + 3 + i, y1 - 4 - int((h - 2) * (0.5 + 0.4 * ((i * 7) % 11 - 5) / 5))) for i in range(0, w, 3)]
        d.line(pts, fill=CY)
    elif kind == "orbit":
        cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
        r = min(w, h) // 2 - 1
        d.ellipse([cx - r, cy - r // 2, cx + r, cy + r // 2], outline=CYD)
        d.ellipse([cx - 2, cy - 2, cx + 2, cy + 2], fill=CY)
        d.point([(cx + r - 1, cy - 1), (cx + r, cy)], fill=AMB)
    elif kind == "bars":
        for i, v in enumerate([0.4, 0.7, 0.5, 0.9, 0.6]):
            bx = x0 + 4 + i * (w // 5)
            d.rectangle([bx, y1 - 3 - int(h * v), bx + max(1, w // 5 - 2), y1 - 4], fill=GRN if i % 2 else CY)
    elif kind == "text":
        for i, y in enumerate(range(y0 + 4, y1 - 3, 3)):
            d.line([x0 + 4, y, x0 + 4 + (w - 2) * (0.5 + 0.5 * ((i * 5) % 3) / 2), y], fill=CY2 if i == 0 else CY)
    elif kind == "lab":
        pts = [(x0 + 3 + i, y1 - 4 - int((h - 2) * abs(((i // 2) % 8) - 4) / 4)) for i in range(0, w)]
        d.line(pts, fill=PUR)

def console():
    im, d = canvas(96, 72)
    # monitor stands
    for x in (20, 48, 76):
        d.rectangle([x - 2, 34, x + 1, 44], fill=M1); d.line([x - 2, 34, x - 2, 44], fill=M3)
    screen(d, 7, 16, 32, 36, "bars")
    screen(d, 33, 6, 62, 34, "orbit")
    screen(d, 63, 16, 88, 36, "graph")
    # desk top and body
    box(d, 3, 44, 92, 48, L2, L1, M2)
    box(d, 6, 50, 30, 70, M3, M2, M0)
    box(d, 66, 50, 90, 70, M3, M2, M0)
    for y in (55, 62):
        for x0 in (9, 69):
            d.line([x0, y, x0 + 18, y], fill=M0); d.point([(x0 + 9, y - 2)], fill=L1)
    d.rectangle([31, 50, 65, 52], fill=D2)
    # keyboard and status lamps
    box(d, 36, 41, 60, 43, L1, M3, M1)
    for i, c in enumerate([GRN, AMB, RED]):
        d.point([(8 + i * 3, 46)], fill=c)
    return im

def workshop():
    im, d = canvas(96, 72)
    # pegboard
    box(d, 4, 4, 91, 36, M2, M1, M0)
    for y in range(8, 34, 4):
        for x in range(8, 90, 4):
            d.point([(x, y)], fill=D2)
    # tools hanging on the board
    d.rectangle([10, 9, 12, 26], fill=L1); d.ellipse([7, 6, 15, 12], outline=L2)          # wrench
    d.rectangle([20, 12, 22, 30], fill=AMBD); d.rectangle([17, 9, 25, 13], fill=L1)       # hammer
    d.rectangle([31, 10, 32, 24], fill=L2); d.rectangle([30, 24, 33, 31], fill=AMB)       # screwdriver
    d.line([42, 10, 52, 26], fill=L1, width=2); d.line([52, 10, 42, 26], fill=L1, width=2)  # pliers
    d.ellipse([44, 24, 50, 30], outline=RED)
    for i in range(4):                                                                    # spanner set
        d.rectangle([60 + i * 5, 10, 61 + i * 5, 18 + i * 3], fill=L2)
    box(d, 80, 10, 88, 22, CY2, CY, CYD)                                                  # wiring diagram
    # bench top
    box(d, 2, 40, 93, 44, AMB, AMB2, AMBD)
    # legs and shelf
    for x in (6, 86):
        box(d, x, 46, x + 3, 70, M3, M2, M0)
    box(d, 10, 60, 84, 62, M3, M2, M0)
    box(d, 14, 52, 32, 59, AMB, AMB2, AMBD)                                              # toolbox under bench
    d.line([20, 52, 26, 52], fill=OUT)
    # rocket nozzle being built on the bench
    d.polygon([(56, 39), (62, 26), (70, 26), (76, 39)], fill=M3, outline=OUT)
    d.line([63, 27, 59, 38], fill=L2); d.rectangle([62, 22, 70, 26], fill=M2, outline=OUT)
    # vice
    box(d, 26, 33, 38, 38, M3, M2, M0); d.rectangle([30, 30, 34, 33], fill=L1, outline=OUT)
    return im

def laboratory():
    im, d = canvas(144, 78)
    # back panel with data screen
    box(d, 6, 6, 70, 40, M2, M1, M0)
    screen(d, 10, 10, 44, 34, "lab")
    screen(d, 48, 10, 66, 22, "text")
    for i, c in enumerate([GRN, CY, AMB, PUR]):
        d.rectangle([49 + i * 4, 27, 51 + i * 4, 29], fill=c)
    # tall sample tubes
    for x, liquid, dark in ((84, GRN, GRND), (102, CY, CYD), (120, PUR, PURD)):
        box(d, x, 4, x + 13, 9, L1, M3, M1)
        d.rectangle([x + 1, 10, x + 12, 44], fill=(60, 88, 110, 255), outline=OUT)
        d.rectangle([x + 2, 20, x + 11, 43], fill=liquid)
        d.line([x + 3, 21, x + 3, 42], fill=W)
        d.line([x + 10, 21, x + 10, 43], fill=dark)
        for by in (26, 33, 38):
            d.point([(x + 6, by), (x + 8, by + 2)], fill=W)
    # bench
    box(d, 2, 46, 141, 50, L2, L1, M2)
    for x0, x1 in ((6, 44), (52, 92), (100, 138)):
        box(d, x0, 52, x1, 76, M3, M2, M0)
        d.line([x0 + 3, 64, x1 - 3, 64], fill=M0)
        d.point([((x0 + x1) // 2, 58), ((x0 + x1) // 2, 70)], fill=L2)
    # microscope and flasks on the bench
    d.rectangle([12, 42, 22, 45], fill=M1, outline=OUT)
    d.line([18, 42, 18, 32], fill=M3, width=3); d.line([15, 32, 21, 35], fill=L1, width=2)
    for x, c in ((30, GRN), (40, CY), (58, AMB)):
        d.polygon([(x, 45), (x + 3, 38), (x + 3, 35), (x + 5, 35), (x + 5, 38), (x + 8, 45)], fill=(90, 120, 140, 255), outline=OUT)
        d.polygon([(x + 1, 44), (x + 3, 41), (x + 5, 41), (x + 7, 44)], fill=c)
    box(d, 70, 40, 78, 45, M3, M2, M0); d.point([(72, 42), (75, 42)], fill=GRN)
    return im

def archive():
    im, d = canvas(60, 84)
    box(d, 2, 2, 57, 82, M3, M2, M0)
    d.rectangle([5, 5, 54, 79], fill=D1)
    shelves = [22, 41, 60, 79]
    for y in shelves:
        box(d, 4, y, 55, y + 1, L1, M3, M1, outline=False)
    colours = [(CY, CYD), (AMB, AMBD), (GRN, GRND), (PUR, PURD), (RED, (120, 50, 40, 255)), (L1, M2)]
    # binders on shelf 1, boxes on shelf 2, binders on shelf 3, boxes + papers on shelf 4
    x = 7
    for i in range(9):
        c, dk = colours[i % len(colours)]
        h = 12 + (i * 3) % 4
        d.rectangle([x, 22 - h, x + 3, 21], fill=c); d.line([x + 3, 22 - h, x + 3, 21], fill=dk)
        d.line([x + 1, 22 - h + 3, x + 2, 22 - h + 3], fill=W)
        x += 5
    for x0 in (7, 25, 40):
        box(d, x0, 31, x0 + 12, 40, (206, 182, 140, 255), (176, 150, 108, 255), (120, 98, 70, 255))
        d.line([x0 + 4, 34, x0 + 8, 34], fill=(120, 98, 70, 255))
    x = 7
    for i in range(8):
        c, dk = colours[(i + 2) % len(colours)]
        d.rectangle([x, 47, x + 4, 59], fill=c); d.line([x + 4, 47, x + 4, 59], fill=dk)
        x += 6
    box(d, 7, 69, 22, 78, (206, 182, 140, 255), (176, 150, 108, 255), (120, 98, 70, 255))
    for y in range(72, 79, 2):
        d.line([30, y, 50, y], fill=L2)
    return im

def door():
    # Open bunker door: steel frame, hazard-striped header, half-retracted sliding panel.
    im, d = canvas(30, 78)
    box(d, 2, 2, 27, 77, M3, M1, M0)
    d.rectangle([6, 12, 23, 77], fill=(10, 16, 28, 255))
    for x in range(3, 27, 4):
        d.polygon([(x, 3), (x + 2, 3), (x + 4, 9), (x + 2, 9)], fill=AMB)
    d.rectangle([3, 3, 26, 9], outline=OUT)
    box(d, 17, 13, 23, 76, L1, M3, M1)             # panel slid to the right
    for y in (24, 44, 64):
        d.line([18, y, 22, y], fill=M1)
    d.rectangle([19, 34, 21, 38], fill=AMB, outline=OUT)
    d.point([(14, 6)], fill=GRN)                    # "open" light
    d.rectangle([13, 5, 15, 7], outline=OUT)
    d.line([6, 76, 16, 76], fill=M2)                # threshold
    return im

if __name__ == "__main__":
    art = "assets/art/"
    for name, im in (("mission_console", console()), ("workshop", workshop()), ("laboratory", laboratory()),
                     ("archive_shelf", archive()), ("hub_door", door())):
        im.save(art + name + ".png")
        print(name, im.size)
