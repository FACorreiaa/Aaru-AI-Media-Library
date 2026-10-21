import { describe, expect, it } from 'vitest'
import {
  advance,
  airingBadge,
  countChips,
  hoursLabel,
  listening,
  markAdded,
  markOnShelf,
  weekStrip,
  nextLine,
  remainingLabel,
  resumeLine,
  runtimeLabel,
  unfinishedLabel,
  upcoming,
} from './model'
import type { ContinueEntry, DiscoverRow, UnfinishedEntry } from './model'
import type { Stats } from '../recap/model'
import type { CalendarEntry } from '../calendar/model'
import type { LibraryEntry } from '../library/model'

function airing(overrides: Partial<CalendarEntry> = {}): CalendarEntry {
  return {
    libraryItemId: '00000000-0000-4000-8000-000000000001',
    title: {
      id: '00000000-0000-4000-8000-0000000000aa',
      type: 'show',
      title: 'Severance',
      isAnime: false,
      ids: {},
    },
    season: 2,
    number: 3,
    airsAt: '2026-10-16T00:00:00Z',
    airTimeKnown: false,
    watched: false,
    kind: 'regular',
    ...overrides,
  }
}

function continuing(overrides: Partial<ContinueEntry> = {}): ContinueEntry {
  return {
    libraryItemId: '00000000-0000-4000-8000-000000000002',
    title: {
      id: '00000000-0000-4000-8000-0000000000bb',
      type: 'show',
      title: 'The Bear',
      isAnime: false,
      ids: {},
    },
    next: { season: 1, number: 8 },
    nextName: 'Braciole',
    nextRuntimeMinutes: 30,
    remainingCount: 3,
    remainingMinutes: 90,
    isFinale: false,
    ...overrides,
  }
}

describe('home labels', () => {
  it('formats runtimes the way the cards read them', () => {
    expect(runtimeLabel(57)).toBe('57m')
    expect(runtimeLabel(87)).toBe('1h 27m')
    expect(runtimeLabel(120)).toBe('2h')
    expect(runtimeLabel(0)).toBe('')
    expect(runtimeLabel(undefined)).toBe('')
  })

  it('says what is left of a show', () => {
    expect(remainingLabel(10, 520)).toBe('10 left · 8h 40m')
    expect(remainingLabel(2, 0)).toBe('2 left')
  })

  it('names the next episode, without an empty name', () => {
    expect(nextLine(continuing())).toBe('S1 · E8 · Braciole')
    expect(nextLine(continuing({ nextName: undefined }))).toBe('S1 · E8')
  })
})

describe('calendar row badge', () => {
  // Thursday 15 October 2026, 18:00 in Lisbon (UTC+1).
  const now = new Date('2026-10-15T17:00:00Z')
  const lisbon = 'Europe/Lisbon'

  it('counts hours only for an exact time within twelve hours', () => {
    const soon = airing({ airTimeKnown: true, airsAt: '2026-10-15T20:00:00Z' })
    expect(airingBadge(soon, now, lisbon)).toBe('In 3 hours')
    const minutes = airing({
      airTimeKnown: true,
      airsAt: '2026-10-15T17:20:00Z',
    })
    expect(airingBadge(minutes, now, lisbon)).toBe('Within the hour')
    const late = airing({ airTimeKnown: true, airsAt: '2026-10-16T19:00:00Z' })
    expect(airingBadge(late, now, lisbon)).toBe('Tomorrow')
  })

  it('reads a date-only airing by its date, never in hours', () => {
    expect(
      airingBadge(airing({ airsAt: '2026-10-15T00:00:00Z' }), now, lisbon),
    ).toBe('Today · New')
    expect(
      airingBadge(airing({ airsAt: '2026-10-16T00:00:00Z' }), now, lisbon),
    ).toBe('Tomorrow')
    expect(
      airingBadge(airing({ airsAt: '2026-10-18T00:00:00Z' }), now, lisbon),
    ).toBe('In 3 days')
  })

  it('keeps a date-only airing on its date west of UTC', () => {
    // 20:00 on the 15th in Los Angeles is already the 16th in UTC.
    const evening = new Date('2026-10-16T03:00:00Z')
    expect(
      airingBadge(
        airing({ airsAt: '2026-10-15T00:00:00Z' }),
        evening,
        'America/Los_Angeles',
      ),
    ).toBe('Today · New')
  })

  it('says "Today · New" for an exact time already aired today', () => {
    const aired = airing({ airTimeKnown: true, airsAt: '2026-10-15T09:00:00Z' })
    expect(airingBadge(aired, now, lisbon)).toBe('Today · New')
  })

  it('has no badge for an airing before today', () => {
    expect(
      airingBadge(airing({ airsAt: '2026-10-14T00:00:00Z' }), now, lisbon),
    ).toBeNull()
  })

  it('lists airings from today on, soonest first, date-only before timed', () => {
    const rows = upcoming(
      [
        airing({ number: 9, airsAt: '2026-10-17T00:00:00Z' }),
        airing({ number: 1, airsAt: '2026-10-14T00:00:00Z' }),
        airing({
          number: 5,
          airTimeKnown: true,
          airsAt: '2026-10-15T20:00:00Z',
        }),
        airing({ number: 4, airsAt: '2026-10-15T00:00:00Z' }),
      ],
      now,
      lisbon,
    )
    expect(rows.map((r) => r.number)).toEqual([4, 5, 9])
    expect(upcoming(rows, now, lisbon, 2)).toHaveLength(2)
  })
})

describe('continue watching tick', () => {
  it('moves the card to the next episode and takes off its runtime', () => {
    const [row] = advance([continuing()], continuing())
    expect(row.next).toEqual({ season: 1, number: 9 })
    expect(row.nextName).toBeUndefined()
    expect(row.remainingCount).toBe(2)
    expect(row.remainingMinutes).toBe(60)
  })

  it('drops a show with nothing left and leaves the others alone', () => {
    const other = continuing({ libraryItemId: 'other' })
    expect(
      advance([continuing({ remainingCount: 1 }), other], continuing()),
    ).toEqual([other])
  })
})

function weekStats(
  totals: Partial<Stats['totals']> = {},
  minutes: number[] = [0, 0, 0, 0, 0, 0, 0],
): Stats {
  return {
    span: 'last7',
    year: 2026,
    from: '2026-10-15',
    until: '2026-10-21',
    timeZone: 'Europe/Lisbon',
    isPartial: true,
    totals: {
      episodesWatched: 0,
      minutesWatched: 0,
      activeDays: 0,
      moviesFinished: 0,
      showsFinished: 0,
      animeFinished: 0,
      booksFinished: 0,
      albumsFinished: 0,
      ...totals,
    },
    byKind: [],
    buckets: minutes.map((m, i) => ({
      start: `2026-10-${15 + i}`,
      episodes: 0,
      minutes: m,
      finished: 0,
    })),
    topTitles: [],
    topGenres: [],
    ratings: { count: 0, distribution: Array<number>(10).fill(0) },
  }
}

describe('last 7 days strip', () => {
  it('reads episodes, hours, finished and active days', () => {
    expect(
      weekStrip(
        weekStats({
          episodesWatched: 12,
          minutesWatched: 540,
          activeDays: 5,
          moviesFinished: 1,
          booksFinished: 1,
          albumsFinished: 0,
        }),
      ).parts,
    ).toEqual(['12 episodes', '9 hours', '2 finished', '5 active days'])
  })

  it('leaves out zeros, and keeps seven empty days for a quiet week', () => {
    expect(
      weekStrip(weekStats({ booksFinished: 1, activeDays: 1 })).parts,
    ).toEqual(['1 finished', '1 active day'])
    expect(weekStrip(weekStats())).toEqual({
      parts: [],
      days: [0, 0, 0, 0, 0, 0, 0],
    })
  })

  it('scales each day to the busiest by time', () => {
    expect(weekStrip(weekStats({}, [0, 30, 0, 120, 60, 0, 0])).days).toEqual([
      0, 0.25, 0, 1, 0.5, 0, 0,
    ])
  })

  it('reads minutes under an hour', () => {
    expect(hoursLabel(45)).toBe('45 min')
    expect(hoursLabel(60)).toBe('1 hour')
  })
})

describe('status count chips', () => {
  it('uses the neutral words and skips empty statuses', () => {
    expect(
      countChips({ wishlist: 12, inProgress: 3, finished: 0, dropped: 1 }),
    ).toEqual([
      { status: 'wishlist', label: 'Planned', count: 12 },
      { status: 'in_progress', label: 'In progress', count: 3 },
      { status: 'dropped', label: 'Dropped', count: 1 },
    ])
    expect(countChips(undefined)).toEqual([])
  })
})

describe('unfinished business', () => {
  const now = new Date('2026-10-20T12:00:00Z')
  function unfinished(
    overrides: Partial<UnfinishedEntry> = {},
  ): UnfinishedEntry {
    return {
      libraryItemId: 'item',
      title: { id: 't', type: 'show', title: 'Andor', isAnime: false, ids: {} },
      reason: 'stalled',
      since: '2026-09-08T12:00:00Z',
      ...overrides,
    }
  }

  it('says why the title is there', () => {
    expect(unfinishedLabel(unfinished({ reason: 'dropped' }), now)).toBe(
      'Dropped',
    )
    expect(unfinishedLabel(unfinished(), now)).toBe('Paused 6 weeks')
    expect(
      unfinishedLabel(unfinished({ since: '2026-10-15T12:00:00Z' }), now),
    ).toBe('Paused 1 week')
    expect(
      unfinishedLabel(unfinished({ since: '2026-06-20T12:00:00Z' }), now),
    ).toBe('Paused 4 months')
  })

  it('says where to resume when the next episode is known', () => {
    expect(resumeLine(unfinished({ next: { season: 2, number: 3 } }))).toBe(
      'Resume at S2 · E3',
    )
    expect(resumeLine(unfinished())).toBeNull()
  })
})

describe('markAdded', () => {
  const hit = (tmdb: string, title: string) => ({
    type: 'movie' as const,
    title,
    isAnime: false,
    ids: { tmdb },
  })
  const rows: DiscoverRow[] = [
    {
      id: 'movies_trending',
      title: 'Trending movies',
      items: [hit('1', 'A'), hit('2', 'B')],
    },
    { id: 'movies_in_theaters', title: 'In theaters', items: [hit('1', 'A')] },
  ]

  it('links every card for the added title, in every row', () => {
    const marked = markAdded(rows, 'tmdb:1', 'item-1')
    expect(marked[0].items.map((h) => h.libraryItemId)).toEqual([
      'item-1',
      undefined,
    ])
    expect(marked[1].items[0].libraryItemId).toBe('item-1')
  })

  it('leaves the rows it was given untouched', () => {
    markAdded(rows, 'tmdb:1', 'item-1')
    expect(rows[0].items[0].libraryItemId).toBeUndefined()
  })
})

describe('markOnShelf', () => {
  const hit = (ids: Record<string, string>, title: string) => ({
    type: 'show' as const,
    title,
    isAnime: false,
    ids,
  })
  const rows: DiscoverRow[] = [
    {
      id: 'tv_trending',
      title: 'Trending shows',
      items: [hit({ tmdb: '1', imdb: 'tt1' }, 'A'), hit({ tmdb: '2' }, 'B')],
    },
    { id: 'tv_new', title: 'New shows', items: [hit({ imdb: 'tt1' }, 'A')] },
  ]
  const entry = {
    id: 'item-1',
    title: { ids: { imdb: 'tt1' } },
  } as unknown as LibraryEntry

  it('links every card sharing any id with the added entry', () => {
    const marked = markOnShelf(rows, entry)
    expect(marked[0].items.map((h) => h.libraryItemId)).toEqual([
      'item-1',
      undefined,
    ])
    expect(marked[1].items[0].libraryItemId).toBe('item-1')
  })
})

describe('listening row', () => {
  const item = (
    id: string,
    type: LibraryEntry['title']['type'],
    status: LibraryEntry['status'],
    updatedAt: string,
  ): LibraryEntry => ({
    id,
    status,
    isOwned: false,
    addedAt: '2026-10-01T00:00:00Z',
    updatedAt,
    title: { id: `t-${id}`, type, title: id, isAnime: false, ids: {} },
  })

  it('holds albums in progress, the last touched first', () => {
    const rows = listening([
      item('old', 'album', 'in_progress', '2026-10-02T00:00:00Z'),
      item('show', 'show', 'in_progress', '2026-10-09T00:00:00Z'),
      item('planned', 'album', 'wishlist', '2026-10-09T00:00:00Z'),
      item('new', 'album', 'in_progress', '2026-10-08T00:00:00Z'),
    ])
    expect(rows.map((e) => e.id)).toEqual(['new', 'old'])
  })

  it('is empty without albums, so the row hides', () => {
    expect(listening([])).toEqual([])
  })
})
