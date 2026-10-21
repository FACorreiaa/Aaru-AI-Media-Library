import type { components } from '../api/schema'
import { runtimeLabel } from '../home/model'

// SCR-008 on the web: what Stremio or the browser extension is playing now, as Home's
// `NowPlayingCard` shows it. Players report only on start, pause and stop, so the position is
// worked out here from the last report: while playing, the time since it is added.

export type NowPlaying = components['schemas']['NowPlaying']

/** How often Home asks again while the tab is visible. */
export const NOW_PLAYING_POLL_MS = 30_000

const SOURCES: Record<NowPlaying['source'], string> = {
  stremio: 'Stremio',
  netflix: 'Netflix',
  disney_plus: 'Disney+',
  prime_video: 'Prime Video',
}

export function sourceLabel(source: NowPlaying['source']): string {
  return SOURCES[source]
}

/** Where the player is at `now`: frozen while paused, capped at the end while playing. */
export function livePositionMs(playing: NowPlaying, now: Date): number {
  if (playing.state === 'paused') return playing.positionMs
  const since = Math.max(0, now.getTime() - Date.parse(playing.updatedAt))
  const position = playing.positionMs + since
  return playing.durationMs > 0
    ? Math.min(position, playing.durationMs)
    : position
}

/** 0…1, or null while no duration is known. */
export function progress(playing: NowPlaying, now: Date): number | null {
  if (playing.durationMs <= 0) return null
  return livePositionMs(playing, now) / playing.durationMs
}

/** Whole minutes left, rounded up so the last seconds still read "1m left"; null unknown. */
export function minutesLeft(playing: NowPlaying, now: Date): number | null {
  if (playing.durationMs <= 0) return null
  const left = playing.durationMs - livePositionMs(playing, now)
  return Math.max(0, Math.ceil(left / 60_000))
}

/** "Now playing · Stremio", or "Paused · Stremio". */
export function eyebrow(playing: NowPlaying): string {
  const state = playing.state === 'paused' ? 'Paused' : 'Now playing'
  return `${state} · ${sourceLabel(playing.source)}`
}

/** "S2 · E7 · To the Depths with You", or null for a film. */
export function episodeLine(playing: NowPlaying): string | null {
  if (!playing.episode) return null
  return [
    `S${playing.episode.season}`,
    `E${playing.episode.number}`,
    playing.episodeName,
  ]
    .filter(Boolean)
    .join(' · ')
}

/**
 * "17m left", or with `showEnd` "Ends at 10:12 PM" (DESIGN.md §15: a tap flips them). A pause
 * has no end time, so it always reads time left. Empty while no duration is known.
 */
export function timeLabel(
  playing: NowPlaying,
  now: Date,
  showEnd: boolean,
  locale?: string,
  timeZone?: string,
): string {
  const left = minutesLeft(playing, now)
  if (left === null) return ''
  if (left === 0) return 'Ending'
  if (!showEnd || playing.state === 'paused')
    return `${runtimeLabel(left)} left`
  const end = new Date(
    now.getTime() + playing.durationMs - livePositionMs(playing, now),
  )
  const time = new Intl.DateTimeFormat(locale, {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
  }).format(end)
  return `Ends at ${time}`
}
