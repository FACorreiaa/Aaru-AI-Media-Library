"""Turn the four brand drafts into app-icon, web and in-app assets."""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

SRC = "source"
OUT = "out"
os.makedirs(OUT, exist_ok=True)


def load(name):
    return np.asarray(Image.open(f"{SRC}/{name}.jpg").convert("RGB")).astype(np.float32)


def save(arr, path, mode=None):
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode)
    img.save(f"{OUT}/{path}", optimize=True)
    return img


def normalized_fill(img, known, sigma):
    """Smooth background model: blur(img*known)/blur(known), defined everywhere."""
    w = ndimage.gaussian_filter(known.astype(np.float32), sigma)
    out = np.empty_like(img)
    for c in range(3):
        out[..., c] = ndimage.gaussian_filter(img[..., c] * known, sigma) / np.maximum(w, 1e-6)
    return out


# ---------------------------------------------------------------- app icon
def app_icon():
    a = load("app-icon")
    h, w, _ = a.shape
    white = np.abs(a - 255).sum(2) < 30
    shape = ndimage.binary_fill_holes(~white)
    shape = ndimage.binary_opening(shape, iterations=2)
    inner = ndimage.binary_erosion(shape, iterations=22)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    reeds = (R - B > 105) & (R > 140)
    reeds = ndimage.binary_dilation(reeds, iterations=18)
    known = inner & ~reeds

    # Square canvas centred on the reeds, padded so the glyph sits at ~72% height.
    ys, xs = np.where((R - B > 105) & (R > 140) & inner)
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    side = 800
    pad = 120
    big = np.full((h + 2 * pad, w + 2 * pad, 3), 0, np.float32)
    big[pad:-pad, pad:-pad] = a
    kn = np.zeros(big.shape[:2], bool)
    kn[pad:-pad, pad:-pad] = known
    ins = np.zeros(big.shape[:2], np.float32)
    ins[pad:-pad, pad:-pad] = inner
    # Two scales: tight near the shape, wide for the far extrapolation.
    near = normalized_fill(big, kn, 25)
    far = normalized_fill(big, kn, 90)
    wn = ndimage.gaussian_filter(kn.astype(np.float32), 25)
    bg = near * (wn[..., None] > 0.05) + far * (wn[..., None] <= 0.05)
    bg = ndimage.gaussian_filter(bg, (12, 12, 0))
    alpha = ndimage.gaussian_filter(ndimage.binary_erosion(ins > 0, iterations=6).astype(np.float32), 7)[..., None]
    comp = big * alpha + bg * (1 - alpha)

    x0 = int(round(cx - side / 2)) + pad
    y0 = int(round(cy - side / 2)) + pad
    crop = comp[y0 : y0 + side, x0 : x0 + side]
    img = Image.fromarray(np.clip(crop, 0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
    # Fine grain hides JPEG blocking and upscale softness in the gradient.
    rng = np.random.default_rng(7)
    arr = np.asarray(img).astype(np.float32) + rng.normal(0, 1.2, (1024, 1024, 1))
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    img.save(f"{OUT}/icon-1024.png", optimize=True)
    return img


def beta_band(icon):
    img = icon.copy().convert("RGBA")
    band = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(band)
    d.rectangle([0, 812, 1024, 1024], fill=(13, 52, 60, 236))
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 150)
    font.set_variation_by_axes([700])
    text = "BETA"
    tw = d.textlength(text, font=font)
    d.text(((1024 - tw) / 2, 818), text, font=font, fill=(240, 205, 140, 255))
    return Image.alpha_composite(img, band).convert("RGB")


def mac_icon(art):
    """macOS template: 824pt squircle on a 1024 canvas, soft drop shadow."""
    S = 1024
    size, off = 824, 100
    scale = 4
    m = Image.new("L", (S * scale, S * scale), 0)
    # Superellipse (n=5) approximates Apple's continuous corners.
    n = 5.0
    t = np.linspace(0, 2 * np.pi, 2000)
    r = size * scale / 2
    c = (off + size / 2) * scale
    px = c + r * np.sign(np.cos(t)) * np.abs(np.cos(t)) ** (2 / n)
    py = c + r * np.sign(np.sin(t)) * np.abs(np.sin(t)) ** (2 / n)
    ImageDraw.Draw(m).polygon(list(zip(px, py)), fill=255)
    m = m.resize((S, S), Image.LANCZOS)
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh = m.point(lambda v: int(v * 0.32)).filter(ImageFilter.GaussianBlur(14))
    shadow.paste((0, 0, 0, 255), (0, 10), sh)
    canvas = Image.alpha_composite(canvas, shadow)
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    tile.paste(art.resize((size, size), Image.LANCZOS), (off, off))
    tile.putalpha(m)
    return Image.alpha_composite(canvas, tile)


def write_iconset(icon, folder):
    os.makedirs(f"{OUT}/{folder}", exist_ok=True)
    icon.save(f"{OUT}/{folder}/icon-1024.png", optimize=True)
    mac = mac_icon(icon)
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            px = pt * sc
            name = f"icon-mac-{pt}{'@2x' if sc == 2 else ''}.png"
            mac.resize((px, px), Image.LANCZOS).save(f"{OUT}/{folder}/{name}", optimize=True)
    return mac


# ---------------------------------------------------------------- logos
def color_to_alpha(a, bg=(255, 255, 255), lo=0.05, hi=0.38):
    """Flat-logo cut-out: solid ink stays opaque, paper goes clear, edges keep AA."""
    bg = np.array(bg, np.float32)
    diff = (np.abs(a - bg) / 255).max(2)
    alpha = np.clip((diff - lo) / (hi - lo), 0, 1)
    rgb = (a - bg * (1 - alpha[..., None])) / np.maximum(alpha[..., None], 1e-6)
    rgb = np.where(alpha[..., None] > 0.995, a, rgb)
    return np.dstack([np.clip(rgb, 0, 255), alpha * 255])


def trim(rgba, margin):
    ys, xs = np.where(rgba[..., 3] > 8)
    y0, y1 = max(ys.min() - margin, 0), min(ys.max() + margin, rgba.shape[0])
    x0, x1 = max(xs.min() - margin, 0), min(xs.max() + margin, rgba.shape[1])
    return rgba[y0:y1, x0:x1]


def logos():
    word = trim(color_to_alpha(load("wordmark")), 6)
    save(word, "wordmark.png", "RGBA")
    reed = load("reed-lockup")
    reed_rgba = trim(color_to_alpha(reed, bg=reed[5:40, 5:40].reshape(-1, 3).mean(0)), 8)
    save(reed_rgba, "reed-lockup.png", "RGBA")
    # Mark only: the reed and its reflection, without the "Aaru" type below.
    a = reed_rgba
    rows = (a[..., 3] > 30).sum(1)
    gap = [y for y in range(int(a.shape[0] * 0.6), a.shape[0]) if rows[y] == 0]
    cut = gap[0] if gap else int(a.shape[0] * 0.78)
    save(trim(a[:cut], 6), "reed-mark.png", "RGBA")


# ---------------------------------------------------------------- mascot
def mascot():
    a = load("mascot")
    h, w, _ = a.shape
    y0, y1 = 316, 1110
    x0, x1 = 40, 760
    crop = a[y0:y1, x0:x1]
    ch, cw, _ = crop.shape
    paper = np.array([255, 249, 237], np.float32)
    # Feathered ellipse: fades the painted background into transparent paper.
    yy, xx = np.mgrid[0:ch, 0:cw]
    ny = (yy - ch * 0.52) / (ch * 0.56)
    nx = (xx - cw * 0.5) / (cw * 0.58)
    r = np.sqrt(nx**2 + ny**2)
    alpha = np.clip((1.0 - r) / 0.18, 0, 1)
    # Keep anything clearly not paper fully opaque (bird, books, reel, film strip).
    ink = np.abs(crop - paper).sum(2) > 60
    ink = ndimage.binary_dilation(ndimage.binary_opening(ink, iterations=2), iterations=6)
    alpha = np.maximum(alpha, ndimage.gaussian_filter(ink.astype(np.float32), 4))
    alpha = np.clip(alpha, 0, 1)
    rgba = np.dstack([crop, alpha * 255])
    img = Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), "RGBA")
    big = img.resize((cw * 2, ch * 2), Image.LANCZOS).filter(ImageFilter.UnsharpMask(2, 50, 2))
    big.save(f"{OUT}/mascot@2x.png", optimize=True)
    img.save(f"{OUT}/mascot.png", optimize=True)
    return img


# ---------------------------------------------------------------- web set
def web(icon, mac, mascot_img):
    d = f"{OUT}/web"
    os.makedirs(d, exist_ok=True)
    mac.resize((64, 64), Image.LANCZOS).save(f"{d}/favicon-64.png", optimize=True)
    mac.resize((32, 32), Image.LANCZOS).save(f"{d}/favicon-32.png", optimize=True)
    mac.resize((32, 32), Image.LANCZOS).save(f"{d}/favicon.ico", sizes=[(16, 16), (32, 32)])
    icon.resize((180, 180), Image.LANCZOS).save(f"{d}/apple-touch-icon.png", optimize=True)
    icon.resize((192, 192), Image.LANCZOS).save(f"{d}/icon-192.png", optimize=True)
    icon.resize((512, 512), Image.LANCZOS).save(f"{d}/icon-512.png", optimize=True)

    # Open Graph card 1200x630.
    og = Image.new("RGBA", (1200, 630), (251, 246, 236, 255))
    m = mascot_img.copy()
    m.thumbnail((560, 600), Image.LANCZOS)
    og.alpha_composite(m, (40, 630 - m.height + 10))
    word = Image.open(f"{OUT}/wordmark.png")
    word.thumbnail((420, 170), Image.LANCZOS)
    og.alpha_composite(word, (610, 170))
    dr = ImageDraw.Draw(og)
    serif = ImageFont.truetype("/System/Library/Fonts/NewYork.ttf", 44)
    sans = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 26)
    dr.text((614, 350), "A private shelf for", font=serif, fill=(22, 62, 66))
    dr.text((614, 402), "everything you watch", font=serif, fill=(22, 62, 66))
    dr.text((614, 454), "and read.", font=serif, fill=(22, 62, 66))
    dr.text((616, 530), "Films · Shows · Anime · Books", font=sans, fill=(176, 132, 62))
    og.convert("RGB").save(f"{d}/og.png", optimize=True)


if __name__ == "__main__":
    icon = app_icon()
    mac = write_iconset(icon, "AppIcon.appiconset")
    write_iconset(beta_band(icon), "AppIconBeta.appiconset")
    logos()
    m = mascot()
    web(icon, mac, m)
    print("done")
