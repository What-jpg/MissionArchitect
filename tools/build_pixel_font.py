"""Build the OFL-licensed Mission Pixel font from the retained Pixelify Sans source.
Requires fonttools. The supplied font omits capital Ukrainian І and Cyrillic О/П;
use the same font's visually identical Latin I/O and Greek Pi outlines.
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
root = Path(__file__).resolve().parents[1]
font = TTFont(root / 'assets/fonts/PixelifySans.ttf')
font = instantiateVariableFont(font, {'wght': 500}, inplace=False)
aliases = {0x0406: 0x0049, 0x041E: 0x004F, 0x041F: 0x03A0}
best = font.getBestCmap()
for table in font['cmap'].tables:
    if table.isUnicode():
        for target, source in aliases.items():
            table.cmap[target] = best[source]
names = {1:'Mission Pixel',2:'Regular',3:'Mission Pixel 1.0',4:'Mission Pixel Regular',6:'MissionPixel-Regular',16:'Mission Pixel',17:'Regular'}
for record in font['name'].names:
    if record.nameID in names:
        value = names[record.nameID]
        record.string = value.encode(record.getEncoding(), errors='replace')
font.save(root / 'assets/fonts/MissionPixel.ttf')
chars = 'АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯабвгґдеєжзиіїйклмнопрстуфхцчшщьюя0123456789'
missing = [c for c in chars if ord(c) not in font.getBestCmap()]
assert not missing, missing
print('Mission Pixel: all Ukrainian letters and digits verified')
