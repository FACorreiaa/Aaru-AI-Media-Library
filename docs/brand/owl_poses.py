"""The owl's poses (BRD-004): curious, sleeping, celebrating.

Generated from the owl master (`source/owl-2048.png`, composited on night navy at 1024 px) with
FLUX.1 Kontext [dev] on the Hugging Face Space `black-forest-labs/FLUX.1-Kontext-Dev`
(guidance 2.5, 28 steps), owner-approved 2026-10-23. Outputs are usable commercially under the
FLUX.1 [dev] licence. The raw generations are committed in `source/poses/`; this script only
cuts and sizes them, so it runs offline.

Prompts (seeds in brackets):
  curious     [1204012243] "Keep the exact same small white robot owl character: same shapes,
              panel lines, materials, amber glowing eyes, colours and soft lighting. Plain solid
              flat dark navy background, nothing else in the scene, full body, centered, same
              framing. The owl tilts its head to one side with a curious, attentive look, eyes
              wide and glowing amber, one wing lifted slightly as if pondering."
  sleeping    [1651064154] "Close the owl's eyes: draw both eyes shut as gentle downward-curved
              lids, the owl is asleep. Keep everything else exactly the same: same owl, same
              style, same pose of the body, same plain dark navy background."
  celebrating [657235396]  "Raise both of the owl's wings up and outward in celebration, add
              three tiny amber sparkles above it. Keep the same owl, same face, same
              three-quarter view, same style, same plain dark navy background, no shadow."

Cut-out: the background is flat navy, so it is keyed by colour, but only where it is connected
to the image edge. The owl's black pupils and claws are close to navy and stay solid that way.

    python3 owl_poses.py   # writes out/owl-poses/{owl-<pose>.png,@2x}
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "source/poses"
OUT = "out/owl-poses"
POSES = ("curious", "sleeping", "celebrating")
LO, HI = 0.025, 0.08  # colour distance from the navy: clear below LO, solid above HI


def cut(path):
    a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
    edge = np.concatenate([a[:8].reshape(-1, 3), a[-8:].reshape(-1, 3), a[:, :8].reshape(-1, 3), a[:, -8:].reshape(-1, 3)])
    bg = np.median(edge, 0)
    diff = (np.abs(a - bg) / 255).max(2)
    labels, _ = ndimage.label(diff < HI)
    outside = np.isin(labels, np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    outside &= labels > 0
    alpha = np.where(outside, np.clip((diff - LO) / (HI - LO), 0, 1), 1.0)
    rgb = (a - bg * (1 - alpha[..., None])) / np.maximum(alpha[..., None], 1e-6)
    rgb = np.where(alpha[..., None] > 0.995, a, rgb)
    img = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8), "RGBA")
    return img.crop(img.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())


def main():
    os.makedirs(OUT, exist_ok=True)
    for pose in POSES:
        owl = cut(f"{SRC}/{pose}.png")
        for width, suffix in ((360, ""), (720, "@2x")):
            size = (width, round(owl.height * width / owl.width))
            owl.resize(size, Image.LANCZOS).save(f"{OUT}/owl-{pose}{suffix}.png", optimize=True)
        print(pose, owl.size)


if __name__ == "__main__":
    main()
