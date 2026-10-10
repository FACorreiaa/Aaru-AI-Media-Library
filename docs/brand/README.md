# Brand assets

`source/` holds the four AI-drafted originals (2026-10-10). Everything shipped is derived from
them by `process.py`; edit the script, not the outputs.

| Source | Becomes | Where it ships |
| --- | --- | --- |
| `app-icon.jpg` | 1024 full-bleed iOS icon (corners rebuilt, rim removed, padded, upscaled), macOS squircle set, `BETA` band variant, favicons, PWA icons | `aaru-ios/Aaru/Assets.xcassets/AppIcon*`, `aaru-client/static/` |
| `mascot.jpg` | Bird only (the stacked logo above it is dropped), feathered edge; always shown clipped to a paper disc | `Mascot` image set, `aaru-client/src/lib/assets/brand/mascot*.webp`, `og.jpg` |
| `wordmark.jpg` | Transparent wordmark | `Wordmark` image set, landing nav |
| `reed-lockup.jpg` | Transparent reed + reflection mark (type dropped) | `ReedMark` image set, landing bento and footer |

Run (needs Pillow, NumPy, SciPy; writes to `out/`, which is not committed):

```bash
cd docs/brand && python3 -m venv .venv && .venv/bin/pip install pillow numpy scipy
.venv/bin/python process.py
```

Then copy `out/AppIcon*.appiconset/*.png` into the asset catalog, `out/web/*` into
`aaru-client/static/`, and convert the logos to WebP with `cwebp`.

Known limits: the sources are 784–1168 px JPEGs, so the 1024 icon is a 1.3× upscale and the
mascot tops out at 1440 px wide. Ask for 2048 px PNG masters before the App Store release.
The three sources also use three different "Aaru" letterforms; the app uses `wordmark.jpg`'s.
