"""App icon, direction 2: the painted mascot itself, cropped to the face with its books and reel.

No redraw: the pixels come from source/mascot-2048.png, the Real-ESRGAN master of
source/mascot.jpg (see upscale_master.py), framed and set on a background. Two cuts of the bird:
`painted()` keeps its own paper and soft disc; `silhouette()` lifts the bird off the paper so it
can sit on a brand colour. Coordinates below are in source/mascot.jpg pixels (784 wide) and are
scaled to the master, so they match process.py's crop of the same picture.
Run: .venv/bin/python icon_mascot.py  ->  out/mascot/<variant>.png and sheet.png
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

from icon_reeds import S, sheet, vgradient

OUT = "out/mascot"
MASTER = "source/mascot-2048.png"
SOURCE_W = 784  # mascot.jpg width; every coordinate here is in that space
PAPER = (254, 248, 236)
# The same crop process.py takes for the Mascot image set: the bird without the stacked logo.
CROP = (40, 316, 760, 1110)


def painted():
    """The bird on its own paper, soft disc and all, at master resolution. Returns the image and
    the master pixels per source pixel."""
    master = Image.open(MASTER).convert("RGB")
    k = master.width / SOURCE_W
    return master.crop(tuple(round(v * k) for v in CROP)), k


def silhouette():
    """The bird lifted off the paper. Anything clearly not paper is ink; the cream face and belly
    are recovered by filling the holes inside the teal outline; the soft disc, which is closer to
    paper than the face is, falls away."""
    img, k = painted()
    px = max(1, round(k))  # morphology radii, in source pixels
    a = np.asarray(img).astype(np.float32)
    ink = np.abs(a - np.array(PAPER, np.float32)).sum(2) > 60
    ink = ndimage.binary_closing(ink, iterations=3 * px)
    ink = ndimage.binary_fill_holes(ink)
    labels, n = ndimage.label(ink)
    if n > 1:
        sizes = ndimage.sum(ink, labels, range(1, n + 1))
        ink = labels == 1 + int(np.argmax(sizes))
    ink = ndimage.binary_opening(ink, iterations=2 * px)
    ink = ndimage.binary_erosion(ink, iterations=px)  # no paper halo
    alpha = ndimage.gaussian_filter(ink.astype(np.float32), 0.6 * k) * 255
    out = img.convert("RGBA")
    out.putalpha(Image.fromarray(alpha.astype(np.uint8)))
    return out, k


def frame(img, k, x, y, side, fill=(0, 0, 0, 0)):
    """Square crop at (x, y) with the given side, all in source pixels; overhang shows `fill`."""
    px = round(side * k)
    canvas = Image.new("RGBA", (px, px), fill)
    img = img.convert("RGBA")
    canvas.paste(img, (-round(x * k), -round(y * k)), img)
    return canvas.resize((S, S), Image.LANCZOS)


def background(stops):
    return Image.fromarray(vgradient(stops, S, S).astype(np.uint8)).convert("RGBA")


def soft_disc(img, cx, cy, r, color):
    disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(disc).ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    img.alpha_composite(disc.filter(ImageFilter.GaussianBlur(60)))


def drop_shadow(bird, dy=14, blur=22, strength=0.35):
    a = np.asarray(bird)[..., 3].astype(np.float32) * strength
    sh = Image.new("RGBA", bird.size, (8, 30, 34, 0))
    sh.putalpha(Image.fromarray(a.astype(np.uint8)))
    out = Image.new("RGBA", bird.size, (0, 0, 0, 0))
    out.paste(sh, (0, dy))
    return out.filter(ImageFilter.GaussianBlur(blur))


def on_paper(x, y, side):
    """The mascot's own paper, with its soft disc, full bleed."""
    img, k = painted()
    return frame(img, k, x, y, side, PAPER + (255,)).convert("RGB")


def on_colour(stops, disc_color, x, y, side):
    img = background(stops)
    soft_disc(img, 512, 580, 430, disc_color)
    cut, k = silhouette()
    bird = frame(cut, k, x, y, side)
    img.alpha_composite(drop_shadow(bird))
    img.alpha_composite(bird)
    return img.convert("RGB")


def on_dawn(x, y, side):
    """The reed icon's dawn gradient behind a pale sun."""
    return on_colour([(0, "#1d5d66"), (0.55, "#5f9a92"), (1, "#f0d7a2")], (251, 231, 176, 170), x, y, side)


def on_teal(x, y, side):
    """Deep teal with a faint cream glow, like the mascot's disc."""
    return on_colour([(0, "#12434a"), (1, "#1f6a70")], (246, 234, 210, 70), x, y, side)


# Frames: (x, y, side) in source pixels, relative to CROP. "b-portrait-teal" was chosen on 2026-10-21.
PORTRAIT = (85, -10, 560)  # crest to the top of the books, reel in the right hand
FACE = (130, -5, 435)  # the face fills the tile; books and reel peek in below

VARIANTS = {
    "a-portrait-paper": lambda: on_paper(*PORTRAIT),
    "b-portrait-teal": lambda: on_teal(*PORTRAIT),
    "c-portrait-dawn": lambda: on_dawn(*PORTRAIT),
    "d-face-teal": lambda: on_teal(*FACE),
}


def compose(name):
    return VARIANTS[name]()


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icons = {}
    for name, draw in VARIANTS.items():
        icons[name] = draw()
        icons[name].save(f"{OUT}/{name}.png")
    sheet(icons).save(f"{OUT}/sheet.png")
    print("done")
