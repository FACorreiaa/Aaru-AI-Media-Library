"""Build every app-icon output from the chosen reed icon (variant A) into out/icon/."""
import os

from PIL import Image

import icon_reeds
from process import beta_band, mac_icon

OUT = "out/icon"
os.makedirs(f"{OUT}/web", exist_ok=True)


def iconset(icon, folder):
    os.makedirs(f"{OUT}/{folder}", exist_ok=True)
    icon.save(f"{OUT}/{folder}/icon-1024.png", optimize=True)
    mac = mac_icon(icon)
    for pt in (16, 32, 128, 256, 512):
        for sc in (1, 2):
            name = f"icon-mac-{pt}{'@2x' if sc == 2 else ''}.png"
            mac.resize((pt * sc, pt * sc), Image.LANCZOS).save(f"{OUT}/{folder}/{name}", optimize=True)
    return mac


if __name__ == "__main__":
    icon = icon_reeds.compose(**icon_reeds.VARIANTS["a-dawn-silhouette"])
    mac = iconset(icon, "AppIcon.appiconset")
    iconset(beta_band(icon), "AppIconBeta.appiconset")
    w = f"{OUT}/web"
    mac.resize((64, 64), Image.LANCZOS).save(f"{w}/favicon.png", optimize=True)
    mac.resize((32, 32), Image.LANCZOS).save(f"{w}/favicon.ico", sizes=[(16, 16), (32, 32)])
    icon.resize((180, 180), Image.LANCZOS).save(f"{w}/apple-touch-icon.png", optimize=True)
    icon.resize((192, 192), Image.LANCZOS).save(f"{w}/icon-192.png", optimize=True)
    icon.resize((512, 512), Image.LANCZOS).save(f"{w}/icon-512.png", optimize=True)
    print("done")
