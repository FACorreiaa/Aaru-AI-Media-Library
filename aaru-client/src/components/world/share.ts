import { countLabel, laneLabel } from '../../lib/title/world'
import type { World } from '../../lib/title/world'
import { COLORS } from '../../lib/tokens.gen'

// GRAPH-007: `WorldShareCard`, the viewer's path through a World as an image drawn on a canvas in
// their browser: the World's name, their count, and a row of dots per lane, filled where they
// have finished. Text and brand colours only (catalog posters are cross-origin and would taint
// the canvas). Nothing is uploaded and no link carries it. The Apple app draws the same card.

const WIDTH = 1080
const HEIGHT = 1350
const MARGIN = 96
/** Dots a lane shows before it says how many more. */
const MAX_DOTS = 12

export async function drawWorldImage(world: World): Promise<Blob> {
  const canvas = document.createElement('canvas')
  canvas.width = WIDTH
  canvas.height = HEIGHT
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('This browser cannot draw the share image.')
  const ink = COLORS.ink.dark
  const accent = COLORS.accent.dark
  const paper = COLORS.onAccent.dark
  const sans = 'system-ui, -apple-system, sans-serif'

  const gradient = ctx.createLinearGradient(0, 0, WIDTH, HEIGHT)
  gradient.addColorStop(0, accent)
  gradient.addColorStop(1, ink)
  ctx.fillStyle = gradient
  ctx.fillRect(0, 0, WIDTH, HEIGHT)

  ctx.fillStyle = paper
  ctx.strokeStyle = paper
  ctx.textBaseline = 'alphabetic'
  ctx.font = `500 40px ${sans}`
  ctx.fillText('MY PATH THROUGH', MARGIN, 160)

  // The name steps down until it fits on one line.
  const name = world.name ?? ''
  let nameSize = 120
  do {
    ctx.font = `500 ${nameSize}px ${sans}`
    nameSize -= 8
  } while (ctx.measureText(name).width > WIDTH - MARGIN * 2 && nameSize > 48)
  ctx.fillText(name, MARGIN, 310)

  ctx.globalAlpha = 0.9
  ctx.font = `500 72px ${sans}`
  ctx.fillText(countLabel(world.finished, world.total), MARGIN, 420)
  ctx.globalAlpha = 1

  // Six lanes still fit: they step down a size past four.
  const compact = world.lanes.length > 4
  const [labelSize, dot, gap] = compact ? [34, 40, 36] : [40, 48, 52]
  let y = 560
  for (const lane of world.lanes) {
    ctx.globalAlpha = 0.8
    ctx.font = `500 ${labelSize}px ${sans}`
    ctx.fillText(laneLabel(lane.kind), MARGIN, y)
    ctx.globalAlpha = 1
    const shown = lane.titles.slice(0, MAX_DOTS)
    const cy = y + 18 + dot / 2
    shown.forEach((title, i) => {
      const cx = MARGIN + dot / 2 + i * dot * 1.4
      ctx.beginPath()
      ctx.arc(cx, cy, dot / 2 - 2, 0, Math.PI * 2)
      ctx.lineWidth = 4
      ctx.stroke()
      if (title.status === 'finished') ctx.fill()
    })
    const more = lane.titles.length - shown.length
    if (more > 0) {
      ctx.font = `500 ${Math.round(dot * 0.8)}px ${sans}`
      ctx.fillText(
        `+${more}`,
        MARGIN + shown.length * dot * 1.4,
        cy + dot * 0.28,
      )
    }
    y += labelSize + 18 + dot + gap
  }

  ctx.font = `600 44px ${sans}`
  ctx.fillText('Aaru', MARGIN, HEIGHT - MARGIN)
  ctx.globalAlpha = 0.75
  ctx.font = `400 32px ${sans}`
  ctx.fillText(
    'aaruapp.com',
    WIDTH - MARGIN - ctx.measureText('aaruapp.com').width,
    HEIGHT - MARGIN,
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

/** The system share sheet where files can be shared, a download everywhere else. */
export async function shareWorld(
  world: World,
): Promise<'shared' | 'downloaded'> {
  const blob = await drawWorldImage(world)
  const slug = (world.name ?? 'world')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
  const name = `aaru-world-${slug || 'world'}.png`
  const file = new File([blob], name, { type: 'image/png' })
  // Firefox and older desktops have no `canShare`.
  if ('canShare' in navigator && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({
        files: [file],
        title: `My path through ${world.name ?? 'a world'}`,
      })
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
