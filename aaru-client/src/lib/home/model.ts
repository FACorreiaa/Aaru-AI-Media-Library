import type { components } from '../api/schema'
import { entryDay, localDayKey } from '../calendar/model'
import type { CalendarEntry } from '../calendar/model'
import { hitKey, idKeys, kindOf, statusLabel } from '../library/model'
import type { LibraryEntry, LibraryStatus } from '../library/model'
import type { Stats } from '../recap/model'
import { episodeCode } from '../title/model'

// APP-009: the Home rows' pure parts (Trakt-style Continue watching, Start watching, and the
// next airings). Labels and the calendar row's day maths are computed in the browser: the
// Worker runs in UTC and must not decide what "today" is for the viewer.

export type ContinueEntry = components['schemas']['ContinueEntry']
export type StartEntry = components['schemas']['StartEntry']
export type UpNext = components['schemas']['UpNext']
export type LibraryCounts = components['schemas']['LibraryCounts']
export type UnfinishedEntry = components['schemas']['UnfinishedEntry']
export type DiscoverRow = components['schemas']['DiscoverRow']

const HOUR_MS = 3_600_000
/** Closer than this, an exactly-timed airing reads "In 3 hours" rather than a day. */
const HOURS_HORIZON = 12
/** How many airings the calendar row shows before "See calendar". */
export const AIRING_LIMIT = 12
/** Days of airings the row asks for. */
export const AIRING_DAYS = 14
/** How many Continue watching cards Home shows before "All N". */
export const CONTINUE_LIMIT = 12
/** How many Discover rows Home shows; the rest wait on Discover. */
export const HOME_DISCOVER_ROWS = 3

/** "57m", "1h 27m", "2h". Empty for an unknown or zero runtime. */
export function runtimeLabel(minutes?: number | null): string {
  if (!minutes || minutes <= 0) return ''
  const h = Math.floor(minutes / 60)
  const m = Math.round(minutes % 60)
  if (h === 0) return `${m}m`
  return m === 0 ? `${h}h` : `${h}h ${m}m`
}

/** "10 left · 8h 40m": what remains of an in-progress show. */
export function remainingLabel(count: number, minutes: number): string {
  const time = runtimeLabel(minutes)
  return time ? `${count} left · ${time}` : `${count} left`
}

/** "S1 · E8 · Episode name", the line under a Continue watching card. */
export function nextLine(entry: ContinueEntry): string {
  return [`S${entry.next.season}`, `E${entry.next.number}`, entry.nextName]
    .filter(Boolean)
    .join(' · ')
}

/** The day difference between two "YYYY-MM-DD" keys (b − a), DST-proof. */
function daysBetween(a: string, b: string): number {
  return Math.round(
    (Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / 86_400_000,
  )
}

/**
 * The calendar row's badge: "In 3 hours" for an exact time within the next twelve hours,
 * otherwise by day — "Today · New", "Tomorrow", "In 2 days". Date-only air dates never get
 * hours. Null for an airing before today.
 */
export function airingBadge(
  entry: Pick<CalendarEntry, 'airsAt' | 'airTimeKnown'>,
  now: Date,
  timeZone?: string,
): string | null {
  if (entry.airTimeKnown) {
    const ahead = Date.parse(entry.airsAt) - now.getTime()
    if (ahead > 0 && ahead < HOURS_HORIZON * HOUR_MS) {
      const hours = Math.round(ahead / HOUR_MS)
      if (hours < 1) return 'Within the hour'
      return hours === 1 ? 'In 1 hour' : `In ${hours} hours`
    }
  }
  const days = daysBetween(
    localDayKey(now, timeZone),
    entryDay(entry, timeZone),
  )
  if (days < 0) return null
  if (days === 0) return 'Today · New'
  if (days === 1) return 'Tomorrow'
  return `In ${days} days`
}

/** The airings to show from today on, soonest first. A date-only airing sorts as the start of
 * its day, before that day's timed ones. */
export function upcoming(
  entries: CalendarEntry[],
  now: Date,
  timeZone?: string,
  limit = AIRING_LIMIT,
): CalendarEntry[] {
  const today = localDayKey(now, timeZone)
  const sortKey = (e: CalendarEntry) =>
    `${entryDay(e, timeZone)} ${e.airTimeKnown ? e.airsAt : ''}`
  return entries
    .filter((e) => entryDay(e, timeZone) >= today)
    .sort((a, b) =>
      sortKey(a) < sortKey(b) ? -1 : sortKey(a) > sortKey(b) ? 1 : 0,
    )
    .slice(0, limit)
}

/**
 * The optimistic Continue watching row after ticking a show's next episode: the card moves to
 * the following episode of the same season (the refetch corrects season breaks and names), and
 * a show with nothing left drops out.
 */
export function advance(
  rows: ContinueEntry[],
  target: ContinueEntry,
): ContinueEntry[] {
  return rows.flatMap((row) => {
    if (row.libraryItemId !== target.libraryItemId) return [row]
    if (row.remainingCount <= 1) return []
    return [
      {
        ...row,
        next: { season: row.next.season, number: row.next.number + 1 },
        nextName: undefined,
        remainingCount: row.remainingCount - 1,
        remainingMinutes: Math.max(
          0,
          row.remainingMinutes - (row.nextRuntimeMinutes ?? 0),
        ),
        isFinale: false,
      },
    ]
  })
}

function plural(count: number, one: string, many = `${one}s`): string {
  return `${count} ${count === 1 ? one : many}`
}

/** "45 min" under an hour, then whole hours: "1 hour", "9 hours". */
export function hoursLabel(minutes: number): string {
  if (minutes < 60) return `${minutes} min`
  return plural(Math.round(minutes / 60), 'hour')
}

export interface WeekStrip {
  /** Episodes · hours · finished · active days, each left out at zero. */
  parts: string[]
  /** The same four, always all four, as number over word for the wide strip. */
  figures: { value: string; label: string }[]
  /** Seven heights, 0…1 of the busiest day by time, oldest first. */
  days: number[]
  /** Each day's initial ("M", "T"…), under its bar. */
  dayLabels: string[]
}

/** "45m" under an hour, then whole hours: "43h". */
function shortHours(minutes: number): string {
  return minutes < 60 ? `${minutes}m` : `${Math.round(minutes / 60)}h`
}

/**
 * GAM-006d: Home's "last 7 days" strip from `span=last7`. Shown at zero too, so a new account
 * sees where its week will land; `parts` is empty then.
 */
export function weekStrip(stats: Stats, locale?: string): WeekStrip {
  const t = stats.totals
  const manga = t.mangaFinished ?? 0
  const read = t.booksFinished + manga
  const finished =
    t.moviesFinished + t.showsFinished + t.animeFinished + t.albumsFinished
  const days = {
    value: String(t.activeDays),
    label: t.activeDays === 1 ? 'active day' : 'active days',
  }
  const watched = t.episodesWatched > 0 || t.minutesWatched > 0
  // A week of reading and nothing watched says what was read, not "0 episodes".
  if (!watched && read > 0) {
    const figures = [
      {
        count: t.booksFinished,
        label: t.booksFinished === 1 ? 'book read' : 'books read',
      },
      { count: manga, label: 'manga read' },
      { count: finished, label: 'finished' },
    ]
      .filter((figure) => figure.count > 0)
      .map((figure) => ({ value: String(figure.count), label: figure.label }))
    return {
      ...weekBars(stats, locale),
      parts: [
        ...figures.map((figure) => `${figure.value} ${figure.label}`),
        ...(t.activeDays > 0 ? [plural(t.activeDays, 'active day')] : []),
      ],
      figures: [...figures, days],
    }
  }
  const all = finished + read
  const parts: string[] = []
  if (t.episodesWatched > 0) parts.push(plural(t.episodesWatched, 'episode'))
  if (t.minutesWatched > 0) parts.push(hoursLabel(t.minutesWatched))
  if (all > 0) parts.push(`${all} finished`)
  if (t.activeDays > 0) parts.push(plural(t.activeDays, 'active day'))
  const figures = [
    {
      value: String(t.episodesWatched),
      label: t.episodesWatched === 1 ? 'episode' : 'episodes',
    },
    { value: shortHours(t.minutesWatched), label: 'watched' },
    { value: String(all), label: 'finished' },
    days,
  ]
  return { ...weekBars(stats, locale), parts, figures }
}

/** The week's seven bars, by time, and their day letters. */
function weekBars(
  stats: Stats,
  locale?: string,
): Pick<WeekStrip, 'days' | 'dayLabels'> {
  const tallest = Math.max(1, ...stats.buckets.map((b) => b.minutes))
  const weekday = new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    weekday: 'narrow',
  })
  return {
    days: stats.buckets.map((b) => b.minutes / tallest),
    dayLabels: stats.buckets.map((b) =>
      weekday.format(new Date(`${b.start}T12:00:00Z`)),
    ),
  }
}

export interface CountChip {
  status: LibraryStatus
  label: string
  count: number
}

/** The shelf by status, in stored order, worded for a mixed shelf; empty statuses left out. */
export function countChips(counts: LibraryCounts | undefined): CountChip[] {
  if (!counts) return []
  const all: Array<[LibraryStatus, number]> = [
    ['wishlist', counts.wishlist],
    ['in_progress', counts.inProgress],
    ['on_hold', counts.onHold],
    ['finished', counts.finished],
    ['dropped', counts.dropped],
  ]
  return all
    .filter(([, count]) => count > 0)
    .map(([status, count]) => ({
      status,
      label: statusLabel(status, null),
      count,
    }))
}

const WEEK_MS = 7 * 86_400_000

/** Why an Unfinished business card is there: "Dropped", or "Paused 6 weeks" since the last
 * tick ("Paused 3 months" past eight weeks). */
export function unfinishedLabel(entry: UnfinishedEntry, now: Date): string {
  if (entry.reason === 'dropped') return 'Dropped'
  const elapsed = Math.max(0, now.getTime() - Date.parse(entry.since))
  const weeks = Math.max(1, Math.floor(elapsed / WEEK_MS))
  if (weeks <= 8) return `Paused ${plural(weeks, 'week')}`
  return `Paused ${plural(Math.round(elapsed / (30 * 86_400_000)), 'month')}`
}

/** "Resume at S2 · E3" when the next episode is known. */
export function resumeLine(entry: UnfinishedEntry): string | null {
  return entry.next
    ? `Resume at S${entry.next.season} · E${entry.next.number}`
    : null
}

/**
 * Home's few Discover rows: the first row of each kind the user keeps most, then more of those
 * kinds, then any row, up to `HOME_DISCOVER_ROWS`. The user's main kind leads. An empty library
 * takes the server's first rows.
 */
export function homeDiscover(
  rows: DiscoverRow[],
  entries: LibraryEntry[],
): DiscoverRow[] {
  const counts = new Map<string, number>()
  for (const entry of entries) {
    const kind = kindOf(entry.title.type, entry.title.isAnime)
    counts.set(kind, (counts.get(kind) ?? 0) + 1)
  }
  const kinds = [...counts.keys()].sort(
    (a, b) => (counts.get(b) ?? 0) - (counts.get(a) ?? 0),
  )
  const shown = rows.filter((row) => row.items.length > 0)
  const picked: DiscoverRow[] = []
  const pick = (row: DiscoverRow | undefined) => {
    if (row && picked.length < HOME_DISCOVER_ROWS && !picked.includes(row))
      picked.push(row)
  }
  for (const kind of kinds) pick(shown.find((row) => row.kind === kind))
  for (const row of shown) if (counts.has(row.kind)) pick(row)
  for (const row of shown) pick(row)
  return picked
}

/** DISC-001: after an add, every card for that title links to the new item. No refetch. */
export function markAdded(
  rows: DiscoverRow[],
  key: string,
  libraryItemId: string,
): DiscoverRow[] {
  return rows.map((row) => ({
    ...row,
    items: row.items.map((hit) =>
      hitKey(hit) === key ? { ...hit, libraryItemId } : hit,
    ),
  }))
}

/** After an add from Search, the Discover cards for that title link to the new entry too. */
export function markOnShelf(
  rows: DiscoverRow[],
  entry: LibraryEntry,
): DiscoverRow[] {
  const keys = new Set(idKeys(entry.title.ids))
  return rows.map((row) => ({
    ...row,
    items: row.items.map((hit) =>
      idKeys(hit.ids).some((key) => keys.has(key))
        ? { ...hit, libraryItemId: entry.id }
        : hit,
    ),
  }))
}

/** MUS-001: Home's Listening row. Albums in progress, the last one touched first. */
export function listening(entries: LibraryEntry[]): LibraryEntry[] {
  return entries
    .filter((e) => e.title.type === 'album' && e.status === 'in_progress')
    .sort((a, b) => b.updatedAt.localeCompare(a.updatedAt))
}

/** The Undo toast after a tick on Home: "Marked S1 · E3 of Blue Box", or the season. */
export function tickedMessage(
  name: string,
  season: number,
  episode?: number,
): string {
  return episode === undefined
    ? `Marked season ${season} of ${name}`
    : `Marked ${episodeCode(season, episode)} of ${name}`
}

/** The Undo toast after "Not tonight" or "Not for me", saying what it did. */
export function setAsideMessage(
  name: string,
  verdict: 'not_tonight' | 'rejected',
): string {
  return verdict === 'not_tonight'
    ? `${name} set aside for today`
    : `${name} ranked lower for 14 days`
}

/** A book or manga in progress: what the Reading row holds (owner, 2026-10-25). On hold stays
 * out, as it does from Now. Cheap, so Home can tell whether to load the row at all. */
export function isReading(entry: LibraryEntry): boolean {
  return (
    entry.status === 'in_progress' &&
    (entry.title.type === 'book' || entry.title.type === 'manga')
  )
}
