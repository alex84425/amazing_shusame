"""Generates every texture used by 九霄流光訣 VFX.

All shapes are white with the silhouette in the alpha channel, so the
Lua side can tint them freely through SpriteRenderer.color.
Run:  python make_textures.py   (writes into ../Tex)
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Tex")
os.makedirs(OUT, exist_ok=True)


def save(name, alpha):
    a = np.clip(alpha, 0.0, 1.0)
    rgba = np.zeros(a.shape + (4,), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, name + ".png"))


def grid(w, h):
    """Normalised coords: x,y in [-1,1]."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    return (xs + 0.5) / w * 2 - 1, -((ys + 0.5) / h * 2 - 1)


def from_pil(img):
    return np.asarray(img, dtype=np.float32) / 255.0


def glowify(sharp, radius, strength):
    """sharp: PIL 'L' image. Returns alpha = core + soft halo."""
    halo = from_pil(sharp.filter(ImageFilter.GaussianBlur(radius)))
    return np.maximum(from_pil(sharp), halo * strength)


# --- soft glow ---------------------------------------------------------------
x, y = grid(128, 128)
r = np.sqrt(x * x + y * y)
save("glow", np.exp(-r * r * 4.5) * (r < 1))
save("core", np.exp(-r * r * 14) + 0.35 * np.exp(-r * r * 4) * (r < 1))

# --- ring (shockwave) --------------------------------------------------------
save("ring", np.exp(-((r - 0.82) / 0.07) ** 2) + 0.25 * np.exp(-((r - 0.78) / 0.18) ** 2))

# --- 4-point spark -----------------------------------------------------------
ax, ay = np.abs(x), np.abs(y)
star = np.exp(-ax * 9 - ay * ay * 900) + np.exp(-ay * 9 - ax * ax * 900)
d1, d2 = np.abs(x + y) / 1.414, np.abs(x - y) / 1.414
star += 0.35 * (np.exp(-d1 * 14 - d2 * d2 * 1500) + np.exp(-d2 * 14 - d1 * d1 * 1500))
save("spark", star + np.exp(-r * r * 30))

# --- light blade (points to +x) ----------------------------------------------
W, H, S = 512, 96, 4
img = Image.new("L", (W, H), 0)
d = ImageDraw.Draw(img)
cy = H / 2
tip, guard, hilt_end = W - 6, W * 0.30, W * 0.12
half = H * 0.13
d.polygon([(guard, cy - half), (tip - W * 0.10, cy - half * 0.75), (tip, cy),
           (tip - W * 0.10, cy + half * 0.75), (guard, cy + half)], fill=255)
d.rectangle([guard - 8, cy - H * 0.30, guard + 2, cy + H * 0.30], fill=230)   # guard
d.rectangle([hilt_end, cy - H * 0.05, guard - 8, cy + H * 0.05], fill=200)    # grip
d.ellipse([hilt_end - 12, cy - 10, hilt_end + 8, cy + 10], fill=220)        # pommel
blade = glowify(img, 9, 0.85)
# brighter edge-to-centre ridge line
ridge = Image.new("L", (W, H), 0)
ImageDraw.Draw(ridge).line([(guard, cy), (tip - 4, cy)], fill=255, width=3)
blade = np.maximum(blade, from_pil(ridge.filter(ImageFilter.GaussianBlur(1.5))))
save("blade", blade)

# --- streak / trail (bright at right end) ------------------------------------
x, y = grid(256, 48)
t = (x + 1) / 2
save("trail", (t ** 1.6) * np.exp(-(y / (0.15 + 0.55 * t)) ** 2))

# --- beam cross-section for LineRenderer (gaussian across V) ----------------
x, y = grid(16, 64)
save("beam", np.exp(-y * y * 9) * 0.55 + np.exp(-y * y * 60))

# --- crescent slash ----------------------------------------------------------
N = 256 * S
img = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(img)
d.ellipse([N * 0.05, N * 0.05, N * 0.95, N * 0.95], fill=255)
d.ellipse([N * 0.05 + N * 0.05, N * 0.05 - N * 0.01, N * 0.95 + N * 0.02, N * 0.95 - N * 0.05], fill=0)
img = img.resize((256, 256), Image.LANCZOS)
x, y = grid(256, 256)
taper = np.clip((x + 0.9) * 0.9, 0, 1) * np.clip(1.05 - np.abs(y) * 0.9, 0, 1)
save("slash", np.clip(glowify(img, 6, 0.9) * taper * 1.6, 0, 1))

# --- lotus petal (points to +y, base at bottom centre) -----------------------
W, H = 128, 256
x, y = grid(W, H)
v = (y + 1) / 2                         # 0 base .. 1 tip
vs = np.clip(v, 0, 1) ** 0.62          # push the widest point towards the tip
width = 0.95 * np.sin(vs * math.pi) ** 0.8 * (0.35 + 0.65 * np.clip(v * 2.2, 0, 1))
inside = np.abs(x) < width
edge = np.clip((width - np.abs(x)) / 0.12, 0, 1)
body = edge * (0.30 + 0.45 * v)        # translucent body, brighter towards tip
rim = np.exp(-((width - np.abs(x)) / 0.05) ** 2) * inside * 0.9
vein = np.exp(-(x / 0.04) ** 2) * (v > 0.08) * (v < 0.9) * 0.6
save("petal", np.maximum(body, np.maximum(rim, vein)) * (v > 0.0))

# --- snowflake ---------------------------------------------------------------
N = 128 * S
img = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(img)
c = N / 2
for k in range(6):
    a = k * math.pi / 3
    ex, ey = c + math.cos(a) * N * 0.45, c + math.sin(a) * N * 0.45
    d.line([(c, c), (ex, ey)], fill=255, width=4 * S)
    for f in (0.45, 0.7):
        bx, by = c + math.cos(a) * N * 0.45 * f, c + math.sin(a) * N * 0.45 * f
        for s in (-1, 1):
            b = a + s * math.pi / 4
            d.line([(bx, by), (bx + math.cos(b) * N * 0.12, by + math.sin(b) * N * 0.12)], fill=255, width=3 * S)
img = img.resize((128, 128), Image.LANCZOS)
save("snow", glowify(img, 4, 0.6))

# --- rune circle (outer seal) -----------------------------------------------
random.seed(7)
N = 512 * S
img = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(img)
c = N / 2


def circle(rad, width):
    d.ellipse([c - rad, c - rad, c + rad, c + rad], outline=255, width=width)


circle(N * 0.48, 5 * S)
circle(N * 0.455, 2 * S)
circle(N * 0.33, 3 * S)
for k in range(72):                      # tick marks
    a = k * math.tau / 72
    r0, r1 = N * 0.455, N * (0.43 if k % 3 else 0.415)
    d.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)],
           fill=255, width=2 * S)
for k in range(12):                      # invented glyphs between rings
    a = k * math.tau / 12 + math.tau / 24
    gx, gy = c + math.cos(a) * N * 0.375, c + math.sin(a) * N * 0.375
    sz = N * 0.035
    pts = [(gx + random.uniform(-sz, sz), gy + random.uniform(-sz, sz)) for _ in range(4)]
    d.line(pts, fill=255, width=3 * S)
    d.line([(gx - sz, gy + random.uniform(-sz, sz)), (gx + sz, gy + random.uniform(-sz, sz))], fill=255, width=3 * S)
    if k % 2 == 0:
        d.ellipse([gx - sz * 0.3, gy - sz * 0.3, gx + sz * 0.3, gy + sz * 0.3], outline=255, width=2 * S)
img = img.resize((512, 512), Image.LANCZOS)
save("rune_outer", glowify(img, 5, 0.55))

# --- rune circle (inner seal: hexagram + trigram bars) -----------------------
N = 384 * S
img = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(img)
c = N / 2
R = N * 0.46
d.ellipse([c - R, c - R, c + R, c + R], outline=255, width=3 * S)
for off in (0, math.pi):
    pts = [(c + math.cos(off + math.pi / 2 + k * math.tau / 3) * R,
            c + math.sin(off + math.pi / 2 + k * math.tau / 3) * R) for k in range(3)]
    d.polygon(pts, outline=255)
    d.line(pts + [pts[0]], fill=255, width=3 * S)
for k in range(6):
    a = k * math.tau / 6
    for j in range(3):
        rr = R * (0.25 + j * 0.07)
        px, py = c + math.cos(a) * rr, c + math.sin(a) * rr
        tx, ty = -math.sin(a) * N * 0.03, math.cos(a) * N * 0.03
        if (k + j) % 2:
            d.line([(px - tx, py - ty), (px + tx, py + ty)], fill=255, width=3 * S)
        else:
            d.line([(px - tx, py - ty), (px - tx * 0.25, py - ty * 0.25)], fill=255, width=3 * S)
            d.line([(px + tx * 0.25, py + ty * 0.25), (px + tx, py + ty)], fill=255, width=3 * S)
img = img.resize((384, 384), Image.LANCZOS)
save("rune_inner", glowify(img, 4, 0.55))

print("textures written to", os.path.abspath(OUT))
