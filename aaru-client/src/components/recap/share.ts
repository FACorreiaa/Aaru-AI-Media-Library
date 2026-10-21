import { shareLines } from '../../lib/recap/deck'
import { periodLabel } from '../../lib/recap/model'
import type { Stats } from '../../lib/recap/model'
import { COLORS } from '../../lib/tokens.gen'

// GAM-006a: the Recap's share image, drawn on a canvas from the user's own numbers. Text and
// brand colours only: catalog posters are cross-origin and would taint the canvas.

const WIDTH = 1080
const HEIGHT = 1350

function token(name: string, fallback: string): string {
  const value = getComputedStyle(document.documentElement)
    .getPropertyValue(name)
    .trim()
  return value || fallback
}

export async function drawShareImage(stats: Stats): Promise<Blob> {
  const canvas = document.createElement('canvas')
  canvas.width = WIDTH
  canvas.height = HEIGHT
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('This browser cannot draw the share image.')
  const ink = token('--ink', COLORS.ink.light)
  const accent = token('--accent', COLORS.accent.light)
  const paper = token('--on-accent', COLORS.onAccent.light)
  const display =
    "Newsreader, ui-serif, 'New York', 'Iowan Old Style', Georgia, serif"
  // A canvas draws with whatever face is ready; wait for the display face (both weights the
  // card uses) so the image is never the fallback serif. A failed load keeps the fallback.
  await Promise.all(
    ['500 132px Newsreader', '600 44px Newsreader'].map((font) =>
      document.fonts.load(font).catch(() => []),
    ),
  )
  const sans = 'system-ui, -apple-system, sans-serif'

  const gradient = ctx.createLinearGradient(0, 0, WIDTH, HEIGHT)
  gradient.addColorStop(0, accent)
  gradient.addColorStop(1, ink)
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, WIDTH, HEIGHT)

  ctx.fillStyle = paper
  ctx.textBaseline = 'alphabetic'
  ctx.font = `500 40px ${sans}`
  ctx.fillText('MY RECAP', 96, 160)
  ctx.font = `500 132px ${display}`
  ctx.fillText(periodLabel({ year: stats.year, month: stats.month }), 96, 320)

  let y = 500
  const lines = shareLines(stats)
  // A year review can carry seven lines; they step down a size so the footer stays clear.
  const [size, leading, gap] = lines.length > 5 ? [52, 62, 28] : [64, 76, 40]
  for (const line of lines) {
    ctx.font = `500 ${size}px ${display}`
    // Next line: one line's leading, plus a gap between lines.
    y = wrap(ctx, line, 96, y, WIDTH - 192, leading) + leading + gap
  }

  ctx.font = `600 44px ${display}`
  ctx.fillText('Aaru', 96, HEIGHT - 96)
  ctx.globalAlpha = 0.75
  ctx.font = `400 32px ${sans}`
  ctx.fillText(
    'aaruapp.com',
    WIDTH - 96 - ctx.measureText('aaruapp.com').width,
    HEIGHT - 96,
  )
  ctx.globalAlpha = 1

  return new Promise((resolve, reject) =>
    canvas.toBlob(
      (blob) =>
        blob
          ? resolve(blob)
          : reject(new Error('The image could not be made.')),
      'image/png',
    ),
  )
}

/** Draws `text` word-wrapped from `y`; returns the last baseline. */
function wrap(
  ctx: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  width: number,
  leading: number,
): number {
  let line = ''
  for (const word of text.split(' ')) {
    const next = line ? `${line} ${word}` : word
    if (line && ctx.measureText(next).width > width) {
      ctx.fillText(line, x, y)
      line = word
      y += leading
    } else {
      line = next
    }
  }
  ctx.fillText(line, x, y)
  return y
}

/** The system share sheet where files can be shared, a download everywhere else. */
export async function shareRecap(
  stats: Stats,
): Promise<'shared' | 'downloaded'> {
  const blob = await drawShareImage(stats)
  const name = `aaru-recap-${stats.year}${stats.month ? `-${String(stats.month).padStart(2, '0')}` : ''}.png`
  const file = new File([blob], name, { type: 'image/png' })
  // Firefox and older desktops have no `canShare`.
  if ('canShare' in navigator && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file], title: 'My Aaru recap' })
      return 'shared'
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError')
        return 'shared'
    }
  }
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = name
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
  return 'downloaded'
}
