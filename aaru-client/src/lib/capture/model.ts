import type { components } from '../api/schema'

// AG-006 on the web: what the composer sends, and how a capture's plan reads on Home.

type ImportJob = components['schemas']['ImportJob']

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
  const { created, updated, unmatched } = job.stats
  const adds = created + updated
  const parts = [
    adds > 0 ? `Add ${adds}` : null,
    unmatched === 1 ? '1 needs a pick' : null,
    unmatched > 1 ? `${unmatched} need a pick` : null,
  ].filter((part) => part !== null)
  return parts.length > 0 ? parts.join(' · ') : 'Already in your library'
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
