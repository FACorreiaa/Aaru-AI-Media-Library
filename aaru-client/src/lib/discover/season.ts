import type { components } from '../api/schema'

// The Seasons view's pure part (DISC-002): which season a day falls in, stepping between
// seasons, and the words around a season. A season is a calendar quarter, the same for every
// kind: anime by broadcast season, shows by premiere or airing, films by first release.

export type SeasonPage = components['schemas']['SeasonPage']
export type SeasonName = SeasonPage['season']
export type SeasonKind = SeasonPage['kind']

export interface SeasonKey {
  season: SeasonName
  year: number
}

export const SEASONS: readonly SeasonName[] = [
  'winter',
  'spring',
  'summer',
  'fall',
]

/** The kind switch, in order, with the noun its count reads in ("84 anime"). */
export const SEASON_KINDS: readonly {
  kind: SeasonKind
  label: string
  one: string
  many: string
}[] = [
  { kind: 'anime', label: 'Anime', one: 'anime', many: 'anime' },
  { kind: 'shows_new', label: 'New shows', one: 'new show', many: 'new shows' },
  {
    kind: 'shows_returning',
    label: 'Returning',
    one: 'returning show',
    many: 'returning shows',
  },
  { kind: 'movies', label: 'Movies', one: 'film', many: 'films' },
]

/** The oldest year the view goes back to; the server refuses earlier ones. */
export const FIRST_YEAR = 1970

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

/** The season a local "YYYY-MM-DD" day falls in. */
export function seasonOf(day: string): SeasonKey {
  const [year, month] = day.split('-').map(Number)
  return { season: SEASONS[Math.floor((month - 1) / 3)], year }
}

/** The season before (-1) or after (1). */
export function shiftSeason(key: SeasonKey, way: 1 | -1): SeasonKey {
  const index = SEASONS.indexOf(key.season) + way
  if (index < 0) return { season: 'fall', year: key.year - 1 }
  if (index >= SEASONS.length) return { season: 'winter', year: key.year + 1 }
  return { season: SEASONS[index], year: key.year }
}

/** Whether a step that way stays inside FIRST_YEAR … the year after `today`'s. */
export function canShift(key: SeasonKey, way: 1 | -1, today: string): boolean {
  const next = shiftSeason(key, way)
  return next.year >= FIRST_YEAR && next.year <= seasonOf(today).year + 1
}

/** "Fall 2026". */
export function seasonLabel(key: SeasonKey): string {
  return `${key.season[0].toUpperCase()}${key.season.slice(1)} ${key.year}`
}

/** "Oct – Dec": the season's months. */
export function monthSpan(season: SeasonName): string {
  const first = SEASONS.indexOf(season) * 3
  return `${MONTHS[first]} – ${MONTHS[first + 2]}`
}

/** "84 anime", "1 new show", "9,870 films"; null without a count. */
export function countLabel(
  kind: SeasonKind,
  total: number | undefined,
): string | null {
  if (total === undefined) return null
  const option = SEASON_KINDS.find((o) => o.kind === kind)
  if (!option) return null
  return `${total.toLocaleString('en')} ${total === 1 ? option.one : option.many}`
}

/** A stable cache key for one page of one season of one kind. */
export function pageKey(kind: SeasonKind, key: SeasonKey, page = 1): string {
  return `${kind}:${key.year}-${key.season}:${page}`
}

/** -1 when `to` is earlier than `from`, 1 when later, 0 when the same season. */
export function direction(from: SeasonKey, to: SeasonKey): -1 | 0 | 1 {
  const order = (k: SeasonKey) => k.year * 4 + SEASONS.indexOf(k.season)
  return Math.sign(order(to) - order(from)) as -1 | 0 | 1
}
