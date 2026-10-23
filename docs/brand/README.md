# Brand assets

**The standard since 2026-10-22 is the owl poster** (`source/owl-poster.png`, DESIGN.md "Brand").
`owl_poster.py` derives every mark and icon from it; edit the script, not the outputs.

| Output | How | Where it ships |
| --- | --- | --- |
| `source/a-mark.svg` | The A, its swooshes and the amber star. The silver is traced with potrace at 8x; the star is clean geometry measured from the poster | Master for the app icon |
| `source/a-mark-small.svg` | Legs as fitted geometry (no swooshes), thicker, and a bigger star: for 40 px and below | Master for the small icon |
| `source/app-icon.svg` | The A-mark at 64% on a navy gradient with the hologram's blue glow (owner approved 2026-10-22) | iOS 1024, macOS 128–512 pt, PWA, `apple-touch-icon`, extension 96/128, landing `app-icon.webp` |
| `source/app-icon-small.svg` | `a-mark-small` at 80% on flat navy | macOS 16/32 pt, favicons, extension 16/32/48 |
| `source/wordmark.svg` | The poster's "Aaru", traced, `fill="currentColor"` | `Wordmark` image set (template, vector), web `wordmark.svg` as a CSS mask over the text colour |
| `out/owl/web/og.jpg` | The poster cropped to 1200x630 | `aaru-client/public/og.jpg` |
| `source/poses/{curious,sleeping,celebrating}.png` | `owl_poses.py`: generated from the owl master on night navy with FLUX.1 Kontext [dev] (prompts and seeds in the script), approved by the owner 2026-10-23; cut out by keying the edge-connected navy | `OwlCurious`, `OwlSleeping`, `OwlCelebrating` image sets and web `owl-{pose}*.webp` (360/720 wide) |
| `source/owl-2048.png` | `owl_mascot.py`: the owl cropped from the poster, 4x by Real-ESRGAN (`upscale_master.py`) down to 2048 px, cut out with BiRefNet (rembg). Committed master, transparent | `Mascot` image set and web `mascot*.webp` (720/1440 wide); its head is `OwlMark` (iOS @2x/@3x, web `owl-mark.webp` 128 px), the agent's mark |

Run (Pillow, NumPy, SciPy; `brew install potrace librsvg`):

```bash
cd docs/brand && python3 -m venv .venv && .venv/bin/pip install pillow numpy scipy
.venv/bin/python owl_poster.py
```

It rewrites the SVGs in `source/` and writes rasters to `out/owl/` (not committed). Copy
`out/owl/AppIcon*.appiconset/*.png` into the asset catalog, `out/owl/web/*` (except `app-icon.png`,
which goes to `src/assets/brand/app-icon.webp` through `cwebp -q 90`) into `aaru-client/public/`,
and `out/owl/extension/*` into `aaru-extension/public/icon/`. The `BETA` band (`process.py`
`beta_band`) is navy with amber type.

Known limits: the poster is 1536x1024, so the traced marks are smoothed reconstructions, not the
artist's vectors, and the owl tops out at about 600 px tall. Ask for masters before an App Store
release.

## Retired (teal bird and reeds, 2026-10-10 to 2026-10-21)

Kept for reference; nothing below ships once BRD-003 lands.

| Source | Became | Shipped in |
| --- | --- | --- |
| `icon_mascot.py` (variant B, chosen 2026-10-21) | The app icon: the painted mascot from `mascot-2048.png`, cropped from crest to books with the reel in hand, lifted off its paper and set on deep teal with a soft glow. No redraw; the pixels are the master's. `install_icon.py` builds the iOS icon, macOS squircle set and `BETA` band variant | `aaru-ios/Aaru/Assets.xcassets/AppIcon*` |
| `icon_reeds.py` (variant A, 2026-10-10) | Retired as the app icon on 2026-10-21: five cattail reeds in front of a half sun. Still behind the web favicons, PWA icons and landing `app-icon.webp` until those are redone | `aaru-client/static/`, landing `app-icon.webp` |
| `app-icon.jpg` | Retired: its golden leaves read as feathers. Kept for reference | nowhere |
| `mascot.jpg` | Bird only (the stacked logo above it is dropped), feathered edge; always shown clipped to a paper disc | `Mascot` image set, `aaru-client/src/lib/assets/brand/mascot*.webp`, `og.jpg` |
| `mascot-2048.png` | 2048 px master of `mascot.jpg`, made by `upscale_master.py` (Real-ESRGAN x4plus, 2026-10-21). Not an original: rebuild it if the painting changes | The app icon, through `icon_mascot.py` |
| `wordmark.jpg` | Transparent wordmark | `Wordmark` image set, landing nav |
| `reed-lockup.jpg` | Transparent reed + reflection mark (type dropped) | `ReedMark` image set, landing bento and footer |

Run (needs Pillow, NumPy, SciPy; writes to `out/`, which is not committed):

```bash
cd docs/brand && python3 -m venv .venv && .venv/bin/pip install pillow numpy scipy
.venv/bin/python process.py
```

For the icon, run `.venv/bin/python install_icon.py` and copy `out/icon/AppIcon*.appiconset/*.png`
into the asset catalog. It also writes a web set to `out/icon/web/`, but the site still ships the
reed favicons on purpose; copy those into `aaru-client/static/` only when the web switches too.
`icon_mascot.py` alone renders its four crops plus a comparison sheet, and `icon_reeds.py` the
three reed concepts. For the logos and mascot, copy from `out/` and convert to WebP with `cwebp`.

Known limits: the sources are 784–1168 px JPEGs. The mascot has a 2048 px master and the app icon
uses it; the `Mascot` image set and `og.jpg` still come from the JPEG and top out at 1440 px wide,
and the wordmark and reed mark have no masters yet. The three sources also use three different
"Aaru" letterforms; the app uses `wordmark.jpg`'s.
