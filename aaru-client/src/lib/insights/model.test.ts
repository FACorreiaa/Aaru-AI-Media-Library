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
  totals,
  windowLabel,
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

describe('last 7 and 30 days (GAM-006d)', () => {
  const week = (overrides: Partial<Stats> = {}) =>
    stats({
      span: 'last7',
      from: '2026-10-14',
      until: '2026-10-20',
      // Wed 14 Oct … Tue 20 Oct: a film night on Friday, two episodes on Monday.
      buckets: [0, 0, 120, 0, 0, 90, 0].map((minutes, i) => ({
        start: `2026-10-${14 + i}`,
        episodes: i === 5 ? 2 : 0,
        minutes,
        finished: 0,
      })),
      busiest: { start: '2026-10-16', episodes: 0, minutes: 120, finished: 1 },
      ...overrides,
    })

  it('reads the URL, never steps, and has no Recap', () => {
    expect(periodFromSearch({ span: 'last7' }, now)).toEqual({ span: 'last7' })
    expect(periodFromSearch({ span: 'last30', year: 2025 }, now)).toEqual({
      span: 'last30',
    })
    expect(toSearch({ span: 'last30' })).toEqual({ span: 'last30' })
    expect(shift({ span: 'last7' }, -1, now)).toBeNull()
    expect(recapPeriod({ span: 'last7' })).toBeNull()
    expect(insightsLabel({ span: 'last30' })).toBe('Last 30 days')
    expect(statsQuery({ span: 'last7' }, 'UTC')).toEqual({
      span: 'last7',
      tz: 'UTC',
    })
  })

  it('switches between rolling and calendar spans', () => {
    expect(withSpan({ span: 'last7' }, 'month', now)).toEqual({
      span: 'month',
      year: 2026,
      month: 10,
    })
    expect(withSpan({ span: 'last7' }, 'year', now)).toEqual({
      span: 'year',
      year: 2026,
    })
    expect(withSpan({ span: 'year', year: 2024 }, 'last30', now)).toEqual({
      span: 'last30',
    })
  })

  it('draws time per day with weekday initials and the busiest day marked', () => {
    const chart = chartBars(week())
    expect(chart.map((b) => b.label)).toEqual([
      'W',
      'T',
      'F',
      'S',
      'S',
      'M',
      'T',
    ])
    expect(chart.map((b) => b.height)).toEqual([0, 0, 1, 0, 0, 0.75, 0])
    expect(chart.map((b) => b.busiest)).toEqual([
      false,
      false,
      true,
      false,
      false,
      false,
      false,
    ])
    expect(chartBars(week({ span: 'last30' }))[0].label).toBe('14')
    expect(windowLabel(week())).toBe('Oct 14 – Oct 20')
    expect(windowLabel(stats())).toBeNull()
  })

  it('shows absolute deltas against the window before, never at zero', () => {
    const t = stats().totals
    const tiles = totals(
      week({
        prior: {
          ...t,
          episodesWatched: 27,
          minutesWatched: 1350,
          activeDays: 11,
        },
      }),
    )
    expect(tiles.map((tile) => tile.delta)).toEqual([
      { text: '+3', up: true },
      undefined,
      undefined,
      { text: '−2', up: false },
    ])
    expect(totals(stats()).every((tile) => tile.delta === undefined)).toBe(true)
  })
})
