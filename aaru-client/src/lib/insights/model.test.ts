import { describe, expect, it } from 'vitest'
import {
  chartBars,
  insightsLabel,
  kindShares,
  periodFromSearch,
  ratingBars,
  recapPeriod,
  shift,
  statsQuery,
  toSearch,
  withSpan,
} from './model'
import type { Stats } from '../recap/model'

const now = new Date(2026, 9, 20, 12) // 20 Oct 2026, local time

function stats(overrides: Partial<Stats> = {}): Stats {
  return {
    span: 'all',
    year: 2026,
    timeZone: 'Europe/Lisbon',
    isPartial: true,
    totals: {
      episodesWatched: 30,
      minutesWatched: 1350,
      activeDays: 9,
      moviesFinished: 1,
      showsFinished: 1,
      animeFinished: 0,
      booksFinished: 2,
    },
    byKind: [
      { kind: 'movie', episodes: 0, minutes: 150, finished: 1 },
      { kind: 'show', episodes: 30, minutes: 1200, finished: 1 },
      { kind: 'anime', episodes: 0, minutes: 0, finished: 0 },
      { kind: 'book', episodes: 0, minutes: 0, finished: 2 },
    ],
    buckets: [
      { start: '2024-01-01', episodes: 5, minutes: 0, finished: 0 },
      { start: '2025-01-01', episodes: 20, minutes: 0, finished: 0 },
      { start: '2026-01-01', episodes: 5, minutes: 0, finished: 0 },
    ],
    mostEpisodes: {
      start: '2025-01-01',
      episodes: 20,
      minutes: 0,
      finished: 0,
    },
    topTitles: [],
    ratings: { count: 0, distribution: Array<number>(10).fill(0) },
    ...overrides,
  }
}

describe('insights period', () => {
  it('opens on this month when the URL says nothing', () => {
    expect(periodFromSearch({}, now)).toEqual({
      span: 'month',
      year: 2026,
      month: 10,
    })
  })

  it('reads a year, all time, and refuses the future', () => {
    expect(periodFromSearch({ span: 'year', year: 2024 }, now)).toEqual({
      span: 'year',
      year: 2024,
    })
    expect(periodFromSearch({ span: 'all', year: 2024 }, now)).toEqual({
      span: 'all',
    })
    expect(
      periodFromSearch({ span: 'month', year: 2026, month: 12 }, now),
    ).toEqual({ span: 'month', year: 2026, month: 10 })
  })

  it('steps months across a year boundary and stops at today', () => {
    expect(shift({ span: 'month', year: 2026, month: 1 }, -1, now)).toEqual({
      span: 'month',
      year: 2025,
      month: 12,
    })
    expect(shift({ span: 'month', year: 2025, month: 12 }, 1, now)).toEqual({
      span: 'month',
      year: 2026,
      month: 1,
    })
    expect(shift({ span: 'month', year: 2026, month: 10 }, 1, now)).toBeNull()
    expect(shift({ span: 'year', year: 2026 }, 1, now)).toBeNull()
    expect(shift({ span: 'year', year: 2026 }, -1, now)).toEqual({
      span: 'year',
      year: 2025,
    })
    expect(shift({ span: 'all' }, -1, now)).toBeNull()
  })

  it('keeps the year in view when the span changes', () => {
    expect(withSpan({ span: 'year', year: 2025 }, 'month', now)).toEqual({
      span: 'month',
      year: 2025,
      month: 12,
    })
    expect(withSpan({ span: 'year', year: 2026 }, 'month', now)).toEqual({
      span: 'month',
      year: 2026,
      month: 10,
    })
    expect(withSpan({ span: 'all' }, 'year', now)).toEqual({
      span: 'year',
      year: 2026,
    })
  })

  it('labels each span', () => {
    expect(insightsLabel({ span: 'month', year: 2026, month: 10 })).toBe(
      'October 2026',
    )
    expect(insightsLabel({ span: 'year', year: 2025 })).toBe('2025')
    expect(insightsLabel({ span: 'all' })).toBe('All time')
  })

  it('offers a Recap for a month or year only', () => {
    expect(recapPeriod({ span: 'year', year: 2025 })).toEqual({ year: 2025 })
    expect(recapPeriod({ span: 'all' })).toBeNull()
  })

  it('asks the server for exactly what the span needs', () => {
    expect(statsQuery({ span: 'all' }, 'UTC')).toEqual({
      span: 'all',
      tz: 'UTC',
    })
    expect(statsQuery({ span: 'year', year: 2025 }, 'UTC')).toEqual({
      year: 2025,
      tz: 'UTC',
    })
    expect(toSearch({ span: 'month', year: 2026, month: 3 })).toEqual({
      span: 'month',
      year: 2026,
      month: 3,
    })
  })
})

describe('insights figures', () => {
  it('labels all-time bars by year and marks the busiest', () => {
    const chart = chartBars(stats())
    expect(chart.map((b) => b.label)).toEqual(['2024', '2025', '2026'])
    expect(chart.map((b) => b.height)).toEqual([0.25, 1, 0.25])
    expect(chart.map((b) => b.busiest)).toEqual([false, true, false])
  })

  it('splits the time by kind, in a fixed order', () => {
    const shares = kindShares(stats())
    expect(shares.map((k) => k.label)).toEqual([
      'Films',
      'Shows',
      'Anime',
      'Books',
    ])
    expect(shares[1].share).toBeCloseTo(1200 / 1350)
    expect(shares[3].finished).toBe(2)
  })

  it('draws ten rating bars scaled to the tallest', () => {
    const bars = ratingBars([0, 0, 0, 0, 0, 0, 1, 4, 2, 0])
    expect(bars).toHaveLength(10)
    expect(bars[7]).toEqual({ label: '8', count: 4, height: 1 })
    expect(bars[0].height).toBe(0)
  })
})
