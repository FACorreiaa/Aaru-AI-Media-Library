#!/usr/bin/env node
// Writes Aaru's design tokens from design/tokens.json to both clients:
//   aaru-client/src/tokens.css                       (web colours, light + dark + data-theme override,
//                                                     plus the motion and alpha scales)
//   aaru-client/src/tokens.theme.css                 (web: Tailwind @theme for radii and the easing)
//   aaru-client/src/lib/tokens.gen.ts                (values for script that cannot read CSS)
//   aaru-ios/Aaru/Assets.xcassets/<Name>.colorset    (app colours)
//   aaru-ios/AaruWidgets/WidgetAssets.xcassets/...   (widget extension colours)
//   aaru-ios/Aaru/Design/Tokens.gen.swift            (app: AaruRadius, AaruAlpha, AaruMotion, AaruSpace)
//   aaru-ios/AaruWidgets/Tokens.gen.swift            (widget extension: the same enums)
//   aaru-extension/src/entrypoints/popup/tokens.css  (browser extension popup, system scheme only)
//   aaru-extension/src/lib/tokens.gen.ts             (the extension's toolbar badge)
//   aaru-client/public/manifest.webmanifest          (its two colours)
// and fails when a contrast pair in the file is under its minimum.
//
//   node scripts/generate-tokens.mjs           write
//   node scripts/generate-tokens.mjs --check   write nothing; exit 1 if anything is stale
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const check = process.argv.includes('--check')
const tokens = JSON.parse(readFileSync(join(root, 'design/tokens.json'), 'utf8'))
const colors = tokens.colors

const hexToRgb = (hex) => {
  const m = /^#([0-9a-f]{6})$/i.exec(hex)
  if (!m) throw new Error(`not a #rrggbb colour: ${hex}`)
  const n = parseInt(m[1], 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

// One appearance of one token: { rgb: [r,g,b], alpha }.
function resolve(name, scheme) {
  const value = colors[name]?.[scheme]
  if (value === undefined) throw new Error(`unknown token ${name}.${scheme}`)
  if (typeof value === 'string') return { rgb: hexToRgb(value), alpha: 1 }
  return { rgb: resolve(value.of, scheme).rgb, alpha: value.alpha }
}

const luminance = ([r, g, b]) => {
  const lin = (c) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
  }
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
}

const contrast = (a, b) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (hi + 0.05) / (lo + 0.05)
}

// A translucent token is checked as the colour it becomes on top of the layer under it: a
// translucent background sits on paper, a translucent foreground sits on that background.
const over = ({ rgb, alpha }, under) => rgb.map((c, i) => Math.round(c * alpha + under[i] * (1 - alpha)))

const failures = []
for (const [fg, bg, min] of tokens.contrast.pairs) {
  for (const scheme of ['light', 'dark']) {
    const b = over(resolve(bg, scheme), resolve('paper', scheme).rgb)
    const f = over(resolve(fg, scheme), b)
    const ratio = contrast(f, b)
    if (ratio < min) {
      failures.push(`${scheme}: ${fg} on ${bg} is ${ratio.toFixed(2)}, needs ${min}`)
    }
  }
}
if (failures.length) {
  console.error(`Contrast below WCAG AA:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}

// Web ------------------------------------------------------------------------------------------

const cssValue = (name, scheme) => {
  const value = colors[name][scheme]
  if (typeof value === 'string') return value
  const [r, g, b] = resolve(value.of, scheme).rgb
  return `rgb(${r} ${g} ${b} / ${value.alpha})`
}

const block = (scheme, indent) =>
  Object.keys(colors)
    .map((name) => `${indent}--${name}: ${cssValue(name, scheme)};`)
    .join('\n')

// Scales -----------------------------------------------------------------------------------------

const { radius, alpha, motion, space } = tokens
const ease = /^cubic-bezier\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)$/.exec(motion.ease)
if (!ease) throw new Error(`motion.ease is not cubic-bezier(a, b, c, d): ${motion.ease}`)

// Plain variables for CSS and color-mix(); Tailwind's own namespaces are in the theme file.
const scalesBlock = (indent) =>
  [
    ...Object.entries(motion)
      .filter(([name]) => name !== 'ease' && !name.startsWith('$'))
      .map(([name, ms]) => `${indent}--motion-${name}: ${ms}ms;`),
    `${indent}--motion-ease: ${motion.ease};`,
    ...Object.entries(alpha)
      .filter(([name]) => !name.startsWith('$'))
      .map(([name, value]) => `${indent}--alpha-${name}: ${value};`),
  ].join('\n')

const radiusEntries = Object.entries(radius).filter(([name]) => !name.startsWith('$'))

// Tailwind reads these as `rounded-card`, `rounded-sm` (= thumb) … `rounded-xl` (= panel) and
// `ease-aaru`. Its default radius scale is replaced so every rounded-* class is one of Aaru's.
const themeCss = `/* Generated by scripts/generate-tokens.mjs from design/tokens.json. Do not edit. */
@theme {
${radiusEntries.map(([name, px]) => `  --radius-${name}: ${px}px;`).join('\n')}
  --radius-sm: ${radius.thumb}px;
  --radius-md: ${radius.row}px;
  --radius-lg: ${radius.field}px;
  --radius-xl: ${radius.panel}px;
  --ease-aaru: ${motion.ease};
}
`

const css = `/* Generated by scripts/generate-tokens.mjs from design/tokens.json. Do not edit. */
:root {
${block('light', '  ')}
${scalesBlock('  ')}
  color-scheme: light;
}

@media (prefers-color-scheme: dark) {
  :root:not([data-theme='light']) {
${block('dark', '    ')}
    color-scheme: dark;
  }
}

:root[data-theme='dark'] {
${block('dark', '  ')}
  color-scheme: dark;
}
`

// Values page script needs: the browser's theme-color follows the paper, and the share canvas
// and the landing's fixed brand art draw with the solid tokens.
const camel = (name) => name.replace(/-(\w)/g, (_, c) => c.toUpperCase())
const solid = Object.entries(colors).filter(([, value]) => typeof value.light === 'string')
const ts = `// Generated by scripts/generate-tokens.mjs from design/tokens.json. Do not edit.
export const PAPER = { light: '${colors.paper.light}', dark: '${colors.paper.dark}' } as const

/** Every solid colour token, for script that cannot read CSS variables. */
export const COLORS = {
${solid.map(([name, value]) => `  ${camel(name)}: { light: '${value.light}', dark: '${value.dark}' },`).join('\n')}
} as const

/** Corner radii in px. */
export const RADIUS = {
${radiusEntries.map(([name, px]) => `  ${name}: ${px},`).join('\n')}
} as const

/** Tint steps of a token over a surface. */
export const ALPHA = {
${Object.entries(alpha)
  .filter(([name]) => !name.startsWith('$'))
  .map(([name, value]) => `  ${name}: ${value},`)
  .join('\n')}
} as const

/** Durations in ms and the one ease-out curve as a bezier, for motion/mini (CSS has --motion-*). */
export const MOTION = {
${Object.entries(motion)
  .filter(([name]) => !name.startsWith('$') && name !== 'ease')
  .map(([name, value]) => `  ${name}: ${value},`)
  .join('\n')}
  easeBezier: [${ease.slice(1).join(', ')}],
} as const
`

// The browser extension's popup follows the system scheme; it has no appearance setting. It has
// no Tailwind either, so the radii are plain variables there.
const extensionCss = `/* Generated by scripts/generate-tokens.mjs from design/tokens.json. Do not edit. */
:root {
${block('light', '  ')}
${scalesBlock('  ')}
${radiusEntries.map(([name, px]) => `  --radius-${name}: ${px}px;`).join('\n')}
  color-scheme: light dark;
}

@media (prefers-color-scheme: dark) {
  :root {
${block('dark', '    ')}
  }
}
`

// Apple ----------------------------------------------------------------------------------------

const component = (c) => (c / 255).toFixed(3)

const appleColor = (name, scheme) => {
  const { rgb, alpha } = resolve(name, scheme)
  return {
    color: {
      'color-space': 'srgb',
      components: {
        alpha: alpha.toFixed(3),
        red: component(rgb[0]),
        green: component(rgb[1]),
        blue: component(rgb[2]),
      },
    },
    idiom: 'universal',
  }
}

const colorset = (name) =>
  `${JSON.stringify(
    {
      colors: [
        appleColor(name, 'light'),
        {
          ...appleColor(name, 'dark'),
          appearances: [{ appearance: 'luminosity', value: 'dark' }],
        },
      ],
      info: { author: 'xcode', version: 1 },
    },
    null,
    2,
  )}\n`

// The scales as Swift. One copy per target: the app and the widget extension are separate
// modules, and both folders are synchronized groups, so no project file changes.
const swiftLines = (entries, type, suffix = '') =>
  entries
    .filter(([name]) => !name.startsWith('$'))
    .map(([name, value]) => `    static let ${name}: ${type} = ${value}${suffix}`)
    .join('\n')
const swift = `// Generated by scripts/generate-tokens.mjs from design/tokens.json. Do not edit.
import SwiftUI

/// Corner radii (DESIGN.md "Mindspace"). Always \`.rect(cornerRadius:style: .continuous)\`.
enum AaruRadius {
${swiftLines(radiusEntries, 'CGFloat')}
}

/// The only tint steps of a token over a surface: \`Color(.accent).opacity(AaruAlpha.tint)\`.
enum AaruAlpha {
${swiftLines(Object.entries(alpha), 'Double')}
}

/// Durations and the one ease-out curve every client shares. Entrances only.
enum AaruMotion {
${swiftLines(
  Object.entries(motion).filter(([name]) => name !== 'ease'),
  'TimeInterval',
  ' / 1000',
)}

    /// \`${motion.ease}\`.
    static func ease(_ duration: TimeInterval = base) -> Animation {
        .timingCurve(${ease.slice(1).join(', ')}, duration: duration)
    }
}

/// The 4 pt spacing grid.
enum AaruSpace {
${swiftLines(Object.entries(space), 'CGFloat')}
}
`

// The PWA manifest cannot read CSS variables. Its two colours are the dark paper (the art is
// dark-first; an installed app's splash is one colour for both appearances), written here so the
// brand guard can refuse any other literal under aaru-client/public.
const manifestPath = 'aaru-client/public/manifest.webmanifest'
const manifest = JSON.parse(readFileSync(join(root, manifestPath), 'utf8'))
manifest.background_color = colors.paper.dark
manifest.theme_color = colors.paper.dark
const manifestJson = `${JSON.stringify(manifest, null, 2)}\n`

// Outputs ----------------------------------------------------------------------------------------

const outputs = [
  ['aaru-client/src/tokens.css', css],
  ['aaru-client/src/tokens.theme.css', themeCss],
  ['aaru-client/src/lib/tokens.gen.ts', ts],
  ['aaru-extension/src/entrypoints/popup/tokens.css', extensionCss],
  ['aaru-extension/src/lib/tokens.gen.ts', ts],
  ['aaru-ios/Aaru/Design/Tokens.gen.swift', swift],
  ['aaru-ios/AaruWidgets/Tokens.gen.swift', swift],
  [manifestPath, manifestJson],
]
const catalogs = {
  apple: 'aaru-ios/Aaru/Assets.xcassets',
  widget: 'aaru-ios/AaruWidgets/WidgetAssets.xcassets',
}
for (const [name, token] of Object.entries(colors)) {
  for (const [key, catalog] of Object.entries(catalogs)) {
    for (const set of token[key] ?? []) {
      outputs.push([`${catalog}/${set}.colorset/Contents.json`, colorset(name)])
    }
  }
}

const stale = []
for (const [path, content] of outputs) {
  const file = join(root, path)
  const current = existsSync(file) ? readFileSync(file, 'utf8') : null
  if (current === content) continue
  stale.push(path)
  if (!check) {
    mkdirSync(dirname(file), { recursive: true })
    writeFileSync(file, content)
  }
}

if (check && stale.length) {
  console.error(
    `Tokens are stale. Run node scripts/generate-tokens.mjs and commit:\n  ${stale.join('\n  ')}`,
  )
  process.exit(1)
}
console.log(
  check ? 'Tokens up to date.' : `Wrote ${stale.length} of ${outputs.length} files.`,
)
