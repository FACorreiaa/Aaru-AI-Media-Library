import type { components } from '../api/schema'
import { entryDay, localDayKey } from '../calendar/model'
import type { CalendarEntry } from '../calendar/model'
import { hitKey } from '../library/model'

// APP-009: the Home rows' pure parts (Trakt-style Continue watching, Start watching, and the
// next airings). Labels and the calendar row's day maths are computed in the browser: the
// Worker runs in UTC and must not decide what "today" is for the viewer.

export type ContinueEntry = components['schemas']['ContinueEntry']
export type StartEntry = components['schemas']['StartEntry']
export type UpNext = components['schemas']['UpNext']
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
  entry: CalendarEntry,
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
