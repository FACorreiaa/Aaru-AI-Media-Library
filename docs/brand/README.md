# Brand assets

`source/` holds the four AI-drafted originals (2026-10-10). Everything shipped is derived from
them by `process.py`; edit the script, not the outputs.

| Source | Becomes | Where it ships |
| --- | --- | --- |
| `icon_reeds.py` (variant A, chosen 2026-10-10) | The app icon: five cattail reeds of uneven height, like spines on a shelf, in front of a half sun on the Field of Reeds horizon. Flat vector shapes drawn at 4096 px. `install_icon.py` builds the iOS icon, macOS squircle set, `BETA` band variant, favicons and PWA icons | `aaru-ios/Aaru/Assets.xcassets/AppIcon*`, `aaru-client/static/`, landing `app-icon.webp` |
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
into the asset catalog and `out/icon/web/*` into `aaru-client/static/`. `icon_reeds.py` alone
renders all three concepts plus a comparison sheet. For the logos and mascot, copy from `out/`
and convert to WebP with `cwebp`.

Known limits: the sources are 784–1168 px JPEGs, so the mascot tops out at 1440 px wide. Ask for 2048 px PNG masters before the App Store release.
The three sources also use three different "Aaru" letterforms; the app uses `wordmark.jpg`'s.
