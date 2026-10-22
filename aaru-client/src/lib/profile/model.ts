import type { components } from '../api/schema'
import { timeLabel } from '../insights/model'
import type { LibraryStatus, MediaKind } from '../library/model'

// The profile page's words and bar widths, from `/v1/me/profile/stats`. Pure, so the page only
// draws: the hero reads like MyAnimeList's "days watched", in days and hours.

export type ProfileStats = components['schemas']['ProfileStats']
type StatsGenre = components['schemas']['StatsGenre']

const plural = (n: number, one: string, many = `${one}s`) =>
  `${n.toLocaleString('en')} ${n === 1 ? one : many}`

/** "41 days, 6 hours"; "6 hours" under a day; "45 minutes" under an hour. */
export function timeSpent(minutes: number): string {
  if (minutes < 60) return plural(Math.max(0, Math.round(minutes)), 'minute')
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  if (days === 0) return plural(hours, 'hour')
  return hours === 0
    ? plural(days, 'day')
    : `${plural(days, 'day')}, ${plural(hours, 'hour')}`
}

/** The line under the hero: "990 hours · 4,812 episodes". */
export function heroLine(stats: ProfileStats): string {
  return [
    stats.minutesWatched >= 60
      ? plural(Math.floor(stats.minutesWatched / 60), 'hour')
      : null,
    stats.episodesWatched > 0 ? plural(stats.episodesWatched, 'episode') : null,
  ]
    .filter(Boolean)
    .join(' · ')
}

/** "In Aaru since Oct 2026". */
export function memberSince(date: string | undefined): string | null {
  if (!date) return null
  return `In Aaru since ${new Date(date).toLocaleDateString('en-GB', {
    month: 'short',
    year: 'numeric',
  })}`
}

export interface CountTile {
  label: string
  value: number
  /** "3 watching", "4,210 pages". */
  detail?: string
  /** The Library filter the tile opens. */
  kind: MediaKind
  status: LibraryStatus
}

/** Shows, Anime, Films and Books, in that order: what is done, and for series what is going. */
export function countTiles(stats: ProfileStats): CountTile[] {
  const watching = (n: number) =>
    n > 0 ? `${n.toLocaleString('en')} watching` : undefined
  return [
    {
      label: 'Shows watched',
      value: stats.shows.finished,
      detail: watching(stats.shows.inProgress),
      kind: 'show',
      status: 'finished',
    },
    {
      label: 'Anime watched',
      value: stats.anime.finished,
      detail: watching(stats.anime.inProgress),
      kind: 'anime',
      status: 'finished',
    },
    {
      label: 'Films watched',
      value: stats.movies.finished,
      kind: 'film',
      status: 'finished',
    },
    {
      label: 'Books read',
      value: stats.books.finished,
      detail: stats.pagesRead > 0 ? plural(stats.pagesRead, 'page') : undefined,
      kind: 'book',
      status: 'finished',
    },
  ]
}

export interface TimeShare {
  kind: 'show' | 'anime' | 'movie'
  label: string
  minutes: number
  /** Of the three kinds' time together, 0…1. */
  share: number
}

const TIME_KINDS: Array<[TimeShare['kind'], string]> = [
  ['show', 'TV'],
  ['anime', 'Anime'],
  ['movie', 'Films'],
]

/** "Where the time went": TV, anime and films, each a share of their time together. Books and
 * albums have no minutes; a kind with none is left out. */
export function timeShares(stats: ProfileStats): TimeShare[] {
  const minutesOf = (kind: TimeShare['kind']) =>
    stats.byKind.find((k) => k.kind === kind)?.minutes ?? 0
  const total = TIME_KINDS.reduce((sum, [kind]) => sum + minutesOf(kind), 0)
  if (total === 0) return []
  return TIME_KINDS.map(([kind, label]) => ({
    kind,
    label,
    minutes: minutesOf(kind),
    share: minutesOf(kind) / total,
  })).filter((s) => s.minutes > 0)
}

export interface GenreBar {
  name: string
  /** Against the top genre, 0…1. */
  width: number
  time: string
  titles: string
}

/** The top genres as bars, the first one full width. */
export function genreBars(genres: StatsGenre[]): GenreBar[] {
  const longest = Math.max(1, ...genres.map((g) => g.minutes))
  return genres.map((g) => ({
    name: g.name,
    width: g.minutes / longest,
    time: timeLabel(g.minutes),
    titles: plural(g.titles, 'title'),
  }))
}

/** Nothing watched, finished or rated yet: the page shows its empty state instead. */
export function isEmptyProfile(stats: ProfileStats): boolean {
  const finished =
    stats.shows.finished +
    stats.anime.finished +
    stats.movies.finished +
    stats.books.finished
  return (
    stats.minutesWatched === 0 &&
    stats.episodesWatched === 0 &&
    finished === 0 &&
    stats.ratings.count === 0
  )
}
