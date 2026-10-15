import type { components } from '../api/schema'

// APP-010: the calendar's pure parts (week grid and month view). Days are local calendar dates
// as "YYYY-MM-DD" keys, computed in the browser: the Worker runs in UTC and must not decide
// what "today" is. Weeks start on Monday, like CAT and Stremio.

export type CalendarEntry = components['schemas']['CalendarEntry']

const DAY_MS = 86_400_000

/** "YYYY-MM-DD" for an instant in a timezone (the browser's by default). */
export function localDayKey(date: Date, timeZone?: string): string {
  // en-CA formats dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date)
}

/** The day an entry belongs to: its local day when the time is exact, else the UTC date of the
 * date-only air date (stored as midnight UTC), which must not shift with the timezone. */
export function entryDay(entry: CalendarEntry, timeZone?: string): string {
  return entry.airTimeKnown
    ? localDayKey(new Date(entry.airsAt), timeZone)
    : entry.airsAt.slice(0, 10)
}

/** Day-key arithmetic, done at UTC noon so DST never moves the date. */
export function addDays(key: string, days: number): string {
  return new Date(Date.parse(`${key}T12:00:00Z`) + days * DAY_MS)
    .toISOString()
    .slice(0, 10)
}

/** Monday of the week containing `key`: the grid opens on the current Monday, like CAT. */
export function mondayOf(key: string): string {
  const weekday = new Date(`${key}T12:00:00Z`).getUTCDay() // 0 = Sunday
  return addDays(key, -((weekday + 6) % 7))
}

export function daysFrom(start: string, count = 7): string[] {
  return Array.from({ length: count }, (_, i) => addDays(start, i))
}

/** The instants to ask `/v1/calendar` for so every day in [first, last] is complete. Two days
 * of padding on each side cover any UTC offset. */
export function fetchWindow(
  first: string,
  last: string,
): { from: string; to: string } {
  return {
    from: new Date(Date.parse(`${first}T00:00:00Z`) - 2 * DAY_MS).toISOString(),
    to: new Date(Date.parse(`${last}T00:00:00Z`) + 3 * DAY_MS).toISOString(),
  }
}

/** The longest range `/v1/calendar` serves in one request. */
export const MAX_FETCH_DAYS = 42

/** `fetchWindow` cut into back-to-back requests the server accepts. One for a week or a
 * five-row month; a six-row month (42 days plus padding) takes two. */
export function fetchWindows(
  first: string,
  last: string,
): { from: string; to: string }[] {
  const { from, to } = fetchWindow(first, last)
  const end = Date.parse(to)
  const windows: { from: string; to: string }[] = []
  for (let cursor = Date.parse(from); cursor < end;) {
    const next = Math.min(end, cursor + MAX_FETCH_DAYS * DAY_MS)
    windows.push({
      from: new Date(cursor).toISOString(),
      to: new Date(next).toISOString(),
    })
    cursor = next
  }
  return windows
}

/** "YYYY-MM" of a day key. */
export const monthOf = (key: string) => key.slice(0, 7)

/** "YYYY-MM" plus or minus whole months, across years. */
export function addMonths(month: string, delta: number): string {
  const [year, mon] = month.split('-').map(Number)
  const index = year * 12 + (mon - 1) + delta
  const y = Math.floor(index / 12)
  return `${String(y).padStart(4, '0')}-${String(index - y * 12 + 1).padStart(2, '0')}`
}

export function daysInMonth(month: string): number {
  const [year, mon] = month.split('-').map(Number)
  return new Date(Date.UTC(year, mon, 0)).getUTCDate()
}

/** The Monday-start weeks covering a month, as day keys: 28, 35 or 42 days (4 to 6 rows). */
export function monthGrid(month: string): string[] {
  const start = mondayOf(`${month}-01`)
  const end = addDays(
    mondayOf(`${month}-${String(daysInMonth(month)).padStart(2, '0')}`),
    6,
  )
  const count =
    Math.round(
      (Date.parse(`${end}T12:00:00Z`) - Date.parse(`${start}T12:00:00Z`)) /
        DAY_MS,
    ) + 1
  return daysFrom(start, count)
}

/** "October 2026", or "October" with `withYear: false`. */
export function monthLabel(month: string, locale?: string, withYear = true) {
  return new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    month: 'long',
    ...(withYear ? { year: 'numeric' } : {}),
  }).format(new Date(`${month}-15T12:00:00Z`))
}

/** "Mon 13 Oct": an agenda heading. */
export function agendaDayLabel(key: string, locale?: string): string {
  return new Intl.DateTimeFormat(locale, {
    timeZone: 'UTC',
    weekday: 'short',
    day: 'numeric',
    month: 'short',
  }).format(new Date(`${key}T12:00:00Z`))
}

/** The agenda's days: from the selected day to the end of the visible range. */
export function agendaDays(visible: string[], selected: string): string[] {
  const from = visible.indexOf(selected)
  return from < 0 ? visible : visible.slice(from)
}

/** One episode's identity across reloads and views. */
export const entryKey = (entry: CalendarEntry) =>
  `${entry.libraryItemId}:${entry.season}:${entry.number}`

/** "S2 · E5": the agenda's compact episode code. */
export const shortCode = (season: number, number: number) =>
  `S${season} · E${number}`

/** Entries by day for the given days, each day ordered by air time, then show title. */
export function groupByDay(
  entries: CalendarEntry[],
  days: string[],
  timeZone?: string,
): Map<string, CalendarEntry[]> {
  const byDay = new Map<string, CalendarEntry[]>(days.map((d) => [d, []]))
  for (const entry of entries) byDay.get(entryDay(entry, timeZone))?.push(entry)
  for (const list of byDay.values()) {
    list.sort(
      (a, b) =>
        a.airsAt.localeCompare(b.airsAt) ||
        a.title.title.localeCompare(b.title.title),
    )
  }
  return byDay
}

export const episodeCode = (season: number, number: number) =>
  `S${String(season).padStart(2, '0')}E${String(number).padStart(2, '0')}`

/** "Premiere" opens a show, "New season" opens a later season, "Finale" closes one. */
export function badge(entry: CalendarEntry): string | null {
  if (entry.kind === 'premiere')
    return entry.season <= 1 ? 'Premiere' : 'New season'
  if (entry.kind === 'finale') return 'Finale'
  return null
}

/** "9:00 PM" in the viewer's timezone, or null when only the date is known. */
export function airTime(
  entry: CalendarEntry,
  timeZone?: string,
  locale?: string,
): string | null {
  if (!entry.airTimeKnown) return null
  return new Intl.DateTimeFormat(locale, {
    timeZone,
    hour: 'numeric',
    minute: '2-digit',
  }).format(new Date(entry.airsAt))
}

/** "Netflix · 9:00 PM", "Netflix", "9:00 PM", or "". */
export function metaLine(
  entry: CalendarEntry,
  timeZone?: string,
  locale?: string,
): string {
  return [entry.title.network, airTime(entry, timeZone, locale)]
    .filter(Boolean)
    .join(' · ')
}

/** "Thursday 15 October, 9:00 PM on Netflix" — the time only when it is exact. */
export function longWhen(entry: CalendarEntry, locale?: string): string {
  const date = new Date(entry.airsAt)
  const day = entry.airTimeKnown
    ? new Intl.DateTimeFormat(locale, {
        weekday: 'long',
        day: 'numeric',
        month: 'long',
        hour: 'numeric',
        minute: '2-digit',
      }).format(date)
    : new Intl.DateTimeFormat(locale, {
        timeZone: 'UTC',
        weekday: 'long',
        day: 'numeric',
        month: 'long',
      }).format(date)
  return entry.title.network ? `${day} on ${entry.title.network}` : day
}

/** Day number and weekday for a column header: { day: "15", weekday: "Thursday" }. */
export function dayParts(
  key: string,
  locale?: string,
): { day: string; weekday: string; short: string } {
  const date = new Date(`${key}T12:00:00Z`)
  const format = (options: Intl.DateTimeFormatOptions) =>
    new Intl.DateTimeFormat(locale, { timeZone: 'UTC', ...options }).format(
      date,
    )
  return {
    day: String(date.getUTCDate()),
    weekday: format({ weekday: 'long' }),
    short: format({ weekday: 'short' }),
  }
}

/** "12 – 18 Oct 2026" for the visible range. */
export function rangeLabel(first: string, last: string, locale?: string) {
  const format = (key: string, options: Intl.DateTimeFormatOptions) =>
    new Intl.DateTimeFormat(locale, { timeZone: 'UTC', ...options }).format(
      new Date(`${key}T12:00:00Z`),
    )
  const sameMonth = first.slice(0, 7) === last.slice(0, 7)
  const start = sameMonth
    ? format(first, { day: 'numeric' })
    : format(first, { day: 'numeric', month: 'short' })
  return `${start} – ${format(last, { day: 'numeric', month: 'short', year: 'numeric' })}`
}

/** Applies a tick to the loaded entries: the optimistic write and its rollback. */
export function withWatched(
  entries: CalendarEntry[],
  target: CalendarEntry,
  watched: boolean,
): CalendarEntry[] {
  return entries.map((e) =>
    e.libraryItemId === target.libraryItemId &&
    e.season === target.season &&
    e.number === target.number
      ? { ...e, watched }
      : e,
  )
}
