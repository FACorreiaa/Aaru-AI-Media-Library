import type { components } from '../api/schema'
import { entryDay, localDayKey } from '../calendar/model'
import type { CalendarEntry } from '../calendar/model'
import { hitKey, idKeys, statusLabel } from '../library/model'
import type { LibraryEntry, LibraryStatus } from '../library/model'
import type { Stats } from '../recap/model'

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

/**
 * Home's "this month" strip: episodes · hours · finished · active days, each left out at zero.
 * Empty when nothing was tracked, and then the strip is not shown.
 */
export function monthStrip(stats: Stats): string[] {
  const t = stats.totals
  const finished =
    t.moviesFinished + t.showsFinished + t.animeFinished + t.booksFinished
  const parts: string[] = []
  if (t.episodesWatched > 0) parts.push(plural(t.episodesWatched, 'episode'))
  if (t.minutesWatched > 0) parts.push(hoursLabel(t.minutesWatched))
  if (finished > 0) parts.push(`${finished} finished`)
  if (t.activeDays > 0) parts.push(plural(t.activeDays, 'active day'))
  return parts
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
