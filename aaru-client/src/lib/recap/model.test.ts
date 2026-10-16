import { describe, expect, it } from 'vitest'
import {
  bars,
  cards,
  offeredRecap,
  periodLabel,
  shareLines,
  timeCaption,
} from './model'
import type { Stats, TitleSummary } from './model'

function title(
  name: string,
  overrides: Partial<TitleSummary> = {},
): TitleSummary {
  return {
    id: `id-${name}`,
    type: 'show',
    title: name,
    isAnime: false,
    ids: {},
    ...overrides,
  }
}

function stats(overrides: Partial<Stats> = {}): Stats {
  const buckets = Array.from({ length: 12 }, (_, i) => ({
    start: `2026-${String(i + 1).padStart(2, '0')}-01`,
    episodes: 0,
    minutes: 0,
    finished: 0,
  }))
  buckets[2] = { ...buckets[2], episodes: 4, minutes: 180 }
  buckets[6] = { ...buckets[6], episodes: 1, minutes: 45, finished: 1 }
  return {
    year: 2026,
    timeZone: 'Europe/Lisbon',
    isPartial: false,
    totals: {
      episodesWatched: 5,
      minutesWatched: 225,
      activeDays: 3,
      moviesFinished: 0,
      showsFinished: 1,
      animeFinished: 0,
      booksFinished: 0,
    },
    buckets,
    busiest: buckets[2],
    longestRun: { days: 2, start: '2026-03-10', end: '2026-03-11' },
    topTitles: [
      { title: title('Severance'), episodes: 4, minutes: 180 },
      { title: title('Andor'), episodes: 1, minutes: 45 },
    ],
    ratings: { count: 1, mean: 9, highest: title('Andor'), highestRating: 9 },
    first: { title: title('Severance'), at: '2026-03-10T12:00:00Z' },
    last: { title: title('Andor'), at: '2026-07-04T12:00:00Z' },
    ...overrides,
  }
}

describe('cards', () => {
  it('builds the full deck in order', () => {
    expect(cards(stats()).map((c) => c.kind)).toEqual([
      'intro',
      'time',
      'episodes',
      'top',
      'topList',
      'finished',
      'run',
      'ratings',
      'bookends',
      'summary',
    ])
  })

  it('has no deck for a period with no activity', () => {
    const empty = stats({
      totals: { ...stats().totals, activeDays: 0, episodesWatched: 0 },
    })
    expect(cards(empty)).toEqual([])
  })

  it('drops cards with nothing to say', () => {
    const booksOnly = stats({
      totals: {
        episodesWatched: 0,
        minutesWatched: 0,
        activeDays: 1,
        moviesFinished: 0,
        showsFinished: 0,
        animeFinished: 0,
        booksFinished: 2,
      },
      topTitles: [],
      longestRun: { days: 1, start: '2026-05-01', end: '2026-05-01' },
      ratings: { count: 0 },
      first: { title: title('Dune'), at: '2026-05-01T00:00:00Z' },
      last: { title: title('Dune'), at: '2026-05-01T00:00:00Z' },
    })
    expect(cards(booksOnly).map((c) => c.kind)).toEqual([
      'intro',
      'finished',
      'summary',
    ])
  })

  it('names a month recap by its month', () => {
    const intro = cards(stats({ month: 10 }))[0]
    expect(intro).toMatchObject({ kind: 'intro', heading: 'Your October 2026' })
  })
})

describe('bars', () => {
  it('scales to the busiest bucket and marks it', () => {
    const result = bars(stats())
    expect(result).toHaveLength(12)
    expect(result[2]).toEqual({ label: 'M', height: 1, busiest: true })
    expect(result[6].height).toBe(0.25)
    expect(result[0].height).toBe(0)
  })
})

describe('labels', () => {
  it('reads time in the largest whole unit', () => {
    expect(timeCaption(90)).toBe("That's 90 minutes of stories.")
    expect(timeCaption(600)).toBe("That's about 10 hours.")
    expect(timeCaption(60 * 24 * 3)).toBe("That's about 3 days, end to end.")
  })

  it('names periods', () => {
    expect(periodLabel({ year: 2026 })).toBe('2026')
    expect(periodLabel({ year: 2026, month: 2 })).toBe('February 2026')
  })

  it('prints only the user’s own numbers on the share image', () => {
    expect(shareLines(stats())).toEqual([
      '225 minutes',
      '5 episodes',
      'Finished 1 show',
      'Most watched: Severance',
      '2 days in a row',
    ])
  })
})

describe('offeredRecap', () => {
  it('offers the year from December to mid-January, and last month in a month’s first week', () => {
    expect(offeredRecap(new Date(2026, 11, 20))).toEqual({ year: 2026 })
    expect(offeredRecap(new Date(2027, 0, 10))).toEqual({ year: 2026 })
    expect(offeredRecap(new Date(2027, 0, 20))).toBeNull()
    expect(offeredRecap(new Date(2026, 10, 3))).toEqual({
      year: 2026,
      month: 10,
    })
    expect(offeredRecap(new Date(2026, 9, 16))).toBeNull()
  })
})
