# Brand assets

`source/` holds the four AI-drafted originals (2026-10-10). Everything shipped is derived from
them by `process.py`; edit the script, not the outputs.

| Source | Becomes | Where it ships |
| --- | --- | --- |
| `icon_mascot.py` (variant B, chosen 2026-10-21) | The app icon: the painted mascot from `mascot.jpg`, cropped from crest to books with the reel in hand, lifted off its paper and set on deep teal with a soft glow. No redraw; the pixels are the source's, doubled and sharpened. `install_icon.py` builds the iOS icon, macOS squircle set and `BETA` band variant | `aaru-ios/Aaru/Assets.xcassets/AppIcon*` |
| `icon_reeds.py` (variant A, 2026-10-10) | Retired as the app icon on 2026-10-21: five cattail reeds in front of a half sun. Still behind the web favicons, PWA icons and landing `app-icon.webp` until those are redone | `aaru-client/static/`, landing `app-icon.webp` |
| `app-icon.jpg` | Retired: its golden leaves read as feathers. Kept for reference | nowhere |
| `mascot.jpg` | Bird only (the stacked logo above it is dropped), feathered edge; always shown clipped to a paper disc | `Mascot` image set, `aaru-client/src/lib/assets/brand/mascot*.webp`, `og.jpg` |
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

Known limits: the sources are 784–1168 px JPEGs, so the mascot tops out at 1440 px wide. Ask for 2048 px PNG masters before the App Store release.
The three sources also use three different "Aaru" letterforms; the app uses `wordmark.jpg`'s.
