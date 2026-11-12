# Draws HireFly's firefly as the Windows app icon (the same shape as
# FireflyPainter in lib/ui/extras.dart). Run: python tool/make_icon.py
import math
import pathlib

from PIL import Image, ImageDraw, ImageFilter

S = 1024  # drawn large, then reduced
K = S / 48


def box(x, y, w, h):
    return [x * K, y * K, (x + w) * K, (y + h) * K]


def layer():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))


art = layer()
# The light behind the tail.
halo = layer()
ImageDraw.Draw(halo).ellipse(box(14, 23, 20, 18), fill=(245, 196, 81, 170))
art.alpha_composite(halo.filter(ImageFilter.GaussianBlur(S * 0.05)))

# Wings, swept back.
for side in (-1, 1):
    w = layer()
    ImageDraw.Draw(w).ellipse(box(19.5, 18, 9, 21), fill=(239, 233, 222, 105), outline=(239, 233, 222, 170), width=int(K))
    art.alpha_composite(w.rotate(-side * math.degrees(0.78), center=(24 * K, 19 * K), resample=Image.BICUBIC))

d = ImageDraw.Draw(art)
# Antennae.
for pts in ([(22.5, 9), (19.5, 6), (16.5, 5.5)], [(25.5, 9), (28.5, 6), (31.5, 5.5)]):
    d.line([(x * K, y * K) for x, y in pts], fill=(186, 179, 166, 255), width=int(1.3 * K), joint='curve')
# Head and thorax.
d.ellipse(box(20.4, 7.4, 7.2, 7.2), fill=(59, 54, 49, 255))
d.rounded_rectangle(box(19.5, 13.5, 9, 9.5), radius=4 * K, fill=(90, 75, 60, 255))
# The lit abdomen: a vertical gradient, clipped to its shape.
grad = Image.new('RGBA', (S, S))
gd = ImageDraw.Draw(grad)
top, mid, bot = (217, 154, 43), (245, 196, 81), (255, 233, 166)
y0, y1 = int(22 * K), int(39 * K)
for y in range(y0, y1):
    t = (y - y0) / (y1 - y0)
    a, b, u = (top, mid, t * 2) if t < 0.5 else (mid, bot, (t - 0.5) * 2)
    gd.line([(0, y), (S, y)], fill=tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,))
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(box(19.2, 22, 9.6, 17), radius=4.8 * K, fill=255)
art.paste(grad, (0, 0), mask)
d = ImageDraw.Draw(art)
for y in (27.0, 31.5):
    d.line([(19.8 * K, y * K), (28.2 * K, y * K)], fill=(59, 42, 16, 55), width=max(1, int(K * 0.6)))

art = art.rotate(-math.degrees(0.42), center=(S / 2, S / 2), resample=Image.BICUBIC)

# On a dark rounded tile, so it reads on a light taskbar too.
tile = layer()
ImageDraw.Draw(tile).rounded_rectangle([0, 0, S - 1, S - 1], radius=S * 0.2, fill=(20, 19, 17, 255))
tile.alpha_composite(art.resize((int(S * 0.92), int(S * 0.92)), Image.LANCZOS), (int(S * 0.04), int(S * 0.04)))

out = pathlib.Path(__file__).resolve().parent.parent / 'windows' / 'runner' / 'resources' / 'app_icon.ico'
tile.save(out, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
tile.resize((256, 256), Image.LANCZOS).save(out.with_name('app_icon_preview.png'))
print('wrote', out)
