"""BRD-010: the iOS 18 dark and tinted appearances of the app icon.

The default icon (owl_poster.py) is the A-mark on a navy sky with the hologram's blue glow.
iOS 18 lets the Home Screen ask for two more:

- dark: the mark on flat night navy, no glow, so it sits calm beside the system's dark icons;
- tinted: the mark alone, grey on transparent, so iOS can lay the user's tint over it.

Both come from `source/a-mark.svg` (already traced) at the default icon's placement, for the
`AppIcon` and `AppIconBeta` (banded) sets, written straight into the asset catalog.

    cd docs/brand && uv run --python 3.12 --with pillow --with numpy --with scipy python owl_icon_appearances.py
"""

import json
import os
import re
import subprocess

from PIL import Image, ImageDraw, ImageFont

NAVY = "#0e141e"  # tokens.json paper (dark)
MARK = "source/a-mark.svg"
OUT = "out/owl"
CATALOG = "../../aaru-ios/Aaru/Assets.xcassets"
SETS = {"AppIcon.appiconset": False, "AppIconBeta.appiconset": True}
SHARE = 0.64  # the default icon's mark width, as a share of the tile


def mark():
    text = open(MARK).read()
    w, h = (float(v) for v in re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', text).groups())
    inner = text[text.index(">", text.index("<svg")) + 1 : text.rindex("</svg>")]
    return inner, (w, h)


def placed(inner, size, ground=""):
    """The mark centred on a 1024 tile, the same maths as owl_poster.icon(..., glow=False)."""
    mw, mh = size
    w = 1024 * SHARE
    s = w / mw
    x, y = (1024 - w) / 2, (1024 - mh * s) / 2 - 1024 * 0.01
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">\n'
        f'{ground}\n<g transform="translate({x:.2f},{y:.2f}) scale({s:.6f})">{inner}</g>\n</svg>\n'
    )


def render(svg_text, name):
    """rsvg-convert like owl_poster.py; macOS Quick Look when librsvg is not usable."""
    path, png = f"{OUT}/{name}.svg", f"{OUT}/{name}.png"
    open(path, "w").write(svg_text)
    try:
        subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", path, "-o", png], check=True)
    except (OSError, subprocess.CalledProcessError):
        subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", OUT, path], check=True, capture_output=True)
        os.replace(f"{path}.png", png)
    return Image.open(png).convert("RGBA")


def band(img):
    """process.beta_band, keeping the alpha channel (the tinted icon is transparent)."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle([0, 812, 1024, 1024], fill=(14, 20, 30, 236))
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 150)
    font.set_variation_by_axes([700])
    tw = d.textlength("BETA", font=font)
    d.text(((1024 - tw) / 2, 818), "BETA", font=font, fill=(242, 166, 90, 255))
    return Image.alpha_composite(img, layer)


def tinted(img):
    """Grey on transparent: iOS maps luminance to the tint and keeps the alpha."""
    return Image.merge("LA", (img.convert("L"), img.getchannel("A")))


def appearance(value, filename):
    return {
        "appearances": [{"appearance": "luminosity", "value": value}],
        "filename": filename,
        "idiom": "universal",
        "platform": "ios",
        "size": "1024x1024",
    }


def contents(folder):
    path = f"{CATALOG}/{folder}/Contents.json"
    data = json.load(open(path))
    images = [i for i in data["images"] if not i.get("appearances")]
    ios = next(k for k, i in enumerate(images) if i.get("platform") == "ios")
    images[ios + 1 : ios + 1] = [
        appearance("dark", "icon-1024-dark.png"),
        appearance("tinted", "icon-1024-tinted.png"),
    ]
    data["images"] = images
    open(path, "w").write(json.dumps(data, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    inner, size = mark()
    dark = render(placed(inner, size, f'<rect width="1024" height="1024" fill="{NAVY}"/>'), "app-icon-dark")
    mono = render(placed(inner, size), "app-icon-tinted")
    for folder, banded in SETS.items():
        d = band(dark) if banded else dark
        t = band(mono) if banded else mono
        d.convert("RGB").save(f"{CATALOG}/{folder}/icon-1024-dark.png", optimize=True)
        tinted(t).save(f"{CATALOG}/{folder}/icon-1024-tinted.png", optimize=True)
        contents(folder)
    print("done")
