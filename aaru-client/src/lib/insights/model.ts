import { bars, dayLabel, periodLabel } from '../recap/model'
import type { Bar, Period, Stats } from '../recap/model'
import type { MediaKind } from '../library/model'

// Insights: the browsable twin of the Recap. One period at a time — the last 7 or 30 days, a
// month, a year, or all time — from `/v1/me/stats`, drawn as plain numbers and static bars.
// Pure parts only.

export type Span = 'last7' | 'last30' | 'month' | 'year' | 'all'

/** GAM-006d: the days ending today, compared with the window just before. */
export type RollingSpan = 'last7' | 'last30'

export type InsightsPeriod =
  | { span: 'last7' }
  | { span: 'last30' }
  | { span: 'month'; year: number; month: number }
  | { span: 'year'; year: number }
  | { span: 'all' }

export function isRolling(span: Span): span is RollingSpan {
  return span === 'last7' || span === 'last30'
}

/** What the route's search params may hold; anything missing falls back to this month. */
export interface InsightsSearch {
  span?: Span
  year?: number
  month?: number
}

export const SPANS: Array<{ span: Span; label: string }> = [
  { span: 'last7', label: '7 days' },
  { span: 'last30', label: '30 days' },
  { span: 'month', label: 'Month' },
  { span: 'year', label: 'Year' },
  { span: 'all', label: 'All time' },
]

function thisMonth(now: Date): InsightsPeriod {
  return { span: 'month', year: now.getFullYear(), month: now.getMonth() + 1 }
}

/** The period the URL asks for, never past the current month. */
export function periodFromSearch(
  search: InsightsSearch,
  now: Date,
): InsightsPeriod {
  const year = now.getFullYear()
  if (search.span === 'all') return { span: 'all' }
  if (search.span && isRolling(search.span)) return { span: search.span }
  if (search.span === 'year')
    return { span: 'year', year: Math.min(search.year ?? year, year) }
  if (search.year === undefined || search.month === undefined)
    return thisMonth(now)
  const asked = {
    span: 'month' as const,
    year: search.year,
    month: search.month,
  }
  return isFuture(asked, now) ? thisMonth(now) : asked
}

/** The search params for a period: the URL keeps only what the span needs. */
export function toSearch(period: InsightsPeriod): InsightsSearch {
  if (
    period.span === 'all' ||
    period.span === 'last7' ||
    period.span === 'last30'
  )
    return { span: period.span }
  if (period.span === 'year') return { span: 'year', year: period.year }
  return { span: 'month', year: period.year, month: period.month }
}

/** Switching span keeps the year in view: a year opens on its last month (or this one). */
export function withSpan(
  period: InsightsPeriod,
  span: Span,
  now: Date,
): InsightsPeriod {
  if (span === 'all' || isRolling(span)) return { span }
  const year = 'year' in period ? period.year : now.getFullYear()
  if (span === 'year') return { span: 'year', year }
  if (period.span === 'month') return period
  return year === now.getFullYear()
    ? thisMonth(now)
    : { span: 'month', year, month: 12 }
}

function isFuture(period: InsightsPeriod, now: Date): boolean {
  if (
    period.span === 'all' ||
    period.span === 'last7' ||
    period.span === 'last30'
  )
    return false
  const year = now.getFullYear()
  if (period.span === 'year') return period.year > year
  return (
    period.year > year ||
    (period.year === year && period.month > now.getMonth() + 1)
  )
}

/** One step back or forward; null where there is nowhere to go (all time, a window that ends
 * today, or the future). */
export function shift(
  period: InsightsPeriod,
  direction: 1 | -1,
  now: Date,
): InsightsPeriod | null {
  let next: InsightsPeriod
  if (
    period.span === 'all' ||
    period.span === 'last7' ||
    period.span === 'last30'
  )
    return null
  if (period.span === 'year') {
    next = { span: 'year', year: period.year + direction }
  } else {
    const index = period.year * 12 + (period.month - 1) + direction
    next = {
      span: 'month',
      year: Math.floor(index / 12),
      month: (index % 12) + 1,
    }
  }
  if (next.year < 1900 || isFuture(next, now)) return null
  return next
}

/** "Last 7 days", "October 2026", "2026", "All time". */
export function insightsLabel(period: InsightsPeriod): string {
  if (period.span === 'last7') return 'Last 7 days'
  if (period.span === 'last30') return 'Last 30 days'
  if (period.span === 'all') return 'All time'
  if (period.span === 'year') return periodLabel({ year: period.year })
  return periodLabel({ year: period.year, month: period.month })
}

/** The Recap a period can be played as; all time and rolling windows have none. */
export function recapPeriod(period: InsightsPeriod): Period | null {
  if (
    period.span === 'all' ||
    period.span === 'last7' ||
    period.span === 'last30'
  )
    return null
  if (period.span === 'year') return { year: period.year }
  return { year: period.year, month: period.month }
}

/** The `getStats` query for a period in the viewer's time zone. */
export function statsQuery(
  period: InsightsPeriod,
  tz: string,
): { year?: number; month?: number; span?: 'all' | RollingSpan; tz: string } {
  if (
    period.span === 'all' ||
    period.span === 'last7' ||
    period.span === 'last30'
  )
    return { span: period.span, tz }
  if (period.span === 'year') return { year: period.year, tz }
  return { year: period.year, month: period.month, tz }
}

const WEEKDAYS = ['S', 'M', 'T', 'W', 'T', 'F', 'S']

/** Episodes per bucket. All time has one bucket per year, labelled "2024"; months and years
 * read as the Recap's do. A rolling window counts time per day instead, so a film night shows
 * too: weekday initials for 7 days, the day of the month for 30. */
export function chartBars(stats: Stats): Bar[] {
  if (isRolling(stats.span)) return dayBars(stats)
  if (stats.span !== 'all') return bars(stats)
  const tallest = Math.max(1, ...stats.buckets.map((b) => b.episodes))
  return stats.buckets.map((bucket) => ({
    label: bucket.start.slice(0, 4),
    height: bucket.episodes / tallest,
    busiest: bucket.start === stats.mostEpisodes?.start,
  }))
}

/** Minutes per day of a rolling window, the busiest day marked. Empty days stay as bars of
 * height 0, drawn as a track. */
export function dayBars(stats: Stats): Bar[] {
  const tallest = Math.max(1, ...stats.buckets.map((b) => b.minutes))
  return stats.buckets.map((bucket) => {
    const [year, month, day] = bucket.start.split('-').map(Number)
    const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay()
    return {
      label: stats.span === 'last7' ? WEEKDAYS[weekday] : `${day}`,
      height: bucket.minutes / tallest,
      busiest: bucket.minutes > 0 && bucket.start === stats.busiest?.start,
    }
  })
}

/** "Oct 15 – Oct 21", the days a rolling window covers. */
export function windowLabel(stats: Stats): string | null {
  if (!stats.from || !stats.until) return null
  return `${dayLabel(stats.from)} – ${dayLabel(stats.until)}`
}

/** "45 min", "12 h": the time line of a total. */
export function timeLabel(minutes: number): string {
  if (minutes < 60) return `${minutes} min`
  return `${Math.round(minutes / 60).toLocaleString('en')} h`
}

type Totals = Stats['totals']

function finishedOf(t: Totals): number {
  return (
    t.moviesFinished +
    t.showsFinished +
    t.animeFinished +
    t.booksFinished +
    t.albumsFinished
  )
}

export interface Total {
  label: string
  value: string
  /** Against the window just before, in the tile's own unit ("+3", "−2 h"); absent when
   * there is no prior window or nothing changed. Never a percentage. */
  delta?: { text: string; up: boolean }
}

function delta(
  now: number,
  before: number | undefined,
  format: (n: number) => string = (n) => n.toLocaleString('en'),
): Total['delta'] {
  if (before === undefined) return undefined
  const change = now - before
  if (change === 0) return undefined
  const text = format(Math.abs(change))
  return { text: `${change > 0 ? '+' : '−'}${text}`, up: change > 0 }
}

export function totals(stats: Stats): Total[] {
  const t = stats.totals
  const p = stats.prior
  const hours = (minutes: number) => timeLabel(minutes)
  return [
    {
      label: 'Episodes',
      value: t.episodesWatched.toLocaleString('en'),
      delta: delta(t.episodesWatched, p?.episodesWatched),
    },
    {
      label: 'Time',
      value: timeLabel(t.minutesWatched),
      // Hours round, so a change that rounds to nothing says nothing.
      delta:
        p && timeLabel(t.minutesWatched) !== timeLabel(p.minutesWatched)
          ? delta(t.minutesWatched, p.minutesWatched, hours)
          : undefined,
    },
    {
      label: 'Finished',
      value: finishedOf(t).toLocaleString('en'),
      delta: delta(finishedOf(t), p && finishedOf(p)),
    },
    {
      label: 'Active days',
      value: t.activeDays.toLocaleString('en'),
      delta: delta(t.activeDays, p?.activeDays),
    },
  ]
}

/** MUS-008: Insights' music tiles, on their own: listening never adds to the library's. */
export function musicTotals(music: NonNullable<Stats['music']>): Total[] {
  return [
    {
      label: 'Listens',
      value: music.listens.toLocaleString('en'),
      delta: delta(music.listens, music.priorListens),
    },
    {
      label: 'Time',
      value: timeLabel(music.minutes),
      delta:
        music.priorMinutes !== undefined &&
        timeLabel(music.minutes) !== timeLabel(music.priorMinutes)
          ? delta(music.minutes, music.priorMinutes, timeLabel)
          : undefined,
    },
  ]
}

const KIND_LABELS: Record<
  Stats['byKind'][number]['kind'],
  [MediaKind, string]
> = {
  movie: ['film', 'Films'],
  show: ['show', 'Shows'],
  anime: ['anime', 'Anime'],
  book: ['book', 'Books'],
  album: ['album', 'Albums'],
}

export interface KindShare {
  kind: MediaKind
  label: string
  minutes: number
  episodes: number
  finished: number
  /** 0…1 of all minutes in the period. */
  share: number
}

/** Films · Shows · Anime · Books, in that order, then Albums when the period finished one,
 * with each one's share of the time. */
export function kindShares(stats: Stats): KindShare[] {
  const total = stats.byKind.reduce((sum, k) => sum + k.minutes, 0)
  return stats.byKind.map((k) => {
    const [kind, label] = KIND_LABELS[k.kind]
    return {
      kind,
      label,
      minutes: k.minutes,
      episodes: k.episodes,
      finished: k.finished,
      share: total > 0 ? k.minutes / total : 0,
    }
  })
}

/** The numbers beside one kind: "12 h · 30 episodes · 2 finished". An album is listened to, and
 * never counted in time: albums have no minutes. */
export function kindDetail(kind: KindShare): string {
  if (kind.kind === 'album')
    return kind.finished > 0 ? `${kind.finished} listened` : 'Nothing yet'
  return (
    [
      kind.minutes > 0 ? timeLabel(kind.minutes) : null,
      kind.episodes > 0 ? `${kind.episodes} episodes` : null,
      kind.finished > 0 ? `${kind.finished} finished` : null,
    ]
      .filter(Boolean)
      .join(' · ') || 'Nothing yet'
  )
}

/** Ten bars for the ratings 1…10 (index n holds ratings up to n + 1), scaled to the tallest. */
export function ratingBars(
  distribution: number[],
): Array<{ label: string; count: number; height: number }> {
  const counts = Array.from({ length: 10 }, (_, i) => distribution[i] ?? 0)
  const tallest = Math.max(1, ...counts)
  return counts.map((count, i) => ({
    label: `${i + 1}`,
    count,
    height: count / tallest,
  }))
}
