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
    span: 'year',
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
    byKind: [
      { kind: 'movie', episodes: 0, minutes: 0, finished: 0 },
      { kind: 'show', episodes: 5, minutes: 225, finished: 1 },
      { kind: 'anime', episodes: 0, minutes: 0, finished: 0 },
      { kind: 'book', episodes: 0, minutes: 0, finished: 0 },
    ],
    buckets,
    busiest: buckets[2],
    mostEpisodes: buckets[2],
    longestRun: { days: 2, start: '2026-03-10', end: '2026-03-11' },
    topTitles: [
      { title: title('Severance'), episodes: 4, minutes: 180 },
      { title: title('Andor'), episodes: 1, minutes: 45 },
    ],
    ratings: {
      count: 1,
      mean: 9,
      highest: title('Andor'),
      highestRating: 9,
      distribution: [0, 0, 0, 0, 0, 0, 0, 0, 1, 0],
    },
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
      ratings: { count: 0, distribution: Array<number>(10).fill(0) },
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
  it("counts episodes and marks the server's mostEpisodes, not its busiest-by-time", () => {
    const base = stats()
    // A long film can win `busiest`; the episodes card follows `mostEpisodes`.
    const result = bars({ ...base, busiest: base.buckets[6] })
    expect(result).toHaveLength(12)
    expect(result[2]).toEqual({ label: 'M', height: 1, busiest: true })
    expect(result[6]).toEqual({ label: 'J', height: 0.25, busiest: false })
    expect(result[0].height).toBe(0)
  })

  it('marks nothing and says nothing when the server names no winner (a tie)', () => {
    const tie = stats({ mostEpisodes: undefined })
    expect(bars(tie).some((bar) => bar.busiest)).toBe(false)
    const card = cards(tie).find((c) => c.kind === 'episodes')
    expect(card).toMatchObject({ busiest: undefined })
  })

  it('names a day in a month recap', () => {
    const buckets = Array.from({ length: 30 }, (_, i) => ({
      start: `2026-04-${String(i + 1).padStart(2, '0')}`,
      episodes: i === 2 ? 3 : 0,
      minutes: i === 2 ? 135 : 0,
      finished: 0,
    }))
    const card = cards(
      stats({
        month: 4,
        buckets,
        busiest: buckets[2],
        mostEpisodes: buckets[2],
      }),
    ).find((c) => c.kind === 'episodes')
    expect(card).toMatchObject({ busiest: 'Most episodes on Apr 3.' })
  })

  it('names the month with the most episodes on the card', () => {
    const card = cards(stats()).find((c) => c.kind === 'episodes')
    expect(card).toMatchObject({ busiest: 'Most episodes in March.' })
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
