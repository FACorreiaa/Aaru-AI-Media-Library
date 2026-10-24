import type { components } from '../api/schema'

// SPT-003's pure part on the web: the date strip, how an event's status and time read, the
// "Where to watch" grouping, and when the tab asks again. Times arrive in UTC and are shown in
// the viewer's zone; a day key is always the viewer's local `YYYY-MM-DD`.

export type SportEntity = components['schemas']['SportEntity']
export type SportEntityKind = components['schemas']['SportEntityKind']
export type SportEntityList = components['schemas']['SportEntityList']
export type SportEvent = components['schemas']['SportEvent']
export type SportSide = components['schemas']['SportSide']
export type SportFavorite = components['schemas']['SportFavorite']
export type SportFavorites = components['schemas']['SportFavorites']
export type SportSchedule = components['schemas']['SportSchedule']
export type SportScheduleGroup = components['schemas']['SportScheduleGroup']
export type SportBroadcast = components['schemas']['SportBroadcast']
export type SportEventDetail = components['schemas']['SportEventDetail']
export type SportSettings = components['schemas']['SportSettings']

export const SPORT_KINDS = ['league', 'team', 'player'] as const

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
const MONTHS = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
]

const DAY_KEY = /^(\d{4})-(\d{2})-(\d{2})$/

function parseDay(key: string): Date | null {
  const match = DAY_KEY.exec(key)
  if (!match) return null
  const [, y, m, d] = match.map(Number)
  const date = new Date(Date.UTC(y, m - 1, d))
  // Rejects 2026-02-30 and friends, which Date would roll over.
  return date.getUTCMonth() === m - 1 && date.getUTCDate() === d ? date : null
}

/** True for a real `YYYY-MM-DD`. */
export const isDayKey = (key: string) => parseDay(key) !== null

/** The day `n` days from `key` (negative goes back), as `YYYY-MM-DD`. */
export function addDays(key: string, n: number): string {
  const date = parseDay(key)
  if (!date) return key
  date.setUTCDate(date.getUTCDate() + n)
  return date.toISOString().slice(0, 10)
}

export type StripDay = {
  key: string
  /** "Today", "Yesterday", "Tomorrow", else the weekday: "Sat". */
  name: string
  /** The day of the month and the month: "25 Oct". */
  date: string
  isToday: boolean
  /** For a screen reader: "Today, Saturday 25 October". */
  label: string
}

export const STRIP_BACK = 3
export const STRIP_AHEAD = 7

const LONG_WEEKDAYS = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
]
const LONG_MONTHS = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
]

function relativeName(offset: number): string | null {
  if (offset === 0) return 'Today'
  if (offset === -1) return 'Yesterday'
  if (offset === 1) return 'Tomorrow'
  return null
}

/** The Schedule's date strip: `back` days before `today` to `ahead` days after, in order. */
export function dayStrip(
  today: string,
  back = STRIP_BACK,
  ahead = STRIP_AHEAD,
): StripDay[] {
  const days: StripDay[] = []
  for (let offset = -back; offset <= ahead; offset++) {
    const key = addDays(today, offset)
    const date = parseDay(key)
    if (!date) continue
    const weekday = date.getUTCDay()
    const month = date.getUTCMonth()
    const day = date.getUTCDate()
    const relative = relativeName(offset)
    const long = `${LONG_WEEKDAYS[weekday]} ${day} ${LONG_MONTHS[month]}`
    days.push({
      key,
      name: relative ?? WEEKDAYS[weekday],
      date: `${day} ${MONTHS[month]}`,
      isToday: offset === 0,
      label: relative ? `${relative}, ${long}` : long,
    })
  }
  return days
}

/** True when `day` is one of the strip's days around `today`. */
export function inStrip(day: string, today: string): boolean {
  return dayStrip(today).some((d) => d.key === day)
}

/** The viewer's local day of an instant, `YYYY-MM-DD`. */
export function localDay(iso: string, timeZone?: string): string | null {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return null
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date)
}

/** The local time of an instant, 24-hour: "20:45". */
export function localTime(iso: string, timeZone?: string): string | null {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return null
  return new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(date)
}

/** A day named from today: "Today", "Tomorrow", "Yesterday", else "Sat 25 Oct". */
export function dayName(key: string, today: string): string {
  const date = parseDay(key)
  if (!date) return key
  for (const offset of [-1, 0, 1]) {
    if (addDays(today, offset) === key) return relativeName(offset) ?? key
  }
  const sameYear = key.slice(0, 4) === today.slice(0, 4)
  const base = `${WEEKDAYS[date.getUTCDay()]} ${date.getUTCDate()} ${MONTHS[date.getUTCMonth()]}`
  return sameYear ? base : `${base} ${date.getUTCFullYear()}`
}

/** When an event starts, in the viewer's zone: "Today · 20:45", "Sat 25 Oct · 15:00". */
export function whenLine(
  event: Pick<SportEvent, 'startsAt' | 'day'>,
  today: string,
  timeZone?: string,
): string {
  const day = event.startsAt ? localDay(event.startsAt, timeZone) : null
  const time = event.startsAt ? localTime(event.startsAt, timeZone) : null
  const name = dayName(day ?? event.day, today)
  return time ? `${name} · ${time}` : name
}

/** The live clock as it reads: a bare minute gets its prime ("67′"); "HT" and "Q3" stay. */
export function clockLabel(progress: string | undefined): string | null {
  const clock = progress?.trim()
  if (!clock) return null
  if (/^\d{1,3}(\+\d{1,2})?$/.test(clock)) return `${clock}′`
  return clock
}

/** Football ends at full time; every other sport reads "Final". */
export function finishedLabel(sport: string): string {
  return /^(soccer|football)$/i.test(sport.trim()) ? 'FT' : 'Final'
}

/**
 * The short status beside a score or in a row: "Live · 67′", "FT", "Final", "Postponed",
 * "Cancelled", or the kick-off time ("20:45") for an event still to come.
 */
export function statusLabel(
  event: Pick<SportEvent, 'status' | 'progress' | 'sport' | 'startsAt'>,
  timeZone?: string,
): string {
  switch (event.status) {
    case 'live': {
      const clock = clockLabel(event.progress)
      return clock ? `Live · ${clock}` : 'Live'
    }
    case 'finished':
      return finishedLabel(event.sport)
    case 'postponed':
      return 'Postponed'
    case 'cancelled':
      return 'Cancelled'
    case 'scheduled':
      return (event.startsAt && localTime(event.startsAt, timeZone)) ?? 'TBA'
  }
}

/** A UFC or WWE card: no sides, only its name and poster. */
export const isCard = (event: Pick<SportEvent, 'home' | 'away'>) =>
  !event.home && !event.away

/** Whether a score is worth showing: the game is on or over, and both sides have one. */
export function hasScore(event: SportEvent): boolean {
  if (event.status !== 'live' && event.status !== 'finished') return false
  return event.home?.score !== undefined && event.away?.score !== undefined
}

/** "Arsenal v Chelsea", or the card's own name. */
export function eventTitle(event: SportEvent): string {
  if (event.home && event.away) return `${event.home.name} v ${event.away.name}`
  return event.name
}

/** Venue and round, joined: "Emirates Stadium · Round 9". */
export function placeLine(
  event: Pick<SportEvent, 'venue' | 'round'>,
): string | null {
  const round = event.round?.trim()
  const parts = [
    event.venue?.trim(),
    round && /^\d+$/.test(round) ? `Round ${round}` : round,
  ].filter(Boolean)
  return parts.length > 0 ? parts.join(' · ') : null
}

export type BroadcastGroup = { country: string; channels: SportBroadcast[] }

const NO_COUNTRY = 'Other'

/** "Other countries": channels grouped by country, A to Z, channels without one last. */
export function groupBroadcasts(list: SportBroadcast[]): BroadcastGroup[] {
  const groups = new Map<string, SportBroadcast[]>()
  for (const broadcast of list) {
    const channel = broadcast.channel.trim()
    if (!channel) continue
    const country = broadcast.country?.trim() || NO_COUNTRY
    const channels = groups.get(country) ?? []
    if (!channels.some((c) => c.channel.trim() === channel))
      channels.push(broadcast)
    groups.set(country, channels)
  }
  return [...groups.entries()]
    .map(([country, channels]) => ({ country, channels }))
    .sort((a, b) => {
      if (a.country === NO_COUNTRY) return 1
      if (b.country === NO_COUNTRY) return -1
      return a.country.localeCompare(b.country)
    })
}

/** Search sends a query only from two characters to a hundred. */
export function sportQuery(text: string): string | null {
  const q = text.trim()
  return q.length >= 2 && q.length <= 100 ? q : null
}

/** "Soccer · England", "Basketball", "Real Madrid" (a player's team). */
export function entityLine(entity: SportEntity): string {
  const second =
    entity.kind === 'player' ? entity.teamName?.trim() : entity.country?.trim()
  return second ? `${entity.sport} · ${second}` : entity.sport
}

export const KIND_LABEL: Record<SportEntityKind, string> = {
  league: 'League',
  team: 'Team',
  player: 'Player',
}

// Near-live (SPT-003): ask again every 90 s while a live event is on screen, and a few
// seconds after an answer that says some of it is still being fetched.
export const LIVE_REFRESH_MS = 90_000
export const PENDING_RETRY_MS = 4_000
export const PENDING_MAX_TRIES = 3

export type LiveState = { live: boolean; pending: boolean }

/**
 * How long until the next quiet refresh, or null for none. `pendingTries` counts the pending
 * retries already made in a row; past the cap, only a live event keeps the tab asking.
 */
export function refreshDelay(
  state: LiveState,
  pendingTries: number,
): number | null {
  if (state.pending && pendingTries < PENDING_MAX_TRIES) return PENDING_RETRY_MS
  if (state.live) return LIVE_REFRESH_MS
  return null
}

export function favoritesState(favorites: SportFavorites): LiveState {
  return {
    live: favorites.items.some((f) => f.live.length > 0),
    pending: favorites.items.some((f) => f.pending),
  }
}

export function scheduleState(schedule: SportSchedule): LiveState {
  return {
    live: schedule.groups.some((g) =>
      g.events.some((e) => e.status === 'live'),
    ),
    pending: schedule.pending,
  }
}

/** A follow's key, the same for an entity in search, in picks and in Favorites. */
export const followKey = (entity: Pick<SportEntity, 'kind' | 'id'>) =>
  `${entity.kind}:${entity.id}`
