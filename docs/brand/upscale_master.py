"""Make source/mascot-2048.png: a 2048 px master of source/mascot.jpg.

Real-ESRGAN x4plus (the general model; the anime_6B one flattens the watercolour grain) runs
4x over the JPEG, tiled, then Lanczos brings the result down to 2048 px wide. Needs a separate
environment from process.py, because of torch:

    uv venv --python 3.12 .venv-upscale
    uv pip install --python .venv-upscale/bin/python torch torchvision spandrel pillow numpy
    curl -LO https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth
    .venv-upscale/bin/python upscale_master.py source/mascot.jpg RealESRGAN_x4plus.pth source/mascot-2048.png

Run it again only if mascot.jpg itself changes; the master is committed.
"""

import sys

import numpy as np
import torch
from PIL import Image
from spandrel import ModelLoader

MASTER_WIDTH = 2048


def run_tiled(model, x, scale, tile=384, overlap=32):
    _, c, h, w = x.shape
    out = torch.zeros((1, c, h * scale, w * scale), dtype=x.dtype)
    for y0 in range(0, h, tile):
        for x0 in range(0, w, tile):
            y1, x1 = min(y0 + tile, h), min(x0 + tile, w)
            py0, px0 = max(y0 - overlap, 0), max(x0 - overlap, 0)
            py1, px1 = min(y1 + overlap, h), min(x1 + overlap, w)
            with torch.no_grad():
                sr = model(x[:, :, py0:py1, px0:px1]).cpu()
            oy0, ox0 = (y0 - py0) * scale, (x0 - px0) * scale
            oy1, ox1 = oy0 + (y1 - y0) * scale, ox0 + (x1 - x0) * scale
            out[:, :, y0 * scale : y1 * scale, x0 * scale : x1 * scale] = sr[:, :, oy0:oy1, ox0:ox1]
    return out


def main(src, weights, dst):
    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    model = ModelLoader().load_from_file(weights).eval().to(dev)
    img = Image.open(src).convert("RGB")
    x = torch.from_numpy(np.asarray(img).astype(np.float32) / 255.0).permute(2, 0, 1)[None].to(dev)
    y = run_tiled(model.model, x, model.scale)
    big = Image.fromarray((y[0].permute(1, 2, 0).clamp(0, 1).numpy() * 255.0).round().astype(np.uint8))
    h = round(big.height * MASTER_WIDTH / big.width)
    big.resize((MASTER_WIDTH, h), Image.LANCZOS).save(dst, optimize=True)
    print(dst, MASTER_WIDTH, "x", h, "from", big.size, "on", dev)


if __name__ == "__main__":
    main(*sys.argv[1:4])
