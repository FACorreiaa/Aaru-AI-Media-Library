#!/usr/bin/env python3
"""Assembles the Aaru videos from real app recordings, the Higgsfield room and the music bed.

    python3 capture/assemble.py v3            # one video
    python3 capture/assemble.py all

Every product shot is a real Simulator recording (assets/raw/capture). Text is drawn by
render.swift in the system sans with design/tokens.json colours; this ffmpeg has no text filter.
Cuts are calm cross-fades (brand.md, Motion). Outputs land in assets/raw/exports (git-ignored).
"""

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MKT = HERE.parent
REPO = MKT.parent
RAW = MKT / "assets/raw"
CAP = RAW / "capture"
HF = RAW / "higgsfield"
OUT = RAW / "exports"
WORK = RAW / "work"
FF = "/opt/homebrew/bin/ffmpeg"
FPS = 30
XF = 0.4  # cross-fade seconds

os.environ["AARU_TOKENS"] = str(REPO / "design/tokens.json")
RENDER = WORK / "render"


def run(cmd):
    subprocess.run([str(c) for c in cmd], check=True)


def ff(*args):
    run([FF, "-loglevel", "error", "-y", *map(str, args)])


def hexcolor(token):
    return subprocess.run([str(RENDER), "hex", token], check=True, capture_output=True, text=True).stdout.strip()


def text_png(name, w, h, size, weight, token, text):
    path = WORK / f"{name}.png"
    run([RENDER, "text", path, w, h, size, weight, token, text])
    return path


def cfr(name):
    """A take at a constant 30 fps. Simulator recordings only write a frame when the screen changes,
    so seeking into a still stretch jumps to the next change; cut from this copy instead."""
    path = RAW / "cfr" / f"{name}.mp4"
    if not path.exists():
        path.parent.mkdir(exist_ok=True)
        ff("-i", CAP / f"{name}.mov", "-vf", f"fps={FPS}", "-c:v", "libx264", "-crf", "14", "-preset", "fast",
           "-pix_fmt", "yuv420p", path)
    return path


def duration(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
        check=True, capture_output=True, text=True,
    )
    return float(out.stdout)


# Formats ------------------------------------------------------------------------------------------

V916 = dict(W=1080, H=1920, room="H1-916.mp4", dev_h=1440, dev_y=410, cap_h=330, cap_y=60, cap_size=62)
V169 = dict(W=1920, H=1080, room="H1-169.mp4", dev_h=940, dev_y=70, cap_h=1080, cap_y=0, cap_size=60)


def background(fmt):
    """The room, blurred and dimmed, slowed and played forward then back: 30 s behind the device."""
    path = WORK / f"bg-{fmt['W']}x{fmt['H']}.mp4"
    if path.exists():
        return path
    w, h = fmt["W"] // 2, fmt["H"] // 2
    ff("-i", HF / fmt["room"], "-filter_complex",
       f"[0]scale={w}:{h},gblur=sigma=14,eq=brightness=-0.10:saturation=0.85,setpts=3*PTS,fps=15,split[a][b];"
       f"[b]reverse[r];[a][r]concat=n=2:v=1,scale={fmt['W']}:{fmt['H']},fps={FPS},format=yuv420p",
       "-c:v", "libx264", "-crf", "18", "-preset", "medium", path)
    return path


def device_assets(fmt):
    dh = fmt["dev_h"]
    dw = round(dh * 1206 / 2622 / 2) * 2
    r = round(165 * dw / 1206)
    pad = round(dw * 0.022)
    names = {}
    for key, (w, h, rr) in {"screen": (dw, dh, r), "bezel": (dw + 2 * pad, dh + 2 * pad, r + pad)}.items():
        p = WORK / f"mask-{key}-{w}x{h}.png"
        run([RENDER, "mask", p, w, h, rr])
        names[key] = p
    ring = WORK / f"ring-{dw + 2 * pad}x{dh + 2 * pad}.png"
    run([RENDER, "ring", ring, dw + 2 * pad, dh + 2 * pad, r + pad, 3, "line-strong"])
    return dict(dw=dw, dh=dh, pad=pad, ring=ring, **names)


def caption_inputs(fmt, caption, dur, tag):
    if not caption:
        return [], ""
    png = text_png(f"cap-{tag}", fmt["W"] if fmt["W"] < fmt["H"] else 700, fmt["cap_h"], fmt["cap_size"], "semibold", "ink", caption)
    fade = f"fade=in:st=0.15:d=0.45:alpha=1,fade=out:st={max(dur - 0.55, 0.2):.2f}:d=0.45:alpha=1"
    return ["-loop", "1", "-t", f"{dur:.3f}", "-i", png], fade


def seg_room(fmt, out, start, dur, caption, tag, dim=0.0, owl=None, cap_at=None):
    """The night room, a caption, and optionally the brand owl (docs/brand/source, never generated)."""
    cap_in, cap_fade = caption_inputs(fmt, caption, dur, tag)
    portrait = fmt["W"] < fmt["H"]
    if cap_at is not None:
        y = cap_at
    else:
        y = (fmt["H"] - fmt["cap_h"]) // 2 if portrait else 0
    x = 0 if portrait else (150 if owl else (fmt["W"] - 700) // 2)
    inputs = ["-i", HF / fmt["room"]]
    chain = f"[0]trim=start={start}:duration={dur},setpts=PTS-STARTPTS,fps={FPS},eq=brightness={-dim}[v]"
    n = 1
    if owl:
        png, oh, ox, oy = owl
        inputs += ["-loop", "1", "-t", f"{dur:.3f}", "-i", png]
        chain += (f";[{n}]scale=-1:{oh},format=rgba,fade=in:st=0.3:d=0.8:alpha=1[o];"
                  f"[v][o]overlay={ox}:{oy}[v]")
        n += 1
    if cap_in:
        inputs += cap_in
        chain += f";[{n}]format=rgba,{cap_fade}[c];[v][c]overlay={x}:{y}[v]"
    ff(*inputs, "-filter_complex", chain, "-map", "[v]", "-t", f"{dur:.3f}",
       "-c:v", "libx264", "-crf", "17", "-pix_fmt", "yuv420p", out)


def clip(name, src, ranges):
    """Joins pieces of one take into a single source, for beats that skip dead time (A5's ticks)."""
    path = WORK / f"clip-{name}.mp4"
    parts = "".join(f"[0]trim=start={a}:end={b},setpts=PTS-STARTPTS[p{i}];" for i, (a, b) in enumerate(ranges))
    joined = "".join(f"[p{i}]" for i in range(len(ranges)))
    ff("-i", src, "-filter_complex", f"{parts}{joined}concat=n={len(ranges)}:v=1[v]", "-map", "[v]",
       "-c:v", "libx264", "-crf", "14", "-preset", "fast", "-pix_fmt", "yuv420p", path)
    return path, sum(b - a for a, b in ranges)


def seg_device(fmt, dev, out, src, start, end, speed, caption, tag, bg_at=0.0):
    dur = (end - start) / speed
    cap_in, cap_fade = caption_inputs(fmt, caption, dur, tag)
    stone = hexcolor("stone")
    bw, bh = dev["dw"] + 2 * dev["pad"], dev["dh"] + 2 * dev["pad"]
    if fmt["W"] < fmt["H"]:
        bx, by = (fmt["W"] - bw) // 2, fmt["dev_y"] - dev["pad"]
        cx, cy = 0, fmt["cap_y"]
    else:  # landscape: device on the right third, caption on the left
        bx, by = fmt["W"] - bw - 260, (fmt["H"] - bh) // 2
        cx, cy = 150, 0
    inputs = ["-ss", start, "-to", end, "-i", src, "-ss", bg_at, "-i", background(fmt),
              "-i", dev["screen"], "-i", dev["bezel"], "-i", dev["ring"], *cap_in]
    f = (
        f"[0]setpts=(PTS-STARTPTS)/{speed},fps={FPS},scale={dev['dw']}:{dev['dh']},format=rgba[s];"
        f"[2]format=gray[m];[s][m]alphamerge[sc];"
        f"color=c={stone}:s={bw}x{bh}:r={FPS},format=rgba[bz0];[3]format=gray[bm];[bz0][bm]alphamerge[bz];"
        f"[1]setpts=PTS-STARTPTS[bg];[bg][bz]overlay={bx}:{by}:shortest=1[a];"
        f"[a][sc]overlay={bx + dev['pad']}:{by + dev['pad']}[b];[b][4]overlay={bx}:{by}[v]"
    )
    if cap_in:
        f += f";[5]format=rgba,{cap_fade}[c];[v][c]overlay={cx}:{cy}[v]"
    ff(*inputs, "-filter_complex", f, "-map", "[v]", "-t", f"{dur:.3f}",
       "-c:v", "libx264", "-crf", "17", "-pix_fmt", "yuv420p", out)


def seg_end(fmt, out, dur, tagline, tag):
    """End card: the room, dark; wordmark, tagline, CTA and the credits (brand.md)."""
    W, H = fmt["W"], fmt["H"]
    portrait = W < H
    ink, paper = hexcolor("ink"), hexcolor("paper")
    wm_w = 520 if portrait else 460
    wm_h = round(wm_w * 420 / 1600 / 2) * 2
    tl = text_png(f"end-tag-{tag}", W, 260, 54 if portrait else 46, "medium", "ink", tagline)
    cta = text_png(f"end-cta-{W}", W, 90, 44 if portrait else 38, "semibold", "accent", "Download on the App Store")
    web = text_png(f"end-web-{W}", W, 70, 34 if portrait else 30, "regular", "muted", "or aaruapp.com")
    cred = text_png(
        f"end-cred-{W}", W, 150, 22 if portrait else 19, "regular", "muted",
        "This product uses the TMDB API but is not endorsed or certified by TMDB.\\n"
        "Anime data from AniList. Book data from Open Library.",
    )
    tmdb_w = 150 if portrait else 120  # smaller than the wordmark, always
    y0 = 560 if portrait else 250
    ys = dict(wm=y0, tl=y0 + 200, cta=y0 + 470, web=y0 + 550, tmdb=H - 260 if portrait else H - 190,
              cred=H - 210 if portrait else H - 160)
    if not portrait:
        ys.update(tl=y0 + 150, cta=y0 + 380, web=y0 + 450)
    f = (
        f"[0]trim=start=0:duration={dur},setpts=PTS-STARTPTS,fps={FPS},eq=brightness=-0.32:saturation=0.7[bg];"
        f"[1]crop=1600:420:0:590,scale={wm_w}:{wm_h},format=gray,negate[wa];"
        f"color=c={ink}:s={wm_w}x{wm_h}:r={FPS},format=rgba[wc];[wc][wa]alphamerge[wm];"
        f"[2]crop=1200:170:0:515,scale={tmdb_w}:-1,format=rgba,colorkey=white:0.25:0.15[tm];"
        f"[bg][wm]overlay=(W-w)/2:{ys['wm']}:shortest=1[a];"
        f"[a][3]overlay=0:{ys['tl']}[b];[b][4]overlay=0:{ys['cta']}[c];[c][5]overlay=0:{ys['web']}[d];"
        f"[d][tm]overlay=(W-w)/2:{ys['tmdb']}[e];[e][6]overlay=0:{ys['cred']},fade=in:st=0:d=0.6[v]"
    )
    tmdb_png = WORK / "tmdb.png"
    if not tmdb_png.exists():
        run(["qlmanage", "-t", "-s", "1200", "-o", WORK, REPO / "aaru-client/src/assets/brand/tmdb-blue-short.svg"])
        (WORK / "tmdb-blue-short.svg.png").rename(tmdb_png)
    ff("-i", HF / fmt["room"], "-loop", "1", "-i", RAW / "endcard/wordmark.svg.png", "-loop", "1", "-i", tmdb_png,
       "-loop", "1", "-i", tl, "-loop", "1", "-i", cta, "-loop", "1", "-i", web, "-loop", "1", "-i", cred,
       "-filter_complex", f, "-map", "[v]", "-t", f"{dur:.3f}", "-c:v", "libx264", "-crf", "17", "-pix_fmt", "yuv420p", out)
    _ = paper


def join(parts, out, music_start=0.0):
    """Cross-fades the parts, lays the music bed under them, -14 LUFS."""
    durs = [duration(p) for p in parts]
    inputs = []
    for p in parts:
        inputs += ["-i", p]
    chain, last, offset = "", "[0]", 0.0
    for i in range(1, len(parts)):
        offset += durs[i - 1] - XF
        chain += f"{last}[{i}]xfade=transition=fade:duration={XF}:offset={offset:.3f}[x{i}];"
        last = f"[x{i}]"
    total = sum(durs) - XF * (len(parts) - 1)
    n = len(parts)
    chain += (
        f"[{n}]atrim=start={music_start}:duration={total:.3f},asetpts=PTS-STARTPTS,"
        f"afade=in:st=0:d=0.8,afade=out:st={total - 2.2:.3f}:d=2.2,loudnorm=I=-14:TP=-1.5:LRA=11[a]"
    )
    ff(*inputs, "-i", HF / "M1-music-a.mp3", "-filter_complex", chain, "-map", last, "-map", "[a]",
       "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p", "-r", FPS,
       "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out)
    return total


# Videos -------------------------------------------------------------------------------------------

def v3():
    """Bring your history: 9:16, about 30 s (videos/03-bring-your-history/script.md)."""
    fmt, dev = V916, device_assets(V916)
    t1, t2 = cfr("v3-take1"), cfr("v3-take2")
    parts = []

    def p(name):
        path = WORK / f"v3-{name}.mp4"
        parts.append(path)
        return path

    seg_room(fmt, p("open"), 0.0, 3.2, "Years of films\\nin another app?", "v3-open")
    seg_device(fmt, dev, p("b1"), t1, 12.6, 18.2, 1.5, "Bring your Letterboxd export.", "v3-b1", 0)
    seg_device(fmt, dev, p("plan"), t1, 24.6, 27.4, 1.0, "See what matched\\nbefore anything is added.", "v3-plan", 4)
    seg_device(fmt, dev, p("fix"), t1, 61.0, 71.6, 2.0, "Pick the one it meant.", "v3-fix", 7)
    seg_device(fmt, dev, p("approve"), t1, 79.6, 85.6, 1.5, "Approve it, and it is in your library.", "v3-approve", 11)
    seg_device(fmt, dev, p("lib"), t1, 98.6, 101.6, 1.0, "", "v3-lib", 15)
    seg_device(fmt, dev, p("undo"), t2, 112.6, 122.6, 1.7, "Changed your mind?\\nUndo the whole import.", "v3-undo", 18)
    seg_device(fmt, dev, p("empty"), t2, 136.6, 139.6, 1.0, "", "v3-empty", 23)
    seg_end(fmt, p("end"), 4.6, "Bring your history.\\nLeave whenever you like.", "v3")
    return join(parts, OUT / "v3-bring-your-history-916.mp4")


OWL = REPO / "docs/brand/source/owl-2048.png"
CTA_TAG = "Your stories. Your world."


def v1():
    """Teaser: 9:16, about 12 s (videos/01-teaser/script.md)."""
    fmt, dev = V916, device_assets(V916)
    parts = []

    def p(name):
        path = WORK / f"v1-{name}.mp4"
        parts.append(path)
        return path

    seg_room(fmt, p("open"), 0.0, 2.6, "Everything you watch,\\nread and follow.", "v1-open",
             owl=(OWL, 620, (fmt["W"] - 620) // 2, 980), cap_at=520)
    seg_device(fmt, dev, p("a3"), cfr("a3-take1"), 22.8, 27.0, 2.0, "Films, books, anime. One search.", "v1-a3", 2)
    a5, _ = clip("a5-ticks", cfr("a5-take1"), [(29.8, 31.2), (34.3, 35.5), (59.3, 60.9)])
    seg_device(fmt, dev, p("a5"), a5, 0.0, 4.2, 1.8, "To the episode.", "v1-a5", 5)
    seg_device(fmt, dev, p("b2"), cfr("v3-take1"), 79.6, 85.2, 2.0, "Bring your history with you.", "v1-b2", 8)
    seg_room(fmt, p("owl"), 1.5, 2.2, CTA_TAG, "v1-owl", dim=0.18,
             owl=(OWL, 760, (fmt["W"] - 760) // 2, 880), cap_at=520)
    seg_end(fmt, p("end"), 3.4, "Everything you watch,\\nread and follow.", "v1")
    return join(parts, OUT / "v1-teaser-916.mp4", music_start=4.0)


def v2(fmt, suffix):
    """Showcase: about 55 s (videos/02-showcase/script.md), iPhone footage in both ratios."""
    dev = device_assets(fmt)
    portrait = fmt["W"] < fmt["H"]
    t1, t2 = cfr("v3-take1"), cfr("v3-take2")
    parts = []

    def p(name):
        path = WORK / f"v2{suffix}-{name}.mp4"
        parts.append(path)
        return path

    owl_h = 760 if portrait else 760
    owl_pos = ((fmt["W"] - owl_h) // 2, 900) if portrait else (fmt["W"] - owl_h - 220, (fmt["H"] - owl_h) // 2)
    seg_room(fmt, p("hook"), 0.0, 3.6, "Four apps for what\\nyou watch and read?", f"v2{suffix}-hook",
             cap_at=None if not portrait else 760)
    seg_room(fmt, p("owl"), 1.2, 3.8, "Everything you watch,\\nread and follow.", f"v2{suffix}-owl", dim=0.12,
             owl=(OWL, owl_h, *owl_pos), cap_at=500 if portrait else None)
    seg_device(fmt, dev, p("b1"), t1, 12.6, 18.2, 1.5, "Bring your history.", f"v2{suffix}-b1", 0)
    seg_device(fmt, dev, p("b2"), t1, 61.0, 71.6, 2.0, "See what matched\\nbefore anything is added.", f"v2{suffix}-b2", 4)
    seg_device(fmt, dev, p("b2b"), t1, 79.6, 85.0, 1.6, "", f"v2{suffix}-b2b", 9)
    seg_device(fmt, dev, p("a2"), cfr("a2-take1"), 8.0, 16.4, 1.5, "What's next,\\nto the episode.", f"v2{suffix}-a2", 12)
    a5, _ = clip("a5-ticks", cfr("a5-take1"), [(29.8, 31.2), (34.3, 35.5), (59.3, 60.9)])
    seg_device(fmt, dev, p("a5"), a5, 0.0, 4.2, 1.2, "", f"v2{suffix}-a5", 16)
    seg_device(fmt, dev, p("a6"), cfr("a6-take2"), 7.8, 21.0, 1.9, "Your week,\\nacross everything.", f"v2{suffix}-a6", 20)
    seg_device(fmt, dev, p("a3"), cfr("a3-take1"), 21.4, 40.0, 2.6, "Films, shows, anime,\\nmanga, books and albums.", f"v2{suffix}-a3", 24)
    seg_device(fmt, dev, p("b3"), t2, 112.6, 122.6, 1.7, "Changed your mind?\\nUndo the whole import.", f"v2{suffix}-b3", 0)
    seg_device(fmt, dev, p("g1"), cfr("g1-take1"), 12.0, 20.0, 1.4, "Private by default.\\nExport everything.", f"v2{suffix}-g1", 6)
    seg_end(fmt, p("end"), 5.0, CTA_TAG, f"v2{suffix}")
    return join(parts, OUT / f"v2-showcase-{suffix}.mp4", music_start=0.0)


VIDEOS = {"v1": v1, "v2": lambda: v2(V169, "169"), "v2v": lambda: v2(V916, "916"), "v3": v3}

if __name__ == "__main__":
    WORK.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    run(["xcrun", "swiftc", "-O", HERE / "render.swift", "-o", RENDER])
    names = list(VIDEOS) if sys.argv[1:] == ["all"] else sys.argv[1:]
    for name in names:
        total = VIDEOS[name]()
        print(f"{name}: {total:.1f} s")
