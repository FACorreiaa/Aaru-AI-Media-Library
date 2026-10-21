"""App icon, direction 2: the painted mascot itself, cropped to the face with its books and reel.

No redraw: the pixels come from source/mascot.jpg, doubled with the same unsharp mask process.py
uses for the Mascot image set, then framed and set on a background. Two cuts of the bird:
`painted()` keeps its own paper and soft disc; `silhouette()` lifts the bird off the paper so it
can sit on a brand colour. Run: .venv/bin/python icon_mascot.py  ->  out/mascot/<variant>.png and sheet.png
"""

import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

from icon_reeds import S, sheet, vgradient

OUT = "out/mascot"
PAPER = (254, 248, 236)
# process.py crops source/mascot.jpg to (40, 316)-(760, 1110) before doubling it; frames below
# are in those 1440x1588 coordinates so they match the Mascot image set.
CROP = (40, 316, 760, 1110)


def painted():
    """The bird on its own paper, soft disc and all, doubled and sharpened."""
    src = Image.open("source/mascot.jpg").convert("RGB").crop(CROP)
    return src.resize((src.width * 2, src.height * 2), Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 50, 2))


def silhouette():
    """The bird lifted off the paper. Anything clearly not paper is ink; the cream face and belly
    are recovered by filling the holes inside the teal outline; the soft disc, which is closer to
    paper than the face is, falls away."""
    img = painted()
    a = np.asarray(img).astype(np.float32)
    ink = np.abs(a - np.array(PAPER, np.float32)).sum(2) > 60
    ink = ndimage.binary_closing(ink, iterations=6)
    ink = ndimage.binary_fill_holes(ink)
    labels, n = ndimage.label(ink)
    if n > 1:
        sizes = ndimage.sum(ink, labels, range(1, n + 1))
        ink = labels == 1 + int(np.argmax(sizes))
    ink = ndimage.binary_opening(ink, iterations=3)
    ink = ndimage.binary_erosion(ink, iterations=2)  # no paper halo
    alpha = ndimage.gaussian_filter(ink.astype(np.float32), 1.2) * 255
    out = img.convert("RGBA")
    out.putalpha(Image.fromarray(alpha.astype(np.uint8)))
    return out


def frame(img, x, y, side, fill=(0, 0, 0, 0)):
    """Square crop at (x, y) with the given side; overhang shows `fill`."""
    canvas = Image.new("RGBA", (side, side), fill)
    img = img.convert("RGBA")
    canvas.paste(img, (-x, -y), img)
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
    return frame(painted(), x, y, side, PAPER + (255,)).convert("RGB")


def on_colour(stops, disc_color, x, y, side):
    img = background(stops)
    soft_disc(img, 512, 580, 430, disc_color)
    bird = frame(silhouette(), x, y, side)
    img.alpha_composite(drop_shadow(bird))
    img.alpha_composite(bird)
    return img.convert("RGB")


def on_dawn(x, y, side):
    """The reed icon's dawn gradient behind a pale sun."""
    return on_colour([(0, "#1d5d66"), (0.55, "#5f9a92"), (1, "#f0d7a2")], (251, 231, 176, 170), x, y, side)


def on_teal(x, y, side):
    """Deep teal with a faint cream glow, like the mascot's disc."""
    return on_colour([(0, "#12434a"), (1, "#1f6a70")], (246, 234, 210, 70), x, y, side)


# Frames: (x, y, side) in mascot@2x coordinates. "b-portrait-teal" was chosen on 2026-10-21.
PORTRAIT = (170, -20, 1120)  # crest to the top of the books, reel in the right hand
FACE = (260, -10, 870)  # the face fills the tile; books and reel peek in below

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
