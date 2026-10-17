"""Generates 4x4 flipbook sheets for the ParticleSystem effects.

fire.png   : a flame tongue licking upward (colour baked in, white-hot core)
smoke.png  : a puff that billows and thins out (white, tinted in game)
Both are driven by tileable fractal noise scrolled over time, so frames
loop smoothly when played by the textureSheetAnimation module.
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Tex")
F = 128          # frame size
N = 4            # 4x4 frames
rng = np.random.default_rng(11)


def value_noise(shape, cells):
    """Tileable smooth value noise in [0,1]."""
    h, w = shape
    g = rng.random((cells, cells))
    ys = np.linspace(0, cells, h, endpoint=False)
    xs = np.linspace(0, cells, w, endpoint=False)
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    y1, x1 = (y0 + 1) % cells, (x0 + 1) % cells
    a = g[np.ix_(y0, x0)]
    b = g[np.ix_(y0, x1)]
    c = g[np.ix_(y1, x0)]
    d = g[np.ix_(y1, x1)]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(size, octaves=5):
    total = np.zeros((size, size))
    amp, cells, norm = 1.0, 16, 0.0
    for _ in range(octaves):
        total += value_noise((size, size), cells) * amp
        norm += amp
        amp *= 0.5
        cells *= 2
    return total / norm


# one big tileable noise field; each frame samples it at a scrolled offset
FIELD = 512
noise_a = fbm(FIELD)
noise_b = fbm(FIELD)


def sample(field, ox, oy):
    ys = (np.arange(F)[:, None] + int(oy)) % FIELD
    xs = (np.arange(F)[None, :] + int(ox)) % FIELD
    return field[ys, xs]


ys, xs = np.mgrid[0:F, 0:F].astype(np.float32)
u = (xs + 0.5) / F * 2 - 1          # -1..1 left/right
v = 1 - (ys + 0.5) / F              # 0 bottom .. 1 top


def sheet(frame_fn):
    out = np.zeros((F * N, F * N, 4), dtype=np.float32)
    for i in range(N * N):
        t = i / (N * N)
        fr = frame_fn(t, i)
        r, c = divmod(i, N)
        # Unity reads sheets from the top-left, row by row
        out[r * F:(r + 1) * F, c * F:(c + 1) * F] = fr
    return out


def fire_frame(t, i):
    # flame envelope: wide at the base, tapering tongue at the top
    # sideways wobble so the tongue sways instead of standing still
    sway = 0.12 * np.sin(v * 5 + t * np.pi * 2) * v
    uu = u - sway
    width = 0.62 * (1 - v) ** 0.55 + 0.04
    env = np.clip(1 - (np.abs(uu) / width) ** 2, 0, 1) * np.clip(v * 7, 0, 1) * np.clip((1 - v) * 1.2, 0, 1)
    n = sample(noise_a, 37 * i, -48 * i) * 0.6 + sample(noise_b, -23 * i, -90 * i) * 0.4
    n = (n - 0.5) * 2.4 + 0.5                    # boost contrast -> distinct tongues
    # noise eats the flame from the outside in, more aggressively towards the tip
    heat = env * 1.9 - (1 - n) * (0.7 + 1.3 * v)
    heat = np.clip(heat, 0, 1)
    # fade the whole tongue in and out over the loop so frames blend nicely
    heat *= 0.85 + 0.15 * np.sin(t * np.pi * 2)
    r = np.clip(heat * 2.2, 0, 1)
    g = np.clip(heat * 1.6 - 0.25, 0, 1)
    b = np.clip(heat * 2.0 - 1.2, 0, 1)
    a = np.clip(heat * 1.8, 0, 1)
    return np.dstack([r, g, b, a])


def smoke_frame(t, i):
    rad = 0.62 + 0.3 * t                        # puff grows as it ages
    w = v * 2 - 1
    d = np.sqrt(u * u + w * w)
    body = np.clip(1 - (d / rad) ** 2, 0, 1)
    n = sample(noise_a, 19 * i, 31 * i) * 0.6 + sample(noise_b, -29 * i, 13 * i) * 0.4
    n = (n - 0.5) * 2.2 + 0.5
    dens = np.clip(body * 1.9 - (1 - n) * 1.0, 0, 1) ** 1.1
    dens *= 1 - 0.55 * t                         # thins out
    shade = 0.75 + 0.25 * n                      # cheap self-shadowing
    return np.dstack([shade, shade, shade, dens])


def save(name, arr):
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name + ".png"))


save("fire", sheet(fire_frame))
save("smoke", sheet(smoke_frame))
print("flipbooks written")
