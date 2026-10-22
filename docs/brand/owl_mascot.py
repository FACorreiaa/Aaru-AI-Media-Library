"""The owl mascot and the agent's owl mark, from the owl poster (BRD-003, DESIGN.md "Brand").

Two steps, each in the `.venv-upscale` environment of upscale_master.py plus rembg:

    uv pip install --python .venv-upscale/bin/python "rembg[cpu]"
    # 1. the owl out of the poster, 4x by Real-ESRGAN, down to 2048 px wide (RGB, background kept)
    .venv-upscale/bin/python owl_mascot.py crop out/owl-src.png
    .venv-upscale/bin/python upscale_master.py out/owl-src.png RealESRGAN_x4plus.pth out/owl-2048-rgb.png
    # 2. cut out with BiRefNet into the committed master, then every shipped size
    .venv-upscale/bin/python owl_mascot.py cut out/owl-2048-rgb.png

Step 2 writes `source/owl-2048.png` (transparent, trimmed; committed) and `out/owl-mascot/`.
Run step 1 again only if the poster changes; `owl_mascot.py derive` rebuilds the sizes from the
committed master alone.
"""
import os
import sys

from PIL import Image

POSTER = "source/owl-poster.png"
MASTER = "source/owl-2048.png"
OUT = "out/owl-mascot"
OWL_BOX = (800, 160, 1410, 880)  # the owl, its tail and the top book in the poster

# The head mark: a square around the face, in master pixels. The ear tufts may leave the square;
# the disc clips them anyway.
HEAD_CENTER = (770, 480)
HEAD_SIDE = 1440


def crop(dest):
    Image.open(POSTER).convert("RGB").crop(OWL_BOX).save(dest)


def cut(src):
    from rembg import new_session, remove  # only this step needs the model

    owl = remove(Image.open(src).convert("RGB"), session=new_session("birefnet-general"), post_process_mask=True)
    owl.crop(owl.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()).save(MASTER, optimize=True)


def derive():
    os.makedirs(OUT, exist_ok=True)
    owl = Image.open(MASTER).convert("RGBA")
    # Mascot: the whole owl, as wide as the old bird's image set (720 / 1440).
    for width, name in ((720, "mascot.png"), (1440, "mascot@2x.png")):
        owl.resize((width, round(owl.height * width / owl.width)), Image.LANCZOS).save(f"{OUT}/{name}", optimize=True)
    # Agent mark: the head, square, on transparency (each client puts it on the night disc).
    cx, cy = HEAD_CENTER
    half = HEAD_SIDE // 2
    head = Image.new("RGBA", (HEAD_SIDE, HEAD_SIDE), (0, 0, 0, 0))
    head.paste(owl.crop((cx - half, cy - half, cx + half, cy + half)), (0, 0))
    for px, name in ((256, "owl-mark.png"), (128, "owl-mark@2x.png"), (192, "owl-mark@3x.png")):
        head.resize((px, px), Image.LANCZOS).save(f"{OUT}/{name}", optimize=True)


if __name__ == "__main__":
    step = sys.argv[1] if len(sys.argv) > 1 else "derive"
    if step == "crop":
        crop(sys.argv[2])
    elif step == "cut":
        cut(sys.argv[2])
        derive()
    else:
        derive()
    print("done")
