"""Draws the 離火試煉木樁 sprite: a wooden post with a crossbar and a straw target.

Run:  python make_dummy.py   (writes Resources/Spr/Building/mcs_muzhuang.png)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources", "Spr", "Building")
os.makedirs(OUT, exist_ok=True)

S = 4                       # supersample
W, H = 128 * S, 192 * S
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

WOOD = (128, 84, 46, 255)
WOOD_DARK = (88, 56, 30, 255)
WOOD_LIGHT = (160, 112, 64, 255)
STRAW = (214, 182, 104, 255)
STRAW_DARK = (170, 138, 70, 255)
RED = (178, 48, 36, 255)
ROPE = (196, 170, 120, 255)

cx = W // 2
# 底座
d.ellipse([cx - 44 * S, H - 26 * S, cx + 44 * S, H - 6 * S], fill=(60, 44, 30, 140))
d.rectangle([cx - 30 * S, H - 30 * S, cx + 30 * S, H - 16 * S], fill=WOOD_DARK)
# 主樁
d.rectangle([cx - 11 * S, 22 * S, cx + 11 * S, H - 26 * S], fill=WOOD)
d.rectangle([cx - 11 * S, 22 * S, cx - 5 * S, H - 26 * S], fill=WOOD_LIGHT)
d.rectangle([cx + 6 * S, 22 * S, cx + 11 * S, H - 26 * S], fill=WOOD_DARK)
d.ellipse([cx - 11 * S, 16 * S, cx + 11 * S, 28 * S], fill=WOOD_LIGHT)
# 橫木（手臂）
for y in (58, 112):
    d.rectangle([cx - 46 * S, (y - 5) * S, cx + 46 * S, (y + 5) * S], fill=WOOD)
    d.rectangle([cx - 46 * S, (y - 5) * S, cx + 46 * S, (y - 2) * S], fill=WOOD_LIGHT)
    for x in (-46, 40):
        d.rectangle([cx + x * S, (y - 6) * S, cx + (x + 6) * S, (y + 6) * S], fill=WOOD_DARK)
# 草靶
ty = 86 * S
d.ellipse([cx - 30 * S, ty - 30 * S, cx + 30 * S, ty + 30 * S], fill=STRAW)
rng = np.random.default_rng(3)
for _ in range(90):
    a = rng.uniform(0, np.pi * 2)
    r0, r1 = rng.uniform(4, 22), rng.uniform(22, 30)
    d.line([(cx + np.cos(a) * r0 * S, ty + np.sin(a) * r0 * S), (cx + np.cos(a) * r1 * S, ty + np.sin(a) * r1 * S)],
           fill=STRAW_DARK, width=S)
for r, col in ((22, RED), (16, STRAW), (10, RED), (4, STRAW)):
    d.ellipse([cx - r * S, ty - r * S, cx + r * S, ty + r * S], fill=col)
# 綁繩
for y in (30, 140, 160):
    d.rectangle([cx - 12 * S, y * S, cx + 12 * S, (y + 4) * S], fill=ROPE)

img = img.resize((W // S, H // S), Image.LANCZOS)
img.save(os.path.join(OUT, "mcs_muzhuang.png"))
print("dummy sprite written")
