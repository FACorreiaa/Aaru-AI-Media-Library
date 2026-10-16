import type { components } from '../api/schema'
import { kindOf } from '../library/model'
import type { MediaKind } from '../library/model'

// GAM-006a: the Recap's pure parts. The deck is built from `/v1/me/stats` the same way the
// Apple apps' `RecapModel` builds it: cards with nothing to say are left out, and a period
// with no activity has no deck at all.

export type Stats = components['schemas']['Stats']
export type StatsBucket = components['schemas']['StatsBucket']
export type StatsTitle = components['schemas']['StatsTitle']
export type TitleSummary = components['schemas']['TitleSummary']

export interface Period {
  year: number
  month?: number
}

export interface Bar {
  label: string
  /** 0…1 of the tallest bucket. */
  height: number
  busiest: boolean
}

export type RecapCard =
  | { kind: 'intro'; heading: string; partial: boolean }
  | { kind: 'time'; minutes: number; caption: string }
  | { kind: 'episodes'; episodes: number; bars: Bar[]; busiest?: string }
  | { kind: 'top'; entry: StatsTitle }
  | { kind: 'topList'; entries: StatsTitle[] }
  | { kind: 'finished'; parts: Array<{ kind: MediaKind; count: number }> }
  | { kind: 'run'; days: number; range: string }
  | {
      kind: 'ratings'
      mean: number
      count: number
      highest?: TitleSummary
      highestRating?: number
    }
  | {
      kind: 'bookends'
      first: { title: TitleSummary; at: string }
      last: { title: TitleSummary; at: string }
    }
  | { kind: 'summary' }

const MONTHS = [
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

/** "October 2026", or "2026" for a whole year. */
export function periodLabel(period: Period): string {
  return period.month
    ? `${MONTHS[period.month - 1]} ${period.year}`
    : `${period.year}`
}

/** "Mar 10" from a local `YYYY-MM-DD`. */
export function dayLabel(day: string): string {
  const [, month, date] = day.split('-').map(Number)
  return `${MONTHS[month - 1].slice(0, 3)} ${date}`
}

/** What the minutes come to, in the largest unit that still reads as a whole. */
export function timeCaption(minutes: number): string {
  const hours = minutes / 60
  if (hours < 2) return `That's ${minutes} minutes of stories.`
  if (hours < 48) return `That's about ${Math.round(hours)} hours.`
  const days = Math.round((hours / 24) * 10) / 10
  return `That's about ${days} days, end to end.`
}

/** One bar per bucket; the busiest one is marked. Months read "J F M…", days "1 2 3…". */
export function bars(stats: Stats): Bar[] {
  const tallest = Math.max(1, ...stats.buckets.map(weight))
  return stats.buckets.map((bucket) => {
    const [, month, day] = bucket.start.split('-').map(Number)
    return {
      label: stats.month ? `${day}` : MONTHS[month - 1].slice(0, 1),
      height: weight(bucket) / tallest,
      busiest: bucket.start === stats.busiest?.start,
    }
  })
}

function weight(bucket: StatsBucket): number {
  return bucket.minutes || bucket.episodes + bucket.finished
}

function busiestLabel(stats: Stats): string | undefined {
  const busiest = stats.busiest
  if (!busiest) return undefined
  const [, month] = busiest.start.split('-').map(Number)
  return stats.month ? dayLabel(busiest.start) : MONTHS[month - 1]
}

/** Nothing tracked in the period: no deck, an empty state instead. */
export function isEmpty(stats: Stats): boolean {
  return stats.totals.activeDays === 0
}

export function cards(stats: Stats): RecapCard[] {
  if (isEmpty(stats)) return []
  const t = stats.totals
  const period = { year: stats.year, month: stats.month }
  const deck: RecapCard[] = [
    {
      kind: 'intro',
      heading: stats.month
        ? `Your ${periodLabel(period)}`
        : `Your ${stats.year} in Aaru`,
      partial: stats.isPartial,
    },
  ]
  if (t.minutesWatched > 0)
    deck.push({
      kind: 'time',
      minutes: t.minutesWatched,
      caption: timeCaption(t.minutesWatched),
    })
  if (t.episodesWatched > 0)
    deck.push({
      kind: 'episodes',
      episodes: t.episodesWatched,
      bars: bars(stats),
      busiest: busiestLabel(stats),
    })
  if (stats.topTitles.length > 0)
    deck.push({ kind: 'top', entry: stats.topTitles[0] })
  if (stats.topTitles.length > 1)
    deck.push({ kind: 'topList', entries: stats.topTitles })
  const parts = (
    [
      { kind: 'film', count: t.moviesFinished },
      { kind: 'show', count: t.showsFinished },
      { kind: 'anime', count: t.animeFinished },
      { kind: 'book', count: t.booksFinished },
    ] as const
  ).filter((part) => part.count > 0)
  if (parts.length > 0) deck.push({ kind: 'finished', parts: [...parts] })
  const run = stats.longestRun
  if (run && run.days > 1)
    deck.push({
      kind: 'run',
      days: run.days,
      range: `${dayLabel(run.start)} – ${dayLabel(run.end)}`,
    })
  const ratings = stats.ratings
  if (ratings.count > 0 && ratings.mean !== undefined)
    deck.push({
      kind: 'ratings',
      mean: ratings.mean,
      count: ratings.count,
      highest: ratings.highest,
      highestRating: ratings.highestRating,
    })
  if (stats.first && stats.last && stats.first.title.id !== stats.last.title.id)
    deck.push({ kind: 'bookends', first: stats.first, last: stats.last })
  deck.push({ kind: 'summary' })
  return deck
}

export function titleKind(title: TitleSummary): MediaKind {
  return kindOf(title.type, title.isAnime)
}

const KIND_WORDS: Record<MediaKind, [string, string]> = {
  film: ['film', 'films'],
  show: ['show', 'shows'],
  anime: ['anime', 'anime'],
  book: ['book', 'books'],
}

export function countLabel(kind: MediaKind, count: number): string {
  return `${count} ${KIND_WORDS[kind][count === 1 ? 0 : 1]}`
}

/** "8.5": ratings are 1–10 in half steps; a mean shows one decimal at most. */
export function ratingLabel(rating: number): string {
  return `${Math.round(rating * 10) / 10}`
}

/** The lines the share image prints, top to bottom. No other user's data, ever. */
export function shareLines(stats: Stats): string[] {
  const t = stats.totals
  const lines: string[] = []
  if (t.minutesWatched > 0)
    lines.push(`${t.minutesWatched.toLocaleString('en')} minutes`)
  if (t.episodesWatched > 0)
    lines.push(`${t.episodesWatched.toLocaleString('en')} episodes`)
  const finished = [
    countLabel('film', t.moviesFinished),
    countLabel('show', t.showsFinished),
    countLabel('anime', t.animeFinished),
    countLabel('book', t.booksFinished),
  ].filter((label) => !label.startsWith('0 '))
  if (finished.length > 0) lines.push(`Finished ${finished.join(', ')}`)
  if (stats.topTitles[0])
    lines.push(`Most watched: ${stats.topTitles[0].title.title}`)
  if (stats.longestRun && stats.longestRun.days > 1)
    lines.push(`${stats.longestRun.days} days in a row`)
  return lines
}

/**
 * The recap Home offers right now, if any: the year review from Dec 1 to Jan 15, and last
 * month's recap in the first week of a month. `now` is the viewer's local clock.
 */
export function offeredRecap(now: Date): Period | null {
  const month = now.getMonth() + 1
  const day = now.getDate()
  if (month === 12) return { year: now.getFullYear() }
  if (month === 1 && day <= 15) return { year: now.getFullYear() - 1 }
  if (day <= 7) return previousMonth(now)
  return null
}

export function previousMonth(now: Date): Period {
  const month = now.getMonth() + 1
  return month === 1
    ? { year: now.getFullYear() - 1, month: 12 }
    : { year: now.getFullYear(), month: month - 1 }
}

/** Settings' recap shortcuts: this year so far, last month, and last year. */
export function recapShortcuts(now: Date): Period[] {
  return [
    { year: now.getFullYear() },
    previousMonth(now),
    { year: now.getFullYear() - 1 },
  ]
}
