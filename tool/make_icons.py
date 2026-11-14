"""Generates launcher icons, splash logo and the in-app logo asset from
assets/brand/app_icon_source.png (the wallet icon). Run: python3 -I tool/make_icons.py"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.join(HERE, '..')
RES = os.path.join(PROJECT, 'android', 'app', 'src', 'main', 'res')
src = Image.open(os.path.join(PROJECT, 'assets', 'brand', 'app_icon_source.png')).convert('RGBA')

# Square crop around the white tile (drops the drop-shadow margin), flattened on white.
CX, CY, HALF = 627, 604, 521
tile = src.crop((CX - HALF, CY - HALF, CX + HALF, CY + HALF))
flat = Image.new('RGBA', tile.size, (255, 255, 255, 255))
flat.alpha_composite(tile)
N = tile.size[0]

def masked(size, round_=False):
    img = flat.resize((size * 4, size * 4), Image.LANCZOS)
    m = Image.new('L', img.size, 0)
    d = ImageDraw.Draw(m)
    if round_: d.ellipse([0, 0, img.size[0] - 1, img.size[1] - 1], fill=255)
    else: d.rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=img.size[0] * 0.22, fill=255)
    out = Image.new('RGBA', img.size, (0, 0, 0, 0)); out.paste(img, (0, 0), m)
    return out.resize((size, size), Image.LANCZOS)

def foreground(size):
    """Adaptive-icon foreground: artwork at 70/108 of the canvas, centred."""
    art = int(size * 70 / 108)
    canvas = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    canvas.alpha_composite(flat.resize((art, art), Image.LANCZOS), ((size - art) // 2, (size - art) // 2))
    return canvas

for name, f in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
    d = os.path.join(RES, f'mipmap-{name}'); os.makedirs(d, exist_ok=True)
    masked(int(48 * f)).save(os.path.join(d, 'ic_launcher.png'))
    masked(int(48 * f), round_=True).save(os.path.join(d, 'ic_launcher_round.png'))
    foreground(int(108 * f)).save(os.path.join(d, 'ic_launcher_foreground.png'))
    Image.new('RGB', (int(108 * f),) * 2, (255, 255, 255)).save(os.path.join(d, 'ic_launcher_background.png'))
    dd = os.path.join(RES, f'drawable-{name}'); os.makedirs(dd, exist_ok=True)
    masked(int(112 * f)).save(os.path.join(dd, 'splash_logo.png'))

any_ = os.path.join(RES, 'mipmap-anydpi-v26'); os.makedirs(any_, exist_ok=True)
xml = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'''
for f in ('ic_launcher.xml', 'ic_launcher_round.xml'):
    open(os.path.join(any_, f), 'w').write(xml)

# In-app logo asset (square, rounded corners applied in Flutter).
flat.resize((512, 512), Image.LANCZOS).convert('RGB').save(os.path.join(PROJECT, 'assets', 'brand', 'logo.png'), optimize=True)
print('done')
