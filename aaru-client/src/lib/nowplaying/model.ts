import type { components } from '../api/schema'
import { runtimeLabel } from '../home/model'

// SCR-008 and SCR-009 on the web: everything players are playing now, as Home's
// `NowPlayingCard` shows it. Library episodes and films from Stremio or the browser extension,
// YouTube videos and music tracks: at most three, in the server's order, which is the order on
// the page. Players report only on start, pause and stop, so a position is worked out here from
// the last report: while playing, the time since it is added.

export type NowPlaying = components['schemas']['NowPlaying']
export type NowPlayingItem = components['schemas']['NowPlayingItem']
export type NowPlayingKind = NowPlayingItem['kind']

/** What the clock needs from a report: an item, or SCR-008's one session. */
type Report = Pick<
  NowPlayingItem,
  'state' | 'positionMs' | 'durationMs' | 'updatedAt'
>

/** How often Home asks again while the tab is visible. */
export const NOW_PLAYING_POLL_MS = 30_000

/** The most the server sends (`NowPlayingReply.items`). */
const MAX_ITEMS = 3

const SOURCES: Record<NowPlayingItem['source'], string> = {
  stremio: 'Stremio',
  netflix: 'Netflix',
  disney_plus: 'Disney+',
  prime_video: 'Prime Video',
  listenbrainz: 'ListenBrainz',
  youtube: 'YouTube',
}

export function sourceLabel(source: NowPlayingItem['source']): string {
  return SOURCES[source]
}

/**
 * The reply as Home shows it: `items` as the server ordered them. An API older than SCR-009
 * sends only `nowPlaying`, which becomes the one item.
 */
export function playingItems(reply: {
  items?: NowPlayingItem[]
  nowPlaying?: NowPlaying
}): NowPlayingItem[] {
  if (reply.items) return reply.items.slice(0, MAX_ITEMS)
  return reply.nowPlaying ? [fromNowPlaying(reply.nowPlaying)] : []
}

/** SCR-008's one session, in SCR-009's shape. */
export function fromNowPlaying(playing: NowPlaying): NowPlayingItem {
  return {
    id: playing.watchEventId,
    kind: playing.episode ? 'episode' : 'movie',
    name: playing.title.title,
    subtitle: episodeLine(playing) ?? undefined,
    service: sourceLabel(playing.source),
    source: playing.source,
    state: playing.state,
    positionMs: playing.positionMs,
    durationMs: playing.durationMs,
    updatedAt: playing.updatedAt,
    artworkUrl: playing.title.posterUrl,
    libraryItemId: playing.libraryItemId,
    title: playing.title,
    episode: playing.episode,
  }
}

/** The library items playing: Tonight and Continue watching leave every one of them out. */
export function playingLibraryItems(
  items: readonly NowPlayingItem[],
): ReadonlySet<string> {
  return new Set(
    items.flatMap((item) => (item.libraryItemId ? [item.libraryItemId] : [])),
  )
}

/**
 * Whether a library episode or film stopped between two polls (its stop may have ticked the
 * episode, so Continue watching moves on). A track or video ending changes nothing there.
 */
export function libraryPlayEnded(
  before: readonly NowPlayingItem[],
  after: readonly NowPlayingItem[],
): boolean {
  const still = new Set(after.map((item) => item.id))
  return before.some((item) => !!item.libraryItemId && !still.has(item.id))
}

/** Where it plays, as a person reads it: the server's "YouTube Music", else the source. */
export function serviceLabel(item: NowPlayingItem): string {
  return item.service ?? sourceLabel(item.source)
}

/** Where the player is at `now`: frozen while paused, capped at the end while playing. */
export function livePositionMs(playing: Report, now: Date): number {
  if (playing.state === 'paused') return playing.positionMs
  const since = Math.max(0, now.getTime() - Date.parse(playing.updatedAt))
  const position = playing.positionMs + since
  return playing.durationMs > 0
    ? Math.min(position, playing.durationMs)
    : position
}

/** 0…1, or null while no duration is known. */
export function progress(playing: Report, now: Date): number | null {
  if (playing.durationMs <= 0) return null
  return livePositionMs(playing, now) / playing.durationMs
}

/** Whole minutes left, rounded up so the last seconds still read "1m left"; null unknown. */
export function minutesLeft(playing: Report, now: Date): number | null {
  if (playing.durationMs <= 0) return null
  const left = playing.durationMs - livePositionMs(playing, now)
  return Math.max(0, Math.ceil(left / 60_000))
}

/** "Now playing · Stremio", or "Paused · YouTube Music". */
export function eyebrow(item: NowPlayingItem): string {
  const state = item.state === 'paused' ? 'Paused' : 'Now playing'
  return `${state} · ${serviceLabel(item)}`
}

/** A compact row's second line: "S1 · E8 · Lanterns · Stremio", "Burial · YouTube Music". */
export function itemLine(item: NowPlayingItem): string {
  return [item.subtitle, serviceLabel(item)].filter(Boolean).join(' · ')
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
  playing: Report,
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
