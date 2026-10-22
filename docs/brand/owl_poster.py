"""Derive Aaru's marks and icons from the owl poster (owner, 2026-10-22; DESIGN.md "Brand").

Everything here comes from `source/owl-poster.png` (1536x1024). The A-mark and the wordmark are
traced to vector with potrace, so every size renders sharp even though the poster's A is only
about 270 px tall. Writes the vector masters to `source/` (committed) and the rasters to
`out/owl/` (not committed; copy them by hand, see README.md).

Needs Pillow, NumPy, SciPy, plus `potrace` and `rsvg-convert` on the PATH (Homebrew: potrace,
librsvg).
"""
import os
import re
import subprocess

import numpy as np
from PIL import Image
from scipy import ndimage

from process import beta_band, mac_icon

POSTER = "source/owl-poster.png"
OUT = "out/owl"
SCALE = 8  # trace at 8x the poster's pixels; potrace smooths what bicubic leaves

SILVER = "#e7ebf1"  # tokens.json ink (dark)
AMBER = "#f2a65a"  # the star, a touch brighter than the gold token so it glows on navy
NAVY = "#0e141e"  # tokens.json paper (dark)

A_BOX = (190, 160, 500, 410)  # the A-mark in the poster
WORDMARK_BOX = (130, 440, 550, 545)  # "Aaru" under it


def upscaled(box):
    crop = POSTER_IMG.crop(box)
    big = crop.resize((crop.width * SCALE, crop.height * SCALE), Image.BICUBIC)
    return np.asarray(big).astype(float) / 255


def trace(mask, name, turd=40):
    """potrace a boolean mask; returns (transform, path markup) of its one <g>."""
    pbm = f"{OUT}/{name}.pbm"
    Image.fromarray(((~mask) * 255).astype(np.uint8)).convert("1").save(pbm)
    svg = f"{OUT}/{name}.raw.svg"
    subprocess.run(["potrace", pbm, "-s", "-o", svg, "-t", str(turd), "-a", "1.0", "-O", "0.4"], check=True)
    g = re.search(r'<g transform="([^"]+)"[^>]*>(.*?)</g>', open(svg).read(), re.S)
    return g.group(1), g.group(2).strip()


def smooth(mask, sigma):
    return ndimage.gaussian_filter(mask.astype(float), sigma) > 0.5


def silver(a):
    lum = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    return (lum > 0.42) & (a.max(-1) - a.min(-1) < 0.22)


def amber(a):
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    return (r > 0.75) & (g > 0.45) & (b < 0.75) & (r - b > 0.18)


def star_path(a, grow=1.0, drop=0.0):
    """The four-point star as clean geometry, sized from the amber blob in the poster.

    The amber mask misses the star's white-hot tips, so the height is read off the poster by
    eye: taller than wide, centred a little above the blob's middle."""
    am = ndimage.binary_opening(amber(a), iterations=4)
    lab, n = ndimage.label(am)
    star = lab == 1 + int(np.argmax(ndimage.sum(am, lab, range(1, n + 1))))
    ys, xs = np.nonzero(star)
    cx = (xs.min() + xs.max()) / 2
    cy = (ys.min() + ys.max()) / 2 - 0.45 * (ys.max() - ys.min()) / 2
    rx, ry = (xs.max() - xs.min()) / 2, 1.5 * (ys.max() - ys.min()) / 2
    cy, rx, ry = cy + drop, rx * grow, ry * grow
    k = 0.16  # how far the sides bow in
    d = (
        f"M{cx:.0f},{cy - ry:.0f} Q{cx + k * rx:.0f},{cy - k * ry:.0f} {cx + rx:.0f},{cy:.0f} "
        f"Q{cx + k * rx:.0f},{cy + k * ry:.0f} {cx:.0f},{cy + ry:.0f} "
        f"Q{cx - k * rx:.0f},{cy + k * ry:.0f} {cx - rx:.0f},{cy:.0f} "
        f"Q{cx - k * rx:.0f},{cy - k * ry:.0f} {cx:.0f},{cy - ry:.0f}Z"
    )
    return d, (cx, cy, rx, ry)


def a_mark():
    """The full mark (legs, swooshes, star) and the small-size mark (legs and star only)."""
    a = upscaled(A_BOX)
    h, w = a.shape[:2]
    star, (cx, cy, rx, ry) = star_path(a)
    yy, xx = np.mgrid[0:h, 0:w]
    glow = np.abs(xx - cx) / (rx * 1.25) + np.abs(yy - cy) / (ry * 1.25) < 1  # the star's halo
    t, paths = trace(smooth(silver(a) & ~glow, 0.9 * SCALE / 2), "a-mark-silver")
    full = f'<g transform="{t}" fill="{SILVER}">{paths}</g>\n<path fill="{AMBER}" d="{star}"/>'

    # Below ~40 px the swooshes turn to noise. The legs are clean geometry fitted to the traced
    # edges (apex 1282,92; feet at y 1895), thickened ~35% so each stays over a pixel at 16 px,
    # and the star grows and drops clear of them.
    legs = "M1282,92 L2331,1895 L1960,1895 L1276,640 L560,1895 L179,1895 Z"
    big_star, _ = star_path(a, grow=1.4, drop=120)
    small = f'<path fill="{SILVER}" d="{legs}"/>\n<path fill="{AMBER}" d="{big_star}"/>'
    return full, small, (w, h)


def wordmark():
    a = upscaled(WORDMARK_BOX)
    lum = 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]
    mask = smooth(lum > 0.45, 3)
    t, paths = trace(mask, "wordmark", turd=200)
    ys, xs = np.nonzero(mask)
    pad = 8
    x0, y0, x1, y1 = xs.min() - pad, ys.min() - pad, xs.max() + pad, ys.max() + pad
    # One colour, the text's: currentColor on the web (a CSS mask), a template image on Apple.
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} {y0} {x1 - x0} {y1 - y0}" '
        f'fill="currentColor">\n<g transform="{t}">{paths}</g>\n</svg>\n'
    )


def svg(inner, w, h):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">\n{inner}\n</svg>\n'


def icon(inner, mark_size, share, glow):
    """The mark centred on night navy, `share` of the tile wide, optically a touch high."""
    mw, mh = mark_size
    w = 1024 * share
    s = w / mw
    x, y = (1024 - w) / 2, (1024 - mh * s) / 2 - 1024 * (0.02 if glow else 0.01)
    if glow:  # the poster's hologram light behind the A
        ground = """<defs>
  <radialGradient id="sky" cx="50%" cy="38%" r="75%">
    <stop offset="0" stop-color="#18233a"/><stop offset="1" stop-color="#0b1019"/>
  </radialGradient>
  <radialGradient id="glow" cx="50%" cy="50%" r="50%">
    <stop offset="0" stop-color="#579edb" stop-opacity="0.28"/><stop offset="1" stop-color="#579edb" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect width="1024" height="1024" fill="url(#sky)"/>
<circle cx="512" cy="480" r="430" fill="url(#glow)"/>"""
    else:
        ground = f'<rect width="1024" height="1024" fill="{NAVY}"/>'
    return svg(f'{ground}\n<g transform="translate({x:.2f},{y:.2f}) scale({s:.6f})">{inner}</g>', 1024, 1024)


def render(svg_path, px):
    png = f"{OUT}/.render-{px}.png"
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg_path, "-o", png], check=True)
    return Image.open(png).convert("RGBA")


def iconsets(full, small):
    """iOS 1024 + macOS squircles. macOS 16 and 32 pt take the small mark; iOS has one size."""
    for folder, banded in (("AppIcon.appiconset", False), ("AppIconBeta.appiconset", True)):
        os.makedirs(f"{OUT}/{folder}", exist_ok=True)
        big = render(full, 1024).convert("RGB")
        lil = render(small, 1024).convert("RGB")
        if banded:
            big, lil = beta_band(big), beta_band(lil)
        big.save(f"{OUT}/{folder}/icon-1024.png", optimize=True)
        mac_big, mac_small = mac_icon(big), mac_icon(lil)
        for pt in (16, 32, 128, 256, 512):
            for sc in (1, 2):
                src = mac_small if pt <= 32 else mac_big
                name = f"icon-mac-{pt}{'@2x' if sc == 2 else ''}.png"
                src.resize((pt * sc, pt * sc), Image.LANCZOS).save(f"{OUT}/{folder}/{name}", optimize=True)


def web_and_extension(full, small):
    w = f"{OUT}/web"
    e = f"{OUT}/extension"
    os.makedirs(w, exist_ok=True)
    os.makedirs(e, exist_ok=True)
    render(small, 64).save(f"{w}/favicon.png", optimize=True)
    render(small, 32).save(f"{w}/favicon.ico", sizes=[(16, 16), (32, 32)])
    for px, name in ((180, "apple-touch-icon.png"), (192, "icon-192.png"), (512, "icon-512.png")):
        render(full, px).convert("RGB").save(f"{w}/{name}", optimize=True)
    render(full, 512).save(f"{w}/app-icon.png")  # landing, convert to WebP
    for px in (16, 32, 48, 96, 128):
        render(small if px <= 48 else full, px).save(f"{e}/{px}.png", optimize=True)
    # Link previews: the poster itself, cropped to 1200x630 around the logo and the owl.
    POSTER_IMG.crop((0, 110, 1536, 916)).resize((1200, 630), Image.LANCZOS).save(f"{w}/og.jpg", quality=86)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    POSTER_IMG = Image.open(POSTER).convert("RGB")
    full, small, size = a_mark()
    open("source/a-mark.svg", "w").write(svg(full, *size))
    open("source/a-mark-small.svg", "w").write(svg(small, *size))
    open("source/wordmark.svg", "w").write(wordmark())
    open("source/app-icon.svg", "w").write(icon(full, size, 0.64, glow=True))
    open("source/app-icon-small.svg", "w").write(icon(small, size, 0.80, glow=False))
    iconsets("source/app-icon.svg", "source/app-icon-small.svg")
    web_and_extension("source/app-icon.svg", "source/app-icon-small.svg")
    print("done")
