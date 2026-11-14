"""Draws the status-bar notification icon: a simplified, single-colour version of
the wallet logo (receipt with rising bars, wallet, coin, clasp). Android tints
it, so only the alpha channel matters. Run: python3 -I tool/make_notification_icon.py"""
import os
import sys
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, '..', 'android', 'app', 'src', 'main', 'res')
SS = 16  # supersampling


def mask(px: int) -> Image.Image:
    n = px * SS
    s = n / 24.0  # 24-unit design grid
    im = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(im)
    P = lambda pts: [(x * s, y * s) for x, y in pts]
    R = lambda x0, y0, x1, y1: [x0 * s, y0 * s, x1 * s, y1 * s]

    # Receipt with a zig-zag top, peeking out of the wallet.
    d.polygon(P([(6.6, 8.8), (6.6, 3.0), (8.15, 2.1), (9.7, 3.0), (11.25, 2.1), (12.8, 3.0), (14.35, 2.1), (15.9, 3.0), (15.9, 8.8)]), fill=255)
    # Rising bars cut into the receipt.
    for x0, top in ((8.4, 6.4), (10.6, 5.3), (12.8, 4.2)):
        d.rounded_rectangle(R(x0, top, x0 + 1.25, 8.8), radius=0.35 * s, fill=0)
    # Wallet body (a gap below the receipt keeps them separate).
    d.rounded_rectangle(R(1.8, 9.6, 21.0, 21.4), radius=2.6 * s, fill=255)
    # Clasp: notch in the body, then a tab with a stud hole.
    d.rectangle(R(15.4, 12.6, 21.2, 17.6), fill=0)
    d.rounded_rectangle(R(16.3, 13.4, 22.4, 16.8), radius=1.2 * s, fill=255)
    d.ellipse(R(18.5, 14.3, 20.1, 15.9), fill=0)
    # Coin on the front: ring with a solid centre.
    d.ellipse(R(4.3, 11.4, 12.3, 19.4), fill=0)
    d.ellipse(R(5.6, 12.7, 11.0, 18.1), fill=255)
    return im.resize((px, px), Image.LANCZOS)


def white_icon(px: int) -> Image.Image:
    out = Image.new('RGBA', (px, px), (255, 255, 255, 0))
    out.putalpha(mask(px))
    return out


if __name__ == '__main__':
    for name, f in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
        d = os.path.join(RES, f'drawable-{name}')
        os.makedirs(d, exist_ok=True)
        white_icon(int(24 * f)).save(os.path.join(d, 'ic_notification.png'))
    if len(sys.argv) > 1:  # optional preview folder
        big = mask(240)
        prev = Image.new('RGB', (240, 240), (20, 43, 74))
        prev.paste((255, 255, 255), (0, 0), big)
        small = Image.new('RGB', (24, 24), (20, 43, 74))
        small.paste((255, 255, 255), (0, 0), mask(24))
        prev.paste(small.resize((96, 96), Image.NEAREST), (144, 144))
        prev.save(os.path.join(sys.argv[1], 'notif_icon_preview.png'))
    print('done')
