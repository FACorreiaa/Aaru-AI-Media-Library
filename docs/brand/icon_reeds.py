"""App icon, direction 1: cattail reeds of uneven height, like spines on a shelf, at a dawn horizon.

Flat vector geometry, drawn at 4x and downsampled, so every size is crisp.
Run: .venv/bin/python icon_reeds.py  ->  out/reeds/<variant>.png and sheet.png
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 1024
K = 4  # supersampling
W = S * K
OUT = "out/reeds"
os.makedirs(OUT, exist_ok=True)

HORIZON = 712
# Cattails: (x at base, height above horizon, lean in degrees). Heights vary like spines on a shelf.
REEDS = [
    (318, 410, 0),
    (414, 520, 0),
    (510, 600, 0),
    (606, 470, 0),
    (706, 540, -11),
]
STALK = 15
HEAD_W, HEAD_H = 46, 168
SPIKE = 58


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], np.float32)


def vgradient(stops, h=W, w=W):
    """stops: [(t, hex)] top to bottom."""
    ts = np.array([t for t, _ in stops])
    cs = np.array([hexrgb(c) for _, c in stops])
    y = np.linspace(0, 1, h)
    col = np.stack([np.interp(y, ts, cs[:, i]) for i in range(3)], 1)
    return np.repeat(col[:, None, :], w, 1)


def cattail(fill, x, height, lean):
    """One reed: thin stalk, seed head, fine spike. Drawn upright, then leaned about its base."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    top = HORIZON - height
    head_top = top + SPIKE
    d.rectangle([(x - STALK / 2) * K, head_top * K, (x + STALK / 2) * K, (HORIZON + 2) * K], fill=fill)
    d.rounded_rectangle(
        [(x - HEAD_W / 2) * K, head_top * K, (x + HEAD_W / 2) * K, (head_top + HEAD_H) * K],
        radius=HEAD_W / 2 * K,
        fill=fill,
    )
    d.polygon(
        [((x - 5) * K, (head_top + 6) * K), ((x + 5) * K, (head_top + 6) * K), (x * K, top * K)],
        fill=fill,
    )
    if lean:
        layer = layer.rotate(lean, resample=Image.BICUBIC, center=(x * K, HORIZON * K))
    return layer


def spines_layer(fill, band=None):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    for x, h, lean in REEDS:
        layer.alpha_composite(cattail(fill, x, h, lean))
    return layer


def disc(cx, cy, r, inner, outer):
    yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
    dist = np.sqrt((xx - cx * K) ** 2 + (yy - cy * K) ** 2) / (r * K)
    t = np.clip(dist, 0, 1)[..., None]
    rgb = hexrgb(inner) * (1 - t) + hexrgb(outer) * t
    alpha = np.clip((1 - dist) * r * K / 2, 0, 1) * 255
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def reflection(layer, strength):
    """Mirror everything above the horizon into the water, faded and rippled."""
    hz = HORIZON * K
    top = layer.crop((0, 0, W, hz)).transpose(Image.FLIP_TOP_BOTTOM)
    refl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    refl.paste(top, (0, hz))
    a = np.asarray(refl).astype(np.float32)
    y = np.arange(W)[:, None]
    fade = np.clip(1 - (y - hz) / (220 * K), 0, 1) * strength
    ripple = (np.sin((y - hz) / (4.0 * K)) > 0.1).astype(np.float32)
    a[..., 3] *= fade * ripple
    return Image.fromarray(a.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(1.5 * K))


def compose(sky, water, sun, spine_fill, band, refl_strength, shelf=None):
    base = np.zeros((W, W, 3), np.float32)
    hz = HORIZON * K
    base[:hz] = vgradient(sky, hz, W)
    base[hz:] = vgradient(water, W - hz, W)
    img = Image.fromarray(base.astype(np.uint8)).convert("RGBA")
    above = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    if sun:
        above.alpha_composite(disc(*sun))
        # The sun sets behind the horizon: clip it there.
        cut = Image.new("L", (W, W), 0)
        ImageDraw.Draw(cut).rectangle([0, 0, W, hz], fill=255)
        above.putalpha(Image.fromarray(np.minimum(np.asarray(above)[..., 3], np.asarray(cut))))
    above.alpha_composite(spines_layer(spine_fill, band))
    img.alpha_composite(reflection(above, refl_strength))
    img.alpha_composite(above)
    if shelf:
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([232 * K, (HORIZON - 2) * K, 792 * K, (HORIZON + 20) * K], radius=10 * K, fill=shelf)
    else:
        d = ImageDraw.Draw(img)
        d.rectangle([0, (HORIZON - 1) * K, W, (HORIZON + 2) * K], fill=(236, 210, 150, 150))
    return img.convert("RGB").resize((S, S), Image.LANCZOS)


VARIANTS = {
    # A: dawn sky, gold sun on the horizon, deep teal spines in silhouette.
    "a-dawn-silhouette": dict(
        sky=[(0, "#1d5d66"), (0.55, "#5f9a92"), (1, "#f0d7a2")],
        water=[(0, "#174a51"), (1, "#0d3138")],
        sun=(512, HORIZON, 300, "#fbe7b0", "#e2b45a"),
        spine_fill=(14, 52, 58, 255),
        band=(226, 180, 90, 255),
        refl_strength=0.24,
    ),
    # B: night teal, pale gold sun, cream spines.
    "b-cream-on-night": dict(
        sky=[(0, "#0c3138"), (1, "#1f6970")],
        water=[(0, "#0b2a30"), (1, "#081f24")],
        sun=(512, HORIZON, 300, "#f6dc9a", "#c99645"),
        spine_fill=(251, 243, 226, 255),
        band=(31, 105, 112, 255),
        refl_strength=0.22,
    ),
    # C: A's palette, spines standing on a gold shelf instead of water.
    "c-on-a-shelf": dict(
        sky=[(0, "#1d5d66"), (0.55, "#5f9a92"), (1, "#f0d7a2")],
        water=[(0, "#174a51"), (1, "#0d3138")],
        sun=(512, HORIZON, 300, "#fbe7b0", "#e2b45a"),
        spine_fill=(14, 52, 58, 255),
        band=(226, 180, 90, 255),
        refl_strength=0.0,
        shelf=(226, 180, 90, 255),
    ),
}


def squircle_mask(size):
    m = Image.new("L", (size * 4, size * 4), 0)
    n = 5.0
    t = np.linspace(0, 2 * np.pi, 1500)
    r = size * 2
    px = r + r * np.sign(np.cos(t)) * np.abs(np.cos(t)) ** (2 / n)
    py = r + r * np.sign(np.sin(t)) * np.abs(np.sin(t)) ** (2 / n)
    ImageDraw.Draw(m).polygon(list(zip(px, py)), fill=255)
    return m.resize((size, size), Image.LANCZOS)


def sheet(icons):
    rows = len(icons)
    sheet = Image.new("RGB", (1500, 430 * rows + 20), (246, 242, 234))
    for i, (name, icon) in enumerate(icons.items()):
        y = 20 + i * 430
        big = icon.resize((400, 400), Image.LANCZOS)
        sheet.paste(big, (20, y), squircle_mask(400))
        x = 450
        for size in (180, 120, 60, 40, 29):
            small = icon.resize((size, size), Image.LANCZOS)
            sheet.paste(small, (x, y + 200 - size // 2), squircle_mask(size))
            x += size + 30
        # Dark home-screen tile for contrast.
        dark = Image.new("RGB", (330, 400), (28, 28, 30))
        dark.paste(icon.resize((120, 120), Image.LANCZOS), (105, 140), squircle_mask(120))
        sheet.paste(dark, (1150, y))
        ImageDraw.Draw(sheet).text((450, y + 360), name, fill=(40, 60, 60))
    return sheet


if __name__ == "__main__":
    icons = {}
    for name, spec in VARIANTS.items():
        icons[name] = compose(**spec)
        icons[name].save(f"{OUT}/{name}.png")
    sheet(icons).save(f"{OUT}/sheet.png")
    print("done")
