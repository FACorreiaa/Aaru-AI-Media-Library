import type { components } from '../api/schema'

// GAM-006a: the Recap's shared parts: the stats types, period labels and bars that Home,
// Insights and Settings use too. The story's deck lives in `./deck`.

export type Stats = components['schemas']['Stats']
export type StatsBucket = components['schemas']['StatsBucket']
export type StatsTitle = components['schemas']['StatsTitle']
export type StatsGenre = components['schemas']['StatsGenre']
export type Persona = NonNullable<Stats['persona']>
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

/** "June" from a 1-based month. */
export function monthName(month: number): string {
  return MONTHS[month - 1]
}

/** "Mar 10" from a local `YYYY-MM-DD`. */
export function dayLabel(day: string): string {
  const [, month, date] = day.split('-').map(Number)
  return `${MONTHS[month - 1].slice(0, 3)} ${date}`
}

/** Episodes per bucket; the server's `mostEpisodes` is marked (none on a tie). Months read
 * "J F M…", days "1 2 3…". */
export function bars(stats: Stats): Bar[] {
  const tallest = Math.max(1, ...stats.buckets.map((b) => b.episodes))
  const top = stats.mostEpisodes
  return stats.buckets.map((bucket) => {
    const [, month, day] = bucket.start.split('-').map(Number)
    return {
      label: stats.month ? `${day}` : MONTHS[month - 1].slice(0, 1),
      height: bucket.episodes / tallest,
      busiest: bucket.start === top?.start,
    }
  })
}

/** Nothing tracked in the period: no deck, an empty state instead. */
export function isEmpty(stats: Stats): boolean {
  return stats.totals.activeDays === 0
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
