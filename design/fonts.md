# Fonts

Aaru's display face is **Newsreader** (Production Type, SIL Open Font License 1.1; the licence
ships next to the files as `OFL.txt`). Body and interface text stay the system sans on every
platform. Source: `ofl/newsreader/` in github.com/google/fonts (`Newsreader[opsz,wght].ttf` and
`Newsreader-Italic[opsz,wght].ttf`).

| Client | Files | Cut |
| --- | --- | --- |
| Web | `aaru-client/public/fonts/newsreader-{roman,italic}{,-ext}.woff2` | variable, weight 450–600, optical size pinned at 36; Latin and Latin Extended split by `unicode-range` |
| Apple | `aaru-ios/Aaru/Fonts/Newsreader-{Medium,SemiBold,MediumItalic}.ttf` | static: Medium 500 at opsz 24, SemiBold 600 at opsz 36, Medium Italic 500 at opsz 24; Latin + Latin Extended |

The web roman Latin file is about 35 KB. Headings use weights 500–600 and sizes of 18 px and up,
so the optical-size axis and the light and heavy masters are dropped.

## Recipe

With `fonttools` and `brotli` in a throwaway venv:

```sh
LATIN="U+0020-007E,U+00A0-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2013-2014,U+2018-201A,U+201C-201E,U+2022,U+2026,U+2032-2033,U+20AC,U+2122"
EXT="U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,U+20AD-20C4,U+2113,U+2C60-2C7F,U+A720-A7FF"

# Web (repeat for the italic)
fonttools varLib.instancer 'Newsreader[opsz,wght].ttf' wght=450:600 opsz=36 -o roman-w.ttf
pyftsubset roman-w.ttf --unicodes="$LATIN" --flavor=woff2 --layout-features='kern,liga,lnum,tnum' \
  --no-hinting --desubroutinize --output-file=newsreader-roman.woff2
pyftsubset roman-w.ttf --unicodes="$EXT" --flavor=woff2 --layout-features='kern,liga,lnum,tnum' \
  --no-hinting --desubroutinize --output-file=newsreader-roman-ext.woff2

# Apple: one static instance per weight, then set the name table so the PostScript names are
# Newsreader-Medium / Newsreader-SemiBold / Newsreader-MediumItalic (AaruType.swift uses them)
fonttools varLib.instancer 'Newsreader[opsz,wght].ttf' wght=500 opsz=24 -o medium.ttf
pyftsubset medium.ttf --unicodes="$LATIN,$EXT" --layout-features='*' --output-file=Newsreader-Medium.ttf
```
