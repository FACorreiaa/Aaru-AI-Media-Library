import type { components } from '../api/schema'

// AG-006 on the web: what the composer sends, and how a capture's plan reads on Home.

type ImportJob = components['schemas']['ImportJob']

/** What one capture sends at most; the server holds the same limit. */
export const MAX_CAPTURE_PICTURES = 5

/** A piece of a picture, in its pixels. */
export type Slice = { top: number; height: number }

/**
 * Where to cut a picture of this size: whole up to 12:5, else pieces of 11:5 with a tenth of a
 * piece shared, so a line cut at one edge is whole in the next. Shrunk whole, a tall scrolling
 * screenshot would be too narrow to read (BOOK-002).
 */
export function captureSlices(width: number, height: number): Slice[] {
  if (width <= 0 || height * 5 <= width * 12) return [{ top: 0, height }]
  const piece = Math.floor((width * 11) / 5)
  const overlap = Math.floor(piece / 10)
  const step = piece - overlap
  const slices: Slice[] = []
  for (let top = 0; top < height - overlap; top += step)
    slices.push({ top, height: Math.min(piece, height - top) })
  return slices
}

/** What one capture sends: a link alone is a link, anything else typed is text. */
export type CaptureSend = { url: string } | { text: string }

/** A message that is one link and nothing else goes as a link; the server never opens it. */
export function captureSend(typed: string): CaptureSend | null {
  const text = typed.trim()
  if (text.length === 0) return null
  return /^https?:\/\/\S+$/i.test(text) ? { url: text } : { text }
}

/** The plan card's line: "Add 7 · 2 need a pick". Null while it is still being read. */
export function captureHeadline(job: ImportJob): string | null {
  if (job.state !== 'planned') return null
  const { created, updated, unmatched, skipped } = job.stats
  const adds = created + updated
  const parts = [
    adds > 0 ? `Add ${adds}` : null,
    unmatched === 1 ? '1 needs a pick' : null,
    unmatched > 1 ? `${unmatched} need a pick` : null,
  ].filter((part) => part !== null)
  if (parts.length > 0) return parts.join(' · ')
  return skipped > 0 ? 'Already in your library' : 'Nothing chosen'
}

/** Captures that still want the user: being read, or a plan to approve. */
export const waitingCaptures = (jobs: ImportJob[]) =>
  jobs.filter(
    (job) =>
      job.source === 'capture' &&
      (job.state === 'queued' ||
        job.state === 'running' ||
        job.state === 'planned'),
  )
